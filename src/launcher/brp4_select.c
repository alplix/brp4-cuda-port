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
static int own_dir(char *dir, size_t dirLen) {
  wchar_t wdir[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, wdir, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return -1;
  wchar_t *cut = wcsrchr(wdir, L'\\');
  wchar_t *cut2 = wcsrchr(wdir, L'/');
  if (cut2 > cut) cut = cut2;
  if (cut == NULL) return -1;
  *cut = L'\0';
  int m = WideCharToMultiByte(CP_UTF8, 0, wdir, -1, dir, (int)dirLen, NULL, NULL);
  return (m > 0) ? 0 : -1;
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

/* read a single-tag value out of init_data.xml (e.g. "<project_dir>") */
static int read_init_data_tag(const char *tag, char *out, size_t outLen) {
  FILE *f = fopen("init_data.xml", "r");
  if (f == NULL) return -1;
  char line[1024];
  int found = -1;
  while (fgets(line, sizeof(line), f) != NULL) {
    char *p = strstr(line, tag);
    if (p != NULL) {
      char *open = strchr(p, '>');   /* the tag's own closing '>' */
      if (open != NULL) {
        char *close = strchr(open + 1, '<');
        if (close != NULL && close > open + 1) {
          size_t n = (size_t)(close - open - 1);
          if (n >= outLen) n = outLen - 1;
          memcpy(out, open + 1, n);
          out[n] = '\0';
          found = 0;
        }
      }
      break;
    }
  }
  fclose(f);
  return found;
}

/* does this path exist as a runnable file? */
static int file_ok(const char *path) {
#ifdef _WIN32
  DWORD attr = GetFileAttributesA(path);
  return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
#else
  return access(path, X_OK) == 0;
#endif
}

/* strip the last path component: "proj/slots/3" -> "proj/slots" */
static void parent_dir(const char *in, char *out, size_t outLen) {
  size_t len = strlen(in);
  while (len > 1 && (in[len - 1] == '/' || in[len - 1] == '\\')) len--;
  size_t s = len;
  while (s > 0 && in[s - 1] != '/' && in[s - 1] != '\\') s--;
  if (s == 0) {
    snprintf(out, outLen, "%s", in);
    return;
  }
  size_t keep = (s == 1) ? 1 : s - 1;
  if (keep >= outLen) keep = outLen - 1;
  memcpy(out, in, keep);
  out[keep] = '\0';
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

  /* Where is the era binary? BOINC hardlinks/copies only the MAIN program
   * (this router) and file_ref'd files into the slot directory - the other
   * era builds stay in the project directory. Search, in order:
     1. the launcher's own directory            (standalone runs)
     2. its parent                              (BOINC: <project>/slots/<n> -> <project>)
     3. <project_dir> from init_data.xml        (authoritative BOINC answer)
     4. the current working directory */
  enum { MAX_DIRS = 4 };
  char dirs[MAX_DIRS][4096];
  int ndirs = 0;
  char self[4096];
  if (own_dir(self, sizeof(self)) == 0) {
    snprintf(dirs[ndirs++], sizeof(dirs[0]), "%s", self);
    char par[4096];
    parent_dir(self, par, sizeof(par));
    if (par[0] != '\0' && strcmp(par, self) != 0 && ndirs < MAX_DIRS)
      snprintf(dirs[ndirs++], sizeof(dirs[0]), "%s", par);
  }
  char pdir[4096] = {0};
  if (read_init_data_tag("<project_dir>", pdir, sizeof(pdir)) == 0 &&
      pdir[0] != '\0' && ndirs < MAX_DIRS)
    snprintf(dirs[ndirs++], sizeof(dirs[0]), "%s", pdir);
  if (ndirs < MAX_DIRS)
    snprintf(dirs[ndirs++], sizeof(dirs[0]), "%s", ".");

  char exePath[8192] = {0};
  char bname[128];
  snprintf(bname, sizeof(bname), "%s", binary);
  int found = 0, di;
  for (di = 0; di < ndirs; di++) {
    snprintf(exePath, sizeof(exePath), "%s/%s", dirs[di], bname);
    if (file_ok(exePath)) {
      found = 1;
      break;
    }
  }
  if (!found) {
    fprintf(stderr, "brp4_select: cannot find %s in any of:\n", binary);
    for (di = 0; di < ndirs; di++)
      fprintf(stderr, "  %s\n", dirs[di]);
    return 1;
  }

  if (ccMaj > 0) {
    fprintf(stderr, "brp4_select: %s (CC %d.%d) -> %s build\n",
            devName, ccMaj, ccMin, flavor);
  } else {
    fprintf(stderr, "brp4_select: BRP4_BUILD=%s override -> %s build\n",
            flavor, flavor);
  }

#ifdef _WIN32
  wchar_t wexePath[8192];
  MultiByteToWideChar(CP_UTF8, 0, exePath, -1, wexePath, 8192);

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
  size_t cmdLen = lstrlenW(wexePath) + 3 + lstrlenW(args);
  wchar_t *cmdLine = (wchar_t *)malloc(cmdLen * sizeof(wchar_t));
  if (cmdLine == NULL) return 1;
  _snwprintf(cmdLine, cmdLen - 1, L"\"%ls\" %ls", wexePath, args);
  cmdLine[cmdLen - 1] = L'\0';

  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  if (!CreateProcessW(wexePath, cmdLine, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    fprintf(stderr, "brp4_select: cannot launch %s (Win32 error %lu)\n",
            exePath, (unsigned long)GetLastError());
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
  execv(exePath, argv);
  fprintf(stderr, "brp4_select: cannot launch %s (errno %d: %s)\n",
          exePath, errno, strerror(errno));
  return 1;
#endif
}
