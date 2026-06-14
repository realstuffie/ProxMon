#pragma once
// Ported from noVNC's domkeytable.js and keysym.js
// noVNC Copyright (C) 2018 The noVNC authors, Licensed under MPL 2.0
// C++ port for ProxMon VNC console

#include <QHash>
#include <QString>
#include <QtGlobal>

// Location constants (matching DOM spec)
#define KEY_LOC_STANDARD  0
#define KEY_LOC_LEFT      1
#define KEY_LOC_RIGHT     2
#define KEY_LOC_NUMPAD    3

// XK keysym values (subset needed for VNC)
#define XK_Cancel           0xFF69
#define XK_BackSpace        0xFF08
#define XK_Tab              0xFF09
#define XK_Clear            0xFF0B
#define XK_Return           0xFF0D
#define XK_Pause            0xFF13
#define XK_Scroll_Lock      0xFF14
#define XK_Escape           0xFF1B
#define XK_Delete           0xFFFF
#define XK_Home             0xFF50
#define XK_Left             0xFF51
#define XK_Up               0xFF52
#define XK_Right            0xFF53
#define XK_Down             0xFF54
#define XK_Prior            0xFF55
#define XK_Next             0xFF56
#define XK_End              0xFF57
#define XK_Insert           0xFF63
#define XK_Menu             0xFF67
#define XK_Num_Lock         0xFF7F
#define XK_KP_Space         0xFF80
#define XK_KP_Enter         0xFF8D
#define XK_KP_Home          0xFF95
#define XK_KP_Left          0xFF96
#define XK_KP_Up            0xFF97
#define XK_KP_Right         0xFF98
#define XK_KP_Down          0xFF99
#define XK_KP_Prior         0xFF9A
#define XK_KP_Next          0xFF9B
#define XK_KP_End           0xFF9C
#define XK_KP_Insert        0xFF9E
#define XK_KP_Delete        0xFF9F
#define XK_KP_Equal         0xFFBD
#define XK_KP_Multiply      0xFFAA
#define XK_KP_Add           0xFFAB
#define XK_KP_Separator     0xFFAC
#define XK_KP_Subtract      0xFFAD
#define XK_KP_Decimal       0xFFAE
#define XK_KP_Divide        0xFFAF
#define XK_KP_0             0xFFB0
#define XK_KP_1             0xFFB1
#define XK_KP_2             0xFFB2
#define XK_KP_3             0xFFB3
#define XK_KP_4             0xFFB4
#define XK_KP_5             0xFFB5
#define XK_KP_6             0xFFB6
#define XK_KP_7             0xFFB7
#define XK_KP_8             0xFFB8
#define XK_KP_9             0xFFB9
#define XK_KP_Begin         0xFF9D
#define XK_F1               0xFFBE
#define XK_F2               0xFFBF
#define XK_F3               0xFFC0
#define XK_F4               0xFFC1
#define XK_F5               0xFFC2
#define XK_F6               0xFFC3
#define XK_F7               0xFFC4
#define XK_F8               0xFFC5
#define XK_F9               0xFFC6
#define XK_F10              0xFFC7
#define XK_F11              0xFFC8
#define XK_F12              0xFFC9
#define XK_F13              0xFFCA
#define XK_F14              0xFFCB
#define XK_F15              0xFFCC
#define XK_F16              0xFFCD
#define XK_F17              0xFFCE
#define XK_F18              0xFFCF
#define XK_F19              0xFFD0
#define XK_F20              0xFFD1
#define XK_F21              0xFFD2
#define XK_F22              0xFFD3
#define XK_F23              0xFFD4
#define XK_F24              0xFFD5
#define XK_F25              0xFFD6
#define XK_F26              0xFFD7
#define XK_F27              0xFFD8
#define XK_F28              0xFFD9
#define XK_F29              0xFFDA
#define XK_F30              0xFFDB
#define XK_F31              0xFFDC
#define XK_F32              0xFFDD
#define XK_F33              0xFFDE
#define XK_F34              0xFFDF
#define XK_F35              0xFFE0
#define XK_Shift_L          0xFFE1
#define XK_Shift_R          0xFFE2
#define XK_Control_L        0xFFE3
#define XK_Control_R        0xFFE4
#define XK_Caps_Lock        0xFFE5
#define XK_Meta_L           0xFFE7
#define XK_Meta_R           0xFFE8
#define XK_Alt_L            0xFFE9
#define XK_Alt_R            0xFFEA
#define XK_Super_L          0xFFEB
#define XK_Super_R          0xFFEC
#define XK_ISO_Level3_Shift 0xFE03
#define XK_space            0x0020
#define XK_equal            0x003D
#define XK_plus             0x002B
#define XK_minus            0x002D
#define XK_asterisk         0x002A
#define XK_slash            0x002F
#define XK_period           0x002E
#define XK_comma            0x002C
#define XK_0                0x0030
#define XK_1                0x0031
#define XK_2                0x0032
#define XK_3                0x0033
#define XK_4                0x0034
#define XK_5                0x0035
#define XK_6                0x0036
#define XK_7                0x0037
#define XK_8                0x0038
#define XK_9                0x0039
#define XK_Print            0xFF61
#define XK_Execute          0xFF62
#define XK_Select           0xFF60
#define XK_Redo             0xFF66
#define XK_Undo             0xFF65
#define XK_Find             0xFF68
#define XK_Help             0xFF6A

