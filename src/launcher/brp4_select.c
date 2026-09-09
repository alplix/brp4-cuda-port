/***************************************************************************
 *   BRP4 CUDA port - GPU generation router launcher                       *
 *   Coded by Alperen Yavuz.                                               *
 *   Part of the unofficial BRP4 CUDA port (GPLv2+ like upstream).         *
 *                                                                         *
 *   Probes the installed NVIDIA driver for the highest compute            *
 *   capability present and execs (Linux) / spawns (Windows) the matching  *
 *   era binary from the same directory:                                   *
 *                                                                         *
 *     CC 2.x        ->  fermi build   (CUDA 8.0,  driver 391+)            *
 *                       GTX 400/500, GT 610/620/630 (GF108/GF119)         *
 *     CC 3.x        ->  kepler build  (CUDA 10.2, driver 470+)            *
 *                       GTX 600/700, GT 710/720/730/740, Titan/Titan Black*
 *     CC 5.x - 12.x ->  modern build  (CUDA 12.9, driver 575+)            *
 *                       GTX 900/1000 up to RTX 50 series                  *
 *                                                                         *
 *   On a mixed-generation rig the GPU with the highest compute capability *
 *   wins (that is also the device the application itself prefers).        *
 *   Set BRP4_BUILD=modern|kepler|fermi to override the automatic choice.  *
 *                                                                         *
 *   The launcher keeps the same PID (Linux execv) or stays in the BOINC   *
 *   job object (Windows) and forwards the child's exit code, so BOINC     *
 *   suspend/quit/abort semantics are unchanged.                           *
 ***************************************************************************/

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#include <unistd.h>
#endif

/* driver API types (kept local so we do not need cuda.h at build time) */
typedef int CUdevice;
typedef int CUresult;
#define CU_SUCCESS 0
/* CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR/MINOR - stable since CUDA 3.0 */
#define CU_ATTR_CC_MAJOR 75
#define CU_ATTR_CC_MINOR 76

typedef CUresult (*pfn_cuInit)(unsigned int);
typedef CUresult (*pfn_cuDeviceGetCount)(int *);
typedef CUresult (*pfn_cuDeviceGet)(CUdevice *, int);
typedef CUresult (*pfn_cuDeviceGetAttribute)(int *, int, CUdevice);

typedef struct {
#ifdef _WIN32
  HMODULE lib;
#else
  void *lib;
#endif
  pfn_cuInit init;
  pfn_cuDeviceGetCount getCount;
  pfn_cuDeviceGet get;
  pfn_cuDeviceGetAttribute getAttr;
} cuda_api;

static int cuda_api_load(cuda_api *api) {
  memset(api, 0, sizeof(*api));
#ifdef _WIN32
  api->lib = LoadLibraryW(L"nvcuda.dll");
  if (api->lib == NULL) return -1;
#define SYM(x) (pfn_##x)(void *)GetProcAddress(api->lib, #x)
#else
  api->lib = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
  if (api->lib == NULL) return -1;
#define SYM(x) (pfn_##x)(void *)dlsym(api->lib, #x)
#endif
  api->init = SYM(cuInit);
  api->getCount = SYM(cuDeviceGetCount);
  api->get = SYM(cuDeviceGet);
  api->getAttr = SYM(cuDeviceGetAttribute);
#undef SYM
  if (api->init == NULL || api->getCount == NULL || api->get == NULL ||
      api->getAttr == NULL) {
    return -1;
  }
  return 0;
}

/* highest compute capability across all visible devices (or of one specific
 * device when devIdx >= 0); returns 0 on success */
