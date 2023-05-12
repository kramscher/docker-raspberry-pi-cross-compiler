FROM debian:bullseye

ENV CMAKE_VERSION 3.26.3
ENV GCC_VERSION 10.2.0
ENV GLIBC_VERSION 2.31
ENV BINUTILS_VERSION 2.35.2

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y apt-utils \
 && DEBIAN_FRONTEND=noninteractive dpkg-reconfigure apt-utils \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        dpkg-dev \
        g++ \
        gcc \
        libc-dev \
        make \
        bison \
        gawk \
        git \
        libssl-dev \
        python3 \
        rsync \
        runit \
        wget

# Here is where we hardcode the toolchain decision.
ENV HOST=arm-linux-gnueabihf \
    TOOLCHAIN=gcc-linaro-arm-linux-gnueabihf-raspbian-x64 \
    RPXC_ROOT=/rpxc

WORKDIR $RPXC_ROOT/build

# Download and extract CMake
RUN wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz && \
    tar xf cmake-${CMAKE_VERSION}.tar.gz && \
    rm cmake-${CMAKE_VERSION}.tar.gz

# Download and extract GCC
RUN wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz && \
    tar xf gcc-${GCC_VERSION}.tar.gz && \
    rm gcc-${GCC_VERSION}.tar.gz

# Download and extract LibC
RUN wget https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.gz && \
    tar xf glibc-${GLIBC_VERSION}.tar.gz && \
    rm glibc-${GLIBC_VERSION}.tar.gz

# Download and extract BinUtils
RUN wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.bz2 && \
    tar xjf binutils-${BINUTILS_VERSION}.tar.bz2 && \
    rm binutils-${BINUTILS_VERSION}.tar.bz2

# Download the GCC prerequisites
RUN cd gcc-${GCC_VERSION} && contrib/download_prerequisites && rm *.tar.*

# Patch LibC
WORKDIR ${RPXC_ROOT}/build/glibc-${GLIBC_VERSION}
COPY patches/glibc_gcc-10.patch glibc_gcc-10.patch
RUN patch -p1 < glibc_gcc-10.patch
RUN rm glibc_gcc-10.patch

# Build CMake
WORKDIR $RPXC_ROOT/build/build-cmake
RUN ../cmake-${CMAKE_VERSION}/bootstrap
RUN make -j$(nproc)
RUN make install

# Build BinUtils
WORKDIR $RPXC_ROOT/build/build-binutils
RUN mkdir -p $RPXC_ROOT/gcc
RUN ../binutils-${BINUTILS_VERSION}/configure \
        --prefix=$RPXC_ROOT/gcc \
        --target=$HOST \
        --with-arch=armv6 \
        --with-fpu=vfp \
        --with-float=hard \
        --disable-multilib
RUN make -j$(nproc)
RUN make install

# Build the first part of GCC
WORKDIR $RPXC_ROOT/build/build-gcc
RUN ../gcc-${GCC_VERSION}/configure \
        --prefix=$RPXC_ROOT/gcc \
        --target=$HOST \
        --enable-languages=c,c++,fortran \
        --with-arch=armv6 \
        --with-fpu=vfp \
        --with-float=hard \
        --disable-multilib
RUN make -j$(nproc) 'LIMITS_H_TEST=true' all-gcc
RUN make install-gcc
ENV PATH=$RPXC_ROOT/gcc/bin:${PATH}

# Download and install the Linux headers
WORKDIR $RPXC_ROOT/build
RUN git clone --depth=1 https://github.com/raspberrypi/linux
WORKDIR $RPXC_ROOT/build/linux
ENV KERNEL=kernel7
RUN make ARCH=arm INSTALL_HDR_PATH=$RPXC_ROOT/gcc/arm-linux-gnueabihf headers_install

# Build GLIBC
WORKDIR $RPXC_ROOT/build/build-glibc
RUN ../glibc-${GLIBC_VERSION}/configure \
        --prefix=$RPXC_ROOT/gcc/arm-linux-gnueabihf \
        --build=$MACHTYPE \
        --host=$HOST \
        --target=$HOST \
        --with-arch=armv6 \
        --with-fpu=vfp \
        --with-float=hard \
        --with-headers=$RPXC_ROOT/gcc/arm-linux-gnueabihf/include \
        --disable-multilib \
        libc_cv_forced_unwind=yes
RUN make install-bootstrap-headers=yes install-headers
RUN make -j$(nproc) csu/subdir_lib
RUN install csu/crt1.o csu/crti.o csu/crtn.o $RPXC_ROOT/gcc/arm-linux-gnueabihf/lib
RUN arm-linux-gnueabihf-gcc -nostdlib -nostartfiles -shared -x c /dev/null \
        -o $RPXC_ROOT/gcc/arm-linux-gnueabihf/lib/libc.so
RUN touch $RPXC_ROOT/gcc/arm-linux-gnueabihf/include/gnu/stubs.h

# Continue building GCC
WORKDIR $RPXC_ROOT/build/build-gcc
RUN make -j$(nproc) all-target-libgcc
RUN make install-target-libgcc

# Finish building GLIBC
WORKDIR $RPXC_ROOT/build/build-glibc
RUN make -j$(nproc)
RUN make install

# Finish building GCC
WORKDIR $RPXC_ROOT/build/build-gcc
RUN make -j$(nproc)
RUN make install

WORKDIR $RPXC_ROOT

RUN rm -rf $RPXC_ROOT/build

ENV ARCH=arm \
    CROSS_COMPILE=$RPXC_ROOT/bin/$HOST- \
    PATH=$RPXC_ROOT/bin:$PATH \
    QEMU_PATH=/usr/bin/qemu-arm-static \
    QEMU_EXECVE=1 \
    SYSROOT=$RPXC_ROOT/sysroot \
    TOOLCHAIN_FILE=$RPXC_ROOT/Toolchain.cmake

# Create toolchain file
COPY Raspbian-Toolchain.cmake $TOOLCHAIN_FILE

WORKDIR $SYSROOT
RUN wget https://downloads.raspberrypi.org/raspios_lite_armhf/root.tar.xz && \
    tar -xJf root.tar.xz && \
    rm root.tar.xz
ADD https://github.com/resin-io-projects/armv7hf-debian-qemu/raw/master/bin/qemu-arm-static $SYSROOT/$QEMU_PATH

RUN chmod +x $SYSROOT/$QEMU_PATH \
 && mkdir -p $SYSROOT/build

RUN chroot $SYSROOT $QEMU_PATH /bin/sh -c '\
        echo "deb http://raspbian.raspberrypi.org/raspbian/ stable firmware" \
            >> /etc/apt/sources.list \
        && apt-get update --allow-releaseinfo-change \
        && sudo apt-mark hold \
      raspberrypi-bootloader raspberrypi-kernel raspberrypi-sys-mods raspi-config \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y apt-utils \
        && DEBIAN_FRONTEND=noninteractive dpkg-reconfigure apt-utils \
        && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y \
                libc6-dev \
                symlinks \
        && symlinks -cors /'

COPY image/ /

WORKDIR /build
ENTRYPOINT [ "/rpxc/entrypoint.sh" ]