// XF86 keys
#define XF86XK_Copy                 0x1008FF57
#define XF86XK_Cut                  0x1008FF58
#define XF86XK_Paste                0x1008FF6D
#define XF86XK_ZoomIn               0x1008FF8B
#define XF86XK_ZoomOut              0x1008FF8C
#define XF86XK_MonBrightnessDown    0x1008FF03
#define XF86XK_MonBrightnessUp      0x1008FF02
#define XF86XK_Eject                0x1008FF2C
#define XF86XK_LogOff               0x1008FF61
#define XF86XK_PowerOff             0x1008FF2A
#define XF86XK_PowerDown            0x1008FF21
#define XF86XK_Hibernate            0x1008FFA8
#define XF86XK_Standby              0x1008FF10
#define XF86XK_WakeUp               0x1008FF2B
#define XF86XK_AudioLowerVolume     0x1008FF11
#define XF86XK_AudioMute            0x1008FF12
#define XF86XK_AudioRaiseVolume     0x1008FF13
#define XF86XK_AudioPlay            0x1008FF14
#define XF86XK_AudioStop            0x1008FF15
#define XF86XK_AudioPrev            0x1008FF16
#define XF86XK_AudioNext            0x1008FF17
#define XF86XK_AudioRecord          0x1008FF1C
#define XF86XK_AudioPause           0x1008FF31
#define XF86XK_AudioForward         0x1008FF97
#define XF86XK_AudioRewind          0x1008FF3E
#define XF86XK_AudioMicMute         0x1008FFB2
#define XF86XK_Back                 0x1008FF26
#define XF86XK_Forward              0x1008FF27
#define XF86XK_Stop                 0x1008FF28
#define XF86XK_Refresh              0x1008FF29
#define XF86XK_HomePage             0x1008FF18
#define XF86XK_Favorites            0x1008FF30
#define XF86XK_Search               0x1008FF1B
#define XF86XK_Mail                 0x1008FF19
#define XF86XK_Reply                0x1008FF72
#define XF86XK_MailForward          0x1008FF90
#define XF86XK_Send                 0x1008FF7F
#define XF86XK_Close                0x1008FF56
#define XF86XK_Save                 0x1008FF77
#define XF86XK_New                  0x1008FF68
#define XF86XK_Open                 0x1008FF6B
#define XF86XK_Spell                0x1008FF7C
#define XF86XK_MyComputer           0x1008FF33
#define XF86XK_Calculator           0x1008FF1D
#define XF86XK_Calendar             0x1008FF20
#define XF86XK_AudioMedia           0x1008FF32
#define XF86XK_Music                0x1008FF92
#define XF86XK_Phone                0x1008FF6E
#define XF86XK_ScreenSaver          0x1008FF2D
#define XF86XK_Excel                0x1008FF5C
#define XF86XK_WWW                  0x1008FF2E
#define XF86XK_WebCam               0x1008FF8F
#define XF86XK_Word                 0x1008FF89
#define XF86XK_BrightnessAdjust     0x1008FF3B
#define XF86XK_AudioCycleTrack      0x1008FF9B
#define XF86XK_AudioRandomPlay      0x1008FF99
#define XF86XK_SplitScreen          0x1008FF7D
#define XF86XK_Subtitle             0x1008FF9A
#define XF86XK_Next_VMode           0x1008FE22

