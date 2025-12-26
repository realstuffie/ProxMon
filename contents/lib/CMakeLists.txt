cmake_minimum_required(VERSION 3.16)
project(proxmoxclientplugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Network Qml)

qt_add_library(proxmoxclientplugin SHARED
    plugin.cpp
    proxmoxclient.cpp
    proxmoxclient.h
)

target_link_libraries(proxmoxclientplugin PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Qml
)
