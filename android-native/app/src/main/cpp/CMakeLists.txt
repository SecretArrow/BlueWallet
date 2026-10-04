cmake_minimum_required(VERSION 3.22.1)

project("octra_wallet_native")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Oz -fPIC -Wall")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections -Wl,--strip-all -flto=thin")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Oz -fPIC -ffunction-sections -fdata-sections -flto=thin")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections -flto=thin -fvisibility=hidden")
set(OCTRA_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../webcli)

add_library(octra_wallet_native SHARED
    octra_jni.cpp
    crypto_utils.cpp
    wallet.cpp
    rpc_client.cpp
    tx_builder.cpp
    stealth.cpp
    tweetnacl.c
    randombytes.c
    ${OCTRA_ROOT}/pvac/pvac_c_api.cpp
)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(octra_wallet_native PRIVATE -march=armv8-a+crypto)
elseif(ANDROID_ABI STREQUAL "x86_64")
    target_compile_options(octra_wallet_native PRIVATE -maes -msse2)
endif()

find_library(log-lib log)
find_library(z-lib z)

target_link_libraries(octra_wallet_native
    ${log-lib}
    ${z-lib}
)

target_include_directories(octra_wallet_native PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${OCTRA_ROOT}/pvac
    ${OCTRA_ROOT}/pvac/include
    ${OCTRA_ROOT}/lib
)

target_compile_definitions(octra_wallet_native PRIVATE
    ANDROID_BUILD
)
