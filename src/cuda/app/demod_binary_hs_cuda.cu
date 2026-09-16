/***************************************************************************
 *   Copyright (C) 2008 by Benjamin Knispel, Holger Pletsch                *
 *   benjamin.knispel[AT]aei.mpg.de                                        *
 *   Copyright (C) 2009,2010 by Oliver Bock                                *
 *   oliver.bock[AT]aei.mpg.de                                             *
 *   Copyright (C) 2009,2010 by Heinz-Bernd Eggenstein                     *
 *                                                                         *
 *   This file is part of Einstein@Home (Radio Pulsar Edition).            *
 *                                                                         *
 *   Description:                                                          *
 *   Performs harmonic summing (2nd ... 16th harmonic) of powerspectrum    *
 *   CUDA variant.                                                         *
 *                                                                         *
 *   Einstein@Home is free software: you can redistribute it and/or modify *
 *   it under the terms of the GNU General Public License as published     *
 *   by the Free Software Foundation, version 2 of the License.            *
 *                                                                         *
 *   Einstein@Home is distributed in the hope that it will be useful,      *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the          *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with Einstein@Home. If not, see <http://www.gnu.org/licenses/>. *
 *                                                                         *
 ***************************************************************************/

#include <cuda.h>
#include <stdlib.h>
#include <string.h>

#include "../../demod_binary.h"
#include "../../erp_utilities.h"
#include "../../hs_common.h"
#include "cuda_utilities.h"
#include "demod_binary_hs_cuda.cuh"

// fatbin image of the device module, embedded into the executable at link time
// (see the dbhs_dev.o rule in the CUDA makefiles)
extern "C" const char _binary_dbhs_fat_start[];
extern "C" const char _binary_dbhs_fat_end[];

#define HS_BLOCKSIZE 256    // must be an integer power of 2 (because of the following constraint)
#define HS_LOG_BLOCKSIZE 8  // constraint: HS_LOG_BLOCKSIZE = lrint(log2(HS_BLOCKSIZE))

// device kernels are only visible to the device compiler (fatbin generation);
// the host build links against the driver API only
#ifdef __CUDACC__
#include "harmonic_summing_kernel.cuh"
#endif

// module global state (set up once per work unit, reused for every template)

static float *powerspectrumHost = NULL;  // host copy of the power spectrum (sumspec[0])
static int stdmemFlags = 0;              // bit i set: sumspec[i] is a plain calloc, not pinned

static CUdeviceptr h_lutDev = 0;  // look up tables in global device memory
static CUdeviceptr k_lutDev = 0;
static CUdeviceptr thrADev = 0;        // threshold for 1st , 2nd, 4th, 8th, 16th harmonics on device
static CUdeviceptr sumspecDev[5];      // device sumspec arrays ([0] is the power spectrum itself)
static CUdeviceptr dirtyDev = 0;       // dirty page flags, 5 * nr_pages int32 on the device
static int32_t *dirtyHost = NULL;      // pinned staging buffer for the dirty page flags
static float *thrHost = NULL;          // pinned staging buffer for the five thresholds
static unsigned int nrPagesTotal = 0;  // 5 * nr_pages

static CUmodule cuModuleHS = NULL;  // device module and kernel handles
static CUfunction kernelHarmonicSumming;
static CUfunction kernelHarmonicSummingGaps;
static CUstream hsStream[2] = {NULL, NULL};  // main and gap kernels may overlap

// allocates page-locked host memory, falling back to calloc (flag bit is set on fallback)
static float *allocHostFloats(size_t count, int flagBit, const char *what) {
  float *buffer = NULL;
  CUresult cuResult = cuMemAllocHost((void **)&buffer, count * sizeof(float));
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true,
               "Couldn't allocate %lu bytes of pinned host memory for %s (error: %i)! Using "
               "conventional memory...\n",
               (unsigned long)(count * sizeof(float)), what, cuResult);
    buffer = (float *)calloc(count, sizeof(float));
    stdmemFlags |= (1 << flagBit);
  }
  else {
    memset(buffer, 0, count * sizeof(float));
  }
  return buffer;
}

