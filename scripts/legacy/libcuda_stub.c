/* Minimal libcuda.so.1 stand-in so a cross-built aarch64 binary can load
 * under qemu-user on a host with no real NVIDIA driver installed for that
 * architecture (--help / smoke testing only -- every function just returns
 * CUDA_ERROR_NOT_SUPPORTED (999); nothing here is meant to run real work). */
typedef int CUresult;
#define CUDA_ERROR_NOT_SUPPORTED 999

#define STUB(name) CUresult name() { return CUDA_ERROR_NOT_SUPPORTED; }

STUB(cuInit)
STUB(cuDeviceGet)
STUB(cuDeviceGetCount)
STUB(cuDeviceGetAttribute)
STUB(cuDeviceGetName)
STUB(cuDeviceTotalMem_v2)
STUB(cuDriverGetVersion)
STUB(cuCtxCreate_v2)
STUB(cuCtxDestroy_v2)
STUB(cuCtxSynchronize)
STUB(cuLaunchKernel)
STUB(cuMemAlloc_v2)
STUB(cuMemAllocHost_v2)
STUB(cuMemFree_v2)
STUB(cuMemFreeHost)
STUB(cuMemGetInfo_v2)
STUB(cuMemcpyHtoD_v2)
STUB(cuMemcpyDtoH_v2)
STUB(cuMemcpyHtoDAsync_v2)
STUB(cuMemcpyDtoHAsync_v2)
STUB(cuMemsetD32Async)
STUB(cuModuleLoad)
STUB(cuModuleLoadData)
STUB(cuModuleGetFunction)
STUB(cuModuleGetGlobal_v2)
STUB(cuStreamCreate)
STUB(cuStreamDestroy_v2)