static int probe_best_cc(const cuda_api *api, int *majOut, int *minOut,
                         char *nameOut, size_t nameLen, int devIdx) {
  int count = 0;
  int bestMaj = -1, bestMin = -1;
  char bestName[256] = "?";
  CUresult r = api->init(0);
  if (r != CU_SUCCESS) {
    fprintf(stderr, "brp4_select: cuInit() failed with error %d - "
            "is the NVIDIA driver installed and the GPU visible?\n", r);
    return -1;
  }
  if (api->getCount(&count) != CU_SUCCESS || count < 1) {
    fprintf(stderr, "brp4_select: no CUDA-capable NVIDIA GPU found.\n");
    return -1;
  }
  int lo = 0, hi = count;
  if (devIdx >= 0) {
    if (devIdx >= count) {
      fprintf(stderr, "brp4_select: requested GPU device #%d but only %d "
              "CUDA device(s) present - falling back to device 0.\n",
              devIdx, count);
      devIdx = 0;
    }
    lo = devIdx;
    hi = devIdx + 1;
  }
  for (int i = lo; i < hi; i++) {
    CUdevice dev;
    int maj = 0, min = 0;
    char dname[256] = "?";
    if (api->get(&dev, i) != CU_SUCCESS) continue;
    if (api->getAttr(&maj, CU_ATTR_CC_MAJOR, dev) != CU_SUCCESS) continue;
    if (api->getAttr(&min, CU_ATTR_CC_MINOR, dev) != CU_SUCCESS) continue;
#ifdef _WIN32
    {
      typedef CUresult (*pfn_cuDeviceGetName)(char *, int, CUdevice);
      pfn_cuDeviceGetName getName =
          (pfn_cuDeviceGetName)(void *)GetProcAddress(api->lib, "cuDeviceGetName");
      if (getName != NULL) getName(dname, (int)sizeof(dname) - 1, dev);
    }
#else
    {
      typedef CUresult (*pfn_cuDeviceGetName)(char *, int, CUdevice);
      pfn_cuDeviceGetName getName =
          (pfn_cuDeviceGetName)(void *)dlsym(api->lib, "cuDeviceGetName");
      if (getName != NULL) getName(dname, (int)sizeof(dname) - 1, dev);
    }
#endif
    dname[sizeof(dname) - 1] = '\0';
    if (maj > bestMaj || (maj == bestMaj && min > bestMin)) {
      bestMaj = maj;
      bestMin = min;
      snprintf(bestName, sizeof(bestName), "%s", dname);
    }
  }
  if (bestMaj < 0) {
    fprintf(stderr, "brp4_select: could not read compute capability from any GPU.\n");
    return -1;
  }
  *majOut = bestMaj;
  *minOut = bestMin;
  if (nameOut != NULL && nameLen > 0) snprintf(nameOut, nameLen, "%s", bestName);
  return 0;
}

static const char *flavor_for_cc(int maj) {
  if (maj >= 5) return "modern";
  if (maj == 3) return "kepler";
  if (maj == 2) return "fermi";
  return NULL;
}

/* directory of this executable, without trailing separator */
#ifdef _WIN32
static int own_dir(wchar_t *dir, size_t dirChars) {
  DWORD n = GetModuleFileNameW(NULL, dir, (DWORD)dirChars);
  if (n == 0 || n >= dirChars) return -1;
  wchar_t *cut = wcsrchr(dir, L'\\');
  wchar_t *cut2 = wcsrchr(dir, L'/');
  if (cut2 > cut) cut = cut2;
  if (cut == NULL) return -1;
  *cut = L'\0';
  return 0;
}
#else
static int own_dir(char *dir, size_t dirLen) {
  ssize_t n = readlink("/proc/self/exe", dir, dirLen - 1);
  if (n <= 0) return -1;
  dir[n] = '\0';
  char *cut = strrchr(dir, '/');
  if (cut == NULL) return -1;
  *cut = '\0';
  return 0;
}
#endif

/* which GPU will the application itself run on?
 * 1) BOINC passes the assigned device via <gpu_device_num> in init_data.xml
 *    (same source the app reads - keeps mixed-generation rigs correct)
 * 2) a --device/-device command line argument (app's standalone flag)
 * 3) -1 = no preference: route by the highest compute capability present */
static int find_target_device(int argc, char **argv) {
  for (int i = 1; i < argc - 1; i++) {
    if (!strcmp(argv[i], "--device") || !strcmp(argv[i], "-device")) {
      int v = atoi(argv[i + 1]);
      if (v >= 0) return v;
    }
  }
  FILE *f = fopen("init_data.xml", "r");
  if (f == NULL) return -1;
  char line[512];
  int val = -1;
  while (fgets(line, sizeof(line), f) != NULL) {
    const char *p = strstr(line, "<gpu_device_num>");
    if (p != NULL) {
      val = atoi(p + strlen("<gpu_device_num>"));
      break;
    }
  }
  fclose(f);
  return val;
}

