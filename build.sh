#!/bin/bash                                                                                                                                                                      
#                                                                                                                                                                                
# date: 2018/05/26                                                                                                                                                               
# author: Raymond Burkholder                                                                                                                                                     
#                                                                                                                                                                                
# https://developer.android.com/ndk/guides/standalone_toolchain                                                                                                                  
# https://developer.android.com/studio/projects/add-native-code                                                                                                                  
# https://developer.android.com/studio/projects/configure-cmake                                                                                                                  
# https://developer.android.com/studio/build/build-variants                                                                                                                      
# Android Studio uses LLDB to debug native code                                                                                                                                  
# https://proandroiddev.com/android-ndk-how-to-integrate-pre-built-libraries-in-case-of-the-ffmpeg-7ff24551a0f                                                                   
                                                                                                                                                                                 
# in bin/studio.vmoptions:                                                                                                                                                       
#  1 -Xms512m                                                                                                                                                                    
#  2 -Xmx2048m                                                                                                                                                                   
                                                                                                                                                                                 
# a c++ native application:                                                                                                                                                      
# https://github.com/googlesamples/android-ndk/blob/master/native-activity/app/src/main/cpp/main.cpp                                                                             
                                                                                                                                                                                 
# allows BASE to be defined at command line                                                                                                                                      
if [ "" = "${BASE}" ]; then                                                                                                                                                      
  BASE="/var/local/rpb"                                                                                                                                                          
fi                                                                                                                                                                               
                                                                                                                                                                                 
# allows PROJECT to be defined at command line                                                                                                                                   
if [ "" = "${PROJECT}" ]; then                                                                                                                                                   
  PROJECT="projects/secretsign"                                                                                                                                                  
fi                                                                                                                                                                               
                                                                                                                                                                                 
# BASE/android contains the sdk as well as results of builds                                                                                                                     
#   builds are then copied to a particular project                                                                                                                               
NDK="${BASE}/android/sdk/ndk-bundle"                                                                                                                                             
                                                                                                                                                                                 
echo "*** ${NDK} ***"                                                                                                                                                            
                                                                                                                                                                                 
# command lines:                                                                                                                                                                 
                                                                                                                                                                                 
# build x86_64 x86_64      x86_64  <library>                                                                                                                                     
# build x86    x86         i686    <library>                                                                                                                                     
# build arm64  arm64-v8a   aarch64 <library>                                                                                                                                     
# build arm    armeabi-v7a arm     <library>                                                                                                                                     
                                                                                                                                                                                 
export ARCH=$1                                                                                                                                                                   
export DEST=$2                                                                                                                                                                   
export CPU=$3                                                                                                                                                                    
export LIB=$4                                                                                                                                                                    
                                                                                                                                                                                 
echo "*** $ARCH $DEST $CPU $LIB ***"                                                                                                                                             
                                                                                                                                                                                 
export INSTALL_PATH="${BASE}/android/${DEST}"                                                                                                                                    
                                                                                                                                                                                 
echo "*** ${INSTALL_PATH} ***"                                                                                                                                                   
                                                                                                                                                                                 
#if [ ! -e ${INSTALL_PATH} ]; then                                                                                                                                               
#  mkdir -p ${INSTALL_PATH}                                                                                                                                                      
#fi                                                                                                                                                                              
                                                                                                                                                                                 
# api 21 for 64, api 14 for 32                                                                                                                                                   
# api 24 required for building boost:
# https://stackoverflow.com/questions/48806294/error-while-building-boost-for-android-arm-architectures
if [ ! -d "${INSTALL_PATH}" ]; then
  echo "toolchain build ..."
  $NDK/build/tools/make_standalone_toolchain.py \
    --arch ${ARCH} --api 24 --stl=libc++ --force \
    --install-dir ${INSTALL_PATH}
else 
  echo "toolchain exists"
fi

# Add the standalone toolchain to the search path.
export PATH=$PATH:${INSTALL_PATH}/bin

# Tell configure what tools to use.
TARGET_PLATFORM=${CPU}-linux-android
if [ "arm" = "$CPU" ]; then
  TARGET_PLATFORM="${TARGET_PLATFORM}eabi"
  fi
echo "*** ${TARGET_PLATFORM} ***"
export AR=${TARGET_PLATFORM}-ar
export AS=${TARGET_PLATFORM}-clang
export CC=${TARGET_PLATFORM}-clang
export CXX=${TARGET_PLATFORM}-clang++
export LD=${TARGET_PLATFORM}-ld
export STRIP=${TARGET_PLATFORM}-strip

