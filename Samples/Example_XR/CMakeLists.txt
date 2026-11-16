cmake_minimum_required(VERSION 3.19)
project(Example_XR)

if (WIN32)
    set(SOURCE_FILES main_Windows.cpp XRExample.h)
    set(LIB_DXCOMPILER "dxcompiler.dll")
else()
    set(SOURCE_FILES main_SDL2.cpp XRExample.h)
    set(LIB_DXCOMPILER "libdxcompiler.so")
endif()

add_executable(Example_XR ${SOURCE_FILES})

target_link_libraries(Example_XR PUBLIC
    WickedEngine
)

if (WIN32)
    set_target_properties(Example_XR PROPERTIES WIN32_EXECUTABLE YES)
    target_compile_definitions(Example_XR PRIVATE WIN32 _WINDOWS)
endif()

if(WICKED_ENABLE_IPO)
set_target_properties(Example_XR PROPERTIES
    INTERPROCEDURAL_OPTIMIZATION ON
    INTERPROCEDURAL_OPTIMIZATION_DEBUG OFF
)
endif()

add_custom_command(
    TARGET Example_XR POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${WICKED_ROOT_DIR}/WickedEngine/${LIB_DXCOMPILER} $<TARGET_FILE_DIR:Example_XR>
)

# The OpenXR loader is a shared library on Windows (openxr_loader.dll), it must be next to the executable:
if (TARGET OpenXR::openxr_loader)
    get_target_property(OPENXR_LOADER_TYPE OpenXR::openxr_loader TYPE)
    if (OPENXR_LOADER_TYPE STREQUAL "SHARED_LIBRARY")
        add_custom_command(
            TARGET Example_XR POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:OpenXR::openxr_loader> $<TARGET_FILE_DIR:Example_XR>
        )
    endif()
endif()
