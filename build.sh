#!/bin/bash

###########################################################################
#   Copyright (C) 2008-2023 by Oliver Behnke                              #
#   oliver.behnke[AT]aei.mpg.de                                           #
#                                                                         #
#   This file is part of Einstein@Home.                                   #
#                                                                         #
#   Einstein@Home is free software: you can redistribute it and/or modify #
#   it under the terms of the GNU General Public License as published     #
#   by the Free Software Foundation, version 2 of the License.            #
#                                                                         #
#   Einstein@Home is distributed in the hope that it will be useful,      #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the          #
#   GNU General Public License for more details.                          #
#                                                                         #
#   You should have received a copy of the GNU General Public License     #
#   along with Einstein@Home. If not, see <http://www.gnu.org/licenses/>. #
#                                                                         #
###########################################################################


### Globals ###############################################################


ROOT=`pwd`
PATH_ORG="$PATH"
PATH_MINGW="$PATH"
LOGFILE=$ROOT/build.log
ARCH=`uname -m`

# use SSE to avoid cross-platform precision issues
#export CFLAGS="-mfpmath=sse -msse $CFLAGS"
#export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

# NVIDIA CUDA compiler wrapper options
export NVCCFLAGS="-Xptxas -v -arch=compute_10 -code=compute_10 -g --verbose"

# component versions
BINUTILS_VERSION=2.42
GSL_VERSION=2.7
FFTW_VERSION=3.3.10
LIBXML_VERSION=2.12 LIBXML_REVISION=6
ZLIB_VERSION=1.3.1
OPENSSL_VERSION=1.1.1w
NDK_VERSION=r21d
NDK_PLATFORM=29
VKFFT_VERSION="1.3.4"
METALCPP_VERSION="macOS13.3_iOS16.4"

# git tags
TAG_APPS=${TAG_APPS_OVERRIDE:-"current_brp_apps"}
TAG_CLFFT=${TAG_CLFFT_OVERRIDE:-"current_brp_apps"}
TAG_DAEMONS="current_server"

