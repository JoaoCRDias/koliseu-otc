# Try to find the Ultralight SDK
#  Ultralight_FOUND - system has Ultralight
#  Ultralight_INCLUDE_DIR - the Ultralight include directory
#  Ultralight_LIBRARY - the Ultralight library
#  UltralightCore_LIBRARY - the UltralightCore library
#  WebCore_LIBRARY - the WebCore library
#  AppCore_LIBRARY - the AppCore library

set(_ULTRALIGHT_SEARCH_PATHS
    "${ULTRALIGHT_SDK_PATH}"
    "${CMAKE_SOURCE_DIR}/../ultralight-free-sdk-1.4.0-win-x64"
    "${CMAKE_SOURCE_DIR}/../ultralight-free-sdk-1.4.0"
    "${CMAKE_SOURCE_DIR}/../ultralight-sdk"
    "C:/ultralight-free-sdk-1.4.0-win-x64"
    "C:/ultralight-free-sdk-1.4.0"
    "C:/ultralight-sdk"
)

file(GLOB _ULTRALIGHT_GLOB_PATHS "${CMAKE_SOURCE_DIR}/../ultralight-free-sdk*")
if(_ULTRALIGHT_GLOB_PATHS)
    list(GET _ULTRALIGHT_GLOB_PATHS 0 _ULTRALIGHT_GLOB_FIRST)
    list(APPEND _ULTRALIGHT_SEARCH_PATHS "${_ULTRALIGHT_GLOB_FIRST}")
endif()

find_path(Ultralight_INCLUDE_DIR
    NAMES Ultralight/Ultralight.h
    HINTS ${_ULTRALIGHT_SEARCH_PATHS}
    PATH_SUFFIXES include
)

find_library(Ultralight_LIBRARY
    NAMES Ultralight
    HINTS ${_ULTRALIGHT_SEARCH_PATHS}
    PATH_SUFFIXES lib
)

find_library(UltralightCore_LIBRARY
    NAMES UltralightCore
    HINTS ${_ULTRALIGHT_SEARCH_PATHS}
    PATH_SUFFIXES lib
)

find_library(WebCore_LIBRARY
    NAMES WebCore
    HINTS ${_ULTRALIGHT_SEARCH_PATHS}
    PATH_SUFFIXES lib
)

find_library(AppCore_LIBRARY
    NAMES AppCore
    HINTS ${_ULTRALIGHT_SEARCH_PATHS}
    PATH_SUFFIXES lib
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Ultralight
    REQUIRED_VARS
        Ultralight_INCLUDE_DIR
        Ultralight_LIBRARY
        UltralightCore_LIBRARY
        WebCore_LIBRARY
        AppCore_LIBRARY
)

mark_as_advanced(
    Ultralight_INCLUDE_DIR
    Ultralight_LIBRARY
    UltralightCore_LIBRARY
    WebCore_LIBRARY
    AppCore_LIBRARY
)
