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
    Qt6::Network
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

qt_add_executable(tst_secretkeyderivation
    tst_secretkeyderivation.cpp
)

target_include_directories(tst_secretkeyderivation PRIVATE ..)

target_link_libraries(tst_secretkeyderivation PRIVATE
    proxmoxclientplugin
    Qt6::Core
    Qt6::Network
    Qt6::Test
)

add_test(NAME secretkeyderivation COMMAND tst_secretkeyderivation)

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

# QML logic test for the config export/import module — runs the shipped
# contents/ui/components/configportability.mjs through the real QML JS engine.
# NOTE: /usr/bin/qmltestrunner can be a qtchooser shim delegating to a
# nonexistent Qt5 binary, so resolve the real Qt6 tools dir via qmake first.
set(_qt6_bin_hints "")
find_program(_proxmon_qmake NAMES qmake6 qmake-qt6 qmake)
if(_proxmon_qmake)
    get_filename_component(_proxmon_qmake_real "${_proxmon_qmake}" REALPATH)
    get_filename_component(_proxmon_qmake_dir "${_proxmon_qmake_real}" DIRECTORY)
    list(APPEND _qt6_bin_hints "${_proxmon_qmake_dir}")
    execute_process(
        COMMAND "${_proxmon_qmake_real}" -query QT_INSTALL_BINS
        OUTPUT_VARIABLE _proxmon_qt_install_bins
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_proxmon_qt_install_bins)
        list(APPEND _qt6_bin_hints "${_proxmon_qt_install_bins}")
    endif()
endif()
list(APPEND _qt6_bin_hints
    "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_BINS}"
    "${QT6_INSTALL_PREFIX}/lib/qt6/bin"
    "${QT6_INSTALL_PREFIX}/bin"
)
find_program(QMLTESTRUNNER_EXECUTABLE
    NAMES qmltestrunner qmltestrunner6
    HINTS ${_qt6_bin_hints}
)
if(QMLTESTRUNNER_EXECUTABLE)
    add_test(NAME configportability
        COMMAND ${QMLTESTRUNNER_EXECUTABLE} -input ${CMAKE_CURRENT_SOURCE_DIR}/tst_configportability.qml)
    set_tests_properties(configportability PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
else()
    message(STATUS "qmltestrunner not found — skipping the configportability QML test")
endif()

qt_add_executable(tst_pbsrequesttally
    tst_pbsrequesttally.cpp
)

target_include_directories(tst_pbsrequesttally PRIVATE ..)

target_link_libraries(tst_pbsrequesttally PRIVATE
    Qt6::Core
    Qt6::Test
)

add_test(NAME pbsrequesttally COMMAND tst_pbsrequesttally)
