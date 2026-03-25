cmake_minimum_required(VERSION 3.20)
project(foo_dsd_output VERSION 1.0.0 LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "Build universal binary")

set(SDK_ROOT "${CMAKE_SOURCE_DIR}/sdk")

# ============================================================
# pfc static library
# ============================================================
file(GLOB PFC_CPP "${SDK_ROOT}/pfc/*.cpp")
file(GLOB PFC_MM  "${SDK_ROOT}/pfc/*.mm")
# Exclude Windows-only files
list(FILTER PFC_CPP EXCLUDE REGEX "win-objects\\.cpp$")
list(FILTER PFC_CPP EXCLUDE REGEX "stdafx\\.cpp$")

add_library(pfc STATIC ${PFC_CPP} ${PFC_MM})
target_include_directories(pfc PUBLIC "${SDK_ROOT}" "${SDK_ROOT}/pfc")
target_compile_definitions(pfc PUBLIC PFC_LEAK_STATIC_OBJECTS=1)
target_compile_options(pfc PRIVATE -Wno-everything)
set_target_properties(pfc PROPERTIES
    XCODE_ATTRIBUTE_GCC_WARN_ABOUT_RETURN_TYPE "NO"
)

# ============================================================
# shared static library (non-Windows subset)
# ============================================================
set(SHARED_SOURCES
    "${SDK_ROOT}/foobar2000/shared/shared-nix.cpp"
    "${SDK_ROOT}/foobar2000/shared/utf8.cpp"
    "${SDK_ROOT}/foobar2000/shared/audio_math.cpp"
)
add_library(shared STATIC ${SHARED_SOURCES})
target_include_directories(shared PUBLIC
    "${SDK_ROOT}"
    "${SDK_ROOT}/foobar2000"
    "${SDK_ROOT}/foobar2000/shared"
)
target_link_libraries(shared PUBLIC pfc)
target_compile_options(shared PRIVATE -Wno-everything)

# ============================================================
# foobar2000_SDK static library
# ============================================================
file(GLOB FB2K_SDK_CPP "${SDK_ROOT}/foobar2000/SDK/*.cpp")
file(GLOB FB2K_SDK_MM  "${SDK_ROOT}/foobar2000/SDK/*.mm")
# Exclude PCH stub
list(FILTER FB2K_SDK_CPP EXCLUDE REGEX "stdafx\\.cpp$|PCH\\.cpp$")

add_library(foobar2000_SDK STATIC ${FB2K_SDK_CPP} ${FB2K_SDK_MM})
target_include_directories(foobar2000_SDK PUBLIC
    "${SDK_ROOT}"
    "${SDK_ROOT}/foobar2000"
    "${SDK_ROOT}/foobar2000/SDK"
)
target_link_libraries(foobar2000_SDK PUBLIC shared pfc)
target_compile_options(foobar2000_SDK PRIVATE -Wno-everything)
target_link_libraries(foobar2000_SDK PRIVATE "-framework Foundation" "-framework AppKit")

# ============================================================
# foobar2000_SDK_helpers static library (macOS subset only)
# ============================================================
set(FB2K_HELPERS_CPP
    "${SDK_ROOT}/foobar2000/helpers/readers.cpp"
    "${SDK_ROOT}/foobar2000/helpers/text_file_loader.cpp"
    "${SDK_ROOT}/foobar2000/helpers/text_file_loader_v2.cpp"
    "${SDK_ROOT}/foobar2000/helpers/file_list_helper.cpp"
    "${SDK_ROOT}/foobar2000/helpers/ThreadUtils.cpp"
    "${SDK_ROOT}/foobar2000/helpers/input_helpers.cpp"
    "${SDK_ROOT}/foobar2000/helpers/seekabilizer.cpp"
    "${SDK_ROOT}/foobar2000/helpers/stream_buffer_helper.cpp"
    "${SDK_ROOT}/foobar2000/helpers/create_directory_helper.cpp"
    "${SDK_ROOT}/foobar2000/helpers/filetimetools.cpp"
    "${SDK_ROOT}/foobar2000/helpers/StdAfx.cpp"
    "${SDK_ROOT}/foobar2000/helpers/cfg_var_import.cpp"
    "${SDK_ROOT}/foobar2000/helpers/win-systemtime.cpp"
    "${SDK_ROOT}/foobar2000/helpers/track_property_callback_impl.cpp"
    "${SDK_ROOT}/foobar2000/helpers/VolumeMap.cpp"
    "${SDK_ROOT}/foobar2000/helpers/dynamic_bitrate_helper.cpp"
)
set(FB2K_HELPERS_MM
    "${SDK_ROOT}/foobar2000/helpers-mac/fb2k-platform.mm"
)

