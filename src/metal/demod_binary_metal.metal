/***************************************************************************
 *   Copyright (C) 2023 by Oliver Behnke                                   *
 *   oliver.behnke[AT]aei.mpg.de                                           *
 *                                                                         *
 *   This file is part of Einstein@Home (Radio Pulsar Edition).            *
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

#include <metal_atomic>
#include <metal_compute>
#include <metal_math>
#include <metal_simdgroup>

#define ERP_SINCOS_LUT_RES 64
#define ERP_TWO_PI 6.283185f

using namespace metal;

float deviceSinLUTLookup(const device float *constSinSamples,
                         const device float *constCosSamples,
                         float x)
{
  float xt;
  int i0;
  float d, d2;
  float ts, tc;

  /* normalize value */
  xt = modf(x / ERP_TWO_PI, x); /* xt in (-1, 1) */
  if (xt < 0.0f) {
    xt += 1.0f; /* xt in [0, 1 ) */
  }

  /* determine LUT index */
  i0 = (int)(xt * ERP_SINCOS_LUT_RES + 0.5f);
  d = d2 = ERP_TWO_PI * (xt - 1.0f / ERP_SINCOS_LUT_RES * i0);
  d2 *= 0.5f * d;

  /* fetch sin/cos samples from constant memory */
  ts = constSinSamples[i0];
  tc = constCosSamples[i0];

  /* use taylor-expansion for sin around samples */
  return ts + d * tc - d2 * ts;
};

kernel void kernelTimeSeriesModulation(const device float *constSinSamples [[buffer(0)]],
                                       const device float *constCosSamples [[buffer(1)]],
                                       const device float &tau [[buffer(2)]],
                                       const device float &Omega [[buffer(3)]],
                                       const device float &Psi0 [[buffer(4)]],
                                       const device float &dt [[buffer(5)]],
                                       const device float &step_inv [[buffer(6)]],
                                       const device float &S0 [[buffer(7)]],
                                       device float *del_t [[buffer(8)]],
                                       uint index [[thread_position_in_grid]])
{
  /* compute time offset */
  float t = index * dt;
  float x = Omega * t + Psi0;
  float sinX = deviceSinLUTLookup(constSinSamples, constCosSamples, x);

  /* compute time offsets */
  del_t[index] = tau * sinX * step_inv - S0;
}

kernel void kernelTimeSeriesLengthModulated(const device uint &nsamples_unpadded [[buffer(0)]],
                                            const device float *del_t [[buffer(1)]],
                                            device uint *timeSeriesLength [[buffer(2)]],
                                            uint index [[thread_position_in_grid]])
{
  /* number of timesteps that fit into the duration = at most the amount we had before */
  uint n_steps = nsamples_unpadded - 1;

  /* TODO: avoid global memory reads!!! */
  /* nearest_idx (see resampling kernel) must not exceed n_unpadded - 1, so go back as far as needed
   * to ensure that */
  while (n_steps - del_t[n_steps] >= nsamples_unpadded - 1) {
    n_steps--;
  }

  /* copy length into global variable */
  *timeSeriesLength = n_steps;
}

kernel void kernelTimeSeriesResampling(const device float *input [[buffer(0)]],
                                       const device float *del_t [[buffer(1)]],
                                       const device uint &length [[buffer(2)]],
                                       device float *output [[buffer(3)]],
                                       uint index [[thread_position_in_grid]])
{
  /* TODO: ensure coalesced memory access (load/store) !!! */
  /* only resample 'existing' time samples */
  if (index < length) {
    /* sample i arrives at the detector at index - del_t[index], choose nearest neighbor */
    int nearest_idx = (int)(index - del_t[index] + 0.5f);

    /* set index-th bin in resampled time series (at the pulsar) to nearest_idx bin from
     * de-dispersed time series */
    output[index] = input[nearest_idx];
  }
  else {
    /* set remaining buffercells to zero (for upcoming sum reduction) */
    output[index] = 0.0f;
  }
}

kernel void kernelTimeSeriesMeanReduction(const device float *input [[buffer(0)]],
                                          device atomic_float *output [[buffer(1)]],
                                          const device uint &simd_groups [[buffer(2)]],
                                          threadgroup float *group_sum [[threadgroup(0)]],
                                          uint tid [[thread_position_in_grid]],
                                          uint lid [[thread_position_in_threadgroup]],
                                          uint simd_lane_id [[thread_index_in_simdgroup]],
                                          uint simd_group_id [[simdgroup_index_in_threadgroup]])
{
  // load from global memory and sum up each SIMD group (simd_size samples)
  // TODO: is this an efficient/coalesced load?
  group_sum[simd_group_id] = simd_sum(input[tid]);

  // wait for all SIMD sums in threadgroup
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // sum up SIMD sums across threadgroup
  float value = 0.0;
  if (simd_group_id == 0 && simd_lane_id < simd_groups) {
    value = simd_sum(group_sum[simd_lane_id]);
  }

  // atomically add threadgroup sum to global memory
  if (lid == 0) atomic_fetch_add_explicit(output, value, memory_order_relaxed);
}

kernel void kernelTimeSeriesPadding(device float *buffer [[buffer(0)]],
                                    const device float &mean [[buffer(1)]],
                                    const device uint &offset [[buffer(2)]],
                                    uint index [[thread_position_in_grid]])
{
  // can't be avoided as time series varies in length (incl. non-multiple-of-32 values)
  if (index >= offset) {
    buffer[index] = mean;
  }
}

kernel void kernelPowerspectrum(device const float *input [[buffer(0)]],
                                device float *output [[buffer(1)]],
                                device const float &norm_factor [[buffer(2)]],
                                uint index [[thread_position_in_grid]])
{
  // computer power spectrum
  output[index] = norm_factor * (pow(input[index + index], 2) + pow(input[index + index + 1], 2));
}