# enum helper
function \
   _enum()
{
   ## void
   ## (
   ##    _IN $@ : [ array<string> ] list
   ## )

   local list=("$@")
   local len=${#list[@]}

   for (( i=0; i < $len; i++ )); do
      eval "${list[i]}=$i"
   done
}

# target enums
ENUM_TARGET=(
    TARGET
    TARGET_LINUX
    TARGET_LINUX_CUDA
    TARGET_LINUX_OCL
    TARGET_MAC
    TARGET_MAC_ARM
    TARGET_MAC_CUDA
    TARGET_MAC_OCL
    TARGET_MAC_ARM_OCL
    TARGET_MAC_MTL
    TARGET_MAC_ARM_MTL
    TARGET_MAC_ALTIVEC
    TARGET_MAC_PPC
    TARGET_WIN32
    TARGET_WIN32_CUDA
    TARGET_WIN32_OCL
    TARGET_DOC
    TARGET_DAEMONS
    TARGET_WIN64
    TARGET_WIN64_CUDA
    TARGET_WIN64_OCL
    TARGET_LINUX_ARMV6
    TARGET_ANDROID_ARM
    TARGET_LINUX_ARMV7
    TARGET_LINUX_NOBOINC=
) && _enum "${ENUM_TARGET[@]}"

ENUM_SUB_TARGET=(
    SUB_TARGET
    SUB_TARGET_ARMV6_VFP
    SUB_TARGET_ARMV7_NEON
    SUB_TARGET_ARMV7_NEON_PIE
    SUB_TARGET_LINUX_ARMV6_XCOMP
    SUB_TARGET_LINUX_ARMV7NEON_XCOMP
) && _enum "${ENUM_SUB_TARGET[@]}"

# buildstate enum
ENUM_BUILDSTATE=(
    BUILDSTATE
    BS_PREREQUISITES
    BS_PREPARE_TREE
    BS_BUILD_BINUTILS
    BS_BUILD_ZLIB
    BS_BUILD_GSL
    BS_BUILD_FFTW
    BS_BUILD_CLFFT
    BS_PREPARE_VKFFT
    BS_PREPARE_METALCPP
    BS_BUILD_LIBXML
    BS_BUILD_BOINC

    BS_PREPARE_MINGW
    BS_BUILD_MINGW
    BS_BUILD_BINUTILS_MINGW
    BS_BUILD_GSL_MINGW
    BS_BUILD_FFTW_MINGW
    BS_BUILD_CLFFT_MINGW
    BS_BUILD_LIBXML_MINGW
    BS_BUILD_BOINC_MINGW

    BS_PREPARE_NDK
    BS_BUILD_NDK
    BS_BUILD_BINUTILS_NDK
    BS_BUILD_ZLIB_NDK
    BS_BUILD_GSL_NDK
    BS_BUILD_FFTW_NDK
    BS_BUILD_LIBXML_NDK
    BS_BUILD_OPENSSL_NDK
    BS_BUILD_BOINC_NDK
) && _enum "${ENUM_BUILDSTATE[@]}"

BUILD_TYPE_NATIVE="native"
BUILD_TYPE_CROSS="cross"
BUILD_TYPE=$BUILD_TYPE_NATIVE


### Functions (Tools) #####################################################


failure()
{
    echo "************************************" | tee -a $LOGFILE
    echo "Error detected! Stopping build!" | tee -a $LOGFILE
    echo "`date`" | tee -a $LOGFILE

    if [ -f "$LOGFILE" ]; then
        echo "------------------------------------"
        echo "Please check logfile: `basename $LOGFILE`"
        echo "These are the final ten lines:"
        echo "------------------------------------"
        tail -n 15 $LOGFILE
    fi

    echo "************************************" | tee -a $LOGFILE

    exit 1
}

distclean()
{
    cd $ROOT || failure

    echo "Purging build system..." | tee -a $LOGFILE

    rm -rf 3rdparty || failure
    rm -rf build || failure
    rm -rf install || failure
    rm -rf doc/html || failure
    rm -f doc/*.tag || failure

    rm -f .lastbuild || failure
    rm -f .buildstate || failure

    return 0
}


check_last_build()
{
    LASTBUILD=`cat .lastbuild 2>/dev/null`

    if [[ ( -f .lastbuild ) && ( "$LASTBUILD" != "$1" ) ]]; then
        cd $ROOT || failure
        echo "Build target changed! Purging build and install trees..." | tee -a $LOGFILE
        rm -rf build >> $LOGFILE || failure
        rm -rf install >> $LOGFILE || failure
        rm -rf 3rdparty/boinc >> $LOGFILE || failure
        prepare_tree || failure
    fi

    echo "$1" > .lastbuild || failure

    return 0
}


check_build_state()
{
    echo "Checking for previous build checkpoints..." | tee -a $LOGFILE

    if [ ! -f .buildstate ]; then
        cd $ROOT || failure
        echo "No previous build checkpoints found! Starting from scratch..." | tee -a $LOGFILE
    else
        BUILDSTATE=`cat $ROOT/.buildstate 2>/dev/null`
        echo "Recovering previous build..."
    fi

    return 0
}


store_build_state()
{
    echo "Saving build checkpoint..." | tee -a $LOGFILE
    echo "$1" > $ROOT/.buildstate || failure

    return 0
}


### Functions (Features) ##################################################


check_prerequisites()
{
    if [ $BUILDSTATE -ge $BS_PREREQUISITES ]; then
        return 0
    fi

    echo "Checking prerequisites..." | tee -a $LOGFILE

    # required toolchain
    TOOLS="automake autoconf m4 curl git tar patch gcc g++ ld ar pkg-config"

    for tool in $TOOLS; do
        if ! ( type $tool >/dev/null 2>&1 ); then
            echo "Missing \"$tool\" which is a required tool!" | tee -a $LOGFILE
            return 1
        fi
    done

    if ! ( type libtoolize >/dev/null 2>&1 ) &&
       ! ( type glibtoolize >/dev/null 2>&1 ) &&
       ! ( type libtool >/dev/null 2>&1 )
    then
        echo "Missing \"libtool\" which is a required tool!" | tee -a $LOGFILE
        return 1
    fi

    store_build_state $BS_PREREQUISITES
    return 0
}


prepare_tree()
{
    if [ $BUILDSTATE -ge $BS_PREPARE_TREE ]; then
        return 0
    fi

    echo "Preparing tree..." | tee -a $LOGFILE
    mkdir -p 3rdparty >> $LOGFILE || failure
    mkdir -p install/bin >> $LOGFILE || failure
    mkdir -p install/include >> $LOGFILE || failure
    mkdir -p install/include/coff >> $LOGFILE || failure
    mkdir -p install/lib >> $LOGFILE || failure

    store_build_state $BS_PREPARE_TREE
    return 0
}

prepare_version_header()
{
    HEADER_FILE="$ROOT/src/erp_git_version.h"

    cd $ROOT || failure

    echo "Retrieving git version information..." | tee -a $LOGFILE

    if [ -d .git ]; then
        GIT_LOG=`git log -n1 --pretty="format:%H"` || failure
        HOST=`hostname` || failure
    fi

    echo "#ifndef ERP_GIT_VERSION_H" > $HEADER_FILE || failure
    echo "#define ERP_GIT_VERSION_H" >> $HEADER_FILE || failure
    echo "" >> $HEADER_FILE || failure

    if [ "no$GIT_LOG" != "no" ]; then
        echo "#define ERP_GIT_VERSION \"$GIT_LOG ($HOST:$PWD)\"" >> $HEADER_FILE || failure
    else
        echo "#define ERP_GIT_VERSION \"unknown (git repository not found!)\"" >> $HEADER_FILE || failure
    fi

    echo "" >> $HEADER_FILE || failure
    echo "#endif" >> $HEADER_FILE || failure
}


### Prepare 3rd party tools / libraries  ##################################


prepare_binutils()
{
    echo "Preparing binutils..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/binutils >> $LOGFILE || failure

    echo "Retrieving binutils $BINUTILS_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure

    rm -f binutils-$BINUTILS_VERSION.tar.bz2 >> $LOGFILE 2>&1 || failure
    curl https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.bz2 -o binutils-$BINUTILS_VERSION.tar.bz2 >> $LOGFILE 2>&1 || failure
    tar -xjf binutils-$BINUTILS_VERSION.tar.bz2 >> $LOGFILE 2>&1 || failure
    rm binutils-$BINUTILS_VERSION.tar.bz2 >> $LOGFILE 2>&1 || failure
    # substitute old source tree
    rm -rf binutils >> $LOGFILE 2>&1 || failure
    mv binutils-$BINUTILS_VERSION binutils >> $LOGFILE 2>&1 || failure

    return 0
}


prepare_zlib()
{
    echo "Preparing zlib..." | tee -a $LOGFILE

    echo "Retrieving zlib $ZLIB_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure

    curl https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz -o zlib-$ZLIB_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    tar -xzf zlib-$ZLIB_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    mkdir -p $ROOT/build >> $LOGFILE 2>&1 || failure
    cp -r zlib-$ZLIB_VERSION $ROOT/build >> $LOGFILE 2>&1 || failure
    sed s%/usr/bin/libtool%libtool% zlib-$ZLIB_VERSION/configure > $ROOT/build/zlib-$ZLIB_VERSION/configure 2>>$LOGFILE || failure
}


prepare_gsl()
{
    echo "Preparing GSL..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/gsl >> $LOGFILE || failure

    echo "Retrieving GSL $GSL_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure
    rm -f gsl-$GSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    curl https://ftp.gnu.org/gnu/gsl/gsl-$GSL_VERSION.tar.gz -o gsl-$GSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    tar -xzf gsl-$GSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    rm gsl-$GSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    # substitute old source tree
    rm -rf gsl >> $LOGFILE 2>&1 || failure
    mv gsl-$GSL_VERSION gsl >> $LOGFILE 2>&1 || failure

    return 0
}


prepare_fftw()
{
    echo "Preparing FFTW3..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/fftw >> $LOGFILE || failure

    echo "Retrieving FFTW3 $FFTW_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure
    rm -f fftw-$FFTW_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    curl ftp://ftp.fftw.org/pub/fftw/fftw-$FFTW_VERSION.tar.gz -o fftw-$FFTW_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    tar -xzf fftw-$FFTW_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    rm fftw-$FFTW_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    # substitute old source tree
    rm -rf fftw >> $LOGFILE 2>&1 || failure
    mv fftw-$FFTW_VERSION fftw >> $LOGFILE 2>&1 || failure

    return 0
}


prepare_clfft()
{
    echo "Preparing CLFFT..." | tee -a $LOGFILE
    mkdir -p $ROOT/3rdparty/libclfft >> $LOGFILE || failure

    cd $ROOT/3rdparty/libclfft || failure
    if [ -d .git ]; then
        echo "Updating CLFFT (tag: $1)..." | tee -a $LOGFILE
        # make sure local changes (patches) are reverted to ensure fast-forward merge
        git checkout -f $1 >> $LOGFILE  2>&1 || failure
        # update tag info
        git remote update >> $LOGFILE  2>&1 || failure
        git fetch --tags >> $LOGFILE  2>&1 || failure
        # checkout build revision
        git checkout -f $1 >> $LOGFILE  2>&1 || failure
    else
        # workaround for old git versions
        rm -rf $ROOT/3rdparty/libclfft >> $LOGFILE || failure

        echo "Retrieving CLFFT (tag: $1) (this may take a while)..." | tee -a $LOGFILE
        cd $ROOT/3rdparty || failure
        git clone https://gitlab.aei.uni-hannover.de/einsteinathome/libclfft.git libclfft >> $LOGFILE 2>&1 || failure
        cd $ROOT/3rdparty/libclfft || failure
        git checkout $1 >> $LOGFILE  2>&1 || failure
    fi

    return 0
}

prepare_vkfft()
{
    if [ $BUILDSTATE -ge $BS_PREPARE_VKFFT ]; then
        return 0
    fi

    echo "Preparing VkFFT..." | tee -a $LOGFILE
    mkdir -p $ROOT/3rdparty >> $LOGFILE || failure

    echo "Retrieving VkFFT $VKFFT_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure
    curl --location https://github.com/DTolm/VkFFT/archive/refs/tags/v$VKFFT_VERSION.tar.gz -o VkFFT-$VKFFT_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    tar -xzf VkFFT-$VKFFT_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    rm VkFFT-$VKFFT_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    mkdir -p $ROOT/install/include/ >> $LOGFILE || failure
    cp -a VkFFT-$VKFFT_VERSION/vkFFT/* $ROOT/install/include/ >> $LOGFILE || failure

    store_build_state $BS_PREPARE_VKFFT
    return 0
}

prepare_metal-cpp()
{
    if [ $BUILDSTATE -ge $BS_PREPARE_METALCPP ]; then
        return 0
    fi

    echo "Preparing Metal-cpp..." | tee -a $LOGFILE
    mkdir -p $ROOT/3rdparty >> $LOGFILE || failure

    echo "Retrieving Metal-cpp $METALCPP_VERSION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure
    curl https://developer.apple.com/metal/cpp/files/metal-cpp_$METALCPP_VERSION.zip -o metal-cpp_$METALCPP_VERSION.zip >> $LOGFILE 2>&1 || failure
    rm -rf $ROOT/install/include/metal-cpp
    mkdir -p $ROOT/install/include/metal-cpp >> $LOGFILE || failure
    unzip -d $ROOT/install/include metal-cpp_$METALCPP_VERSION.zip -x "__MACOSX*" >> $LOGFILE 2>&1 || failure
    rm metal-cpp_$METALCPP_VERSION.zip >> $LOGFILE 2>&1 || failure

    store_build_state $BS_PREPARE_METALCPP
    return 0
}

prepare_libxml()
{
    echo "Preparing libxml2..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/libxml2 >> $LOGFILE || failure

    echo "Retrieving libxml2 $LIBXML_VERSION.$LIBXML_REVISION (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty || failure
    rm -f libxml2-sources-$LIBXML_VERSION.$LIBXML_REVISION.tar.xz >> $LOGFILE 2>&1 || failure
    # try two possible locations (if needed)
    curl --location https://download.gnome.org/sources/libxml2/$LIBXML_VERSION/libxml2-$LIBXML_VERSION.$LIBXML_REVISION.tar.xz -o libxml2-sources-$LIBXML_VERSION.$LIBXML_REVISION.tar.xz >> $LOGFILE 2>&1 || failure
    tar -xzf libxml2-sources-$LIBXML_VERSION.$LIBXML_REVISION.tar.xz >> $LOGFILE 2>&1 || failure
    rm libxml2-sources-$LIBXML_VERSION.$LIBXML_REVISION.tar.xz >> $LOGFILE 2>&1 || failure
    # substitute old source tree
    rm -rf libxml2 >> $LOGFILE 2>&1 || failure
    mv libxml2-$LIBXML_VERSION.$LIBXML_REVISION libxml2 >> $LOGFILE 2>&1 || failure

    return 0
}


prepare_openssl()
{
    echo "Retrieving OpenSSL $OPENSSL_VERSION (this may take a while)..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/openssl >> $LOGFILE || failure

    cd $ROOT/3rdparty || failure
    curl https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz -o openssl-$OPENSSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    tar -xvzf openssl-$OPENSSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    rm openssl-$OPENSSL_VERSION.tar.gz >> $LOGFILE 2>&1 || failure
    mv openssl-$OPENSSL_VERSION openssl >> $LOGFILE 2>&1 || failure

    return 0
}


prepare_boinc()
{
    echo "Preparing BOINC..." | tee -a $LOGFILE
    mkdir -p $ROOT/3rdparty/boinc >> $LOGFILE || failure
    mkdir -p $ROOT/build/boinc >> $LOGFILE || failure

    cd $ROOT/3rdparty/boinc || failure
    test -n "$NOUPDATE" && return 0
    if [ -d .git ]; then
        echo "Updating BOINC (tag: $1)..." | tee -a $LOGFILE
        # make sure local changes (patches) are reverted to ensure fast-forward merge
        git checkout -f $1 >> $LOGFILE  2>&1 || failure
        # update tag info
        git remote update >> $LOGFILE  2>&1 || failure
        git fetch --tags >> $LOGFILE  2>&1 || failure
        # checkout build revision
        git checkout -f $1 >> $LOGFILE  2>&1 || failure
    else
        # workaround for old git versions
        rm -rf $ROOT/3rdparty/boinc >> $LOGFILE || failure

        echo "Retrieving BOINC (tag: $1) (this may take a while)..." | tee -a $LOGFILE
        cd $ROOT/3rdparty || failure
        if [ ".$1" == ".$TAG_DAEMONS" ]; then
            git clone git@gitlab.aei.uni-hannover.de:einsteinathome/boinc-server.git boinc >> $LOGFILE 2>&1 || failure
        else
            git clone -n https://gitlab.aei.uni-hannover.de/einsteinathome/boinc.git boinc >> $LOGFILE 2>&1 || failure
        fi
        cd $ROOT/3rdparty/boinc || failure
        git checkout -f $1 >> $LOGFILE  2>&1 || failure
    fi

    return 0
}


prepare_mingw()
{
    if [ $BUILDSTATE -ge $BS_PREPARE_MINGW ]; then
        return 0
    fi

    cd $ROOT || failure

    echo "Preparing MinGW source tree..." | tee -a $LOGFILE
    mkdir -p 3rdparty/mingw/xscripts >> $LOGFILE || failure
    cd 3rdparty/mingw/xscripts || failure

    if [ -d CVS ]; then
        echo "Updating MinGW build script..." | tee -a $LOGFILE
        cvs update -C >> $LOGFILE 2>&1 || failure
    else
        cd .. || failure
        echo "Retrieving MinGW build script (this may take a while)..." | tee -a $LOGFILE
        cvs -z3 -d:pserver:anonymous@mingw.cvs.sourceforge.net:/cvsroot/mingw checkout -P xscripts >> $LOGFILE 2>&1 || failure
    fi

    echo "Preparing MinGW build script..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/mingw/xscripts || failure
    # note: svn has no force/overwrite switch. the file might not be updated when patched
    patch x86-mingw32-build.sh.conf < $ROOT/patches/x86-mingw32-build.sh.conf.patch >> $LOGFILE || failure
    chmod +x x86-mingw32-build.sh >> $LOGFILE || failure

    echo "Preparing MinGW packages..." | tee -a $LOGFILE
    mkdir -p $ROOT/3rdparty/mingw/packages >> $LOGFILE || failure
    cd $ROOT/3rdparty/mingw/packages || failure

    rm -f gcc-core-4.6.2.tar.gz >> $LOGFILE 2>&1 || failure
    curl http://ftp.gnu.org/gnu/gcc/gcc-4.6.2/gcc-core-4.6.2.tar.gz -o gcc-core-4.6.2.tar.gz >> $LOGFILE 2>&1 || failure
    mv gcc-core-4.6.2.tar.gz gcc-core-4.6.2-1-src.tar.gz

    rm -f binutils-2.22.tar.gz >> $LOGFILE 2>&1 || failure
    curl http://ftp.gnu.org/gnu/binutils/binutils-2.22.tar.gz -o binutils-2.22.tar.gz >> $LOGFILE 2>&1 || failure
    mv binutils-2.22.tar.gz binutils-2.22-src.tar.gz

    # mingwrt-3.20-mingw32-src.tar.gz

    store_build_state $BS_PREPARE_MINGW
    return 0
}


prepare_ndk()
{
    if [ $BUILDSTATE -ge $BS_PREPARE_NDK ]; then
        return 0
    fi

    cd $ROOT || failure

    echo "Preparing NDK $NDK_VERSION for Android cross compilation" | tee -a $LOGFILE

    rm -rf 3rdparty/ndk >> $LOGFILE || failure
    mkdir -p 3rdparty/ndk >> $LOGFILE || failure
    cd 3rdparty/ndk || failure

    curl https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux-x86_64.zip -o android-ndk-${NDK_VERSION}-linux-x86_64.zip >> $LOGFILE 2>&1 || failure
    unzip android-ndk-${NDK_VERSION}-linux-x86_64.zip >> $LOGFILE 2>&1 || failure
    cd android-ndk-${NDK_VERSION} || failure

    store_build_state $BS_PREPARE_NDK
    return 0
}


### Linux / macOS builds ##################################################


set_arm_xcomp()
{
    echo "Setting cross compilers"
    export TARGET_HOST=arm-linux
    export BUILD_HOST=i386-linux

    export CC=arm-unknown-linux-gnueabi-gcc
    export CXX=arm-unknown-linux-gnueabi-g++
    export LD=arm-unknown-linux-gnueabi-ld
    export TCINCLUDES=$ROOT/install
    export BOINC_PLATFORM=arm-unknown-linux-gnueabihf

    export CFLAGS=" -I$TCINCLUDES/include  $CFLAGS"
    export CXXFLAGS=" -I$TCINCLUDES/include $CXXFLAGS"
    export LDFLAGS=" -L$TCINCLUDES/lib $LDFLAGS"
}


build_binutils()
{
    if [ $BUILDSTATE -ge $BS_BUILD_BINUTILS ]; then
        return 0
    fi

    prepare_binutils || failure

    # build binutils (libbfd) for linux only
    if [ "$1" == "$TARGET_LINUX" -o "$1" == "$TARGET_LINUX_CUDA" -o "$1" == "$TARGET_LINUX_OCL" ]; then
        echo "Patching binutils..." | tee -a $LOGFILE
        # patch: omit subdirs when building bfd (avoids build error and we don't need 'em anyway)
        cd $ROOT/3rdparty/binutils/bfd || failure
        patch Makefile.in < $ROOT/patches/binutils.Makefile.in.patch >> $LOGFILE 2>&1 || failure
        echo "Building binutils (this may take a while)..." | tee -a $LOGFILE
        cd $ROOT/3rdparty/binutils || failure
        chmod +x configure >> $LOGFILE 2>&1 || failure
        cd $ROOT/build/binutils || failure
        CPPFLAGS="-I$ROOT/install/include $CPPFLAGS" LDFLAGS="-L$ROOT/install/lib $LDFLAGS" $ROOT/3rdparty/binutils/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-install-libbfd --enable-install-libiberty --disable-werror >> $LOGFILE 2>&1 || failure
        CPPFLAGS="-I$ROOT/install/include $CPPFLAGS" LDFLAGS="-L$ROOT/install/lib $LDFLAGS" make configure-bfd >> $LOGFILE 2>&1 || failure
        #sed -i~ "s%-lz%$ROOT/install/lib/libz.a%" "$ROOT/build/binutils/bfd/Makefile" >> $LOGFILE 2>&1 || failure
        make >> $LOGFILE 2>&1 || failure
        make install >> $LOGFILE 2>&1 || failure
        # copy required headers and lib (missing install target)
        cp $ROOT/3rdparty/binutils/binutils/sysdep.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/3rdparty/binutils/include/binary-io.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/3rdparty/binutils/include/fopen-bin.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/3rdparty/binutils/include/fopen-same.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/3rdparty/binutils/include/alloca-conf.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/build/binutils/bfd/bfdver.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        cp $ROOT/build/binutils/binutils/config.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
        echo "Successfully built and installed binutils!" | tee -a $LOGFILE
    fi

    store_build_state $BS_BUILD_BINUTILS || failure
    return 0
}


build_zlib()
{
    if [ $BUILDSTATE -ge $BS_BUILD_ZLIB ]; then
        return 0
    fi

    prepare_zlib || failure

    # note: the official zlib distribution doen't allow an out-of-tree build
    echo "Building zlib..." | tee -a $LOGFILE
    cd $ROOT/build/zlib-$ZLIB_VERSION >> $LOGFILE 2>&1 || failure
    if echo "$TARGET_HOST" | grep mingw >/dev/null; then
        I="$ROOT/install"
        make -f win32/Makefile.gcc PREFIX="$TARGET_HOST-" BINARY_PATH="$I/bin" INCLUDE_PATH="$I/include" LIBRARY_PATH="$I/lib" install >> $LOGFILE 2>&1 || failure
    else
        ./configure --static --prefix="$ROOT/install" >> $LOGFILE 2>&1 || failure
        make >> $LOGFILE 2>&1 || failure
        make install >> $LOGFILE 2>&1 || failure
    fi
    sed -i~ "s%-lz%$ROOT/install/lib/libz.a%" "$ROOT/install/lib/pkgconfig/zlib.pc" >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed zlib" | tee -a $LOGFILE

    store_build_state $BS_BUILD_ZLIB || failure
    return 0
}


build_gsl()
{
    if [ $BUILDSTATE -ge $BS_BUILD_GSL ]; then
        return 0
    fi

    prepare_gsl || failure

    echo "Building GSL (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/gsl || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/gsl || failure

    if [ "$BUILD_TYPE" == "$BUILD_TYPE_CROSS"  ]; then
        $ROOT/3rdparty/gsl/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST  --enable-shared=no --enable-static=yes CFLAGS="-g -O2 $CFLAGS" >> $LOGFILE 2>&1 || failure
    else
        $ROOT/3rdparty/gsl/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes CFLAGS="-g -O2 $CFLAGS" >> $LOGFILE 2>&1 || failure
    fi
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed GSL!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_GSL || failure
    return 0
}


build_fftw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_FFTW ]; then
        return 0
    fi

    prepare_fftw || failure

    echo "Building FFTW3 (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/fftw || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/fftw || failure
    if [ "$1" == "$TARGET_DAEMONS" ]; then
        $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_CUDA" ]; then
        $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-float --enable-sse CFLAGS="-O3 -fomit-frame-pointer -m64 -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
    else
        if [ "$1" == "$TARGET_LINUX_ARMV6" -o "$1" == "$TARGET_LINUX_ARMV7" ]; then
            if [ "$BUILD_TYPE" == "$BUILD_TYPE_CROSS" ]; then
		if [  "$SUB_TARGET" == "$SUB_TARGET_LINUX_ARMV7NEON_XCOMP"  ]; then
  		  $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST --with-slow-timer --enable-shared=no --enable-static=yes --enable-float --enable-neon CFLAGS="-O3 -fomit-frame-pointer  -fstrict-aliasing  -ffast-math $CFLAGS" CODELET_OPTIM="-O3  --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
		else
                  $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST --with-slow-timer --enable-shared=no --enable-static=yes --enable-float CFLAGS="-O3 -fomit-frame-pointer  -fstrict-aliasing  -ffast-math $CFLAGS" CODELET_OPTIM="-O3  --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
		fi
            else
              $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --with-slow-timer --enable-shared=no --enable-static=yes --enable-float CFLAGS="-O3 -fomit-frame-pointer  -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O3  --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
            fi
        elif echo $CFLAGS | egrep -e '-[^ ]*sse ' >/dev/null; then
            $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-float --enable-sse CFLAGS="-O3 -fomit-frame-pointer -malign-double -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
        elif echo $CFLAGS | egrep -e '-[^ ]*altivec ' >/dev/null; then
            $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-float --enable-altivec CFLAGS="-O3 -mno-fused-madd -fomit-frame-pointer -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
        else
            $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-float CFLAGS="-O3 -fomit-frame-pointer -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
        fi
    fi
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed FFTW3!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_FFTW || failure
    return 0
}


build_clfft()
{
    if [ $BUILDSTATE -ge $BS_BUILD_CLFFT ]; then
        return 0
    fi

    prepare_clfft $TAG_CLFFT || failure

    echo "Building CLFFT (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/libclfft/src
    if [ "$1" == "$TARGET_LINUX_OCL" ]; then
        make >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_OCL" -o "$1" == "$TARGET_MAC_ARM_OCL" ]; then
        make >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN32_OCL" ]; then
        make -f Makefile.mingw >> $LOGFILE 2>&1 || failure
    fi
    cp $ROOT/3rdparty/libclfft/include/clFFT.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    cp $ROOT/3rdparty/libclfft/lib/libclfft.a $ROOT/install/lib >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed CLFFT!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_CLFFT || failure
    return 0
}


build_libxml()
{
    if [ $BUILDSTATE -ge $BS_BUILD_LIBXML ]; then
        return 0
    fi

    prepare_libxml || failure

    echo "Building libxml2 (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/libxml2 || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/libxml2 || failure
    if [ "$BUILD_TYPE" == "$BUILD_TYPE_CROSS" ]; then
      $ROOT/3rdparty/libxml2/configure --host=$TARGET_HOST --build=$BUILD_HOST  --prefix=$ROOT/install --without-zlib --without-lzma --enable-shared=no --enable-static=yes --without-python >> $LOGFILE 2>&1 || failure
    else
      $ROOT/3rdparty/libxml2/configure --prefix=$ROOT/install --without-zlib --without-lzma --enable-shared=no --enable-static=yes --without-python >> $LOGFILE 2>&1 || failure
    fi
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    sed -i~ "s%-lz%$ROOT/install/lib/libz.a%" "$ROOT/install/lib/pkgconfig/libxml-2.0.pc" >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed libxml2!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_LIBXML || failure
    return 0
}


build_boinc()
{
    if [ $BUILDSTATE -ge $BS_BUILD_BOINC ]; then
        return 0
    fi

    if [ "$1" == "$TARGET_DAEMONS" ]; then
        prepare_boinc $TAG_DAEMONS || failure
    else
        prepare_boinc $TAG_APPS || failure
    fi

    if [ "$BUILD_TYPE" == "$BUILD_TYPE_CROSS" ]; then
        prepare_openssl_cross || failure
        build_openssl_cross   || failure
    fi


    echo "Configuring BOINC..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/boinc || failure
    chmod +x _autosetup >> $LOGFILE 2>&1 || failure
    if [ "$1" == "$TARGET_DAEMONS" ]; then
        # don't build example app (removed in later upstream commit: 5e354e4)
        patch $ROOT/3rdparty/boinc/Makefile.am < $ROOT/patches/boinc.Makefile.am.2.patch >> $LOGFILE 2>&1 || failure
    fi
    patch $ROOT/3rdparty/boinc/api/boinc_api.h < $ROOT/patches/boinc.boinc_api.h.patch >> $LOGFILE 2>&1 || failure
    ./_autosetup >> $LOGFILE 2>&1 || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/boinc || failure
    # include server components for daemon build only
    if [ "$1" == "$TARGET_DAEMONS" ]; then
        $ROOT/3rdparty/boinc/configure CPPFLAGS="-I$ROOT/3rdparty/boinc $CPPFLAGS" --prefix=$ROOT/install --enable-shared=no --enable-static=yes --enable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi >> $LOGFILE 2>&1 || failure
    elif [[ ( -d "/usr/local/ssl" ) && ( "$BUILD_TYPE" == "$BUILD_TYPE_NATIVE" ) ]]; then
        echo "Using local SSL library..." | tee -a $LOGFILE
        $ROOT/3rdparty/boinc/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --disable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi CPPFLAGS=-I/usr/local/ssl/include LDFLAGS=-L/usr/local/ssl/lib >> $LOGFILE 2>&1 || failure
    elif [ -n "$cross_host" ]; then
        $ROOT/3rdparty/boinc/configure $cross_host --prefix=$ROOT/install --enable-shared=no --enable-static=yes --disable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi >> $LOGFILE 2>&1 || failure
    else
        if [ "$BUILD_TYPE" == "$BUILD_TYPE_NATIVE" ]; then
            $ROOT/3rdparty/boinc/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes --disable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi >> $LOGFILE 2>&1 || failure
        else
            $ROOT/3rdparty/boinc/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST  --with-boinc-platform="$BOINC_PLATFORM" --with-ssl=$TCINCLUDES --enable-shared=no --enable-static=yes --disable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi >> $LOGFILE 2>&1 || failure
        fi
    fi
    echo "Building BOINC (this may take a while)..." | tee -a $LOGFILE
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    # workaround for some boinc versions still in use (current_server) - shouldn't harm
    cp $ROOT/3rdparty/boinc/lib/cl_boinc.h $ROOT/install/include/boinc
    echo "Successfully built and installed BOINC!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_BOINC || failure
    return 0
}


### Windows / MinGW builds  ###############################################


build_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_MINGW ]; then
        return 0
    fi

    prepare_mingw || failure

    TARGET_HOST=i586-pc-mingw32

    echo "Building MinGW (this will take quite a while)..." | tee -a $LOGFILE
    # note: the script's current config for unattended setup expects it to be run from three levels below root!
    cd $ROOT/3rdparty/mingw/xscripts || failure

    ./x86-mingw32-build.sh --unattended --no-post-clean $TARGET_HOST >> $LOGFILE 2>&1 || failure

    store_build_state $BS_BUILD_MINGW
    return 0
}


set_mingw()
{
    # general config
    PREFIX=$ROOT/install
    # the following target host spec is Debian specific!
    # use "i586-pc-mingw32" when building MinGW automatically
    TARGET_HOST=i686-w64-mingw32
    BUILD_HOST=i386-linux
    PATH_MINGW="$PREFIX/bin:$PREFIX/$TARGET_HOST/bin:$PATH"
    PATH="$PATH_MINGW"
    export PATH

    export CC=`which ${TARGET_HOST}-gcc`
    export CXX=`which ${TARGET_HOST}-g++`
    export AR=`which ${TARGET_HOST}-ar`

    export CPPFLAGS="-D_WIN32_WINDOWS=0x0410 -DMINGW_WIN32 $CPPFLAGS"
    export CXXFLAGS="-gstabs -g3 $CXXFLAGS"
}


set_mingw64()
{
    # general config
    PREFIX=$ROOT/install
    # the following target host spec is Debian specific!
    TARGET_HOST=x86_64-w64-mingw32
    BUILD_HOST=i386-linux
    PATH_MINGW="$PREFIX/bin:$PREFIX/$TARGET_HOST/bin:$PATH"
    PATH="$PATH_MINGW"
    export PATH

    export CC=`which ${TARGET_HOST}-gcc`
    export CXX=`which ${TARGET_HOST}-g++`
    export AR=`which ${TARGET_HOST}-ar`

    # export CPPFLAGS="-D_WIN32_WINDOWS=0x0410 -DMINGW_WIN32 $CPPFLAGS"
}


build_binutils_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_BINUTILS_MINGW ]; then
        return 0
    fi

    prepare_binutils || failure

    echo "Building binutils (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/binutils || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/binutils || failure
    $ROOT/3rdparty/binutils/configure --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$PREFIX --enable-shared=no --enable-static=yes --enable-install-libbfd --enable-install-libiberty >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Patching binutils [post-build]..." | tee -a $LOGFILE
    # patch: remove previous declarations by winnt.h
    cd $ROOT/3rdparty/binutils/include/coff || failure
    patch internal.h < $ROOT/patches/binutils.internal.h.minggw.patch >> $LOGFILE 2>&1 || failure
    # copy required headers and lib (missing install target)
    cp $ROOT/3rdparty/binutils/include/coff/internal.h $ROOT/install/include/coff >> $LOGFILE 2>&1 || failure
    cp $ROOT/3rdparty/binutils/bfd/coff-bfd.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    cp $ROOT/3rdparty/binutils/bfd/libcoff.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    cp $ROOT/build/binutils/bfd/config.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    cp $ROOT/build/binutils/intl/libintl.a $ROOT/install/lib >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed binutils!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_BINUTILS_MINGW || failure
    return 0
}


build_gsl_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_GSL_MINGW ]; then
        return 0
    fi

    prepare_gsl || failure

    echo "Building GSL (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/gsl || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    if [ -f "$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-gsl-config" ]; then
        GSL_CONFIG="$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-gsl-config"
        export GSL_CONFIG
        echo "Cross-compile GSL_CONFIG: $GSL_CONFIG" >> $LOGFILE
    fi
    cd $ROOT/build/gsl || failure
    $ROOT/3rdparty/gsl/configure --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$PREFIX --enable-shared=no --enable-static=yes CFLAGS="-g -O2 $CFLAGS" >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed GSL!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_GSL_MINGW || failure
    return 0
}


build_fftw_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_FFTW_MINGW ]; then
        return 0
    fi

    prepare_fftw || failure

    echo "Building FFTW3 (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/fftw || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    if [ -f "$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-fftw-config" ]; then
        FFTW_CONFIG="$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-fftw-config"
        export FFTW_CONFIG
        echo "Cross-compile FFTW_CONFIG: $FFTW_CONFIG" >> $LOGFILE
    fi
    cd $ROOT/build/fftw || failure
    if [ "$1" == "$TARGET_WIN64" -o "$1" == "$TARGET_WIN64_CUDA" -o "$1" == "$TARGET_WIN64_OCL" ]; then
        $ROOT/3rdparty/fftw/configure --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$PREFIX --enable-shared=no --enable-static=yes --enable-float --enable-sse --with-our-malloc16 CFLAGS="-O3 -fomit-frame-pointer -malign-double -fstrict-aliasing -ffast-math -m64 $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
    else
        $ROOT/3rdparty/fftw/configure --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$PREFIX --enable-shared=no --enable-static=yes --enable-float --enable-sse --with-our-malloc16 CFLAGS="-O3 -fomit-frame-pointer -malign-double -fstrict-aliasing -ffast-math -march=pentium3 $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
    fi
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed FFTW3!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_FFTW_MINGW || failure
    return 0
}


build_clfft_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_CLFFT_MINGW ]; then
        return 0
    fi

    prepare_clfft $TAG_CLFFT || failure

    echo "Building CLFFT (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/libclfft/src
    make -f Makefile.mingw >> $LOGFILE 2>&1 || failure
    cp $ROOT/3rdparty/libclfft/include/clFFT.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    cp $ROOT/3rdparty/libclfft/lib/libclfft.a $ROOT/install/lib >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed CLFFT!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_CLFFT_MINGW || failure
    return 0
}


build_libxml_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_LIBXML_MINGW ]; then
        return 0
    fi

    prepare_libxml || failure

    echo "Building libxml2 (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/libxml2 || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    if [ -f "$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-xml2-config" ]; then
        LIBXML2_CONFIG="$PREFIX/$TARGET_HOST/bin/$TARGET_HOST-xml2-config"
        export LIBXML2_CONFIG
        echo "Cross-compile LIBXML2_CONFIG: $LIBXML2_CONFIG" >> $LOGFILE
    fi
    cd $ROOT/build/libxml2 || failure
    $ROOT/3rdparty/libxml2/configure --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$PREFIX --without-zlib --without-lzma --enable-shared=no --enable-static=yes --without-python --without-threads >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed libxml2!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_LIBXML_MINGW || failure
    return 0
}


build_boinc_mingw()
{
    if [ $BUILDSTATE -ge $BS_BUILD_BOINC_MINGW ]; then
        return 0
    fi

    prepare_boinc $TAG_APPS || failure

    cd $ROOT/3rdparty/boinc/lib || failure
    echo "Building BOINC (this may take a while)..." | tee -a $LOGFILE
    BOINC_SRC="$ROOT/3rdparty/boinc" AR="${TARGET_HOST}-ar" make -f Makefile.mingw >> $LOGFILE 2>&1 || failure
    BOINC_PREFIX="$ROOT/install" RANLIB="${TARGET_HOST}-ranlib" make -f Makefile.mingw install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed BOINC!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_BOINC_MINGW || failure
    return 0
}


### Android / NDK builds ##################################################


set_ndk()
{
    export BUILD_HOST=x86_64-unknown-linux-gnu
    export TARGET_HOST=armv7a-linux-androideabi
    export NDK_ROOT=$ROOT/3rdparty/ndk/android-ndk-${NDK_VERSION}
    export TOOLCHAIN=$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64

    export CC=${TARGET_HOST}${NDK_PLATFORM}-clang
    export CXX=${TARGET_HOST}${NDK_PLATFORM}-clang++
    export LD=${TARGET_HOST}-ld
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip

    export TCBINARIES="$TOOLCHAIN/bin"
    export TCSYSROOT="$TOOLCHAIN/sysroot"
    export TCINCLUDES="$TCSYSROOT/usr/include"
    export TCLIBS="$TCSUSROOT/usr/lib/arm-linux-androideabi"

    export PATH="$PATH:$TOOLCHAIN/bin"
    export CFLAGS="--sysroot=$TCSYSROOT -I$TCINCLUDES -DANDROID -DDECLARE_TIMEZONE -Wall -O3 -fomit-frame-pointer $CFLAGS"
    export CXXFLAGS="--sysroot=$TCSYSROOT -I$TCINCLUDES -DANDROID -Wall -funroll-loops -fexceptions -O3 -fomit-frame-pointer $CXXFLAGS"
    export LDFLAGS="-static-libstdc++ -L$TCLIBS -llog $LDFLAGS"
    export GDB_CFLAGS="--sysroot=$TCSYSROOT -Wall -g -I$TCINCLUDES"
}


build_zlib_ndk()
{
    if [ $BUILDSTATE -ge $BS_BUILD_ZLIB_NDK ]; then
        return 0
    fi

    prepare_zlib || failure

    # note: the official zlib distribution doen't allow an out-of-tree build
    echo "Building zlib..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/zlib-$ZLIB_VERSION >> $LOGFILE 2>&1 || failure
    ./configure --static --prefix="$ROOT/install" >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    sed -i~ "s%-lz%$ROOT/install/lib/libz.a%" "$ROOT/install/lib/pkgconfig/zlib.pc" >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed zlib" | tee -a $LOGFILE

    store_build_state $BS_BUILD_ZLIB_NDK || failure
}


build_gsl_ndk()
{
    # TODO: remerge with build_gsl if the differences are not not major

    if [ $BUILDSTATE -ge $BS_BUILD_GSL_NDK ]; then
        return 0
    fi

    prepare_gsl || failure

    echo "Building GSL (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/gsl || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/gsl || failure
    $ROOT/3rdparty/gsl/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST  --enable-shared=no --enable-static=yes CFLAGS="-g -O2 $CFLAGS" >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed GSL!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_GSL_NDK || failure
    return 0
}


build_fftw_ndk()
{
    if [ $BUILDSTATE -ge $BS_BUILD_FFTW_NDK ]; then
        return 0
    fi

    prepare_fftw || failure

    echo "Building FFTW3 (this may take a while)..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/fftw || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/fftw || failure
    if [ "$1" == "$TARGET_DAEMONS" ]; then
        $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --enable-shared=no --enable-static=yes >> $LOGFILE 2>&1 || failure
    elif [ "$SUB_TARGET" == "$SUB_TARGET_ARMV7_NEON" -o "$SUB_TARGET" == "$SUB_TARGET_ARMV7_NEON_PIE" ]; then
        $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST --with-slow-timer --enable-shared=no --enable-static=yes --enable-float --enable-neon CFLAGS="-O3 -fomit-frame-pointer  -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O -fno-schedule-insns -fno-web -fno-loop-optimize --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
    else
        $ROOT/3rdparty/fftw/configure --prefix=$ROOT/install --host=$TARGET_HOST --build=$BUILD_HOST --with-slow-timer --enable-shared=no --enable-static=yes --enable-float CFLAGS="-O3 -fomit-frame-pointer  -fstrict-aliasing -ffast-math $CFLAGS" CODELET_OPTIM="-O3 --param inline-unit-growth=1000 --param large-function-growth=1000" >> $LOGFILE 2>&1 || failure
    fi
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed FFTW3!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_FFTW_NDK || failure
    return 0
}


build_libxml_ndk()
{
    if [ $BUILDSTATE -ge $BS_BUILD_LIBXML_NDK ]; then
        return 0
    fi

    prepare_libxml || failure

    echo "Building libxml2 (this may take a while)..." | tee -a $LOGFILE

    # TODO: do it nicer
    mkdir -p $TCINCLUDES/include
    cp $ROOT/patches/android/glob.h $TCINCLUDES/include

    cd $ROOT/3rdparty/libxml2 || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/libxml2 || failure
    $ROOT/3rdparty/libxml2/configure  --host=$TARGET_HOST --build=$BUILD_HOST --prefix=$ROOT/install --without-zlib --without-lzma --enable-shared=no --enable-static=yes --without-python >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    sed -i~ "s%-lz%$ROOT/install/lib/libz.a%" "$ROOT/install/lib/pkgconfig/libxml-2.0.pc" >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed libxml2!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_LIBXML_NDK || failure
    return 0
}


build_openssl_ndk()
{
    if [ $BUILDSTATE -ge $BS_BUILD_OPENSSL_NDK ]; then
        return 0
    fi

    prepare_openssl || failure

	echo "Building OpenSSL (this may take a while)..." | tee -a $LOGFILE

    cd $ROOT/build/openssl || failure
    $ROOT/3rdparty/openssl/Configure linux-generic32 no-shared no-dso -DL_ENDIAN --prefix="$ROOT/install" --openssldir="$ROOT/install" >> $LOGFILE 2>&1 || failure
    make >> $LOGFILE 2>&1 || failure
    make install_sw  >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed OpenSSL!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_OPENSSL_NDK || failure
	return 0
}


build_boinc_ndk()
{
    if [ $BUILDSTATE -ge $BS_BUILD_BOINC_NDK ]; then
        return 0
    fi

    prepare_boinc $TAG_APPS || failure

    echo "Configuring BOINC..." | tee -a $LOGFILE
    cd $ROOT/3rdparty/boinc || failure
    chmod +x _autosetup >> $LOGFILE 2>&1 || failure

    patch $ROOT/3rdparty/boinc/api/boinc_api.h < $ROOT/patches/boinc.boinc_api.h.patch >> $LOGFILE 2>&1 || failure
    ./_autosetup >> $LOGFILE 2>&1 || failure
    chmod +x configure >> $LOGFILE 2>&1 || failure
    cd $ROOT/build/boinc || failure

    # include server components for daemon build only
    echo configuring ... 4

    $ROOT/3rdparty/boinc/configure --prefix=$ROOT/install --host=arm-linux --with-boinc-platform="arm-android-linux-gnu" --enable-shared=no --enable-static=yes --disable-server --disable-client --enable-install-headers --enable-libraries --disable-manager --disable-fcgi >> $LOGFILE 2>&1 || failure

    echo "Building BOINC (this may take a while)..." | tee -a $LOGFILE
    make >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    cp $ROOT/build/boinc/config.h $ROOT/install/include >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed BOINC!" | tee -a $LOGFILE

    store_build_state $BS_BUILD_BOINC_NDK || failure
    return 0
}


### Common builds #########################################################


build_einsteinradio()
{
    echo "Preparing Arecibo Binary Pulsar Search [Application]..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/einsteinradio >> $LOGFILE || failure

    prepare_version_header || failure

    echo "Building Binary Radio Pulsar Search [Application]..." | tee -a $LOGFILE
    export EINSTEIN_RADIO_SRC=$ROOT/src || failure
    export EINSTEIN_RADIO_INSTALL=$ROOT/install || failure
    cd $ROOT/build/einsteinradio || failure
    if [ "$1" == "$TARGET_LINUX" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            EINSTEINBINARY_TARGET=einsteinbinary_x86_64-pc-linux-gnu
        else
            EINSTEINBINARY_TARGET=einsteinbinary_i686-pc-linux-gnu
        fi
        cp -f $ROOT/src/Makefile . >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_LINUX_NOBOINC" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            EINSTEINBINARY_TARGET=einsteinbinary_x86_64-pc-linux-gnu
        else
            EINSTEINBINARY_TARGET=einsteinbinary_i686-pc-linux-gnu
        fi
        cp -f $ROOT/src/Makefile.linux.noboinc Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_LINUX_CUDA" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            EINSTEINBINARY_TARGET=einsteinbinary_x86_64-pc-linux-gnu__cuda
        else
            EINSTEINBINARY_TARGET=einsteinbinary_i686-pc-linux-gnu__cuda
        fi
        cp -f $ROOT/src/Makefile.linux.cuda Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_LINUX_OCL" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            EINSTEINBINARY_TARGET=einsteinbinary_x86_64-pc-linux-gnu__opencl
        else
            EINSTEINBINARY_TARGET=einsteinbinary_i686-pc-linux-gnu__opencl
        fi
        cp -f $ROOT/src/Makefile.linux.opencl Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_LINUX_ARMV6" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_arm-unknown-linux-gnueabihf
        if [ "$BUILD_TYPE" == "$BUILD_TYPE_NATIVE" ]; then
             cp -f $ROOT/src/Makefile.linux.armv6 Makefile >> $LOGFILE 2>&1 || failure
        else
             cp -f $ROOT/src/Makefile.linux.armv6.cross Makefile >> $LOGFILE 2>&1 || failure
        fi
    elif [ "$1" == "$TARGET_LINUX_ARMV7" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_arm-unknown-linux-gnueabihf
        if [ "$BUILD_TYPE" == "$BUILD_TYPE_NATIVE" ]; then
             cp -f $ROOT/src/Makefile.linux.armv7 Makefile >> $LOGFILE 2>&1 || failure
        else
             cp -f $ROOT/src/Makefile.linux.armv7.cross Makefile >> $LOGFILE 2>&1 || failure
        fi
    elif [ "$1" == "$TARGET_ANDROID_ARM" ]; then
        if [ "$SUB_TARGET" == "$SUB_TARGET_ARMV6_VFP" ] ; then
            EINSTEINBINARY_TARGET=einsteinbinary_arm-android-linux-gnu__VFP
        elif [ "$SUB_TARGET" == "$SUB_TARGET_ARMV7_NEON" ] ; then
            EINSTEINBINARY_TARGET=einsteinbinary_arm-android-linux-gnu__NEON
        elif [ "$SUB_TARGET" == "$SUB_TARGET_ARMV7_NEON_PIE" ] ; then
            EINSTEINBINARY_TARGET=einsteinbinary_arm-android-linux-gnu__NEONPIE
        fi
        cp -f $ROOT/src/Makefile.android.arm Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_i686-apple-darwin
        cp -f $ROOT/src/Makefile.macos Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_ARM" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_arm64-apple-darwin
        cp -f $ROOT/src/Makefile.macos Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_PPC" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_powerpc-apple-darwin
        cp -f $ROOT/src/Makefile.macos.ppc Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_ALTIVEC" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_powerpc-apple-darwin__ALTIVEC
        cp -f $ROOT/src/Makefile.macos.ppc Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_CUDA" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_x86_64-apple-darwin__cuda
        cp -f $ROOT/src/Makefile.macos.cuda Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_OCL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_i686-apple-darwin__opencl
        cp -f $ROOT/src/Makefile.macos.opencl Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_ARM_OCL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_arm64-apple-darwin__opencl
        cp -f $ROOT/src/Makefile.macos.opencl Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_MTL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_x86_64-apple-darwin__metal
        cp -f $ROOT/src/Makefile.macos.metal Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_MAC_ARM_MTL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_arm64-apple-darwin__metal
        cp -f $ROOT/src/Makefile.macos.metal Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN32" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_intelx86.exe
        cp -f $ROOT/src/Makefile.mingw Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN32_CUDA" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_intelx86__cuda.exe
        cp -f $ROOT/src/Makefile.mingw.cuda Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN32_OCL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_intelx86__opencl.exe
        cp -f $ROOT/src/Makefile.mingw.opencl Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN64" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_x86_64.exe
        cp -f $ROOT/src/Makefile.mingw Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN64_CUDA" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_x86_64__cuda.exe
        cp -f $ROOT/src/Makefile.mingw.cuda Makefile >> $LOGFILE 2>&1 || failure
    elif [ "$1" == "$TARGET_WIN64_OCL" ]; then
        EINSTEINBINARY_TARGET=einsteinbinary_windows_x86_64__opencl.exe
        cp -f $ROOT/src/Makefile.mingw.opencl Makefile >> $LOGFILE 2>&1 || failure
    else
        echo "Unknown build target encountered!" | tee -a $LOGFILE
        failure
    fi
    export EINSTEINBINARY_TARGET
    make $2 >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed Binary Radio Pulsar Search [Application]!" | tee -a $LOGFILE

    return 0
}


### Target control ########################################################


build_daemons()
{
    build_binutils || failure
    build_gsl || failure
    build_fftw $TARGET_DAEMONS || failure
    build_libxml || failure
    build_boinc $TARGET_DAEMONS || failure

    echo "Preparing Arecibo Binary Pulsar Search [Daemons]..." | tee -a $LOGFILE
    mkdir -p $ROOT/build/daemons >> $LOGFILE || failure

    prepare_version_header || failure

    echo "Building Arecibo Binary Pulsar Search [Daemons]..." | tee -a $LOGFILE
    export EINSTEIN_RADIO_SRC=$ROOT/src || failure
    export EINSTEIN_RADIO_INSTALL=$ROOT/install || failure
    cd $ROOT/build/daemons || failure
    cp -f $ROOT/src/daemons/Makefile . >> $LOGFILE 2>&1 || failure
    make $1 >> $LOGFILE 2>&1 || failure
    make install >> $LOGFILE 2>&1 || failure
    echo "Successfully built and installed Arecibo Binary Pulsar Search [Daemons]" | tee -a $LOGFILE

    return 0
}


build_linux()
{

    if [ "$SUB_TARGET" == "$SUB_TARGET_LINUX_ARMV6_XCOMP" -o  "$SUB_TARGET" == "$SUB_TARGET_LINUX_ARMV7NEON_XCOMP" ]; then
        set_arm_xcomp || failure
    fi

    build_zlib || failure

    if [ "$1" != "$TARGET_LINUX_NOBOINC" ]; then
        build_binutils $1 || failure
    fi

    build_gsl $1 || failure
    build_fftw $1 || failure

    if [ "$1" == "$TARGET_LINUX_OCL" ]; then
        build_clfft $1 || failure
    fi

    if [ "$1" != "$TARGET_LINUX_NOBOINC" ]; then
        build_libxml $1 || failure
        build_boinc $1 || failure
    fi

    build_einsteinradio $1 $2 || failure

    return 0
}


build_android()
{
    prepare_ndk || failure
    set_ndk || failure

    # TODO include binutils if we get the stacktrace working for ARM
    #build_binutils_ndk $1 || failure
    build_zlib_ndk || failure
    build_gsl_ndk $1 || failure
    build_fftw_ndk $1 || failure
    build_libxml_ndk $1 || failure
    build_openssl_ndk $1 || failure
    build_boinc_ndk $1 || failure
    build_einsteinradio $1 $2 || failure

    return 0
}


build_mac()
{
    build_binutils $1 || failure
    build_zlib || failure
    build_gsl $1 || failure
    build_fftw $1 || failure
    if [ "$1" == "$TARGET_MAC_OCL" -o "$1" == "$TARGET_MAC_ARM_OCL" ]; then
        build_clfft $1 || failure
    elif [ "$1" == "$TARGET_MAC_MTL" -o "$1" == "$TARGET_MAC_ARM_MTL" ]; then
        prepare_vkfft || failure
        prepare_metal-cpp || failure
    fi
    build_libxml $1 || failure
    build_boinc $1 || failure
    build_einsteinradio $1 $2 || failure

    return 0
}


build_win32()
{
    # no more prepare/build steps for MinGW
    # we use Debian's MinGW with GCC 4.4 support
    set_mingw || failure

    build_zlib || failure
    build_binutils_mingw || failure
    build_gsl_mingw || failure
    build_fftw_mingw $1 || failure
    if [ "$1" == "$TARGET_WIN32_OCL" ]; then
        build_clfft_mingw || failure
    fi
    build_libxml_mingw || failure
    build_boinc_mingw || failure
    build_einsteinradio $1 $2 || failure

    return 0
}


build_win64()
{
    # no more prepare/build steps for MinGW
    # we use Debian's MinGW with GCC 4.4 support
    set_mingw64 || failure

    build_binutils_mingw || failure
    build_zlib || failure
    build_gsl_mingw || failure
    build_fftw_mingw $1 || failure
    if [ "$1" == "$TARGET_WIN64_OCL" ]; then
        build_clfft_mingw || failure
    fi
    build_libxml_mingw || failure
    build_boinc_mingw || failure
    build_einsteinradio $1 $2 || failure

    return 0
}


print_usage()
{
    cd $ROOT

    echo "*************************"
    echo "Usage: `basename $0` <target> [<modifier>]"
    echo
    echo "Available targets:"
    echo "  --linux"
    echo "  --linux-cuda"
    echo "  --linux-opencl"
    echo "  --linux-armv6"
    echo "  --linux-armv6-xcomp"
    echo "  --linux-armv7neon-xcomp"
    echo "  --linux-noboinc"
    echo "  --android-armv6-vfp"
    echo "  --android-armv7-neon"
    echo "  --android-armv7-neon-pie"
    echo "  --mac"
    echo "  --mac-arm"
    echo "  --mac-ppc"
    echo "  --mac-altivec"
    echo "  --mac-cuda"
    echo "  --mac-opencl"
    echo "  --mac-arm-opencl"
    echo "  --mac-metal"
    echo "  --mac-arm-metal"
    echo "  --win32"
    echo "  --win32-cuda"
    echo "  --win32-opencl"
    echo "  --win64"
    echo "  --win64-cuda"
    echo "  --win64-opencl"
    echo "  --doc"
    echo "  --daemons"
    echo "  --distclean"
    echo
    echo "Target modifiers (except doc/daemons):"
    echo "  debug"
    echo "  profile"
    echo "*************************"

    echo "Wrong usage. Stopping!" >> $LOGFILE

    return 0
}


### Main control ##########################################################


echo "************************************" | tee -a $LOGFILE
echo "Starting new build!" | tee -a $LOGFILE
echo "`date`" | tee -a $LOGFILE
echo "************************************" | tee -a $LOGFILE

# crude command line parsing :-)

if [ $# -gt 2 ]; then
  print_usage
  exit 1
fi

if [[ ($# -lt 1) && ( -f .lastbuild) ]]; then
    BUILDTARGET=`cat .lastbuild 2>/dev/null`
    echo "No build target supplied! Building previous target..."
else
    BUILDTARGET=$1
fi

case "$BUILDTARGET" in
    "--linux")
        TARGET=$TARGET_LINUX
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-noboinc")
        TARGET=$TARGET_LINUX_NOBOINC
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-cuda")
        TARGET=$TARGET_LINUX_CUDA
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux CUDA version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-opencl")
        TARGET=$TARGET_LINUX_OCL
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux OpenCL version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-armv6")
        TARGET=$TARGET_LINUX_ARMV6
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux Raspberry Pi version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-armv6-xcomp")
        TARGET=$TARGET_LINUX_ARMV6
        SUB_TARGET=$SUB_TARGET_LINUX_ARMV6_XCOMP
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux Raspberry Pi version, cross compile:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--linux-armv7neon-xcomp")
        TARGET=$TARGET_LINUX_ARMV7
        SUB_TARGET=$SUB_TARGET_LINUX_ARMV7NEON_XCOMP
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Linux ARMv7NEON version, cross compile:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--android-armv6-vfp")
        TARGET=$TARGET_ANDROID_ARM
        SUB_TARGET=$SUB_TARGET_ARMV6_VFP
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Android (ARMv6 w/ VFP) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--android-armv7-neon")
        TARGET=$TARGET_ANDROID_ARM
        SUB_TARGET=$SUB_TARGET_ARMV7_NEON
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Android (ARMv7 w/ NEON) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--android-armv7-neon-pie")
        TARGET=$TARGET_ANDROID_ARM
        SUB_TARGET=$SUB_TARGET_ARMV7_NEON_PIE
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Android (ARMv7 w/ NEON as PositionIndependentExecutable (PIE)) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;

    "--mac")
        TARGET=$TARGET_MAC
        check_last_build "$BUILDTARGET" || failure
        echo "Building Mac OS X (i386) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-arm")
        TARGET=$TARGET_MAC_ARM
        check_last_build "$BUILDTARGET" || failure
        echo "Building macOS (arm64) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-ppc")
        TARGET=$TARGET_MAC_PPC
        check_last_build "$BUILDTARGET" || failure
        echo "Building Mac OS X (PowerPC) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-altivec")
        TARGET=$TARGET_MAC_ALTIVEC
        check_last_build "$BUILDTARGET" || failure
        echo "Building Mac OS X (PowerPC) version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-cuda")
        TARGET=$TARGET_MAC_CUDA
        check_last_build "$BUILDTARGET" || failure
        echo "Building Mac OS X (Intel) CUDA version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-opencl")
        TARGET=$TARGET_MAC_OCL
        check_last_build "$BUILDTARGET" || failure
        echo "Building Mac OS X (Intel) OpenCL version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-arm-opencl")
        TARGET=$TARGET_MAC_ARM_OCL
        check_last_build "$BUILDTARGET" || failure
        echo "Building macOS (arm64) OpenCL version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-metal")
        TARGET=$TARGET_MAC_MTL
        check_last_build "$BUILDTARGET" || failure
        echo "Building macOS (x86_64) Metal version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--mac-arm-metal")
        TARGET=$TARGET_MAC_ARM_MTL
        check_last_build "$BUILDTARGET" || failure
        echo "Building macOS (arm64) Metal version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win32")
        TARGET=$TARGET_WIN32
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win32 version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win32-cuda")
        TARGET=$TARGET_WIN32_CUDA
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win32 CUDA version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win32-opencl")
        TARGET=$TARGET_WIN32_OCL
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win32 OpenCL version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win64")
        TARGET=$TARGET_WIN64
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win64 version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win64-cuda")
        TARGET=$TARGET_WIN64_CUDA
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win64 CUDA version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--win64-opencl")
        TARGET=$TARGET_WIN64_OCL
        BUILD_TYPE=$BUILD_TYPE_CROSS
        check_last_build "$BUILDTARGET" || failure
        echo "Building Win64 OpenCL version:" | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--doc")
        TARGET=$TARGET_DOC
        echo "Building documentation..." | tee -a $LOGFILE
        ;;
    "--daemons")
        TARGET=$TARGET_DAEMONS
        check_last_build "$BUILDTARGET" || failure
        echo "Building project daemons..." | tee -a $LOGFILE
        check_build_state || failure
        ;;
    "--distclean")
        distclean || failure
        exit 0
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

# here we go...

case $TARGET in
    $TARGET_LINUX)
        if gcc -dumpmachine | egrep 'x86_64|i.86' >/dev/null; then
            export CFLAGS="-mfpmath=sse -msse $CFLAGS"
            export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"
        fi

        check_prerequisites $TARGET_LINUX || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX "$2" || failure
        ;;
    $TARGET_LINUX_NOBOINC)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites $TARGET_LINUX_NOBOINC || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX_NOBOINC "$2" || failure
        ;;
    $TARGET_LINUX_CUDA)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites  $TARGET_LINUX_CUDA || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX_CUDA "$2" || failure
        ;;
    $TARGET_LINUX_OCL)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites $TARGET_LINUX_OCL || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX_OCL "$2" || failure
        ;;
    $TARGET_LINUX_ARMV6)
        export CXXFLAGS="-march=armv6zk -mcpu=arm1176jzf-s -mtune=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard $CXXFLAGS"
        export CFLAGS="-march=armv6zk -mcpu=arm1176jzf-s -mtune=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard $CFLAGS"

        check_prerequisites $TARGET_LINUX_ARMV6 || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX_ARMV6 "$2" || failure
        ;;
    $TARGET_LINUX_ARMV7)
        export CXXFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard $CXXFLAGS"
        export CFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard $CFLAGS"

        check_prerequisites $TARGET_LINUX_ARMV7 || failure
        prepare_tree || failure
        build_linux $TARGET_LINUX_ARMV7 "$2" || failure
        ;;
    $TARGET_ANDROID_ARM)
        if [ "$SUB_TARGET"  == "$SUB_TARGET_ARMV7_NEON" ] ; then
            export CXXFLAGS="-march=armv7-a -mthumb -mfloat-abi=softfp -mfpu=neon $CXXFLAGS "
            export CFLAGS="-march=armv7-a -mthumb -mfloat-abi=softfp -mfpu=neon $CFLAGS "
        elif [ "$SUB_TARGET"  == "$SUB_TARGET_ARMV7_NEON_PIE" ] ; then
            export CXXFLAGS="-march=armv7-a -mthumb -mfloat-abi=softfp -mfpu=neon -fPIE $CXXFLAGS "
            export CFLAGS="-march=armv7-a -mthumb -mfloat-abi=softfp -mfpu=neon -fPIE $CFLAGS "
            export LDFLAGS=" -fPIE -pie $LDFLAGS "
        else
            export CXXFLAGS="-march=armv6 -mthumb -mfloat-abi=softfp -mfpu=vfp $CXXFLAGS "
            export CFLAGS="-march=armv6  -mfloat-abi=softfp -mfpu=vfp $CFLAGS "
        fi
        check_prerequisites $TARGET_ANDROID_ARM || failure
        prepare_tree || failure
        build_android $TARGET_ANDROID_ARM "$2" || failure
        ;;

    $TARGET_MAC)
        if [ -d /Developer/SDKs/MacOSX10.4u.sdk ]; then
            export CFLAGS="-mfpmath=sse -msse $CFLAGS"
            export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"


            echo "Preparing Mac OS X 10.4 (10.4 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk -arch i386 $LDFLAGS"
            export CPPFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch i386 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch i386 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch i386 $CXXFLAGS"
            export SDKROOT="/Developer/SDKs/MacOSX10.4u.sdk"
            export MACOSX_DEPLOYMENT_TARGET=10.4
        else
            echo "Mac OS X 10.4 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC || failure
        prepare_tree || failure
        build_mac $TARGET_MAC "$2" || failure
        ;;
    $TARGET_MAC_ARM)
        export SDKROOT="/Users/Shared/Developer/SDKs/MacOSX11.3.sdk"
        if [ -d $SDKROOT ]; then
            echo "Preparing macOS 11 (11.3 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,$SDKROOT -arch arm64 $LDFLAGS"
            export CPPFLAGS="-isysroot $SDKROOT -arch arm64 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1130 -DMAC_OS_X_VERSION_MIN_REQUIRED=1100 -isysroot $SDKROOT -arch arm64 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1130 -DMAC_OS_X_VERSION_MIN_REQUIRED=1100 -isysroot $SDKROOT -arch arm64 $CXXFLAGS"
            export MACOSX_DEPLOYMENT_TARGET=11.3
        else
            echo "macOS 11.3 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_ARM || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_ARM "$2" || failure
        ;;
    $TARGET_MAC_PPC)
        if [ -d /Developer/SDKs/MacOSX10.4u.sdk ]; then
            echo "Preparing Mac OS X 10.4 (10.4 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk -arch ppc $LDFLAGS"
            export CPPFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc `echo \" $CFLAGS \" | sed 's/-[^ ]*sse //g'`"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc `echo \" $CXXFLAGS \" | sed 's/-[^ ]*sse / /g'`"
            export SDKROOT="/Developer/SDKs/MacOSX10.4u.sdk"
            export MACOSX_DEPLOYMENT_TARGET=10.4
            cross_host=--host=powerpc-apple-darwin
        else
            echo "Mac OS X 10.4 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_PPC "$2" || failure
        ;;
    $TARGET_MAC_ALTIVEC)
        if [ -d /Developer/SDKs/MacOSX10.4u.sdk ]; then
            echo "Preparing Mac OS X 10.4 (10.4 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk -arch ppc $LDFLAGS"
            export CPPFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc -faltivec -maltivec -mno-fused-madd `echo \" $CFLAGS \" | sed 's/-[^ ]*sse //g'`"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1040 -DMAC_OS_X_VERSION_MIN_REQUIRED=1040 -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc -faltivec -maltivec -mno-fused-madd `echo \" $CXXFLAGS \" | sed 's/-[^ ]*sse / /g'`"
            export SDKROOT="/Developer/SDKs/MacOSX10.4u.sdk"
            export MACOSX_DEPLOYMENT_TARGET=10.4
            cross_host=--host=powerpc-apple-darwin
        else
            echo "Mac OS X 10.4 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_PPC "$2" || failure
        ;;
    $TARGET_MAC_CUDA)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        if [ -d /Developer/SDKs/MacOSX10.7.sdk ]; then
            echo "Preparing Mac OS X 10.7 (10.7 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.7.sdk $LDFLAGS"
            export CPPFLAGS="-isysroot /Developer/SDKs/MacOSX10.7.sdk $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1070 -DMAC_OS_X_VERSION_MIN_REQUIRED=1070 -isysroot /Developer/SDKs/MacOSX10.7.sdk $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1070 -DMAC_OS_X_VERSION_MIN_REQUIRED=1070 -isysroot /Developer/SDKs/MacOSX10.7.sdk $CXXFLAGS"
            export SDKROOT="/Developer/SDKs/MacOSX10.7.sdk"
            export MACOSX_DEPLOYMENT_TARGET=10.7
        else
            echo "Mac OS X 10.7 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_CUDA || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_CUDA "$2" || failure
        ;;
    $TARGET_MAC_OCL)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        if [ -d /Developer/SDKs/MacOSX10.7.sdk ]; then
            echo "Preparing Mac OS X 10.7 (10.7 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,/Developer/SDKs/MacOSX10.7.sdk -arch i386 $LDFLAGS"
            export CPPFLAGS="-isysroot /Developer/SDKs/MacOSX10.7.sdk -arch i386 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1070 -DMAC_OS_X_VERSION_MIN_REQUIRED=1070 -isysroot /Developer/SDKs/MacOSX10.7.sdk -arch i386 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1070 -DMAC_OS_X_VERSION_MIN_REQUIRED=1070 -isysroot /Developer/SDKs/MacOSX10.7.sdk -arch i386 $CXXFLAGS"
            export SDKROOT="/Developer/SDKs/MacOSX10.7.sdk"
            export MACOSX_DEPLOYMENT_TARGET=10.7
        else
            echo "Mac OS X 10.7 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_OCL || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_OCL "$2" || failure
        ;;
    $TARGET_MAC_ARM_OCL)
        export SDKROOT="/Users/Shared/Developer/SDKs/MacOSX11.3.sdk"
        if [ -d $SDKROOT ]; then
            echo "Preparing macOS 11 (11.3 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,$SDKROOT -arch arm64 $LDFLAGS"
            export CPPFLAGS="-isysroot $SDKROOT -arch arm64 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1130 -DMAC_OS_X_VERSION_MIN_REQUIRED=1100 -isysroot $SDKROOT -arch arm64 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1130 -DMAC_OS_X_VERSION_MIN_REQUIRED=1100 -isysroot $SDKROOT -arch arm64 $CXXFLAGS"
            export MACOSX_DEPLOYMENT_TARGET=11.3
        else
            echo "macOS 11.3 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_ARM_OCL || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_ARM_OCL "$2" || failure
        ;;
    $TARGET_MAC_MTL)
        export SDKROOT="/Users/Shared/Developer/SDKs/MacOSX13.3.sdk"
        if [ -d $SDKROOT ]; then
            export CFLAGS="-mfpmath=sse -msse $CFLAGS"
            export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"


            echo "Preparing macOS 13 (13.3 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,$SDKROOT -arch x86_64 $LDFLAGS"
            export CPPFLAGS="-isysroot $SDKROOT -arch x86_64 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1390 -DMAC_OS_X_VERSION_MIN_REQUIRED=1330 -isysroot $SDKROOT -arch x86_64 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1390 -DMAC_OS_X_VERSION_MIN_REQUIRED=1330 -isysroot $SDKROOT -arch x86_64 $CXXFLAGS"
            export MACOSX_DEPLOYMENT_TARGET=13.3
        else
            echo "macOS 13.3 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_MTL || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_MTL "$2" || failure
        ;;
    $TARGET_MAC_ARM_MTL)
        export SDKROOT="/Users/Shared/Developer/SDKs/MacOSX13.3.sdk"
        if [ -d $SDKROOT ]; then
            echo "Preparing macOS 13 (13.3 SDK) build environment..." | tee -a $LOGFILE
            export LDFLAGS="-Wl,-syslibroot,$SDKROOT -arch arm64 $LDFLAGS"
            export CPPFLAGS="-isysroot $SDKROOT -arch arm64 $CPPFLAGS"
            export CFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1390 -DMAC_OS_X_VERSION_MIN_REQUIRED=1330 -isysroot $SDKROOT -arch arm64 $CFLAGS"
            export CXXFLAGS="-DMAC_OS_X_VERSION_MAX_ALLOWED=1390 -DMAC_OS_X_VERSION_MIN_REQUIRED=1330 -isysroot $SDKROOT -arch arm64 $CXXFLAGS"
            export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
            export MACOSX_DEPLOYMENT_TARGET=13.3
        else
            echo "macOS 13.3 SDK required but missing!" | tee -a $LOGFILE
            failure
        fi
        check_prerequisites $TARGET_MAC_ARM_MTL || failure
        prepare_tree || failure
        build_mac $TARGET_MAC_ARM_MTL "$2" || failure
        ;;
    $TARGET_WIN32)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites $TARGET_WIN32 || failure
        prepare_tree || failure
        build_win32 $TARGET_WIN32 "$2" || failure
        ;;
    $TARGET_WIN32_CUDA)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites $TARGET_WIN32_CUDA || failure
        prepare_tree || failure
        build_win32 $TARGET_WIN32_CUDA "$2" || failure
        ;;
    $TARGET_WIN32_OCL)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites  $TARGET_WIN32_OCL || failure
        prepare_tree || failure
        build_win32 $TARGET_WIN32_OCL "$2" || failure
        ;;
    $TARGET_WIN64)
        export CFLAGS="-m64 $CFLAGS"
        export CXXFLAGS="-m64 $CXXFLAGS"

        check_prerequisites $TARGET_WIN64 || failure
        prepare_tree || failure
        build_win64 $TARGET_WIN64 "$2" || failure
        ;;
    $TARGET_WIN64_CUDA)
        export CFLAGS="-m64 $CFLAGS"
        export CXXFLAGS="-m64 $CXXFLAGS"

        check_prerequisites $TARGET_WIN64_CUDA || failure
        prepare_tree || failure
        build_win64 $TARGET_WIN64_CUDA "$2" || failure
        ;;
    $TARGET_WIN64_OCL)
        export CFLAGS="-m64 $CFLAGS"
        export CXXFLAGS="-m64 $CXXFLAGS"

        check_prerequisites $TARGET_WIN64_OCL || failure
        prepare_tree || failure
        build_win64 $TARGET_WIN64_OCL "$2" || failure
        ;;
    $TARGET_DOC)
        echo "Sorry, not yet implemented..."
#       doxygen Doxyfile >> $LOGFILE 2>&1 || failure
#       cp -f $ROOT/doc/default/*.png $ROOT/doc/html >> $LOGFILE 2>&1 || failure
#       cp -f $ROOT/doc/default/*.gif $ROOT/doc/html >> $LOGFILE 2>&1 || failure
        ;;
    $TARGET_DAEMONS)
        export CFLAGS="-mfpmath=sse -msse $CFLAGS"
        export CXXFLAGS="-mfpmath=sse -msse $CXXFLAGS"

        check_prerequisites $TARGET_DAEMONS || failure
        prepare_tree || failure
        build_daemons "$2" || failure
        ;;
    *)
        # should be unreachable
        print_usage
        exit 1
        ;;
esac

echo "************************************" | tee -a $LOGFILE
echo "Build finished successfully!" | tee -a $LOGFILE
echo "`date`" | tee -a $LOGFILE
echo "************************************" | tee -a $LOGFILE

exit 0