add_library(foobar2000_SDK_helpers STATIC ${FB2K_HELPERS_CPP} ${FB2K_HELPERS_MM})
target_include_directories(foobar2000_SDK_helpers PUBLIC
    "${SDK_ROOT}"
    "${SDK_ROOT}/foobar2000"
    "${SDK_ROOT}/foobar2000/helpers"
    "${SDK_ROOT}/foobar2000/helpers-mac"
)
target_link_libraries(foobar2000_SDK_helpers PUBLIC foobar2000_SDK)
target_compile_options(foobar2000_SDK_helpers PRIVATE -Wno-everything)
target_link_libraries(foobar2000_SDK_helpers PRIVATE "-framework Foundation" "-framework AppKit")

# ============================================================
# foobar2000_component_client static library
# ============================================================
add_library(foobar2000_component_client STATIC
    "${SDK_ROOT}/foobar2000/foobar2000_component_client/component_client.cpp"
)
target_include_directories(foobar2000_component_client PUBLIC
    "${SDK_ROOT}"
    "${SDK_ROOT}/foobar2000"
)
target_link_libraries(foobar2000_component_client PUBLIC foobar2000_SDK)
target_compile_options(foobar2000_component_client PRIVATE -Wno-everything)

# ============================================================
# foo_dsd_output plugin
# ============================================================
set(PLUGIN_SOURCES
    src/main.mm
    src/fb2k_output.mm
    src/dsd_output.mm
    src/coreaudio_backend.mm
    src/dop_encoder.cpp
    src/dsd_device_manager.mm
    src/dsd_config.mm
)

add_library(foo_dsd_output MODULE ${PLUGIN_SOURCES})

set_target_properties(foo_dsd_output PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION "component"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "foo_dsd_output"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.foobar2000.component.dsd-output"
    PREFIX ""
    SUFFIX ""
)

target_include_directories(foo_dsd_output PRIVATE
    "${CMAKE_SOURCE_DIR}/src"
    "${SDK_ROOT}"
    "${SDK_ROOT}/foobar2000"
    "${SDK_ROOT}/foobar2000/SDK"
    "${SDK_ROOT}/foobar2000/helpers"
)

target_link_libraries(foo_dsd_output PRIVATE
    foobar2000_component_client
    foobar2000_SDK_helpers
    foobar2000_SDK
    shared
    pfc
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit"
    "-framework CoreFoundation"
    "-framework Foundation"
    "-framework AppKit"
)

target_compile_options(foo_dsd_output PRIVATE
    -Wno-unused-parameter
    -Wno-deprecated-declarations
)

target_compile_definitions(foo_dsd_output PRIVATE
    FB2K_COMPONENT_DSD_OUTPUT
)

# ============================================================
# Package as .fb2k-component
# ============================================================
set(PKG_STAGING "${CMAKE_BINARY_DIR}/package")
set(PKG_MAC_DIR "${PKG_STAGING}/mac/foo_dsd_output.component")

add_custom_command(TARGET foo_dsd_output POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E remove_directory "${PKG_STAGING}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PKG_MAC_DIR}/Contents/MacOS"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PKG_MAC_DIR}/Contents/Resources"
    COMMAND ${CMAKE_COMMAND} -E copy
        "$<TARGET_BUNDLE_DIR:foo_dsd_output>/Contents/Info.plist"
        "${PKG_MAC_DIR}/Contents/Info.plist"
    COMMAND ${CMAKE_COMMAND} -E copy
        "$<TARGET_BUNDLE_DIR:foo_dsd_output>/Contents/MacOS/foo_dsd_output"
        "${PKG_MAC_DIR}/Contents/MacOS/foo_dsd_output"
    COMMAND ${CMAKE_COMMAND} -E chdir "${PKG_STAGING}"
        zip -r "${CMAKE_BINARY_DIR}/foo_dsd_output.fb2k-component" mac/
    COMMENT "Packaging foo_dsd_output.fb2k-component"
)

# Direct install to foobar2000
set(FB2K_COMPONENTS_DIR "$ENV{HOME}/Library/foobar2000-v2/user-components/foo_dsd_output")
add_custom_target(install-component
    COMMAND ${CMAKE_COMMAND} -E make_directory "${FB2K_COMPONENTS_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "$<TARGET_BUNDLE_DIR:foo_dsd_output>"
        "${FB2K_COMPONENTS_DIR}/foo_dsd_output.component"
    DEPENDS foo_dsd_output
    COMMENT "Installing to ${FB2K_COMPONENTS_DIR}"
)