// Entry: [standard, left, right, numpad]
struct KeysymEntry {
    quint32 standard;
    quint32 left;
    quint32 right;
    quint32 numpad;
};

inline QHash<QString, KeysymEntry> buildDOMKeyTable()
{
    QHash<QString, KeysymEntry> t;
    auto addStandard = [&](const char *key, quint32 sym) {
        t[key] = {sym, sym, sym, sym};
    };
    auto addLeftRight = [&](const char *key, quint32 left, quint32 right) {
        t[key] = {left, left, right, left};
    };
    auto addNumpad = [&](const char *key, quint32 standard, quint32 numpad) {
        t[key] = {standard, standard, standard, numpad};
    };

    // Modifier keys
    addLeftRight("Alt",         XK_Alt_L,           XK_Alt_R);
    addStandard ("AltGraph",    XK_ISO_Level3_Shift);
    addStandard ("CapsLock",    XK_Caps_Lock);
    addLeftRight("Control",     XK_Control_L,       XK_Control_R);
    addLeftRight("Meta",        XK_Super_L,         XK_Super_R);
    addStandard ("NumLock",     XK_Num_Lock);
    addStandard ("ScrollLock",  XK_Scroll_Lock);
    addLeftRight("Shift",       XK_Shift_L,         XK_Shift_R);

    // Whitespace
    addNumpad("Enter",  XK_Return,  XK_KP_Enter);
    addStandard("Tab",  XK_Tab);
    addNumpad(" ",      XK_space,   XK_KP_Space);

    // Navigation
    addNumpad("ArrowDown",  XK_Down,    XK_KP_Down);
    addNumpad("ArrowLeft",  XK_Left,    XK_KP_Left);
    addNumpad("ArrowRight", XK_Right,   XK_KP_Right);
    addNumpad("ArrowUp",    XK_Up,      XK_KP_Up);
    addNumpad("End",        XK_End,     XK_KP_End);
    addNumpad("Home",       XK_Home,    XK_KP_Home);
    addNumpad("PageDown",   XK_Next,    XK_KP_Next);
    addNumpad("PageUp",     XK_Prior,   XK_KP_Prior);

    // Editing
    addStandard("Backspace",    XK_BackSpace);
    addNumpad("Clear",          XK_Clear,   XK_KP_Begin);
    addStandard("Copy",         XF86XK_Copy);
    addStandard("Cut",          XF86XK_Cut);
    addNumpad("Delete",         XK_Delete,  XK_KP_Delete);
    addNumpad("Insert",         XK_Insert,  XK_KP_Insert);
    addStandard("Paste",        XF86XK_Paste);
    addStandard("Redo",         XK_Redo);
    addStandard("Undo",         XK_Undo);

    // UI
    addStandard("Cancel",       XK_Cancel);
    addStandard("ContextMenu",  XK_Menu);
    addStandard("Escape",       XK_Escape);
    addStandard("Execute",      XK_Execute);
    addStandard("Find",         XK_Find);
    addStandard("Help",         XK_Help);
    addStandard("Pause",        XK_Pause);
    addStandard("Select",       XK_Select);
    addStandard("ZoomIn",       XF86XK_ZoomIn);
    addStandard("ZoomOut",      XF86XK_ZoomOut);

    // Device
    addStandard("BrightnessDown",   XF86XK_MonBrightnessDown);
    addStandard("BrightnessUp",     XF86XK_MonBrightnessUp);
    addStandard("Eject",            XF86XK_Eject);
    addStandard("LogOff",           XF86XK_LogOff);
    addStandard("Power",            XF86XK_PowerOff);
    addStandard("PowerOff",         XF86XK_PowerDown);
    addStandard("PrintScreen",      XK_Print);
    addStandard("Hibernate",        XF86XK_Hibernate);
    addStandard("Standby",          XF86XK_Standby);
    addStandard("WakeUp",           XF86XK_WakeUp);

    // Function keys
    addStandard("F1",  XK_F1);  addStandard("F2",  XK_F2);  addStandard("F3",  XK_F3);
    addStandard("F4",  XK_F4);  addStandard("F5",  XK_F5);  addStandard("F6",  XK_F6);
    addStandard("F7",  XK_F7);  addStandard("F8",  XK_F8);  addStandard("F9",  XK_F9);
    addStandard("F10", XK_F10); addStandard("F11", XK_F11); addStandard("F12", XK_F12);
    addStandard("F13", XK_F13); addStandard("F14", XK_F14); addStandard("F15", XK_F15);
    addStandard("F16", XK_F16); addStandard("F17", XK_F17); addStandard("F18", XK_F18);
    addStandard("F19", XK_F19); addStandard("F20", XK_F20); addStandard("F21", XK_F21);
    addStandard("F22", XK_F22); addStandard("F23", XK_F23); addStandard("F24", XK_F24);
    addStandard("F25", XK_F25); addStandard("F26", XK_F26); addStandard("F27", XK_F27);
    addStandard("F28", XK_F28); addStandard("F29", XK_F29); addStandard("F30", XK_F30);
    addStandard("F31", XK_F31); addStandard("F32", XK_F32); addStandard("F33", XK_F33);
    addStandard("F34", XK_F34); addStandard("F35", XK_F35);

    // Audio
    addStandard("AudioVolumeDown",      XF86XK_AudioLowerVolume);
    addStandard("AudioVolumeUp",        XF86XK_AudioRaiseVolume);
    addStandard("AudioVolumeMute",      XF86XK_AudioMute);
    addStandard("MicrophoneVolumeMute", XF86XK_AudioMicMute);
    addStandard("MediaFastForward",     XF86XK_AudioForward);
    addStandard("MediaPause",           XF86XK_AudioPause);
    addStandard("MediaPlay",            XF86XK_AudioPlay);
    addStandard("MediaRecord",          XF86XK_AudioRecord);
    addStandard("MediaRewind",          XF86XK_AudioRewind);
    addStandard("MediaStop",            XF86XK_AudioStop);
    addStandard("MediaTrackNext",       XF86XK_AudioNext);
    addStandard("MediaTrackPrevious",   XF86XK_AudioPrev);

    // Browser
    addStandard("BrowserBack",      XF86XK_Back);
    addStandard("BrowserFavorites", XF86XK_Favorites);
    addStandard("BrowserForward",   XF86XK_Forward);
    addStandard("BrowserHome",      XF86XK_HomePage);
    addStandard("BrowserRefresh",   XF86XK_Refresh);
    addStandard("BrowserSearch",    XF86XK_Search);
    addStandard("BrowserStop",      XF86XK_Stop);

    // App
    addStandard("Close",        XF86XK_Close);
    addStandard("MailForward",  XF86XK_MailForward);
    addStandard("MailReply",    XF86XK_Reply);
    addStandard("MailSend",     XF86XK_Send);
    addStandard("New",          XF86XK_New);
    addStandard("Open",         XF86XK_Open);
    addStandard("Print",        XK_Print);
    addStandard("Save",         XF86XK_Save);
    addStandard("SpellCheck",   XF86XK_Spell);
    addStandard("LaunchApplication1",   XF86XK_MyComputer);
    addStandard("LaunchApplication2",   XF86XK_Calculator);
    addStandard("LaunchCalendar",       XF86XK_Calendar);
    addStandard("LaunchMail",           XF86XK_Mail);
    addStandard("LaunchMediaPlayer",    XF86XK_AudioMedia);
    addStandard("LaunchMusicPlayer",    XF86XK_Music);
    addStandard("LaunchPhone",          XF86XK_Phone);
    addStandard("LaunchScreenSaver",    XF86XK_ScreenSaver);
    addStandard("LaunchSpreadsheet",    XF86XK_Excel);
    addStandard("LaunchWebBrowser",     XF86XK_WWW);
    addStandard("LaunchWebCam",         XF86XK_WebCam);
    addStandard("LaunchWordProcessor",  XF86XK_Word);

    // Numpad extras
    addNumpad("=", XK_equal,    XK_KP_Equal);
    addNumpad("+", XK_plus,     XK_KP_Add);
    addNumpad("-", XK_minus,    XK_KP_Subtract);
    addNumpad("*", XK_asterisk, XK_KP_Multiply);
    addNumpad("/", XK_slash,    XK_KP_Divide);
    addNumpad(".", XK_period,   XK_KP_Decimal);
    addNumpad(",", XK_comma,    XK_KP_Separator);
    addNumpad("0", XK_0, XK_KP_0); addNumpad("1", XK_1, XK_KP_1);
    addNumpad("2", XK_2, XK_KP_2); addNumpad("3", XK_3, XK_KP_3);
    addNumpad("4", XK_4, XK_KP_4); addNumpad("5", XK_5, XK_KP_5);
    addNumpad("6", XK_6, XK_KP_6); addNumpad("7", XK_7, XK_KP_7);
    addNumpad("8", XK_8, XK_KP_8); addNumpad("9", XK_9, XK_KP_9);

    return t;
}

