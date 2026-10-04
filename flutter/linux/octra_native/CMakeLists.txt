cmake_minimum_required(VERSION 3.13)
project(octra_native CXX C)

# Path to webcli root (sibling directory under blue_wallet)
get_filename_component(WEBCLI "${CMAKE_CURRENT_SOURCE_DIR}/../../../webcli" ABSOLUTE)

# ── OpenSSL via pkg-config ─────────────────────────────────────────────────
find_package(PkgConfig REQUIRED)
pkg_check_modules(OPENSSL REQUIRED openssl)

# ── PVAC — requires __int128 and hardware AES (x86_64 only on Linux) ──────
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(PVAC_SOURCES ${WEBCLI}/pvac/pvac_c_api.cpp)
    set(HAS_PVAC TRUE)
else()
    set(PVAC_SOURCES "")
    set(HAS_PVAC FALSE)
endif()

add_library(octra_native SHARED
    ${WEBCLI}/lib/tweetnacl.c
    ${WEBCLI}/lib/randombytes.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../android/app/src/main/cpp/octra_ffi.cpp
    ${PVAC_SOURCES}
)

target_include_directories(octra_native PRIVATE
    ${WEBCLI}
    ${WEBCLI}/lib
    ${WEBCLI}/pvac
    ${WEBCLI}/pvac/include
    ${OPENSSL_INCLUDE_DIRS}
)

target_compile_options(octra_native PRIVATE
    -Wall
    -O2
    -fvisibility=hidden
    $<$<COMPILE_LANGUAGE:CXX>:-std=c++17>
)

set_source_files_properties(
    ${WEBCLI}/lib/tweetnacl.c
    ${WEBCLI}/lib/randombytes.c
    PROPERTIES COMPILE_FLAGS "-Wno-unused-function -Wno-sign-compare"
)

if(HAS_PVAC)
    set_source_files_properties(
        ${WEBCLI}/pvac/pvac_c_api.cpp
        PROPERTIES COMPILE_FLAGS "-fvisibility=default -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -maes -msse2"
    )
endif()

# Export only octra_* and pvac_* symbols
target_link_options(octra_native PRIVATE
    -Wl,--version-script,${CMAKE_CURRENT_SOURCE_DIR}/../../android/app/src/main/cpp/octra_exported.map
)

target_link_libraries(octra_native
    ${OPENSSL_LIBRARIES}
)

set_target_properties(octra_native PROPERTIES
    OUTPUT_NAME "octra_native"
    PREFIX "lib"
)