int set_up_harmonic_summing(float **sumspec,
                            int32_t **dirty,
                            unsigned int *nr_pages_ptr,
                            unsigned int fundamental_idx_hi,
                            unsigned int harmonic_idx_hi) {
  CUresult cuResult = CUDA_SUCCESS;
  int i;
  unsigned int nr_pages;

  // load device module (fatbin embedded in the executable, an external dbhs.dev file takes
  // precedence if present)
  cuResult = loadPtxModule(&cuModuleHS, "dbhs.dev", _binary_dbhs_fat_start,
                           _binary_dbhs_fat_end - _binary_dbhs_fat_start);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't load HS CUDA device module (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOAD_MODULE);
  }

  cuResult = cuModuleGetFunction(&kernelHarmonicSumming, cuModuleHS, "harmonic_summing_kernel");
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA HS kernel handle (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOOKUP_KERNEL);
  }

  cuResult =
      cuModuleGetFunction(&kernelHarmonicSummingGaps, cuModuleHS, "harmonic_summing_kernel_gaps");
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA HSG kernel handle (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOOKUP_KERNEL);
  }

  // streams for the two (independent) summing kernels; created with the default flags so they
  // still synchronize with the preceding default-stream work (resampling, FFT, power spectrum)
  for (i = 0; i < 2; i++) {
    cuResult = cuStreamCreate(&hsStream[i], 0);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Couldn't create CUDA HS stream (error: %i)!\n", cuResult);
      return (RADPUL_CUDA_KERNEL_PREPARE);
    }
  }

  // host memory for the harmonic summed spectra (pinned: they receive per-template device->host
  // copies). In the CUDA version this includes the 1st harmonic = the power spectrum itself.
  sumspec[0] = powerspectrumHost = allocHostFloats(harmonic_idx_hi, 0, "power spectrum");
  if (powerspectrumHost == NULL) {
    logMessage(error, true, "Couldn't allocate %lu bytes of memory for power spectrum!\n",
               (unsigned long)(harmonic_idx_hi * sizeof(float)));
    return (RADPUL_CUDA_MEM_ALLOC_HOST);
  }
  for (i = 1; i < 5; i++) {
    sumspec[i] = allocHostFloats(fundamental_idx_hi, i, "sumspec");
    if (sumspec[i] == NULL) {
      logMessage(error, true, "Couldn't allocate %lu bytes of memory for sumspec at bottom level.\n",
                 (unsigned long)(fundamental_idx_hi * sizeof(float)));
      return (RADPUL_EMEM);
    }
  }

  // device memory for the summed spectra (sumspecDev[0] is set per template to the power spectrum)
  sumspecDev[0] = 0;
  for (i = 1; i < 5; i++) {
    cuResult = cuMemAlloc(&(sumspecDev[i]), sizeof(float) * fundamental_idx_hi);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Couldn't allocate %lu bytes of CUDA HS summing memory (error: %i)!\n",
                 (unsigned long)(sizeof(float) * fundamental_idx_hi), cuResult);
      return (RADPUL_CUDA_MEM_ALLOC_DEVICE);
    }
  }

  // dirty page flags: host arrays handed to the caller, one device array and a pinned staging
  // buffer covering all five harmonics
  nr_pages = (fundamental_idx_hi >> LOG_PS_PAGE_SIZE) + 1;
  *nr_pages_ptr = nr_pages;
  nrPagesTotal = nr_pages * 5;
  for (i = 0; i < 5; i++) {
    dirty[i] = (int32_t *)calloc(nr_pages, sizeof(int32_t));
    if (dirty[i] == NULL) {
      logMessage(error, true,
                 "Couldn't allocate %lu bytes of memory for sumspec page flags at bottom level.\n",
                 (unsigned long)(nr_pages * sizeof(int32_t)));
      return (RADPUL_EMEM);
    }
  }
  cuResult = cuMemAlloc(&dirtyDev, sizeof(int32_t) * nrPagesTotal);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't allocate %lu bytes of CUDA HS page flag memory (error: %i)!\n",
               (unsigned long)(sizeof(int32_t) * nrPagesTotal), cuResult);
    return (RADPUL_CUDA_MEM_ALLOC_DEVICE);
  }
  cuResult = cuMemAllocHost((void **)&dirtyHost, sizeof(int32_t) * nrPagesTotal);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Couldn't allocate %lu bytes of pinned host memory for HS page flags (error: %i)!\n",
               (unsigned long)(sizeof(int32_t) * nrPagesTotal), cuResult);
    return (RADPUL_CUDA_MEM_ALLOC_HOST);
  }
  cuResult = cuMemAllocHost((void **)&thrHost, sizeof(float) * 5);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't allocate pinned host memory for HS thresholds (error: %i)!\n",
               cuResult);
    return (RADPUL_CUDA_MEM_ALLOC_HOST);
  }

  // look up device-side symbol handles (replacing legacy texture references)
  size_t symSize = 0;
  cuResult = cuModuleGetGlobal(&h_lutDev, &symSize, cuModuleHS, "d_h_lut");
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA HSH symbol handle (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOOKUP_SYMBOL);
  }
  cuResult = cuModuleGetGlobal(&k_lutDev, &symSize, cuModuleHS, "d_k_lut");
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA HSK symbol handle (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOOKUP_SYMBOL);
  }
  cuResult = cuModuleGetGlobal(&thrADev, &symSize, cuModuleHS, "thrA");
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA HST symbol handle (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOOKUP_SYMBOL);
  }

  // copy LUTs to device memory
  cuResult = cuMemcpyHtoD(h_lutDev, h_lut, sizeof(int32_t) * 16);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Error during CUDA host->device HSH lookup table data transfer (error: %i)\n",
               cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }
  cuResult = cuMemcpyHtoD(k_lutDev, k_lut, sizeof(int32_t) * 16);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Error during CUDA host->device HSK lookup table data transfer (error: %i)\n",
               cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }

  logMessage(debug, true, "Harmonic summing set up (%u pages per harmonic)\n", nr_pages);

  return 0;
}

