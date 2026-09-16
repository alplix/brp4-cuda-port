/***************************************************************************
 *   Copyright (C) 2010 by Oliver Bock                                     *
 *   oliver.bock[AT]aei.mpg.de                                             *
 *                                                                         *
 *   This file is part of Einstein@Home (Radio Pulsar Edition).            *
 *                                                                         *
 *   Description:                                                          *
 *   Demodulates dedispersed time series using a bank of orbital           *
 *   parameters. After this step, an FFT of the resampled time series is   *
 *   searched for pulsed, periodic signals by harmonic summing.            *
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
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "../../demod_binary.h"
#include "../../erp_utilities.h"
#include "cuda_utilities.h"
#include "demod_binary_cuda.h"

// fatbin image of the device module, embedded into the executable at link time
// (see the db_dev.o rule in the CUDA makefiles)
extern "C" const char _binary_db_fat_start[];
extern "C" const char _binary_db_fat_end[];

static CUdevice cuDevice = 0;         // CUDA device handle
static CUcontext cuContext = NULL;    // CUDA context we work in
static CUmodule cuModuleMain = NULL;  // Device module, kernel handles
static CUfunction kernelTimeSeriesModulation;
static CUfunction kernelTimeSeriesLengthModulated;
static CUfunction kernelTimeSeriesResampling;
static CUfunction kernelTimeSeriesMeanReduction;
static CUfunction kernelTimeSeriesPadding;
static CUfunction kernelPowerSpectrum;
static CUresult cuResult = CUDA_SUCCESS;         // CUDA return results (driver API)
static cufftResult_t cufResult = CUFFT_SUCCESS;  // CUFFT return results

static CUdeviceptr originalTimeSeriesDeviceBuffer = 0;  // Original time series device buffer
static CUdeviceptr modTimeOffsetsDeviceBuffer = 0;      // Modulated time offsets device buffer
static CUdeviceptr timeSeriesMeanDeviceBuffer = 0;      // Sum-reduction buffer (two halves)
static unsigned int timeSeriesMeanHalfSize = 0;         // elements per reduction buffer half

static cufftHandle cufPlan;  // FFT plan handle

#include "demod_binary_cuda.cuh"

// integer ceil(a / b)
#define CEIL_DIV(a, b) (((a) + (b) - 1) / (b))

// macro for fft padding (based on powerspectrum kernel's blocksize, defined in
// demod_binary_cuda.cuh)
#define PADDED_FFT_SIZE(fftsize) (CUDA_FFT_BLOCKDIM_X * CEIL_DIV((unsigned int)(fftsize), CUDA_FFT_BLOCKDIM_X))

// launches a 1D grid on the legacy default stream
static CUresult launch1D(CUfunction kernel, unsigned int blocks, unsigned int threads, void **args) {
  return cuLaunchKernel(kernel, blocks, 1, 1, threads, 1, 1, 0, NULL, args, NULL);
}

int initialize_cuda(int cudDeviceIdGiven, int *cudDeviceIdPtr) {
  int cudDeviceId = *cudDeviceIdPtr;

  // initialize driver API
  cuResult = cuInit(0);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't initialize CUDA driver API (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_DRIVER_INIT);
  }

#ifdef BOINCIFIED
  // if controlled by a BOINC client, check device_num in init_data.xml
  // terminate if we couldn't find one there.
  if (!cudDeviceIdGiven && !running_standalone()) {
    // we already checked the command line for the device number, so pass empty command line here
    if (boinc_get_cuda_device_id(0, NULL, &cudDeviceId)) {
      logMessage(error, true, "No suitable CUDA device available!\n");
      return (RADPUL_CUDA_DEVICE_FIND);
    }
    cudDeviceIdGiven = 1;
  }
#endif

  // if no device was explicitly specified so far, find best suitable CUDA device
  if (!cudDeviceIdGiven) {
    logMessage(debug, true,
               "No (valid) device ID passed via command line. Determining suitable device... \n");
    cudDeviceId = findBestFreeDevice(0, 0, 0, 0);
    if (cudDeviceId < 0) {
      logMessage(error, true, "No suitable CUDA device available!\n");
      return (RADPUL_CUDA_DEVICE_FIND);
    }
  }

  // update caller's device ID value
  *cudDeviceIdPtr = cudDeviceId;

  // Get handle for requested device
  cuResult = cuDeviceGet(&cuDevice, cudDeviceId);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't acquire CUDA device #%i (error: %i)!\n", cudDeviceId,
               cuResult);
    return (RADPUL_CUDA_DEVICE_SET);
  }

  // acquire device (set thread scheduling to yield/block during GPU execution: increases latency
  // but reduces CPU usage -> BOINC!)
  cuResult = cuCtxCreate(&cuContext, CU_CTX_SCHED_BLOCKING_SYNC, cuDevice);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Failed to enable CUDA thread yielding for device #%i (error: %i)! Sorry, will try "
               "to occupy one CPU core...\n",
               cudDeviceId, cuResult);

    // retry with auto scheduling
    cuResult = cuCtxCreate(&cuContext, CU_CTX_SCHED_AUTO, cuDevice);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Couldn't acquire CUDA context of device #%i (error: %i)!\n",
                 cudDeviceId, cuResult);
      return (RADPUL_CUDA_DEVICE_SET);
    }
  }

  logMessage(info, true, "CUDA global memory status (initial GPU state, including context):\n");
  printDeviceGlobalMemStatus(info, true);

  // show some details if possible
  int compcapMajor = 0;
  int compcapMinor = 0;
  int multiProcessorCount = 0;
  int clockRate = 0;
  char deviceName[256] = {0};

  cuResult = cuDeviceGetAttribute(&multiProcessorCount, CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT,
                                  cuDevice);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true, "Couldn't retrieve multiprocessor count property of device #%i (error: %i)!\n",
               cudDeviceId, cuResult);
  }
  cuResult = cuDeviceGetAttribute(&clockRate, CU_DEVICE_ATTRIBUTE_CLOCK_RATE, cuDevice);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true, "Couldn't retrieve clock rate property of device #%i (error: %i)!\n",
               cudDeviceId, cuResult);
  }
  cuResult =
      cuDeviceGetAttribute(&compcapMajor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cuDevice);
  if (cuResult == CUDA_SUCCESS) {
    cuResult =
        cuDeviceGetAttribute(&compcapMinor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cuDevice);
  }
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true, "Couldn't retrieve compute capability of device #%i (error: %i)!\n",
               cudDeviceId, cuResult);
  }
  cuResult = cuDeviceGetName(deviceName, sizeof(deviceName), cuDevice);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(debug, true, "Couldn't retrieve name of device #%i (error: %i)!\n", cudDeviceId,
               cuResult);
    strcpy(deviceName, "UNKNOWN");
  }

  const int coreCount = multiProcessorCount * cudaCoresPerMultiprocessor(compcapMajor, compcapMinor);
  logMessage(info, true, "Using CUDA device #%i \"%s\" (CC %i.%i, %i CUDA cores / %.2f GFLOPS)\n",
             cudDeviceId, deviceName, compcapMajor, compcapMinor, coreCount,
             coreCount * (double)clockRate * 2.0 * 1e-6);

  // determine CUDA driver version
  int cudDriverVersion = 0;
  cuResult = cuDriverGetVersion(&cudDriverVersion);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true, "Couldn't retrieve CUDA driver version (error: %i)!\n", cuResult);
  }
  else {
    logMessage(info, true, "Version of installed CUDA driver: %i\n", cudDriverVersion);
  }

  // load device module (fatbin embedded in the executable, an external db.dev file takes
  // precedence if present)
  cuResult = loadPtxModule(&cuModuleMain, "db.dev", _binary_db_fat_start,
                           _binary_db_fat_end - _binary_db_fat_start);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't load main CUDA device module (error: %i)!\n", cuResult);
    return (RADPUL_CUDA_LOAD_MODULE);
  }

  struct {
    CUfunction *handle;
    const char *name;
  } kernels[] = {
      {&kernelTimeSeriesModulation, "time_series_modulation"},
      {&kernelTimeSeriesLengthModulated, "time_series_length_modulated"},
      {&kernelTimeSeriesResampling, "time_series_resampling"},
      {&kernelTimeSeriesMeanReduction, "time_series_mean_reduction"},
      {&kernelTimeSeriesPadding, "time_series_padding"},
      {&kernelPowerSpectrum, "fft_powerspectrum"},
  };
  for (size_t k = 0; k < sizeof(kernels) / sizeof(kernels[0]); k++) {
    cuResult = cuModuleGetFunction(kernels[k].handle, cuModuleMain, kernels[k].name);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Couldn't get CUDA kernel handle \"%s\" (error: %i)!\n",
                 kernels[k].name, cuResult);
      return (RADPUL_CUDA_LOOKUP_KERNEL);
    }
  }

  return 0;
}

// copies a host value into a module-global device symbol
static int uploadSymbol(const char *symbolName, const void *data, size_t bytes) {
  CUdeviceptr cudSymbol;
  size_t symbolBytes = 0;

  cuResult = cuModuleGetGlobal(&cudSymbol, &symbolBytes, cuModuleMain, symbolName);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Couldn't get CUDA symbol handle \"%s\" (error: %i)!\n", symbolName,
               cuResult);
    return (RADPUL_CUDA_LOOKUP_SYMBOL);
  }
  if (symbolBytes < bytes) {
    logMessage(error, true, "CUDA symbol \"%s\" is too small (%lu < %lu bytes)!\n", symbolName,
               (unsigned long)symbolBytes, (unsigned long)bytes);
    return (RADPUL_CUDA_LOOKUP_SYMBOL);
  }
  cuResult = cuMemcpyHtoD(cudSymbol, data, bytes);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error during CUDA host->device transfer of \"%s\" (error: %i)\n",
               symbolName, cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }
  logMessage(debug, true, "CUDA host->device transfer of \"%s\" successful...\n", symbolName);
  return 0;
}

// allocates a device buffer and logs the outcome
static int allocDevice(CUdeviceptr *buffer, size_t bytes, const char *what) {
  cuResult = cuMemAlloc(buffer, bytes);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error allocating %s device memory: %lu bytes (error: %i)\n", what,
               (unsigned long)bytes, cuResult);
    return (RADPUL_CUDA_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated %s device memory: %lu bytes\n", what, (unsigned long)bytes);
  return 0;
}

int set_up_resampling(DIfloatPtr input_dip,
                      DIfloatPtr *output_dip,
                      const RESAMP_PARAMS *const params,
                      float *sinLUTsamples,
                      float *cosLUTsamples) {
  int result;
  float *input = input_dip.host_ptr;  // original time series is on host

  CUdeviceptr resampledTimeSeriesDeviceBuffer;  // Resampled time series device buffer (also used
                                                // for FFT in-/output)

  result = allocDevice(&originalTimeSeriesDeviceBuffer, sizeof(float) * params->nsamples_unpadded,
                       "original time series");
  if (result != 0) return result;

  result = allocDevice(&modTimeOffsetsDeviceBuffer, sizeof(float) * params->nsamples_unpadded,
                       "modulated time offsets");
  if (result != 0) return result;

  // increase FFT buffer length such that it matches the powerspectrum kernel's blocklength (no
  // further control flow required in kernel); the buffer is reused as FFT in-/output, hence the
  // cufftComplex element size
  const unsigned int fft_size_padded = PADDED_FFT_SIZE(params->fft_size);
  result = allocDevice(&resampledTimeSeriesDeviceBuffer, sizeof(cufftComplex) * fft_size_padded,
                       "modulated time series");
  if (result != 0) return result;

  // sum reduction ping-pong buffer: two halves, each large enough for the first pass' block sums
  timeSeriesMeanHalfSize = CEIL_DIV(params->nsamples_unpadded, CUDA_RESAMP_REDUCTION_BLOCKDIM_X);
  result = allocDevice(&timeSeriesMeanDeviceBuffer, sizeof(float) * timeSeriesMeanHalfSize * 2,
                       "time series mean reduction");
  if (result != 0) return result;

  // transfer original time series data to device
  cuResult = cuMemcpyHtoD(originalTimeSeriesDeviceBuffer, input,
                          sizeof(float) * params->nsamples_unpadded);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true,
               "Error during CUDA host->device original time series data transfer (error: %i)\n",
               cuResult);
    return (RADPUL_CUDA_MEM_COPY_HOST_DEVICE);
  }
  logMessage(debug, true, "CUDA host->device original time series data transfer successful...\n");

  // sin/cos lookup tables and their parameters live in constant memory
  const float lutTwoPi = ERP_TWO_PI;
  const float lutTwoPiInv = ERP_TWO_PI_INV;
  if ((result = uploadSymbol("constSinSamples", sinLUTsamples, ERP_SINCOS_LUT_SIZE * sizeof(float))) != 0 ||
      (result = uploadSymbol("constCosSamples", cosLUTsamples, ERP_SINCOS_LUT_SIZE * sizeof(float))) != 0 ||
      (result = uploadSymbol("LUT_TWO_PI", &lutTwoPi, sizeof(float))) != 0 ||
      (result = uploadSymbol("LUT_TWO_PI_INV", &lutTwoPiInv, sizeof(float))) != 0) {
    return result;
  }

  // return allocated device pointer to caller
  output_dip->device_ptr = resampledTimeSeriesDeviceBuffer;

  return 0;
}

int run_resampling(DIfloatPtr input_dip, DIfloatPtr output_dip, const RESAMP_PARAMS *const params) {
  (void)input_dip;  // original time series already resides on the device

  CUdeviceptr resampledTimeSeriesDeviceBuffer = output_dip.device_ptr;

  unsigned int nsamplesUnpadded = params->nsamples_unpadded;
  unsigned int nsamples = params->nsamples;

  // All kernels below run in order on the default stream and exchange the resampled length
  // through a device-side variable, so this whole function is asynchronous with respect to
  // the host: no device->host round trip until the harmonic summing stage.

  // compute time offsets
  float tau = params->tau;
  float omega = params->Omega;
  float psi0 = params->Psi0;
  float dt = params->dt;
  float step_inv = params->step_inv;
  float S0 = params->S0;

  void *kernelArgsTSM[] = {&modTimeOffsetsDeviceBuffer, &nsamplesUnpadded, &tau, &omega,
                           &psi0, &dt, &step_inv, &S0};
  cuResult = launch1D(kernelTimeSeriesModulation,
                      CEIL_DIV(nsamplesUnpadded, CUDA_RESAMP_OFFSETS_BLOCKDIM_X),
                      CUDA_RESAMP_OFFSETS_BLOCKDIM_X, kernelArgsTSM);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA TSM kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  // determine modulated time series length (single block, result stays on the device)
  void *kernelArgsTSLM[] = {&modTimeOffsetsDeviceBuffer, &nsamplesUnpadded};
  cuResult = launch1D(kernelTimeSeriesLengthModulated, 1, CUDA_RESAMP_LENGTH_BLOCKDIM_X,
                      kernelArgsTSLM);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA TSLM kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  // compute resampled time series (bins beyond the resampled length are zeroed)
  void *kernelArgsTSR[] = {&originalTimeSeriesDeviceBuffer, &modTimeOffsetsDeviceBuffer,
                           &resampledTimeSeriesDeviceBuffer, &nsamples};
  cuResult = launch1D(kernelTimeSeriesResampling, CEIL_DIV(nsamples, CUDA_RESAMP_BLOCKDIM_X),
                      CUDA_RESAMP_BLOCKDIM_X, kernelArgsTSR);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA TSR kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  // compute time series sum by iterated block reduction, alternating between the two halves of
  // the reduction buffer (kernel invocations are cheap and give us the global sync)
  CUdeviceptr currentInputBuffer = resampledTimeSeriesDeviceBuffer;
  CUdeviceptr currentOutputBuffer = 0;
  unsigned int remaining = nsamplesUnpadded;
  bool useSecondHalfForOutput = false;
  int iteration = 1;

  do {
    unsigned int requiredBlocks = CEIL_DIV(remaining, CUDA_RESAMP_REDUCTION_BLOCKDIM_X);
    currentOutputBuffer = timeSeriesMeanDeviceBuffer +
                          (useSecondHalfForOutput ? timeSeriesMeanHalfSize * sizeof(float) : 0);

    void *kernelArgsTSMR[] = {&currentInputBuffer, &currentOutputBuffer, &remaining};
    cuResult = launch1D(kernelTimeSeriesMeanReduction, requiredBlocks,
                        CUDA_RESAMP_REDUCTION_BLOCKDIM_X, kernelArgsTSMR);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Error launching CUDA TSMR-%i kernel (error: %d)\n", iteration,
                 cuResult);
      return (RADPUL_CUDA_KERNEL_INVOKE);
    }

    remaining = requiredBlocks;
    currentInputBuffer = currentOutputBuffer;
    useSecondHalfForOutput = !useSecondHalfForOutput;
    iteration++;
  } while (remaining > 1);

  // pad the time series (from the resampled length up to nsamples) with the mean value; the
  // kernel derives the mean from the final reduction result and the device-side length
  void *kernelArgsTSP[] = {&resampledTimeSeriesDeviceBuffer, &currentOutputBuffer, &nsamples};
  cuResult = launch1D(kernelTimeSeriesPadding, CEIL_DIV(nsamples, CUDA_RESAMP_PADDING_BLOCKDIM_X),
                      CUDA_RESAMP_PADDING_BLOCKDIM_X, kernelArgsTSP);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA TSP kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  return 0;
}

int tear_down_resampling(DIfloatPtr output) {
  int result = 0;

  struct {
    CUdeviceptr buffer;
    const char *what;
  } buffers[] = {
      {output.device_ptr, "resampled time series"},
      {originalTimeSeriesDeviceBuffer, "original time series"},
      {modTimeOffsetsDeviceBuffer, "modulated time offsets"},
      {timeSeriesMeanDeviceBuffer, "time series mean reduction"},
  };

  // free everything, report the first failure
  for (size_t k = 0; k < sizeof(buffers) / sizeof(buffers[0]); k++) {
    cuResult = cuMemFree(buffers[k].buffer);
    if (cuResult != CUDA_SUCCESS) {
      logMessage(error, true, "Error deallocating %s device memory (error: %i)\n",
                 buffers[k].what, cuResult);
      result = RADPUL_CUDA_MEM_FREE_DEVICE;
    }
  }

  return result;
}

int set_up_fft(DIfloatPtr input_dip,
               DIfloatPtr *output_dip,
               uint32_t nsamples,
               unsigned int fft_size) {
  (void)input_dip;  // FFT input is the resampled time series already on the device

  // increase powerspectrum buffer length such that it matches the powerspectrum kernel's
  // blocklength (no further control flow required in kernel)
  const unsigned int fft_size_padded = PADDED_FFT_SIZE(fft_size);

  logMessage(debug, true, "Padding output size of FFT with %u samples from %u to %u...\n", nsamples,
             fft_size, fft_size_padded);

  // create fft plan
  cufResult = cufftPlan1d(&cufPlan, nsamples, CUFFT_R2C, 1);
  if (cufResult != CUFFT_SUCCESS) {
    logMessage(error, true, "Error creating CUDA FFT plan (error code: %i)\n", cufResult);
    return (RADPUL_CUDA_FFT_PLAN);
  }
  logMessage(debug, true, "Created CUFFT plan...\n");

  // allocate device memory for power spectrum
  return allocDevice(&(output_dip->device_ptr), sizeof(float) * fft_size_padded, "power spectrum");
}

int run_fft(DIfloatPtr input,
            DIfloatPtr output,
            uint32_t nsamples,
            unsigned int fft_size,
            float norm_factor) {
  (void)nsamples;  // fixed by the plan

  CUdeviceptr psDeviceBuffer = output.device_ptr;
  CUdeviceptr resampledTimeSeriesDeviceBuffer = input.device_ptr;

  const unsigned int fft_size_padded = PADDED_FFT_SIZE(fft_size);

  // execute FFT (in place)
  cufResult = cufftExecR2C(cufPlan, (cufftReal *)resampledTimeSeriesDeviceBuffer,
                           (cufftComplex *)resampledTimeSeriesDeviceBuffer);
  if (cufResult != CUFFT_SUCCESS) {
    logMessage(error, true, "Error executing CUDA FFT plan (error code: %i)\n", cufResult);
    return (RADPUL_CUDA_FFT_EXEC);
  }

  // compute powerspectrum (buffers are padded to whole blocks, no bounds checks needed)
  void *kernelArgs[] = {&resampledTimeSeriesDeviceBuffer, &psDeviceBuffer, &norm_factor};
  cuResult = launch1D(kernelPowerSpectrum, fft_size_padded / CUDA_FFT_BLOCKDIM_X,
                      CUDA_FFT_BLOCKDIM_X, kernelArgs);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error launching CUDA PS kernel (error: %d)\n", cuResult);
    return (RADPUL_CUDA_KERNEL_INVOKE);
  }

  return 0;
}

int tear_down_fft(DIfloatPtr output_dip) {
  int result = 0;

  cuResult = cuMemFree(output_dip.device_ptr);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(error, true, "Error deallocating power spectrum device memory (error: %i)\n",
               cuResult);
    result = RADPUL_CUDA_MEM_FREE_DEVICE;
  }

  cufResult = cufftDestroy(cufPlan);
  if (cufResult != CUFFT_SUCCESS) {
    logMessage(error, true, "Error destroying CUDA FFT plan (error code: %i)\n", cufResult);
    result = RADPUL_CUDA_FFT_DESTROY;
  }

  return result;
}

int shutdown_cuda() {
  // destroy context
  cuResult = cuCtxDestroy(cuContext);
  if (cuResult != CUDA_SUCCESS) {
    logMessage(warn, true, "Couldn't destroy CUDA context (error: %i)!\n", cuResult);
  }

  logMessage(debug, true, "CUDA shutdown successful...\n");

  return 0;
}
