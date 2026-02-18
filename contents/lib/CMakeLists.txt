cmake_minimum_required(VERSION 3.16)
project(proxmoxclientplugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Network Qml DBus)

set(CMAKE_AUTOMOC ON)

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

qt_add_library(proxmoxclientplugin SHARED
    plugin.cpp
    proxmoxclient.cpp
    proxmoxclient.h
    secretstore.cpp
    secretstore.h
    notifier.cpp
    notifier.h
)

target_link_libraries(proxmoxclientplugin PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Qml
    Qt6::DBus
    qt6keychain
)
