cmake_minimum_required(VERSION 3.16)
project(llama_napi)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# llama.cpp source — clone into this directory:
#   cd entry/src/main/cpp
#   git clone --depth 1 https://github.com/ggml-org/llama.cpp
set(LLAMA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp)

if(EXISTS ${LLAMA_DIR}/CMakeLists.txt)
  # Build llama.cpp as a static library
  set(LLAMA_STATIC ON CACHE BOOL "Build llama as static lib")
  set(LLAMA_BUILD_TESTS OFF CACHE BOOL "")
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "")
  set(LLAMA_BUILD_SERVER OFF CACHE BOOL "")
  add_subdirectory(${LLAMA_DIR} llama_build)

  # NAPI wrapper
  add_library(llama SHARED napi_llama.cpp)
  target_include_directories(llama PRIVATE
    ${LLAMA_DIR}/include
    ${LLAMA_DIR}/ggml/include
  )
  target_link_libraries(llama PRIVATE
    llama
    ggml
    libace_napi.z.so
    libhilog_ndk.z.so
  )
else()
  message(WARNING "llama.cpp not found at ${LLAMA_DIR} — building stub only")
  add_library(llama SHARED napi_llama.cpp)
  target_compile_definitions(llama PRIVATE LLAMA_STUB=1)
  target_link_libraries(llama PRIVATE
    libace_napi.z.so
    libhilog_ndk.z.so
  )
endif()