// Singleton accessor
inline const QHash<QString, KeysymEntry>& domKeyTable()
{
    static QHash<QString, KeysymEntry> table = buildDOMKeyTable();
    return table;
}

// Look up keysym from DOM key name and location
inline quint32 keysymFromDOMKey(const QString &domKey, int location)
{
    const auto &table = domKeyTable();
    auto it = table.find(domKey);
    if (it == table.end()) return 0;
    const KeysymEntry &e = it.value();
    switch (location) {
    case KEY_LOC_LEFT:   return e.left;
    case KEY_LOC_RIGHT:  return e.right;
    case KEY_LOC_NUMPAD: return e.numpad;
    default:             return e.standard;
    }
}

// Map Qt key + location to DOM key name
inline QString qtKeyToDOMKey(Qt::Key key, int location)
{
    switch (key) {
    case Qt::Key_Shift:      return location == KEY_LOC_RIGHT ? "Shift" : "Shift";
    case Qt::Key_Control:    return "Control";
    case Qt::Key_Alt:        return "Alt";
    case Qt::Key_AltGr:      return "AltGraph";
    case Qt::Key_Meta:       return "Meta";
    case Qt::Key_Super_L:    return "Meta";
    case Qt::Key_Super_R:    return "Meta";
    case Qt::Key_CapsLock:   return "CapsLock";
    case Qt::Key_NumLock:    return "NumLock";
    case Qt::Key_ScrollLock: return "ScrollLock";
    case Qt::Key_Return:     return "Enter";
    case Qt::Key_Enter:      return "Enter";
    case Qt::Key_Tab:        return "Tab";
    case Qt::Key_Backtab:    return "Tab";
    case Qt::Key_Space:      return " ";
    case Qt::Key_Backspace:  return "Backspace";
    case Qt::Key_Delete:     return "Delete";
    case Qt::Key_Insert:     return "Insert";
    case Qt::Key_Escape:     return "Escape";
    case Qt::Key_Home:       return "Home";
    case Qt::Key_End:        return "End";
    case Qt::Key_Left:       return "ArrowLeft";
    case Qt::Key_Right:      return "ArrowRight";
    case Qt::Key_Up:         return "ArrowUp";
    case Qt::Key_Down:       return "ArrowDown";
    case Qt::Key_PageUp:     return "PageUp";
    case Qt::Key_PageDown:   return "PageDown";
    case Qt::Key_Print:      return "PrintScreen";
    case Qt::Key_Pause:      return "Pause";
    case Qt::Key_SysReq:     return "PrintScreen"; // SysRq shares XK_Print
    case Qt::Key_Menu:       return "ContextMenu";
    case Qt::Key_Help:       return "Help";
    case Qt::Key_F1:         return "F1";
    case Qt::Key_F2:         return "F2";
    case Qt::Key_F3:         return "F3";
    case Qt::Key_F4:         return "F4";
    case Qt::Key_F5:         return "F5";
    case Qt::Key_F6:         return "F6";
    case Qt::Key_F7:         return "F7";
    case Qt::Key_F8:         return "F8";
    case Qt::Key_F9:         return "F9";
    case Qt::Key_F10:        return "F10";
    case Qt::Key_F11:        return "F11";
    case Qt::Key_F12:        return "F12";
    case Qt::Key_F13:        return "F13";
    case Qt::Key_F14:        return "F14";
    case Qt::Key_F15:        return "F15";
    case Qt::Key_F16:        return "F16";
    case Qt::Key_F17:        return "F17";
    case Qt::Key_F18:        return "F18";
    case Qt::Key_F19:        return "F19";
    case Qt::Key_F20:        return "F20";
    case Qt::Key_F21:        return "F21";
    case Qt::Key_F22:        return "F22";
    case Qt::Key_F23:        return "F23";
    case Qt::Key_F24:        return "F24";
    case Qt::Key_F25:        return "F25";
    case Qt::Key_F26:        return "F26";
    case Qt::Key_F27:        return "F27";
    case Qt::Key_F28:        return "F28";
    case Qt::Key_F29:        return "F29";
    case Qt::Key_F30:        return "F30";
    case Qt::Key_F31:        return "F31";
    case Qt::Key_F32:        return "F32";
    case Qt::Key_F33:        return "F33";
    case Qt::Key_F34:        return "F34";
    case Qt::Key_F35:        return "F35";
    // Editing / UI actions that have DOM table entries
    case Qt::Key_Clear:      return "Clear";
    case Qt::Key_Cancel:     return "Cancel";
    case Qt::Key_Execute:    return "Execute";
    case Qt::Key_Select:     return "Select";
    case Qt::Key_Undo:       return "Undo";
    case Qt::Key_Redo:       return "Redo";
    case Qt::Key_Find:       return "Find";
    // Volume / media
    case Qt::Key_VolumeDown:              return "AudioVolumeDown";
    case Qt::Key_VolumeUp:               return "AudioVolumeUp";
    case Qt::Key_VolumeMute:             return "AudioVolumeMute";
    case Qt::Key_MicMute:                return "MicrophoneVolumeMute";
    case Qt::Key_MediaPlay:              return "MediaPlay";
    case Qt::Key_MediaPause:             return "MediaPause";
    case Qt::Key_MediaTogglePlayPause:   return "MediaPlay";
    case Qt::Key_MediaStop:              return "MediaStop";
    case Qt::Key_MediaNext:              return "MediaTrackNext";
    case Qt::Key_MediaPrevious:          return "MediaTrackPrevious";
    case Qt::Key_MediaRecord:            return "MediaRecord";
    // Browser
    case Qt::Key_Back:           return "BrowserBack";
    case Qt::Key_Forward:        return "BrowserForward";
    case Qt::Key_Refresh:        return "BrowserRefresh";
    case Qt::Key_Stop:           return "BrowserStop";
    case Qt::Key_Search:         return "BrowserSearch";
    case Qt::Key_HomePage:       return "BrowserHome";
    case Qt::Key_Favorites:      return "BrowserFavorites";
    default:                     return QString();
    }
}

