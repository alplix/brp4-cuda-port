/***************************************************************************
 *   Copyright (C) 2010 by Oliver Bock                                     *
 *   oliver.bock[AT]aei.mpg.de                                             *
 *                                                                         *
 *   This file is part of Einstein@Home (Radio Pulsar Edition).            *
 *                                                                         *
 *   Description:                                                          *
 *   Device kernels of the resampling / FFT stage. Included by the host   *
 *   translation unit (block sizes only) and compiled to a fatbin by nvcc. *
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

#ifndef DEMOD_BINARY_CUDA_CUH
#define DEMOD_BINARY_CUDA_CUH

#ifdef __cplusplus
extern "C" {
#endif

// block dimensions are shared between device kernels and host launch code

#define CUDA_RESAMP_OFFSETS_BLOCKDIM_X 128

// time_series_length_modulated: one block, each iteration inspects this many
// consecutive samples (1024 is the maximum on every supported architecture)
#define CUDA_RESAMP_LENGTH_BLOCKDIM_X 1024

#define CUDA_RESAMP_BLOCKDIM_X 384

#define CUDA_RESAMP_REDUCTION_BLOCKDIM_X 128

#define CUDA_RESAMP_PADDING_BLOCKDIM_X 512

#define CUDA_FFT_BLOCKDIM_X 256

#ifdef __CUDACC__

// use constant (cached) device memory for sin/cos samples and params (computed on host)
__constant__ float constSinSamples[ERP_SINCOS_LUT_SIZE];
__constant__ float constCosSamples[ERP_SINCOS_LUT_SIZE];
__constant__ float LUT_TWO_PI;
__constant__ float LUT_TWO_PI_INV;

// length of the resampled (unpadded) time series for the current template.
// Written by time_series_length_modulated and consumed on the device by the
// resampling and padding kernels, so the host never has to wait for it.
__device__ int timeSeriesLength = 0;

__device__ float sinLUTLookup(float x) {
  float xt;
  int i0;
  float d, d2;
  float ts, tc;

  // normalize value
  xt = modff(x * LUT_TWO_PI_INV, &x);  // xt in (-1, 1)
  if (xt < 0.0f) {
    xt += 1.0f;  // xt in [0, 1 )
  }

  // determine LUT index
  i0 = (int)__fadd_rn(__fmul_rn(xt, ERP_SINCOS_LUT_RES_F), 0.5f);
  d = d2 = __fmul_rn(LUT_TWO_PI, __fadd_rn(xt, -__fmul_rn(ERP_SINCOS_LUT_RES_F_INV, i0)));
  d2 *= 0.5f * d;

  // fetch sin/cos samples from constant memory
  ts = constSinSamples[i0];
  tc = constCosSamples[i0];

  // use taylor-expansion for sin around samples
  return __fadd_rn(__fadd_rn(ts, __fmul_rn(d, tc)), -(__fmul_rn(d2, ts)));
}

__global__ void time_series_modulation(float *del_t,
                                       unsigned int nsamples_unpadded,
                                       float tau,
                                       float Omega,
                                       float Psi0,
                                       float dt,
                                       float step_inv,
                                       float S0) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  if (i >= nsamples_unpadded) {
    return;
  }

  // compute time offset
  float t = i * dt;
  float x = __fadd_rn(__fmul_rn(Omega, t), Psi0);
  float sinX = sinLUTLookup(x);

  // compute time offsets
  del_t[i] = __fadd_rn(__fmul_rn(__fmul_rn(tau, sinX), step_inv), -S0);
}

/* Determines the number of resampled time steps: the largest n_steps for which
 * nearest_idx (see time_series_resampling) stays below nsamples_unpadded - 1,
 * i.e. the first index counting down from nsamples_unpadded - 1 that satisfies
 *     (float)n_steps - del_t[n_steps] < nsamples_unpadded - 1.
 *
 * The original implementation walked down one sample at a time in a single
 * thread; for templates where del_t is negative at the end of the data set
 * that meant tens of thousands of dependent global loads per template. Here a
 * whole block inspects blockDim.x consecutive candidates per iteration and
 * keeps the highest hit, which yields exactly the same index. Launch with a
 * single block of CUDA_RESAMP_LENGTH_BLOCKDIM_X threads. */
