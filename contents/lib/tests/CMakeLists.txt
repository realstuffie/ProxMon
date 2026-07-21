qt_add_executable(tst_vnckeysym
    tst_vnckeysym.cpp
)

target_include_directories(tst_vnckeysym PRIVATE ..)

target_link_libraries(tst_vnckeysym PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME vnckeysym COMMAND tst_vnckeysym)

qt_add_executable(tst_proxmoxdatautils
    tst_proxmoxdatautils.cpp
    ../proxmoxdatautils.cpp
    ../proxmoxdatautils.h
)

target_include_directories(tst_proxmoxdatautils PRIVATE ..)

target_link_libraries(tst_proxmoxdatautils PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME proxmoxdatautils COMMAND tst_proxmoxdatautils)

qt_add_executable(tst_consolecredentials
    tst_consolecredentials.cpp
)

target_include_directories(tst_consolecredentials PRIVATE ..)

target_link_libraries(tst_consolecredentials PRIVATE
    proxmoxclientplugin
    Qt6::Core
    Qt6::Network
    Qt6::Test
)

add_test(NAME consolecredentials COMMAND tst_consolecredentials)

qt_add_executable(tst_proxmoxtaskutils
    tst_proxmoxtaskutils.cpp
    ../proxmoxtaskutils.cpp
    ../proxmoxtaskutils.h
)

target_include_directories(tst_proxmoxtaskutils PRIVATE ..)

target_link_libraries(tst_proxmoxtaskutils PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME proxmoxtaskutils COMMAND tst_proxmoxtaskutils)

qt_add_executable(tst_variantlistmodel
    tst_variantlistmodel.cpp
    ../variantlistmodel.cpp
    ../variantlistmodel.h
)

target_include_directories(tst_variantlistmodel PRIVATE ..)

target_link_libraries(tst_variantlistmodel PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME variantlistmodel COMMAND tst_variantlistmodel)

qt_add_executable(tst_debugsanitizer
    tst_debugsanitizer.cpp
)

target_include_directories(tst_debugsanitizer PRIVATE ..)

target_link_libraries(tst_debugsanitizer PRIVATE
    proxmoxclientplugin
    Qt6::Core
    Qt6::Test
)

add_test(NAME debugsanitizer COMMAND tst_debugsanitizer)
