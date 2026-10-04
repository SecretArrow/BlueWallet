cmake_minimum_required(VERSION 3.14)
project(octra_native CXX C)

# Path to webcli root (sibling directory under blue_wallet)
get_filename_component(WEBCLI "${CMAKE_CURRENT_SOURCE_DIR}/../../../webcli" ABSOLUTE)

# ── OpenSSL ────────────────────────────────────────────────────────────────
# Set OPENSSL_ROOT_DIR before calling find_package if OpenSSL is not in PATH.
# Example: cmake -DOPENSSL_ROOT_DIR="C:/Program Files/OpenSSL-Win64" ..
find_package(OpenSSL REQUIRED)

# ── PVAC (x86_64 Windows only) ─────────────────────────────────────────────
if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
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
    ${OPENSSL_INCLUDE_DIR}
)

# Windows: export all octra_* / pvac_* symbols via __declspec(dllexport)
target_compile_definitions(octra_native PRIVATE OCTRA_BUILDING_DLL)

if(MSVC)
    target_compile_options(octra_native PRIVATE
        /O2 /W3 /EHsc
        $<$<COMPILE_LANGUAGE:CXX>:/std:c++17>
    )
    if(HAS_PVAC)
        set_source_files_properties(
            ${WEBCLI}/pvac/pvac_c_api.cpp
            PROPERTIES COMPILE_FLAGS "/arch:AVX /wd4100 /wd4189"
        )
    endif()
else()
    # MinGW / Clang on Windows
    target_compile_options(octra_native PRIVATE
        -Wall -O2 -fvisibility=hidden
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
endif()

target_link_libraries(octra_native
    OpenSSL::Crypto
)

set_target_properties(octra_native PROPERTIES
    OUTPUT_NAME "octra_native"
)