# Tell configure what flags Android requires.
export CFLAGS="-fPIE -fPIC"
export LDFLAGS="-pie"

# build libsodium
function build_libsodium {
  ./configure \
    --host=${TARGET_PLATFORM} \
    --prefix=${INSTALL_PATH} \
    --with-pthreads \
    --with-sysroot=${INSTALL_PATH}/sysroot
  make clean
  make install
  LIB=${BASE}/${PROJECT}/app/src/main/cpp/libsodium/lib/${DEST}
  mkdir -p ${LIB}
  cp ${INSTALL_PATH}/lib/libsodium.* ${LIB}
  mkdir -p ${LIB}/include
  cp ${INSTALL_PATH}/include/sodium.h ${LIB}/include/
  mkdir -p ${LIB}/include/sodium
  cp -r ${INSTALL_PATH}/include/sodium/* ${LIB}/include/sodium
  }

function build_boost {
  # sample:
  # less $(find . -name user-config.jam)
  # background:
  # http://robmakesapps.blogspot.com/2017/06/how-to-build-boost-1640-for-android.html
  # https://stackoverflow.com/questions/37679587/how-to-compile-boost-1-61-for-android-ndk-11
  # https://stackoverflow.com/questions/35839127/how-to-build-boost-for-android-as-shared-library-with-c11-support

  echo "boost config build ..."
  USER_CONFIG="user-config.jam"
  cat <<EOF > ${USER_CONFIG}
import os ;
tool_chains = ${INSTALL_PATH} ;
using clang : ${ARCH} :
  ${INSTALL_PATH}/bin/${CXX} :
#  <compileflags>-DNDEBUG
  <compileflags>-DANDROID
  <compileflags>-D__ANDROID__
  <compileflags>--sysroot=${INSTALL_PATH}/sysroot
  <compileflags>-O2
  <compileflags>-fexceptions
  <compileflags>-frtti
#  <compileflags>-fno-strict-aliasing
#  <compileflags>-fdata-sections
#  <compileflags>-ffunction-sections
#  <compileflags>-fstack-protector
#  <compileflags>-no-canonical-prefixes
#  <compileflags>-funwind-tables
#  <compileflags>-fomit-frame-pointer
#  <compileflags>-finline-limit=64
#  <compileflags>-Wa,--noexecstack
#  <compileflags>-fvisibility=hidden
#  <compileflags>-fvisibility-inlines-hidden
#  <compileflags>-finline-limit=64
#  <compileflags>-Wformat
#  <compileflags>-Werror=format-security
#  <compileflags>-Wl,--no-undefined
  ;
EOF

  if [ ! -f b2 ]; then
    echo "boost bootstrap ..."
    ./bootstrap.sh
  fi

  if [ "arm64" = ${ARCH} ]; then
    BOOST_ARCH="arm"
  else
    BOOST_ARCH="${ARCH}"
  fi
  # build boost as static link as all variations of layout generate
  #  version named link files
  echo "boost build ..."
  ./b2 -j2 \
    --reconfigure \
    --prefix=${INSTALL_PATH} \
    --user-config=${USER_CONFIG} \
    --with-serialization \
    --with-filesystem \
    --with-date_time \
    --with-thread \
    --with-system \
    --with-chrono \
    --with-atomic \
    target-os=android \
    architecture=${BOOST_ARCH} \
    toolset=clang-${ARCH} \
    cxxflags=-std=c++14 \
    threading=multi \
    link=static\
    variant=release \
    runtime-link=shared \
    include=/home/ubuntu/standalone_toolchains/${DEST}/include/c++/4.9.x \
    --layout=system \
    install

  LIB=${BASE}/${PROJECT}/app/src/main/cpp/boost/lib/${DEST}
  mkdir -p ${LIB}
  cp ${INSTALL_PATH}/lib/libboost_* ${LIB}
  mkdir -p ${LIB}/include
  cp -r ${INSTALL_PATH}/include/boost-1_67/boost ${LIB}/include/
  }

case "$4" in
  libsodium)
    build_libsodium
    ;;

  boost)
    build_boost
    ;;

  *)
    printf "\nusage ./build.sh ARCH DEST CPU LIB\n\n"

  esac