int tear_down_harmonic_summing(float **sumspec, int32_t **dirty) {
  CUresult cuResult = CUDA_SUCCESS;
  int result = 0;
  int i;

  // host spectra (sumspec[0] is the power spectrum buffer)
  for (i = 0; i < 5; i++) {
    if (stdmemFlags & (1 << i)) {
      free(sumspec[i]);
    }
    else {
      cuResult = cuMemFreeHost(sumspec[i]);
      if (cuResult != CUDA_SUCCESS) {
        logMessage(error, true, "Error deallocating CUDA pinned host HS memory (error: %i)\n",
                   cuResult);
        result = RADPUL_CUDA_MEM_FREE_HOST;
      }
    }
    sumspec[i] = NULL;
  }
  powerspectrumHost = NULL;

  for (i = 0; i < 5; i++) {
    free(dirty[i]);
  }
  cuResult = cuMemFreeHost(dirtyHost);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error deallocating CUDA pinned host HS page flags (error: %i)\n",
               cuResult);
    result = RADPUL_CUDA_MEM_FREE_HOST;
  }
  cuMemFreeHost(thrHost);

  for (i = 1; i < 5; i++) {
    cuResult = cuMemFree(sumspecDev[i]);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Error freeing CUDA HS device memory (error: %d)\n", cuResult);
      result = RADPUL_CUDA_MEM_FREE_DEVICE;
    }
  }
  cuResult = cuMemFree(dirtyDev);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error freeing CUDA HS page flag device memory (error: %d)\n", cuResult);
    result = RADPUL_CUDA_MEM_FREE_DEVICE;
  }

  for (i = 0; i < 2; i++) {
    cuStreamDestroy(hsStream[i]);
  }

  return result;
}

