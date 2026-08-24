/***************************************************************************
 *   Copyright (C) 2023 by Oliver Behnke                                   *
 *   oliver.behnke[AT]aei.mpg.de                                           *
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

#include "demod_binary_metal.h"

#include <gsl/gsl_math.h>
#include <stdlib.h>
#include <vkFFT.h>

#include "Foundation/NSTypes.hpp"

// must follow vkFFT.h since that doesn't prevent double includes
#ifndef NS_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#endif
#ifndef CA_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#endif
#ifndef MTL_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#endif
#include <default.metallib.h>

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>

#include "../demod_binary.h"
#include "../erp_utilities.h"

// globals
MTL::Device *device = NULL;
MTL::CommandQueue *queue = NULL;
MTL::Library *library = NULL;
MTL::Function *kernelTimeSeriesModulation = NULL;
MTL::Function *kernelTimeSeriesLengthModulated = NULL;
MTL::Function *kernelTimeSeriesResampling = NULL;
MTL::Function *kernelTimeSeriesMeanReduction = NULL;
MTL::Function *kernelTimeSeriesPadding = NULL;
MTL::Function *kernelPowerspectrum = NULL;
MTL::ComputePipelineState *pipelineTimeSeriesModulation = NULL;
MTL::ComputePipelineState *pipelineTimeSeriesLengthModulated = NULL;
MTL::ComputePipelineState *pipelineTimeSeriesResampling = NULL;
MTL::ComputePipelineState *pipelineTimeSeriesMeanReduction = NULL;
MTL::ComputePipelineState *pipelineTimeSeriesPadding = NULL;
MTL::ComputePipelineState *pipelinePowerspectrum = NULL;
MTL::Buffer *originalTimeSeriesDeviceBuffer = NULL;
MTL::Buffer *sinLUTDeviceBuffer = NULL;
MTL::Buffer *cosLUTDeviceBuffer = NULL;
MTL::Buffer *modTimeOffsetsDeviceBuffer = NULL;
MTL::Buffer *timeSeriesLengthDeviceBuffer = NULL;
MTL::Buffer *resampledTimeSeriesDeviceBuffer = NULL;
MTL::Buffer *timeSeriesMeanDeviceBuffer = NULL;
MTL::Buffer *deviceBuffer = NULL;
MTL::Buffer *powerspectrumDeviceBuffer = NULL;
dispatch_data_t libraryData = NULL;
uint64_t bufferSize = 0;

// TODO: do we wanna keep those global (or use proper C++, or pass them around)?
VkFFTConfiguration configuration = {};
VkFFTApplication app = {};
VkFFTLaunchParams launchParams = {};

int initialize_metal(int metalDeviceIdGiven, int *metalDeviceId) {
  if (metalDeviceIdGiven == 0) {
    // get default device
    logMessage(debug, true,
               "No (valid) Metal device ID passed via command line. Using default device... \n");
    device = MTL::CreateSystemDefaultDevice();
    if (NULL == device) {
      logMessage(error, true, "Couldn't find Metal default device!\n");
      return (RADPUL_METAL_DEVICE_FIND);
    }
  }
  else {
    // retrieve all devices
    NS::Array *devices = MTL::CopyAllDevices();

    // select device based on ordinal provided (via command line)
    if (*metalDeviceId >= 0 && devices->count() > *metalDeviceId) {
      device = (MTL::Device *)devices->object(*metalDeviceId);
      logMessage(debug, true, "Selected Metal device #%i as requested via command line...\n",
                 *metalDeviceId);
    }
  }

  // sanity check
  if (!device) {
    logMessage(error, true, "No suitable Metal device available for use!\n");
    return (RADPUL_METAL_DEVICE_FIND);
  }

  // get device name
  logMessage(info, true, "Using Metal device \"%s\"\n",
             device->name()->cString(NS::UTF8StringEncoding));

  // create OpenCL command queue
  queue = device->newCommandQueue();
  if (!queue) {
    logMessage(error, true, "Couldn't create Metal command queue!\n");
    return (RADPUL_METAL_CMDQUEUE_CREATE);
  }

  // load serialized Metal library (embedded)
  NS::Error *details = NULL;
  libraryData = dispatch_data_create(&default_metallib[0], default_metallib_len, NULL, NULL);
  library = device->newLibrary(libraryData, &details);
  if (!library) {
    logMessage(error, true, "Couldn't load kernel library!\n");
    return RADPUL_METAL_LIBRARY_CREATE;
  }

  // retrieve kernels
  kernelTimeSeriesModulation = library->newFunction(
      NS::String::string("kernelTimeSeriesModulation", NS::UTF8StringEncoding));
  if (!kernelTimeSeriesModulation) {
    logMessage(error, true, "Couldn't find TSM kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  kernelTimeSeriesLengthModulated = library->newFunction(
      NS::String::string("kernelTimeSeriesLengthModulated", NS::UTF8StringEncoding));
  if (!kernelTimeSeriesLengthModulated) {
    logMessage(error, true, "Couldn't find TSLM kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  kernelTimeSeriesResampling = library->newFunction(
      NS::String::string("kernelTimeSeriesResampling", NS::UTF8StringEncoding));
  if (!kernelTimeSeriesResampling) {
    logMessage(error, true, "Couldn't find TSR kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  kernelTimeSeriesMeanReduction = library->newFunction(
      NS::String::string("kernelTimeSeriesMeanReduction", NS::UTF8StringEncoding));
  if (!kernelTimeSeriesMeanReduction) {
    logMessage(error, true, "Couldn't find TSMR kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  kernelTimeSeriesPadding =
      library->newFunction(NS::String::string("kernelTimeSeriesPadding", NS::UTF8StringEncoding));
  if (!kernelTimeSeriesPadding) {
    logMessage(error, true, "Couldn't find TSP kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  kernelPowerspectrum =
      library->newFunction(NS::String::string("kernelPowerspectrum", NS::UTF8StringEncoding));
  if (!kernelPowerspectrum) {
    logMessage(error, true, "Couldn't find PS kernel!\n");
    return RADPUL_METAL_KERNEL_CREATE;
  }

  return (0);
}

int set_up_resampling(DIfloatPtr input_dip,
                      DIfloatPtr *output_dip,
                      const RESAMP_PARAMS *const params,
                      float *sinLUTsamples,
                      float *cosLUTsamples) {
  NS::Error *details = NULL;

  // create compute pipeline state objects
  pipelineTimeSeriesModulation =
      device->newComputePipelineState(kernelTimeSeriesModulation, &details);
  if (!pipelineTimeSeriesModulation) {
    logMessage(error, true, "Couldn't create TSM compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  pipelineTimeSeriesLengthModulated =
      device->newComputePipelineState(kernelTimeSeriesLengthModulated, &details);
  if (!pipelineTimeSeriesLengthModulated) {
    logMessage(error, true, "Couldn't create TSLM compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  pipelineTimeSeriesResampling =
      device->newComputePipelineState(kernelTimeSeriesResampling, &details);
  if (!pipelineTimeSeriesResampling) {
    logMessage(error, true, "Couldn't create TSR compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  pipelineTimeSeriesMeanReduction =
      device->newComputePipelineState(kernelTimeSeriesMeanReduction, &details);
  if (!pipelineTimeSeriesMeanReduction) {
    logMessage(error, true, "Couldn't create TSMR compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  pipelineTimeSeriesPadding = device->newComputePipelineState(kernelTimeSeriesPadding, &details);
  if (!pipelineTimeSeriesPadding) {
    logMessage(error, true, "Couldn't create TSP compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  // sanity check
  NS::UInteger threadGroupSizeTSMR =
      pipelineTimeSeriesMeanReduction->maxTotalThreadsPerThreadgroup();
  if (threadGroupSizeTSMR > params->nsamples) {
    threadGroupSizeTSMR = params->nsamples;
  }
  if (params->nsamples % threadGroupSizeTSMR != 0) {
    logMessage(
        error, true,
        "The time series length %i isn't an integer multiple of the TSMR thread group size %i!\n",
        params->nsamples_unpadded, threadGroupSizeTSMR);
    return (RADPUL_EVAL);
  }

  // allocate device memory for original time series (not copied since source is heap-based)
  originalTimeSeriesDeviceBuffer =
      device->newBuffer(input_dip.host_ptr, params->nsamples_unpadded * sizeof(float),
                        MTL::ResourceStorageModeShared, NULL);
  if (!originalTimeSeriesDeviceBuffer) {
    logMessage(error, true, "Error allocating original time series device memory: %i bytes\n",
               sizeof(float) * params->nsamples_unpadded);
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true,
             "Allocated original time series (%u samples, unpadded) device memory: %i bytes\n",
             params->nsamples_unpadded, sizeof(float) * params->nsamples_unpadded);

  // allocate device memory for sin/cos lookup table (copied since source is stack-based)
  sinLUTDeviceBuffer = device->newBuffer(sinLUTsamples, ERP_SINCOS_LUT_SIZE * sizeof(float),
                                         MTL::ResourceStorageModeShared);
  if (!sinLUTDeviceBuffer) {
    logMessage(error, true, "Error allocating sin lookup table device memory: %i bytes\n",
               ERP_SINCOS_LUT_SIZE * sizeof(float));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated sin lookup table device memory: %i bytes\n",
             ERP_SINCOS_LUT_SIZE * sizeof(float));

  cosLUTDeviceBuffer = device->newBuffer(cosLUTsamples, ERP_SINCOS_LUT_SIZE * sizeof(float),
                                         MTL::ResourceStorageModeShared);
  if (!cosLUTDeviceBuffer) {
    logMessage(error, true, "Error allocating cos lookup table device memory: %i bytes\n",
               ERP_SINCOS_LUT_SIZE * sizeof(float));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated cos lookup table device memory: %i bytes\n",
             ERP_SINCOS_LUT_SIZE * sizeof(float));

  // allocate device memory for modulation time offsets
  modTimeOffsetsDeviceBuffer =
      device->newBuffer(params->nsamples_unpadded * sizeof(float), MTL::ResourceStorageModeShared);
  if (!modTimeOffsetsDeviceBuffer) {
    logMessage(error, true, "Error allocating modulated time offsets device memory: %i bytes\n",
               sizeof(float) * params->nsamples_unpadded);
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated modulated time offsets device memory: %i bytes\n",
             sizeof(float) * params->nsamples_unpadded);

  // allocate device memory for modulated time series length
  timeSeriesLengthDeviceBuffer =
      device->newBuffer(sizeof(unsigned int), MTL::ResourceStorageModeShared);
  if (!timeSeriesLengthDeviceBuffer) {
    logMessage(error, true,
               "Error allocating modulated time series length device memory: %i bytes\n",
               sizeof(int));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated modulated time series length device memory: %i bytes\n",
             sizeof(int));

  // allocate device memory for resampled time series
  // TODO: is this true? (we need twice the amount of samples as buffer because of the fake C2C FFT
  // input (split-complex)
  resampledTimeSeriesDeviceBuffer =
      device->newBuffer(2 * params->nsamples * sizeof(float), MTL::ResourceStorageModeShared);
  if (!resampledTimeSeriesDeviceBuffer) {
    logMessage(error, true, "Error allocating modulated time series device memory: %i bytes\n",
               2 * params->nsamples_unpadded * sizeof(float));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated modulated time series device memory: %i bytes\n",
             2 * params->nsamples_unpadded * sizeof(float));

  // allocate device memory for time series mean sum reduction
  timeSeriesMeanDeviceBuffer = device->newBuffer(sizeof(float), MTL::ResourceStorageModeShared);
  if (!timeSeriesMeanDeviceBuffer) {
    logMessage(error, true,
               "Error allocating modulated time series mean reduction device memory: %i bytes\n",
               sizeof(float));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated time series mean reduction device memory: %i bytes\n",
             sizeof(float));

  return 0;
}

int run_resampling(DIfloatPtr input_dip, DIfloatPtr output_dip, const RESAMP_PARAMS *const params) {
  MTL::CommandBuffer *commandBuffer = queue->commandBuffer();
  MTL::ComputeCommandEncoder *encoder = commandBuffer->computeCommandEncoder();

  // output variables
  unsigned int n_steps = 0;
  float mean = 0.0f;

  // compute time offsets

  logMessage(debug, true, "Executing time series modulation OpenCL kernel %lu times...\n",
             params->nsamples_unpadded);

  encoder->setComputePipelineState(pipelineTimeSeriesModulation);
  encoder->setBuffer(sinLUTDeviceBuffer, 0, 0);
  encoder->setBuffer(cosLUTDeviceBuffer, 0, 1);
  encoder->setBytes(&params->tau, sizeof(params->tau), 2);
  encoder->setBytes(&params->Omega, sizeof(params->Omega), 3);
  encoder->setBytes(&params->Psi0, sizeof(params->Psi0), 4);
  encoder->setBytes(&params->dt, sizeof(params->dt), 5);
  encoder->setBytes(&params->step_inv, sizeof(params->step_inv), 6);
  encoder->setBytes(&params->S0, sizeof(params->S0), 7);
  encoder->setBuffer(modTimeOffsetsDeviceBuffer, 0, 8);

  MTL::Size gridSize = MTL::Size(params->nsamples_unpadded, 1, 1);
  NS::UInteger threadGroupSize = pipelineTimeSeriesModulation->maxTotalThreadsPerThreadgroup();
  if (threadGroupSize > params->nsamples_unpadded) {
    threadGroupSize = params->nsamples_unpadded;
  }
  MTL::Size threadgroupSize = MTL::Size(threadGroupSize, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal TSM kernel execution successful...\n");

  // compute modulated time series length

  logMessage(debug, true,
             "Executing modulated time series length Metal kernel (single work item)...\n");

  commandBuffer = queue->commandBuffer();
  encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(pipelineTimeSeriesLengthModulated);
  encoder->setBytes(&params->nsamples_unpadded, sizeof(params->nsamples_unpadded), 0);
  encoder->setBuffer(modTimeOffsetsDeviceBuffer, 0, 1);
  encoder->setBuffer(timeSeriesLengthDeviceBuffer, 0, 2);

  gridSize = MTL::Size(1, 1, 1);
  threadgroupSize = MTL::Size(1, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal TSLM kernel execution successful...\n");
  n_steps = *(unsigned int *)timeSeriesLengthDeviceBuffer->contents();
  logMessage(debug, true, "Modulated time series length: %u\n", n_steps);

  // compute resampled time series (unpadded)

  commandBuffer = queue->commandBuffer();
  encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(pipelineTimeSeriesResampling);
  encoder->setBuffer(originalTimeSeriesDeviceBuffer, 0, 0);
  encoder->setBuffer(modTimeOffsetsDeviceBuffer, 0, 1);
  encoder->setBytes(&n_steps, sizeof(n_steps), 2);
  encoder->setBuffer(resampledTimeSeriesDeviceBuffer, 0, 3);

  gridSize = MTL::Size(2 * params->nsamples, 1, 1);
  threadGroupSize = pipelineTimeSeriesResampling->maxTotalThreadsPerThreadgroup();
  if (threadGroupSize > gridSize.width) {
    threadGroupSize = gridSize.width;
  }
  threadgroupSize = MTL::Size(threadGroupSize, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);

  logMessage(debug, true, "Executing time series resampling Metal kernel %lu times...\n",
             gridSize.width);

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal TSR kernel execution successful...\n");

  // compute time series mean value

  logMessage(debug, true, "Executing time series mean reduction Metal kernel...\n");

  // determine required threadgroup memory
  threadGroupSize = pipelineTimeSeriesMeanReduction->maxTotalThreadsPerThreadgroup();
  NS::UInteger simdSize = pipelineTimeSeriesMeanReduction->threadExecutionWidth();
  NS::UInteger simdGroups = threadGroupSize / simdSize;

  commandBuffer = queue->commandBuffer();
  encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(pipelineTimeSeriesMeanReduction);
  encoder->setBuffer(resampledTimeSeriesDeviceBuffer, 0, 0);
  encoder->setBuffer(timeSeriesMeanDeviceBuffer, 0, 1);
  encoder->setBytes(&simdGroups, sizeof(NS::UInteger), 2);
  encoder->setThreadgroupMemoryLength(simdGroups, 0);

  gridSize = MTL::Size(params->nsamples_unpadded, 1, 1);

  threadgroupSize = MTL::Size(threadGroupSize, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);
  logMessage(debug, true, "threads: %ld / groupsize: %ld / simdsize: %ld\n", gridSize.width,
             threadGroupSize, pipelineTimeSeriesMeanReduction->threadExecutionWidth());

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal TSMR kernel execution successful...\n");

  // store and reset mean device buffer to 0 (since kernel always adds to it!)
  mean = *(float *)timeSeriesMeanDeviceBuffer->contents();
  *((float *)timeSeriesMeanDeviceBuffer->contents()) = 0.0;
  logMessage(debug, true, "The time series sum is: %f\n", mean);

  // compute actual mean
  mean /= n_steps;
  logMessage(debug, true, "The time series mean is: %e\n", mean);

  // time series mean paddding

  logMessage(debug, true, "Executing time series mean padding Metal kernel...\n");

  commandBuffer = queue->commandBuffer();
  encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(pipelineTimeSeriesPadding);
  encoder->setBuffer(resampledTimeSeriesDeviceBuffer, 0, 0);
  encoder->setBytes(&mean, sizeof(mean), 1);
  encoder->setBytes(&n_steps, sizeof(n_steps), 2);

  gridSize = MTL::Size(params->nsamples, 1, 1);
  threadGroupSize = pipelineTimeSeriesPadding->maxTotalThreadsPerThreadgroup();
  if (threadGroupSize > gridSize.width) {
    threadGroupSize = gridSize.width;
  }
  threadgroupSize = MTL::Size(threadGroupSize, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal TSP kernel execution successful...\n");

  return 0;
}

int tear_down_resampling(DIfloatPtr output_dip) {
  originalTimeSeriesDeviceBuffer->release();
  sinLUTDeviceBuffer->release();
  cosLUTDeviceBuffer->release();
  modTimeOffsetsDeviceBuffer->release();
  timeSeriesLengthDeviceBuffer->release();
  resampledTimeSeriesDeviceBuffer->release();
  timeSeriesMeanDeviceBuffer->release();

  return 0;
}

int set_up_fft(DIfloatPtr input, DIfloatPtr *output, uint32_t nsamples, unsigned int fft_size) {
  // configure VkFFT
  configuration.FFTdim = 1;
  configuration.size[0] = nsamples;
  configuration.performR2C = true;
  configuration.device = device;
  configuration.queue = queue;

  VkFFTResult res = initializeVkFFT(&app, configuration);
  if (res != VKFFT_SUCCESS) {
    logMessage(error, true, "Couldn't initialize VkFFT! Error: %i\n", res);
    return (RADPUL_EMEM);
  }
  logMessage(debug, true, "VkFFT initialized...\n");

  NS::Error *details = NULL;
  pipelinePowerspectrum = device->newComputePipelineState(kernelPowerspectrum, &details);
  if (!pipelinePowerspectrum) {
    logMessage(error, true, "Couldn't create PS compute pipeline!\n");
    return RADPUL_METAL_PIPELINE_CREATE;
  }

  // twice the fft size to hold the real input AND the complex output (on the device)
  bufferSize = (uint64_t)sizeof(float) * 2 * fft_size;
  deviceBuffer = device->newBuffer(bufferSize, MTL::ResourceStorageModePrivate);
  if (!deviceBuffer) {
    logMessage(
        error, true,
        "Couldn't allocate %u bytes of GPU memory for FFT buffer (available: %u)! Error: %i\n",
        bufferSize, device->maxBufferLength());
    return (RADPUL_EMEM);
  }
  logMessage(debug, true, "Allocated FFT buffer device memory: %i bytes\n", bufferSize);

  launchParams.buffer = &deviceBuffer;

  // allocate device memory for the periodogram
  powerspectrumDeviceBuffer =
      device->newBuffer(fft_size * sizeof(float), MTL::ResourceStorageModeShared);
  if (!powerspectrumDeviceBuffer) {
    logMessage(error, true, "Error allocating periodogram device memory: %i bytes\n",
               fft_size * sizeof(float));
    return (RADPUL_METAL_MEM_ALLOC_DEVICE);
  }
  logMessage(debug, true, "Allocated periodogram device memory: %i bytes\n",
             fft_size * sizeof(float));

  // allocate host memory for the periodogram
  output->host_ptr = (float *)calloc(fft_size, sizeof(float));

  if (output->host_ptr == NULL) {
    logMessage(error, true, "Couldn't allocate %d bytes of memory for power spectrum.\n",
               fft_size * sizeof(float));
    return (RADPUL_EMEM);
  }

  // finally: check memory footprint
  // TODO: ensure this is always done in the final set_up_* function
  NS::UInteger deviceMemoryOptimalMax = device->recommendedMaxWorkingSetSize();
  NS::UInteger deviceMemoryCurrent = device->currentAllocatedSize();
  float mib = 1024.0 * 1024.0;
  if (deviceMemoryCurrent > deviceMemoryOptimalMax) {
    logMessage(warn, true,
               "Allocated GPU memory of %.1f MiB exceeds recommended maximum of %.1f MiB!\n",
               deviceMemoryCurrent / mib, deviceMemoryOptimalMax / mib);
  }
  else {
    logMessage(debug, true, "Allocated %.1f MiB of GPU memory (recommended maximum: %.1f MiB)\n",
               deviceMemoryCurrent / mib, deviceMemoryOptimalMax / mib);
  }

  return 0;
}

int run_fft(DIfloatPtr input,
            DIfloatPtr output,
            uint32_t nsamples,
            unsigned int fft_size,
            float norm_factor) {
  // transfer data from CPU to GPU
  // TODO: don't copy device->deivce!
  MTL::CommandBuffer *copyCommandBuffer = queue->commandBuffer();
  if (copyCommandBuffer == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  MTL::BlitCommandEncoder *blitCommandEncoder = copyCommandBuffer->blitCommandEncoder();
  if (blitCommandEncoder == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  blitCommandEncoder->copyFromBuffer(resampledTimeSeriesDeviceBuffer, 0, deviceBuffer, 0,
                                     bufferSize);
  blitCommandEncoder->endEncoding();
  copyCommandBuffer->commit();
  copyCommandBuffer->waitUntilCompleted();
  blitCommandEncoder->release();
  copyCommandBuffer->release();

  // run FFT
  MTL::CommandBuffer *commandBuffer = queue->commandBuffer();
  if (commandBuffer == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  launchParams.commandBuffer = commandBuffer;
  MTL::ComputeCommandEncoder *commandEncoder = commandBuffer->computeCommandEncoder();
  if (commandEncoder == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  launchParams.commandEncoder = commandEncoder;
  VkFFTResult res = VkFFTAppend(&app, -1, &launchParams);
  commandEncoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  commandEncoder->release();
  commandBuffer->release();

  // transfer from GPU to CPU
  MTL::Buffer *stagingBuffer = device->newBuffer(bufferSize, MTL::ResourceStorageModeShared);
  copyCommandBuffer = queue->commandBuffer();
  if (copyCommandBuffer == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  blitCommandEncoder = copyCommandBuffer->blitCommandEncoder();
  if (blitCommandEncoder == 0) return VKFFT_ERROR_FAILED_TO_CREATE_COMMAND_LIST;
  blitCommandEncoder->copyFromBuffer(deviceBuffer, 0, stagingBuffer, 0, bufferSize);
  blitCommandEncoder->endEncoding();
  copyCommandBuffer->commit();
  copyCommandBuffer->waitUntilCompleted();
  blitCommandEncoder->release();
  copyCommandBuffer->release();

  // compute powerspectrum

  logMessage(debug, true, "Executing powerspectrum Metal kernel...\n");

  commandBuffer = queue->commandBuffer();
  MTL::ComputeCommandEncoder *encoder = commandBuffer->computeCommandEncoder();
  encoder->setComputePipelineState(pipelinePowerspectrum);
  encoder->setBuffer(stagingBuffer, 0, 0);
  encoder->setBuffer(powerspectrumDeviceBuffer, 0, 1);
  encoder->setBytes(&norm_factor, sizeof(norm_factor), 2);

  MTL::Size gridSize = MTL::Size(fft_size, 1, 1);
  NS::UInteger threadGroupSize = pipelinePowerspectrum->maxTotalThreadsPerThreadgroup();
  if (threadGroupSize > gridSize.width) {
    threadGroupSize = gridSize.width;
  }
  MTL::Size threadgroupSize = MTL::Size(threadGroupSize, 1, 1);
  encoder->dispatchThreads(gridSize, threadgroupSize);

  encoder->endEncoding();
  commandBuffer->commit();
  commandBuffer->waitUntilCompleted();
  encoder->release();
  commandBuffer->release();

  logMessage(debug, true, "Metal PS kernel execution successful...\n");

  stagingBuffer->release();

  memcpy(output.host_ptr, powerspectrumDeviceBuffer->contents(), fft_size * sizeof(float));

  // set DC power to 0
  output.host_ptr[0] = 0.0f;

  return 0;
}

int tear_down_fft(DIfloatPtr output) {
  deviceBuffer->release();
  powerspectrumDeviceBuffer->release();
  deleteVkFFT(&app);
  free(output.host_ptr);

  return 0;
}

int shutdown_metal() {
  logMessage(info, true, "Metal shutdown complete!\n");
  return 0;
}
