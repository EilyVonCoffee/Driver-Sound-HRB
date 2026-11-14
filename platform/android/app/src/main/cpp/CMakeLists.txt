cmake_minimum_required(VERSION 3.22)
project(iem_android_audio LANGUAGES CXX)

get_filename_component(REPOSITORY_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../../../../../"
    ABSOLUTE
)

add_subdirectory("${REPOSITORY_ROOT}/native/dsp"
                 "${CMAKE_CURRENT_BINARY_DIR}/iem_dsp")
find_package(oboe REQUIRED CONFIG)

add_library(iem_android_audio SHARED AudioEngine.cpp NativeAudioBridge.cpp)
target_compile_features(iem_android_audio PRIVATE cxx_std_17)
target_include_directories(iem_android_audio PRIVATE .)
target_link_libraries(iem_android_audio PRIVATE iem_dsp oboe::oboe)
