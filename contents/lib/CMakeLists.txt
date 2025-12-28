cmake_minimum_required(VERSION 3.16)
project(proxmoxclientplugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Network Qml)

set(CMAKE_AUTOMOC ON)

# Bundled dependency: QtKeychain (stores secrets in the desktop keyring: KWallet/libsecret/etc)
# Build it with Qt6 (this project uses Qt6)
set(BUILD_WITH_QT6 ON CACHE BOOL "Build qtkeychain with Qt 6" FORCE)
set(BUILD_TRANSLATIONS OFF CACHE BOOL "Disable qtkeychain translations" FORCE)
set(BUILD_TEST_APPLICATION OFF CACHE BOOL "Disable qtkeychain test app" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libs for bundling" FORCE)
# Ensure keychain library is built with PIC so we can link it into our plugin .so
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# libsecret dev package may not be installed; allow qtkeychain to build without it (fallbacks: KWallet/plaintext)
set(LIBSECRET_SUPPORT OFF CACHE BOOL "Disable libsecret support for bundled qtkeychain" FORCE)
add_subdirectory(third_party/qtkeychain)

qt_add_library(proxmoxclientplugin SHARED
    plugin.cpp
    proxmoxclient.cpp
    proxmoxclient.h
    secretstore.cpp
    secretstore.h
)

target_link_libraries(proxmoxclientplugin PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Qml
    qt6keychain
)
