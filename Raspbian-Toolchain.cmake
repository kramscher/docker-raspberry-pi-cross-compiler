set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_SYSROOT $ENV{RPXC_ROOT}/sysroot)

set(PLATFORM_PREFIX "arm-linux-gnueabihf")
message(STATUS "Using sysroot path: ${CMAKE_SYSROOT}")

set(CMAKE_C_COMPILER ${PLATFORM_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${PLATFORM_PREFIX}-g++)

set(LIB_DIRS
    "$ENV{RPXC_ROOT}/gcc/${PLATFORM_PREFIX}/lib"
    "$ENV{RPXC_ROOT}/gcc/lib"
    "${CMAKE_SYSROOT}/opt/vc/lib"
    "${CMAKE_SYSROOT}/lib"
    "${CMAKE_SYSROOT}/lib/${PLATFORM_PREFIX}"
    "${CMAKE_SYSROOT}/usr/local/lib"
    "${CMAKE_SYSROOT}/usr/lib/${PLATFORM_PREFIX}"
    "${CMAKE_SYSROOT}/usr/lib"
    "${CMAKE_SYSROOT}/usr/lib/${PLATFORM_PREFIX}/blas"
    "${CMAKE_SYSROOT}/usr/lib/${PLATFORM_PREFIX}/lapack")

set(COMMON_FLAGS "-I${CMAKE_SYSROOT}/usr/include -I${CMAKE_SYSROOT}/usr/include/${PLATFORM_PREFIX} -I${CMAKE_SYSROOT}/opt/vc/include")
foreach (LIB ${LIB_DIRS})
    set(COMMON_FLAGS "${COMMON_FLAGS} -L${LIB} -Wl,-rpath-link,${LIB}")
endforeach ()

# Raspberry Pi 3
set(HW_FLAGS "-mcpu=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard")

# Raspberry Pi 2
#set(HW_FLAGS "-mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard")

#Raspberry Pi 1 / Zero
#set(HW_FLAGS "-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard")

set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH};${CMAKE_SYSROOT}/usr/lib/${PLATFORM_PREFIX}")
set(CMAKE_FIND_ROOT_PATH "${CMAKE_INSTALL_PREFIX};${CMAKE_PREFIX_PATH};${CMAKE_SYSROOT}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${HW_FLAGS} ${COMMON_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${HW_FLAGS} ${COMMON_FLAGS}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
