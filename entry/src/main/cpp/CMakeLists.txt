cmake_minimum_required(VERSION 3.5.0)
project(gemma4_mnn_entry)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH arm64-v8a)
endif()

set(MNN_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../../MNN" CACHE PATH "Local MNN source checkout")
set(MNN_STAGED_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/mnn/include" CACHE PATH "Staged MNN headers")
set(MNN_STAGED_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../libs/${OHOS_ARCH}" CACHE PATH "Staged MNN libraries")

add_library(mnn SHARED IMPORTED)
set_target_properties(mnn PROPERTIES
    IMPORTED_LOCATION "${MNN_STAGED_LIB_DIR}/libMNN.so"
)

add_library(entry SHARED
    napi_init.cpp
    gemma_runner.cpp
)

target_include_directories(entry PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}"
    "${MNN_STAGED_INCLUDE_DIR}"
    "${MNN_SOURCE_ROOT}/include"
    "${MNN_SOURCE_ROOT}/transformers/llm/engine/include"
)

target_link_libraries(entry PUBLIC
    mnn
    libace_napi.z.so
    libhilog_ndk.z.so
)
