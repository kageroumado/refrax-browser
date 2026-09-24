# Builds the Chromium engine plug-in (RefraxChromium.dylib) and its helper
# executable against a CEF binary distribution. Scripts/build-chromium-engine.sh
# drives this and assembles the result into an installable engine directory.
cmake_minimum_required(VERSION 3.21)
set(CMAKE_CONFIGURATION_TYPES Release)
project(RefraxChromium LANGUAGES C CXX)

if(NOT CEF_ROOT)
  message(FATAL_ERROR "Pass -DCEF_ROOT=<path to the CEF binary distribution>")
endif()
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CEF_ROOT}/cmake")
set(USE_SANDBOX OFF)
find_package(CEF REQUIRED)
add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)

set(RFX_OBJC_FLAGS -fobjc-arc -Wno-error)

add_library(RefraxChromium SHARED Sources/RFXChromium.mm Sources/RFXChromium.h)
SET_LIBRARY_TARGET_PROPERTIES(RefraxChromium)
add_dependencies(RefraxChromium libcef_dll_wrapper)
target_compile_options(RefraxChromium PRIVATE ${RFX_OBJC_FLAGS})
target_link_libraries(RefraxChromium libcef_dll_wrapper ${CEF_STANDARD_LIBS})
set_target_properties(RefraxChromium PROPERTIES
  OUTPUT_NAME RefraxChromium
  INSTALL_NAME_DIR "@rpath"
  BUILD_WITH_INSTALL_NAME_DIR ON)

add_executable(RefraxChromiumHelper Helper/HelperMain.mm)
SET_EXECUTABLE_TARGET_PROPERTIES(RefraxChromiumHelper)
add_dependencies(RefraxChromiumHelper libcef_dll_wrapper)
target_compile_options(RefraxChromiumHelper PRIVATE ${RFX_OBJC_FLAGS})
target_link_libraries(RefraxChromiumHelper libcef_dll_wrapper ${CEF_STANDARD_LIBS})
