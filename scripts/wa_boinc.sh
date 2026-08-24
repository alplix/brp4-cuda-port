#!/usr/bin/env bash
set -e
export PATH=/opt/llvm-mingw/bin:$PATH
T=aarch64-w64-mingw32
SRC=/root/build/3rdparty/boinc-current_brp_apps
INST=/root/wa/brp4-install-arm64
mkdir -p $INST/lib $INST/include/boinc
cp "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/compat/mingw_str_shim.h" /root/wa/inc_shim.h
XF_CPP='CPPFLAGS=-I/root/wa -I../win_build -I.. -I../api -include /root/wa/inc_shim.h'
XF_CXX='CXXFLAGS=-O2 -DNDEBUG -w -std=gnu++14'
cd $SRC/lib
make -f Makefile.mingw MINGW=$T clean >/dev/null 2>&1 || true
# ARM64-Windows cannot build the x86-only stackwalker_win.cpp -> override LIB_OBJ without it
LIB_OBJ_NO_SW='app_ipc.o base64.o coproc.o diagnostics.o diagnostics_win.o filesys.o hostinfo.o md5.o md5_file.o mem_usage.o mfile.o miofile.o opencl_boinc.o procinfo_win.o procinfo.o proc_control.o parse.o prefs.o proxy_info.o str_util.o shmem.o url.o util.o win_util.o wslinfo.o'
make -f Makefile.mingw MINGW=$T libboinc.a -j$(nproc) "$XF_CPP" "$XF_CXX" "LIB_OBJ=$LIB_OBJ_NO_SW" >/dev/null
# add ARM64 stackwalker stand-ins (StackwalkThread + StackwalkFilter)
$T-g++ -O2 -DNDEBUG -w -std=gnu++14 -I.. -I../lib "/mnt/c/Users/Alp/Documents/Default Project/brp4-cuda-port/src/compat/stackwalker_arm64_stub.cpp" -c -o /root/wa/sw_stub.o
$T-ar r libboinc.a /root/wa/sw_stub.o
$T-ranlib libboinc.a
ls -la libboinc.a
cd $SRC/api
$T-g++ -O2 -DNDEBUG -w -std=gnu++14 -I/root/wa -I../win_build -I.. -I../api -I../lib -include /root/wa/inc_shim.h -c boinc_api.cpp -o boinc_api.o
$T-g++ -O2 -DNDEBUG -w -std=gnu++14 -I/root/wa -I../win_build -I.. -I../api -I../lib -include /root/wa/inc_shim.h -c graphics2_util.cpp -o graphics2_util.o
$T-ar rcs libboinc_api.a boinc_api.o graphics2_util.o
ls -la libboinc_api.a

cp $SRC/lib/libboinc.a $SRC/api/libboinc_api.a $INST/lib/
# headers: same set the x86 windows install used
cp $SRC/version.h* $INST/include/boinc/ 2>/dev/null || true
cp $SRC/svn_version.h* $INST/include/boinc/ 2>/dev/null || true
cp $SRC/win_build/config.h $INST/include/boinc/
for h in app_ipc boinc_win url common_defs diagnostics diagnostics_win error_numbers \
         filesys hostinfo proxy_info prefs miofile mfile parse util coproc \
         str_util wslinfo base64; do cp $SRC/lib/$h.h $INST/include/boinc/ 2>/dev/null || true; done
for h in boinc_api boinc_opencl graphics2 graphics2_util; do cp $SRC/api/$h.h $INST/include/boinc/ 2>/dev/null || true; done
cp $SRC/lib/*.h $INST/include/boinc/ 2>/dev/null || true
echo "--- built:"
ls -la $INST/lib/
file $INST/lib/libboinc.a | cut -d, -f1-3