int main(int argc, char **argv) {
  const char *flavor = NULL;
  const char *override = NULL;
  int ccMaj = -1, ccMin = -1;
  char devName[256] = "?";
  cuda_api api;

#ifdef _WIN32
  char overrideBuf[32] = {0};
  if (GetEnvironmentVariableA("BRP4_BUILD", overrideBuf, sizeof(overrideBuf)) > 0) {
    override = overrideBuf;
  }
#else
  override = getenv("BRP4_BUILD");
#endif
  if (override != NULL && override[0] != '\0') {
    if (strcmp(override, "modern") && strcmp(override, "kepler") &&
        strcmp(override, "fermi")) {
      fprintf(stderr, "brp4_select: invalid BRP4_BUILD value '%s' "
              "(use modern|kepler|fermi)\n", override);
      return 2;
    }
    flavor = override;
  } else {
    if (cuda_api_load(&api) != 0) {
      fprintf(stderr, "brp4_select: could not load the CUDA driver library - "
              "is the NVIDIA driver installed?\n");
      return 1;
    }
    int targetDev = find_target_device(argc, argv);
    if (probe_best_cc(&api, &ccMaj, &ccMin, devName, sizeof(devName), targetDev) != 0) {
      return 1;
    }
    flavor = flavor_for_cc(ccMaj);
    if (flavor == NULL) {
      fprintf(stderr, "brp4_select: GPU '%s' has compute capability %d.%d. "
              "This package needs Fermi (CC 2.x) or newer - CC 1.x (Tesla) "
              "is not supported.\n", devName, ccMaj, ccMin);
      return 1;
    }
  }

  /* binary names live next to the launcher */
#ifdef _WIN32
  static const char *binaryNames[] = {
      "modern", "einsteinbinary_BRP4_windows_x86_64_cuda_custom.exe",
      "kepler", "einsteinbinary_BRP4_windows_x86_64_cuda102_kepler.exe",
      "fermi",  "einsteinbinary_BRP4_windows_x86_64_cuda80_fermi.exe",
      NULL, NULL};
#else
  static const char *binaryNames[] = {
      "modern", "einsteinbinary_BRP4_linux_x86_64_cuda_custom",
      "kepler", "einsteinbinary_BRP4_linux_x86_64_cuda102_kepler",
      "fermi",  "einsteinbinary_BRP4_linux_x86_64_cuda80_fermi",
      NULL, NULL};
#endif
  const char *binary = NULL;
  for (int i = 0; binaryNames[i] != NULL; i += 2) {
    if (!strcmp(binaryNames[i], flavor)) {
      binary = binaryNames[i + 1];
      break;
    }
  }

#ifdef _WIN32
  wchar_t dir[MAX_PATH];
  if (own_dir(dir, MAX_PATH) != 0) {
    fprintf(stderr, "brp4_select: cannot determine launcher directory.\n");
    return 1;
  }
  wchar_t wbinary[256];
  MultiByteToWideChar(CP_UTF8, 0, binary, -1, wbinary, 256);
  wchar_t exePath[MAX_PATH * 2];
  _snwprintf(exePath, sizeof(exePath) / sizeof(exePath[0]) - 1,
             L"%ls\\%ls", dir, wbinary);
  exePath[sizeof(exePath) / sizeof(exePath[0]) - 1] = L'\0';

  /* rebuild the command line: quoted child path + original arguments */
  LPCWSTR rawCmd = GetCommandLineW();
  LPCWSTR args = rawCmd;
  if (args[0] == L'"') {
    args++;
    while (*args != L'\0' && *args != L'"') args++;
    if (*args == L'"') args++;
  } else {
    while (*args != L'\0' && *args != L' ' && *args != L'\t') args++;
  }
  while (*args == L' ' || *args == L'\t') args++;
  size_t cmdLen = lstrlenW(exePath) + 3 + lstrlenW(args);
  wchar_t *cmdLine = (wchar_t *)malloc(cmdLen * sizeof(wchar_t));
  if (cmdLine == NULL) return 1;
  _snwprintf(cmdLine, cmdLen - 1, L"\"%ls\" %ls", exePath, args);
  cmdLine[cmdLen - 1] = L'\0';

  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  if (ccMaj > 0) {
    fprintf(stderr, "brp4_select: %s (CC %d.%d) -> %s build\n",
            devName, ccMaj, ccMin, flavor);
  } else {
    fprintf(stderr, "brp4_select: BRP4_BUILD=%s override -> %s build\n",
            flavor, flavor);
  }
  if (!CreateProcessW(exePath, cmdLine, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    fprintf(stderr, "brp4_select: cannot launch %s (Win32 error %lu) - "
            "is the file present next to the launcher?\n", binary,
            (unsigned long)GetLastError());
    free(cmdLine);
    return 1;
  }
  free(cmdLine);
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD exitCode = 1;
  GetExitCodeProcess(pi.hProcess, &exitCode);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return (int)exitCode;
#else
  char dir[4096];
  if (own_dir(dir, sizeof(dir)) != 0) {
    fprintf(stderr, "brp4_select: cannot determine launcher directory.\n");
    return 1;
  }
  static char exePath[4600];
  snprintf(exePath, sizeof(exePath), "%s/%s", dir, binary);
  if (flavor != NULL && ccMaj > 0) {
    fprintf(stderr, "brp4_select: %s (CC %d.%d) -> %s build\n",
            devName, ccMaj, ccMin, flavor);
  } else {
    fprintf(stderr, "brp4_select: BRP4_BUILD=%s override -> %s build\n",
            flavor, flavor);
  }
  execv(exePath, argv);
  {
    /* transient diagnostics: ENOENT on an existing file has happened in the
       field before - report exactly what the loader saw */
    char rp[4096] = {0};
    ssize_t rn = readlink("/proc/self/exe", rp, sizeof(rp) - 1);
    if (rn > 0) rp[rn] = '\0';
    fprintf(stderr, "brp4_select: cannot launch (errno %d: %s) - "
            "exePath=[%s] launcher=%s target access=%d\n",
            errno, strerror(errno), exePath, rp, access(exePath, X_OK) == 0);
  }
  return 1;
#endif
}
