cmake_minimum_required(VERSION 3.22)
project(iem_dsp LANGUAGES CXX)

add_library(iem_dsp STATIC
    src/AutoEqTextParser.cpp
    src/ParametricEq.cpp
    src/SpectrumAnalyzer.cpp
)

target_include_directories(iem_dsp PUBLIC include)
target_compile_features(iem_dsp PUBLIC cxx_std_17)
set_target_properties(iem_dsp PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(MSVC)
    target_compile_options(iem_dsp PRIVATE /W4 /permissive-)
else()
    target_compile_options(iem_dsp PRIVATE -Wall -Wextra -Wpedantic)
endif()
