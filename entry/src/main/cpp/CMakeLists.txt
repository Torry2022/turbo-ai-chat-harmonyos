# Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
# See README.md and Git history for provenance and change details.

cmake_minimum_required(VERSION 3.5.0)
project(turbo_ai_chat_entry)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH arm64-v8a)
endif()

set(MNN_STAGED_INCLUDE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/mnn/include" CACHE PATH "Staged MNN headers")
set(MNN_STAGED_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/../libs/${OHOS_ARCH}" CACHE PATH "Staged MNN libraries")

add_library(mnn SHARED IMPORTED)
set_target_properties(mnn PROPERTIES
    IMPORTED_LOCATION "${MNN_STAGED_LIB_DIR}/libMNN.so"
)

add_library(entry SHARED
    h2o_napi.cpp
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/h2o/h2o_decision.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/h2o/h2o_protocol.cpp"
    embedding_runner.cpp
    embedding_napi.cpp
    reranker_runner.cpp
    napi_init.cpp
    mnn_llm_runner.cpp
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/laya/laya_tokenizer.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/laya/laya_decision.cpp"
)

# Identify the exact staged runtime linked into this build, including local patches.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${MNN_STAGED_LIB_DIR}/libMNN.so")
file(SHA256 "${MNN_STAGED_LIB_DIR}/libMNN.so" MNN_LIBRARY_SHA256)
target_compile_definitions(entry PRIVATE MNN_LIBRARY_SHA256="${MNN_LIBRARY_SHA256}")

set_target_properties(entry PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/native-output/${OHOS_ARCH}"
)

target_include_directories(entry PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}"
    "${MNN_STAGED_INCLUDE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/h2o"
    "${CMAKE_CURRENT_LIST_DIR}/../../../../scripts/laya"
)

target_link_libraries(entry PUBLIC
    mnn
    libace_napi.z.so
    libhilog_ndk.z.so
)