__global__ void time_series_length_modulated(const float *del_t, unsigned int nsamples_unpadded) {
  __shared__ int highestHit;

  const float limit = (float)(nsamples_unpadded - 1);
  int result = 0;

  for (int top = (int)nsamples_unpadded - 1; top >= 0; top -= (int)blockDim.x) {
    if (threadIdx.x == 0) {
      highestHit = -1;
    }
    __syncthreads();

    const int k = top - (int)threadIdx.x;
    // negated comparison keeps the original loop's NaN behaviour (a NaN stops the walk)
    if (k >= 0 && !((float)k - del_t[k] >= limit)) {
      atomicMax(&highestHit, k);
    }
    __syncthreads();

    if (highestHit >= 0) {
      result = highestHit;
      break;
    }
  }

  if (threadIdx.x == 0) {
    timeSeriesLength = result;
  }
}

__global__ void time_series_resampling(const float *input,
                                       const float *del_t,
                                       float *output,
                                       unsigned int nsamples) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  if (i >= nsamples) {
    return;
  }

  // only resample "existing" time samples
  if ((int)i < timeSeriesLength) {
    // sample i arrives at the detector at i - del_t[i], choose nearest neighbor
    int nearest_idx = (int)(i - del_t[i] + 0.5f);

    // set i-th bin in resampled time series (at the pulsar) to nearest_idx bin from de-dispersed
    // time series
    output[i] = input[nearest_idx];
  }
  else {
    // set remaining buffercells to zero (for upcoming sum reduction)
    output[i] = 0.0f;
  }
}

/* Sums blockDim.x consecutive inputs per block (inputs at or beyond n count as
 * zero, so partial blocks are handled without changing the summation order). */
__global__ void time_series_mean_reduction(const float *input, float *output, unsigned int n) {
  __shared__ float sharedPartialSum[CUDA_RESAMP_REDUCTION_BLOCKDIM_X];

  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  // coalesced load of time series data into shared memory
  sharedPartialSum[threadIdx.x] = (i < n) ? input[i] : 0.0f;

  // wait for load to finish
  __syncthreads();

  // compute sum of current block (in log2(blocksize) iterations)
  for (unsigned int stride = blockDim.x >> 1; stride > 0; stride >>= 1) {
    // sum two strided values per thread
    if (threadIdx.x < stride) {
      sharedPartialSum[threadIdx.x] += sharedPartialSum[threadIdx.x + stride];
    }

    // wait for (partial) block summing iteration to finish
    __syncthreads();
  }

  // store sum of current block in global memory (single thread)
  if (threadIdx.x == 0) {
    output[blockIdx.x] = sharedPartialSum[0];
  }
}

/* Pads the resampled time series (from timeSeriesLength up to nsamples) with
 * its mean value. sum points at the final result of the reduction above; the
 * division uses IEEE round-to-nearest, exactly like the former host-side
 * "mean /= n_steps". */
__global__ void time_series_padding(float *output, const float *sum, unsigned int nsamples) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  if (i >= nsamples) {
    return;
  }

  const int offset = timeSeriesLength;

  // can't be avoided as time series varies in length (incl. non-multiple-of-32 values)
  if ((int)i >= offset) {
    // coalesced store of resampled time series padding data to global memory
    output[i] = __fdiv_rn(sum[0], (float)offset);
  }
}

__global__ void fft_powerspectrum(const cufftComplex *fft_data, float *ps_data, float norm_factor) {
  unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;

  // coalesced load (the buffer is padded to a multiple of the block size)
  const cufftComplex v = fft_data[i];

  // compute power spectrum (DC bin is zeroed)
  const float nf = (i == 0) ? 0.0f : norm_factor;
  ps_data[i] = __fmul_rn(nf, __fadd_rn(__fmul_rn(v.x, v.x), __fmul_rn(v.y, v.y)));
}

#endif /* __CUDACC__ */

#ifdef __cplusplus
}
#endif

#endif
