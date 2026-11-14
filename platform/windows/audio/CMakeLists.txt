cmake_minimum_required(VERSION 3.22)
project(iem_windows_audio LANGUAGES CXX)

if(NOT TARGET iem_dsp)
    get_filename_component(IEM_REPOSITORY_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
    add_subdirectory("${IEM_REPOSITORY_ROOT}/native/dsp"
                     "${CMAKE_CURRENT_BINARY_DIR}/iem_dsp")
endif()

add_library(iem_windows_endpoint STATIC
    EndpointNotificationClient.cpp
    WasapiToneEngine.cpp
)
target_include_directories(iem_windows_endpoint PUBLIC .)
target_compile_features(iem_windows_endpoint PUBLIC cxx_std_17)
target_link_libraries(iem_windows_endpoint PRIVATE iem_dsp ole32 uuid mmdevapi)
