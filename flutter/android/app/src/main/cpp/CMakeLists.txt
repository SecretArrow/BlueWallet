cmake_minimum_required(VERSION 3.22.1)
project(octra_native)

# Path to webcli root (sibling directory under blue_wallet)
set(WEBCLI "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../webcli")

# ── OpenSSL via Android NDK prefab ────────────────────────────────────────────
# Requires: implementation("com.android.ndk.thirdparty:openssl:1.1.1q-beta-1")
#           and buildFeatures { prefab = true } in build.gradle.kts
find_package(openssl REQUIRED CONFIG)

# ── PVAC — conditionally compiled ───────────────────────────────────────────
# PVAC requires __int128 and hardware AES (ARM Crypto Extension or AES-NI).
# It is NOT supported on armeabi-v7a (ARMv7 lacks __int128 and hardware AES).
# On armeabi-v7a: core crypto (keygen, sign, AES, stealth) works; PVAC disabled.
if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a" OR CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
    set(PVAC_SOURCES ${WEBCLI}/pvac/pvac_c_api.cpp)
    set(HAS_PVAC TRUE)
else()
    set(PVAC_SOURCES "")  # empty — pvac_ symbols not available on this ABI
    set(HAS_PVAC FALSE)
endif()

add_library(
    octra_native
    SHARED

    # FFI bridge: core crypto + AES-256-GCM + exposes pvac symbols
    ${CMAKE_CURRENT_SOURCE_DIR}/octra_ffi.cpp

    # TweetNaCl — ed25519 / curve25519 (portable C, no external deps)
    ${WEBCLI}/lib/tweetnacl.c

    # /dev/urandom entropy for key generation
    ${WEBCLI}/lib/randombytes.c

    # PVAC — only for arm64-v8a and x86_64
    ${PVAC_SOURCES}
)

target_include_directories(octra_native PRIVATE
    ${WEBCLI}           # lets octra_ffi.cpp include "lib/tweetnacl.h" etc.
    ${WEBCLI}/lib       # direct includes of tweetnacl.h / randombytes
    ${WEBCLI}/pvac      # pvac_c_api.cpp includes "include/pvac/pvac.hpp"
    ${WEBCLI}/pvac/include  # pvac headers include "pvac/core/..."
)

# Compiler flags — only -std=c++17 for C++ sources (not tweetnacl.c / randombytes.c)
target_compile_options(octra_native PRIVATE
    -Wall
    -O2
    -fvisibility=hidden
    $<$<COMPILE_LANGUAGE:CXX>:-std=c++17>
)

# Silence warnings in vendored C sources
set_source_files_properties(
    ${WEBCLI}/lib/tweetnacl.c
    ${WEBCLI}/lib/randombytes.c
    PROPERTIES COMPILE_FLAGS "-Wno-unused-function -Wno-sign-compare"
)

# pvac requires hardware AES CPU instructions.
# arm64-v8a: ARM Cryptography Extension (-march=armv8-a+crypto)
# x86_64:    AES-NI (-maes -msse2)
# armeabi-v7a: skipped (PVAC_SOURCES is empty)
# -fvisibility=default overrides the target-level -fvisibility=hidden so that
# pvac's extern "C" symbols are exported from the shared library.
if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
    set_source_files_properties(
        ${WEBCLI}/pvac/pvac_c_api.cpp
        PROPERTIES COMPILE_FLAGS "-fvisibility=default -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -march=armv8-a+crypto"
    )
elseif(CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
    set_source_files_properties(
        ${WEBCLI}/pvac/pvac_c_api.cpp
        PROPERTIES COMPILE_FLAGS "-fvisibility=default -Wno-unused-function -Wno-sign-compare -Wno-unused-parameter -maes -msse2"
    )
endif()

# Export only octra_* and pvac_* symbols; hide everything else
target_link_options(octra_native PRIVATE
    -Wl,--version-script,${CMAKE_CURRENT_SOURCE_DIR}/octra_exported.map
)

target_link_libraries(octra_native
    android
    log
    openssl::crypto   # AES-256-GCM (EVP) + SHA-* + Ed25519 key derivation
)

