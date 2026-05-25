cmake_minimum_required(VERSION 3.16)
project(proxmoxclientplugin LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 REQUIRED COMPONENTS Core Network Qml DBus Gui Quick WebSockets Widgets)
set(CMAKE_AUTOMOC ON)
set(QT_QML_LINT_OPTIONS --disable-warning unqualified)
# Bundled dependency: QtKeychain (stores secrets in the desktop keyring: KWallet/libsecret/etc)
# Build it with Qt6 (this project uses Qt6)
set(BUILD_WITH_QT6 ON CACHE BOOL "Build qtkeychain with Qt 6" FORCE)
set(BUILD_TRANSLATIONS OFF CACHE BOOL "Disable qtkeychain translations" FORCE)
set(BUILD_TEST_APPLICATION OFF CACHE BOOL "Disable qtkeychain test app" FORCE)
# Build qtkeychain as a STATIC library so it is compiled directly into
# libproxmoxclientplugin.so. This eliminates the libqt6keychain.so runtime
# dependency and the RUNPATH pointing to the (deleted) temp build directory.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build qtkeychain as static for bundling into plugin" FORCE)
# Ensure keychain library is built with PIC so we can link it into our plugin .so
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# libsecret dev package may not be installed; allow qtkeychain to build without it (fallbacks: KWallet/plaintext)
set(LIBSECRET_SUPPORT OFF CACHE BOOL "Disable libsecret support for bundled qtkeychain" FORCE)
# Ensure qtkeychain doesn't build its own tests when embedded
set(BUILD_TESTING OFF CACHE BOOL "Disable CTest when embedding qtkeychain" FORCE)
add_subdirectory(third_party/qtkeychain)

# Find libvncclient
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBVNCCLIENT REQUIRED libvncclient)

# QTermWidget6 for the LXC terminal renderer.
# Try the upstream CMake config first, fall back to pkg-config so this
# stays portable across Debian/Fedora/Arch packagings.
find_package(qtermwidget6 QUIET)
if(NOT qtermwidget6_FOUND)
    pkg_check_modules(QTERMWIDGET REQUIRED qtermwidget6)
endif()

qt_add_library(proxmoxclientplugin SHARED
    plugin.cpp
    proxmoxclient.cpp
    proxmoxclient.h
    proxmoxcontroller.cpp
    proxmoxcontroller.h
    pbstypes.h
    secretstore.cpp
    secretstore.h
    notifier.cpp
    notifier.h
    vncclient.cpp
    vncclient.h
    vncframeview.cpp
    vncframeview.h
    vncwsproxy.cpp
    vncwsproxy.h
    lxcterminal.cpp
    lxcterminal.h
)

target_include_directories(proxmoxclientplugin PRIVATE
    ${LIBVNCCLIENT_INCLUDE_DIRS}
    ${QTERMWIDGET_INCLUDE_DIRS}
)

target_link_libraries(proxmoxclientplugin PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Qml
    Qt6::DBus
    Qt6::Gui
    Qt6::Quick
    Qt6::WebSockets
    Qt6::Widgets
    qt6keychain
    ${LIBVNCCLIENT_LIBRARIES}
)

if(qtermwidget6_FOUND)
    target_link_libraries(proxmoxclientplugin PRIVATE qtermwidget6)
else()
    target_link_libraries(proxmoxclientplugin PRIVATE ${QTERMWIDGET_LIBRARIES})
    target_link_directories(proxmoxclientplugin PRIVATE ${QTERMWIDGET_LIBRARY_DIRS})
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  find_program(MOLD_LINKER mold)
  if(MOLD_LINKER)
    target_link_options(proxmoxclientplugin PRIVATE -fuse-ld=mold)
  endif()
endif()