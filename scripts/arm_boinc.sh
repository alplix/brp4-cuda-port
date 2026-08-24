#!/usr/bin/env bash
set -e
SRC=/root/build/3rdparty/boinc-current_brp_apps
BLD=/root/build/boinc-arm64
INST=/root/build/brp4-install-arm64
mkdir -p $BLD $INST/lib $INST/include/boinc

CXX=aarch64-linux-gnu-g++-14
FLAGS="-O2 -I $SRC -I $BLD -I ../ -I . -std=gnu++11 -Wno-deprecated-declarations -fPIC"

cd $SRC/lib
OBJS="app_ipc base64 cc_config cert_sig coproc crypt diagnostics filesys \
hostinfo keyword md5 md5_file mem_usage mfile miofile msg_log msg_queue \
network notice opencl_boinc parse prefs proc_control procinfo procinfo_unix \
project_init proxy_info shmem synch str_util url util"
rm -f libboinc_arm64.a
for o in $OBJS; do
  $CXX $FLAGS -c $o.cpp -o /tmp/$o.a64.o
  ar rcs libboinc_arm64.a /tmp/$o.a64.o
done
# api side
cd $SRC/api
$CXX -O2 -I $SRC -I $BLD -I ../ -I . -I../lib -std=gnu++11 -Wno-deprecated-declarations -fPIC -c boinc_api.cpp -o /tmp/boinc_api.a64.o
$CXX -O2 -I $SRC -I $BLD -I ../ -I . -I../lib -std=gnu++11 -Wno-deprecated-declarations -fPIC -c graphics2_util.cpp -o /tmp/graphics2_util.a64.o
ar rcs $SRC/lib/libboinc_api_arm64.a /tmp/boinc_api.a64.o /tmp/graphics2_util.a64.o

cp $SRC/lib/libboinc_arm64.a $INST/lib/
cp $SRC/lib/libboinc_api_arm64.a $INST/lib/
cp $SRC/lib/*.h $INST/include/boinc/
cp $SRC/api/*.h $INST/include/boinc/
cp $SRC/config.h $INST/include/boinc/
cp $SRC/version.h* $INST/include/boinc/ 2>/dev/null || true
echo "--- arm64 boinc libs:"
ls -la $INST/lib/
file $INST/lib/libboinc_arm64.a | cut -d, -f2