// Main function: get keysym from Qt key event info
// location: 0=standard, 1=left, 2=right, 3=numpad
// text: event.text() for printable character fallback
inline quint32 getKeysym(Qt::Key key, const QString &text, int location)
{
    // First try the DOM key table for special keys
    const QString domKey = qtKeyToDOMKey(key, location);
    if (!domKey.isEmpty()) {
        quint32 sym = keysymFromDOMKey(domKey, location);
        if (sym) return sym;
    }

    // For printable characters, use Unicode codepoint directly
    // This is what noVNC does via keysyms.lookup(codepoint)
    if (!text.isEmpty()) {
        uint cp = text.at(0).unicode();
        if (cp >= 0x20 && cp != 0x7F) {
            // Unicode keysyms: codepoints 0x100-0x10FFFF map to 0x01000100+cp
            if (cp < 0x100) return cp;
            return 0x01000000 | cp;
        }
    }

    // Ctrl+key sets text to a control character (e.g. Ctrl+C → \x03) which
    // fails the cp >= 0x20 check above. Recover the base keysym from the Qt
    // key code so the server sees the correct key identity regardless of modifiers.
    if (key >= Qt::Key_A && key <= Qt::Key_Z)
        return quint32(key) + 0x20; // Qt Key_A–Z are uppercase; send lowercase keysym
    if (key >= Qt::Key_Space && key < Qt::Key(0x100))
        return quint32(key);

    return 0;
}