int run_harmonic_summing(float **sumspec,
                         int32_t **dirty,
                         unsigned int nr_pages,
                         DIfloatPtr powerspectrum_dip,
                         unsigned int window_2,
                         unsigned int fundamental_idx_hi,
                         unsigned int harmonic_idx_hi,
                         float *thresholds) {
  unsigned int l2, i, j, k;
  CUresult cuResult = CUDA_SUCCESS;

  CUdeviceptr powerspectrumDev = powerspectrum_dip.device_ptr;

  // the power spectrum acts as first (1st harmonic) spectrum
  sumspec[0] = powerspectrumHost;
  sumspecDev[0] = powerspectrumDev;

  // the kernels only write sumspec cells above threshold, so the device arrays must start out
  // zeroed for every template (otherwise stale values of earlier templates would survive inside
  // pages that get marked dirty now)
  for (i = 1; i < 5; i++) {
    cuResult = cuMemsetD32Async(sumspecDev[i], 0, fundamental_idx_hi, NULL);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Couldn't erase %lu bytes of CUDA HS summing memory (error: %i)!\n",
                 (unsigned long)(sizeof(float) * fundamental_idx_hi), cuResult);
      return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
    }
  }
  cuResult = cuMemsetD32Async(dirtyDev, 0, nrPagesTotal, NULL);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't erase %lu bytes of CUDA HS page flag memory (error: %i)!\n",
               (unsigned long)(sizeof(int32_t) * nrPagesTotal), cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }

  // copy thresholds to device (asynchronously from pinned staging memory; the previous template's
  // transfer has long completed since every template ends with a full synchronization)
  memcpy(thrHost, thresholds, sizeof(float) * 5);
  cuResult = cuMemcpyHtoDAsync(thrADev, thrHost, sizeof(float) * 5, NULL);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Error during CUDA host->device HS thresholds data transfer (error: %i)\n",
               cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }

  // kernel arguments (both kernels share the same signature)
  void *kernelArgs[] = {&sumspecDev[1], &sumspecDev[2],      &sumspecDev[3],
                        &sumspecDev[4], &dirtyDev,           &powerspectrumDev,
                        &window_2,      &fundamental_idx_hi, &harmonic_idx_hi};

  /* Main kernel: sub-blocks of 16 threads, the number of 16-index segments needed to cover the
   * spectrum up to harmonic_idx_hi - 1 (inclusive); the kernel handles the window_2 offset and
   * the left border itself. A 2D grid (x = 16, y = rest) keeps each dimension within limits. */
  l2 = ((harmonic_idx_hi - 1 + 8) >> 4) + 1;
  unsigned int gridY1 = (l2 + HS_BLOCKSIZE - 1) / HS_BLOCKSIZE;

  logMessage(debug, true,
             "Executing harmonic summing CUDA kernel (%u threads each in %u blocks)...\n",
             HS_BLOCKSIZE, 16 * gridY1);

  cuResult = cuLaunchKernel(kernelHarmonicSumming, 16, gridY1, 1, HS_BLOCKSIZE, 1, 1, 0,
                            hsStream[0], kernelArgs, NULL);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA HS kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  /* Gap kernel: fills the sumspec slots the main kernel leaves out at the sub-block borders.
   * Its block size must be half that of the main kernel. */
  l2 = ((harmonic_idx_hi - 1 + 12) >> 4) + 1;
  unsigned int gridY2 = (l2 + HS_BLOCKSIZE - 1) / HS_BLOCKSIZE;

  logMessage(debug, true,
             "Executing harmonic summing gaps CUDA kernel (%u threads each in %u blocks)...\n",
             HS_BLOCKSIZE / 2, 16 * gridY2);

  cuResult = cuLaunchKernel(kernelHarmonicSummingGaps, 16, gridY2, 1, HS_BLOCKSIZE / 2, 1, 1, 0,
                            hsStream[1], kernelArgs, NULL);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA HSG kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  // queue the dirty page flag read-back behind the kernels (the default stream waits for both
  // blocking streams) and wait for everything issued so far. This is the first of only two
  // host<->device synchronization points per template; errors surfacing here indicate failures
  // of any earlier asynchronous launch or transfer.
  cuResult = cuMemcpyDtoHAsync(dirtyHost, dirtyDev, sizeof(int32_t) * nrPagesTotal, NULL);
  if (cuResult == CUDA_SUCCESS) {
    cuResult = cuCtxSynchronize();
  }
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error during CUDA kernel execution / dirty page read-back (error: %d)\n",
               cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  // distribute the flags to the per-harmonic host arrays and find the dirty page range
  int dirty_idx_min[5];
  int dirty_idx_max[5];

  k = 0;
  for (i = 0; i < 5; i++) {
    int d_min = -1;
    int d_max = -1;
    for (j = 0; j < nr_pages; j++) {
      int32_t d = dirtyHost[k++];
      dirty[i][j] = d;
      if (d != 0) {
        if (d_min < 0) d_min = j;
        d_max = j;
      }
    }
    dirty_idx_min[i] = d_min;
    dirty_idx_max[i] = d_max;
  }

  /* copy back the results from the CUDA kernel.
   * make sure to copy only those cells from sumspec
   * (including the "1st harmonics" powerspectrum itself)
   * that have a chance to include a candidate that makes it to the toplist */
  for (i = 0; i < 5; i++) {
    // no need to copy anything if there is no potential candidate at all
    if (dirty_idx_max[i] < 0) continue;

    size_t seg_offset = (size_t)dirty_idx_min[i] << LOG_PS_PAGE_SIZE;
    size_t seg_length = (size_t)(dirty_idx_max[i] - dirty_idx_min[i] + 1) << LOG_PS_PAGE_SIZE;
    // clip the segment to be copied at the max length of the array
    size_t seg_length_limit = fundamental_idx_hi - seg_offset;
    if (seg_length > seg_length_limit) {
      seg_length = seg_length_limit;
    }

    // asynchronous into pinned memory (degrades to a synchronous copy for a pageable fallback)
    cuResult = cuMemcpyDtoHAsync(sumspec[i] + seg_offset, sumspecDev[i] + seg_offset * sizeof(float),
                                 sizeof(float) * seg_length, NULL);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Error during CUDA device->host HS data transfer (error: %d)\n",
                 cuResult);
      return (RADPUL_CUDA_MEM_COPY_DEVICE_HOST);
    }
  }

  // second synchronization point: the host may read the spectra once this returns
  cuResult = cuCtxSynchronize();
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error waiting for CUDA device->host HS data transfers (error: %d)\n",
               cuResult);
    return (RADPUL_CUDA_MEM_COPY_DEVICE_HOST);
  }

  return 0;
}
