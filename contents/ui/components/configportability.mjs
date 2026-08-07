// configportability.mjs
// Pure-JS logic for ProxMon plasmoid configuration export / import.
//
// SECURITY INVARIANTS (do not relax):
//  - Export copies ONLY the hard-coded whitelisted keys below. Secret keys
//    (apiTokenSecret, pbsTokenSecretBuffer, multiHostSecretsJson) are never
//    copied, and the serialized output is scanned for secret markers before
//    it may be written to disk (fail-closed).
//  - multiHostsJson entries are field-whitelisted as well, so unknown entry
//    sub-keys (e.g. a smuggled "secret") never reach the export file.
//  - Import applies only whitelisted, type-validated keys; unknown keys are
//    ignored silently. It never touches the keyring — matching secrets are
//    picked up automatically by the runtime's keychain auto-detection after
//    the user presses Apply.
//
// This module intentionally has no Qt imports so it runs identically in QML,
// qmltestrunner and Node.js (see contents/lib/tests/tst_configportability.qml).

const APP_ID = "proxmon-plasmoid"
const SCHEMA_VERSION = 1
const MAX_IMPORT_CHARS = 1024 * 1024 // 1 MiB — config exports are a few KiB
const MAX_MULTI_HOSTS = 5

// ---------------------------------------------------------------------------
// Whitelist tables (mirrors contents/config/main.xml, group "General").
// Anything not listed here is neither exported nor importable.
// ---------------------------------------------------------------------------

// Free-form string keys -> default value.
const STRING_KEYS = {
    "proxmoxHost": "",
    "apiTokenId": "",
    "trustedCertPem": "",
    "trustedCertPath": "",
    "pbsHost": "",
    "pbsTokenId": "",
    "pbsTrustedCertPem": "",
    "pbsTrustedCertPath": "",
    "pbsExcludeTag": "",
    "pbsExcludeVmids": "",
    "notifyFilter": "",
    "appearanceRunningColor": "",
    "appearanceStoppedColor": "",
    "appearanceNodeColor": ""
}

// Boolean keys -> default value.
const BOOL_KEYS = {
    "ignoreSsl": false,
    "pbsEnabled": false,
    "pbsIgnoreSsl": false,
    "multiHostSharedCert": true,
    "consoleEnabled": true,
    "powerActionsEnabled": true,
    "statsEnabled": true,
    "enableNotifications": true,
    "notifyOnStart": true,
    "notifyOnStop": true,
    "notifyOnNodeChange": true,
    "notifyRateLimitEnabled": true,
    "redactNotifyIdentities": true,
    "autoRetry": true,
    "lowLatency": false,
    "debugLogToJournal": false
}

// Integer keys -> [min, max, default]. Ranges mirror the KCM spin boxes.
const INT_KEYS = {
    "proxmoxPort": [1, 65535, 8006],
    "refreshInterval": [5, 3600, 30],
    "pbsPort": [1, 65535, 8007],
    "pbsBackupWarningDays": [1, 30, 7],
    "pbsBackupStaleDays": [1, 90, 14],
    "pbsRefreshInterval": [0, 86400, 3600],
    "notifyRateLimitSeconds": [0, 3600, 120],
    "retryStartSeconds": [1, 300, 5],
    "retryMaxSeconds": [5, 3600, 300],
    "appearanceCardTintOpacity": [0, 100, 10],
    "appearanceWindowOpacity": [0, 100, 100]
}

// Enum string keys -> [allowed values, default].
const ENUM_KEYS = {
    "connectionMode": [["single", "multiHost"], "single"],
    "terminalSize": [["small", "medium", "large"], "medium"],
    "defaultSorting": [["status", "statusId", "name", "nameDesc", "id", "idDesc"], "status"],
    "compactMode": [["cpu", "running", "error", "lastUpdate"], "cpu"],
    "notifyMode": [["all", "whitelist", "blacklist"], "all"]
}

// multiHostsJson is stored as a JSON string in KConfig but embedded as a real
// array in the export file. Entry fields are whitelisted too.
const ENTRY_STRING_KEYS = [
    "name", "host", "tokenId",
    "trustedCertPem", "trustedCertPath",
    "pbsHost", "pbsTokenId", "pbsTrustedCertPem", "pbsTrustedCertPath"
]
const ENTRY_BOOL_KEYS = ["enabled", "ignoreSsl", "pbsEnabled", "pbsIgnoreSsl"]
const ENTRY_INT_KEYS = {
    "port": [1, 65535],
    "pbsPort": [1, 65535],
    "pbsBackupWarningDays": [1, 30],
    "pbsBackupStaleDays": [1, 90]
}

// Markers that must never appear in a serialized export. Covers the excluded
// secret key names plus obvious secret substrings (fail-closed backstop; the
// primary invariant is the whitelist above).
const SECRET_MARKERS = [
    "apiTokenSecret",
    "pbsTokenSecretBuffer",
    "multiHostSecretsJson",
    "tokenSecret",
    "TokenSecret",
    "SecretBuffer"
]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isPlainObject(v) {
    return typeof v === "object" && v !== null && !Array.isArray(v)
}

function nonEmptyString(v) {
    return typeof v === "string" && v.trim() !== ""
}

// All whitelisted top-level config keys, in stable order. The config page
// uses this to know which cfg_* properties an import may assign.
function whitelistedKeys() {
    return Object.keys(STRING_KEYS)
        .concat(Object.keys(BOOL_KEYS))
        .concat(Object.keys(INT_KEYS))
        .concat(Object.keys(ENUM_KEYS))
        .concat(["multiHostsJson"])
}

// Single-quote a string for safe inclusion in a POSIX shell command line.
function shq(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// Convert a file dialog URL to a local filesystem path.
function urlToLocalPath(url) {
    var s = String(url || "")
    if (s.indexOf("file://") === 0) {
        s = s.substring(7)
        try {
            return decodeURIComponent(s)
        } catch (e) {
            return s
        }
    }
    return s
}

// UTF-8 encode + base64 encode without any environment globals (btoa is not
// guaranteed to exist and throws on non-Latin1 input anyway).
const B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function utf8ToBase64(text) {
    var s = String(text)
    var bytes = []
    for (var i = 0; i < s.length; i++) {
        var code = s.charCodeAt(i)
        if (code < 0x80) {
            bytes.push(code)
        } else if (code < 0x800) {
            bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
        } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < s.length) {
            var lo = s.charCodeAt(i + 1)
            if (lo >= 0xDC00 && lo <= 0xDFFF) {
                var cp = 0x10000 + ((code - 0xD800) << 10) + (lo - 0xDC00)
                bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
                           0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
                i++
            } else {
                bytes.push(0xEF, 0xBF, 0xBD) // lone high surrogate
            }
        } else if (code >= 0xDC00 && code <= 0xDFFF) {
            bytes.push(0xEF, 0xBF, 0xBD) // lone low surrogate
        } else {
            bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
        }
    }
    var out = []
    for (var j = 0; j < bytes.length; j += 3) {
        var b0 = bytes[j]
        var b1 = (j + 1 < bytes.length) ? bytes[j + 1] : null
        var b2 = (j + 2 < bytes.length) ? bytes[j + 2] : null
        var n = (b0 << 16) | ((b1 === null ? 0 : b1) << 8) | (b2 === null ? 0 : b2)
        out.push(B64_ALPHABET.charAt((n >> 18) & 63),
                 B64_ALPHABET.charAt((n >> 12) & 63),
                 b1 === null ? "=" : B64_ALPHABET.charAt((n >> 6) & 63),
                 b2 === null ? "=" : B64_ALPHABET.charAt(n & 63))
    }
    return out.join("")
}

// Build a shell command that writes `jsonText` to `path` atomically with
// owner-only permissions: base64 payload (no shell-escaping hazards) ->
// mktemp (0600) in the destination directory -> chmod 600 -> mv over the
// target (atomic rename within one filesystem) -> best-effort fsync.
function buildAtomicWriteCommand(path, jsonText) {
    var p = String(path)
    var idx = p.lastIndexOf("/")
    var dir = idx > 0 ? p.substring(0, idx) : "/"
    var b64 = utf8ToBase64(jsonText)
    return "set -e; " +
        "tmp=$(mktemp " + shq(dir + "/.proxmon-export.XXXXXX") + "); " +
        "trap 'rm -f \"$tmp\"' EXIT; " +
        "printf '%s' " + shq(b64) + " | base64 -d > \"$tmp\"; " +
        "chmod 600 \"$tmp\"; " +
        "mv -f \"$tmp\" " + shq(p) + "; " +
        "trap - EXIT; " +
        "sync -f " + shq(p) + " 2>/dev/null || true"
}

// Shell command to read a file's contents on stdout (non-zero exit if the
// file cannot be read).
function buildReadCommand(path) {
    return "cat -- " + shq(path)
}

// ---------------------------------------------------------------------------
// multiHostsJson entry sanitizing
// ---------------------------------------------------------------------------

// strict=false (export): silently drop fields with wrong types.
// strict=true  (import): return an error string on the first bad field.
function sanitizeEntry(entry, strict) {
    if (!isPlainObject(entry))
        return strict ? "multiHostsJson entries must be objects" : null
    var clean = {}
    var i, k, v
    for (i = 0; i < ENTRY_STRING_KEYS.length; i++) {
        k = ENTRY_STRING_KEYS[i]
        v = entry[k]
        if (v === undefined) continue
        if (typeof v === "string") clean[k] = v
        else if (strict) return "multiHostsJson entry field '" + k + "' must be a string"
    }
    for (i = 0; i < ENTRY_BOOL_KEYS.length; i++) {
        k = ENTRY_BOOL_KEYS[i]
        v = entry[k]
        if (v === undefined) continue
        if (typeof v === "boolean") clean[k] = v
        else if (strict) return "multiHostsJson entry field '" + k + "' must be a boolean"
    }
    for (var key in ENTRY_INT_KEYS) {
        if (!Object.prototype.hasOwnProperty.call(ENTRY_INT_KEYS, key)) continue
        v = entry[key]
        if (v === undefined) continue
        var range = ENTRY_INT_KEYS[key]
        if (typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= range[0] && v <= range[1]) {
            clean[key] = v
        } else if (strict) {
            return "multiHostsJson entry field '" + key + "' must be an integer between " + range[0] + " and " + range[1]
        }
    }
    // Unknown entry fields are dropped on purpose (blocks smuggled secrets).
    if (strict) return { entry: clean }
    return clean
}

// Export side: stored JSON string -> sanitized array for the export file.
function multiHostsToArray(stored) {
    if (typeof stored !== "string" || stored.trim() === "") return []
    var arr
    try {
        arr = JSON.parse(stored)
    } catch (e) {
        return []
    }
    if (!Array.isArray(arr)) return []
    var out = []
    for (var i = 0; i < arr.length && out.length < MAX_MULTI_HOSTS; i++) {
        var clean = sanitizeEntry(arr[i], false)
        if (clean) out.push(clean)
    }
    return out
}

// Import side: array from the file -> sanitized compact JSON string for
// storage, or an error string.
function multiHostsFromArray(value) {
    if (!Array.isArray(value))
        return "'multiHostsJson' must be an array"
    if (value.length > MAX_MULTI_HOSTS)
        return "'multiHostsJson' may contain at most " + MAX_MULTI_HOSTS + " entries"
    var out = []
    for (var i = 0; i < value.length; i++) {
        var res = sanitizeEntry(value[i], true)
        if (typeof res === "string") return res
        out.push(res.entry)
    }
    return { json: JSON.stringify(out) }
}

// ---------------------------------------------------------------------------
// Secret-exclusion guard (mandatory; mirrors assertNoSecretMaterial in the
// Electron reference implementation). Returns the offending marker or null.
// ---------------------------------------------------------------------------

function findSecretMaterial(serialized) {
    for (var i = 0; i < SECRET_MARKERS.length; i++) {
        if (serialized.indexOf(SECRET_MARKERS[i]) !== -1)
            return SECRET_MARKERS[i]
    }
    return null
}

// ---------------------------------------------------------------------------
// Export
// ---------------------------------------------------------------------------

// values: plain object of whitelisted cfg_* values from the config page.
// Missing/invalid values fall back to the main.xml defaults.
// Returns { ok, error, jsonText }.
function buildExportEnvelope(values) {
    values = isPlainObject(values) ? values : {}
    var cfg = {}
    var k, v

    for (k in STRING_KEYS) {
        if (!Object.prototype.hasOwnProperty.call(STRING_KEYS, k)) continue
        v = values[k]
        cfg[k] = (typeof v === "string") ? v : STRING_KEYS[k]
    }
    for (k in BOOL_KEYS) {
        if (!Object.prototype.hasOwnProperty.call(BOOL_KEYS, k)) continue
        v = values[k]
        cfg[k] = (typeof v === "boolean") ? v : BOOL_KEYS[k]
    }
    for (k in INT_KEYS) {
        if (!Object.prototype.hasOwnProperty.call(INT_KEYS, k)) continue
        var range = INT_KEYS[k]
        v = values[k]
        if (typeof v === "number" && isFinite(v)) {
            v = Math.round(v)
            if (v < range[0]) v = range[0]
            if (v > range[1]) v = range[1]
            cfg[k] = v
        } else {
            cfg[k] = range[2]
        }
    }
    for (k in ENUM_KEYS) {
        if (!Object.prototype.hasOwnProperty.call(ENUM_KEYS, k)) continue
        var allowed = ENUM_KEYS[k][0]
        v = values[k]
        cfg[k] = (typeof v === "string" && allowed.indexOf(v) !== -1) ? v : ENUM_KEYS[k][1]
    }
    cfg["multiHostsJson"] = multiHostsToArray(values["multiHostsJson"])

    var envelope = {
        "app": APP_ID,
        "schemaVersion": SCHEMA_VERSION,
        "exportedAt": new Date().toISOString(),
        "config": cfg
    }
    var jsonText = JSON.stringify(envelope, null, 2)

    var marker = findSecretMaterial(jsonText)
    if (marker !== null) {
        return { "ok": false, "error": "Export blocked: secret-like material detected (" + marker + ")", "jsonText": "" }
    }
    return { "ok": true, "error": "", "jsonText": jsonText }
}

// ---------------------------------------------------------------------------
// Import
// ---------------------------------------------------------------------------

function computeNeedsSecrets(cfg) {
    var mode = cfg["connectionMode"] || "single"
    if (mode === "multiHost") {
        var arr = []
        if (typeof cfg["multiHostsJson"] === "string") {
            try {
                arr = JSON.parse(cfg["multiHostsJson"])
            } catch (e) {
                arr = []
            }
        }
        if (!Array.isArray(arr)) arr = []
        for (var i = 0; i < arr.length; i++) {
            var e = arr[i]
            if (!isPlainObject(e)) continue
            if (e["enabled"] !== false && nonEmptyString(e["host"]) && nonEmptyString(e["tokenId"])) return true
            if (e["pbsEnabled"] === true && nonEmptyString(e["pbsHost"]) && nonEmptyString(e["pbsTokenId"])) return true
        }
        return false
    }
    if (nonEmptyString(cfg["proxmoxHost"]) && nonEmptyString(cfg["apiTokenId"])) return true
    if (cfg["pbsEnabled"] === true && nonEmptyString(cfg["pbsHost"]) && nonEmptyString(cfg["pbsTokenId"])) return true
    return false
}

// jsonText: raw file contents. Returns { ok, error, needsSecrets, config }.
// On !ok, config is an empty object and nothing must be applied.
function validateImportFile(jsonText) {
    var fail = function (msg) {
        return { "ok": false, "error": msg, "needsSecrets": false, "config": {} }
    }

    if (typeof jsonText !== "string" || jsonText.trim() === "")
        return fail("File is empty or could not be read")
    if (jsonText.length > MAX_IMPORT_CHARS)
        return fail("File is too large to be a ProxMon configuration export")

    var parsed
    try {
        parsed = JSON.parse(jsonText)
    } catch (e) {
        return fail("File is not valid JSON")
    }
    if (!isPlainObject(parsed))
        return fail("File is not a ProxMon configuration export")
    if (parsed["app"] !== APP_ID)
        return fail("Not a ProxMon plasmoid export (app identifier mismatch)")
    if (parsed["schemaVersion"] !== SCHEMA_VERSION)
        return fail("Unsupported schema version (expected " + SCHEMA_VERSION + ")")

    var rawCfg = parsed["config"]
    if (!isPlainObject(rawCfg))
        return fail("Export file has no configuration object")

    var cfg = {}
    for (var key in rawCfg) {
        if (!Object.prototype.hasOwnProperty.call(rawCfg, key)) continue
        var v = rawCfg[key]

        if (Object.prototype.hasOwnProperty.call(STRING_KEYS, key)) {
            if (typeof v !== "string") return fail("Setting '" + key + "' must be a string")
            cfg[key] = v
        } else if (Object.prototype.hasOwnProperty.call(BOOL_KEYS, key)) {
            if (typeof v !== "boolean") return fail("Setting '" + key + "' must be a boolean")
            cfg[key] = v
        } else if (Object.prototype.hasOwnProperty.call(INT_KEYS, key)) {
            var range = INT_KEYS[key]
            if (typeof v !== "number" || !isFinite(v) || Math.floor(v) !== v)
                return fail("Setting '" + key + "' must be an integer")
            if (v < range[0] || v > range[1])
                return fail("Setting '" + key + "' is out of range (" + range[0] + "–" + range[1] + ")")
            cfg[key] = v
        } else if (Object.prototype.hasOwnProperty.call(ENUM_KEYS, key)) {
            if (typeof v !== "string" || ENUM_KEYS[key][0].indexOf(v) === -1)
                return fail("Setting '" + key + "' has an invalid value")
            cfg[key] = v
        } else if (key === "multiHostsJson") {
            var res = multiHostsFromArray(v)
            if (typeof res === "string") return fail(res)
            cfg[key] = res.json
        }
        // Unknown keys are ignored silently (forward compatibility). Secret
        // key names are unknown by design, so they can never be applied.
    }

    return {
        "ok": true,
        "error": "",
        "needsSecrets": computeNeedsSecrets(cfg),
        "config": cfg
    }
}

// ---------------------------------------------------------------------------
// Legacy "Default Settings" seed reader (flat pre-envelope format)
// ---------------------------------------------------------------------------

// Reads the old flat defaults file:
//   {host, port, tokenId, tokenSecret, refreshInterval, ignoreSsl,
//    enableNotifications}
// and maps the non-secret fields onto cfg key names. tokenSecret is NEVER
// mapped — legacy files may contain one and it must stay dead. Returns the
// same result shape as validateImportFile so callers can chain:
//   var r = CP.validateImportFile(t); if (!r.ok) r = CP.parseLegacyDefaults(t)
function parseLegacyDefaults(jsonText) {
    var fail = function (msg) {
        return { "ok": false, "error": msg, "needsSecrets": false, "config": {} }
    }
    if (typeof jsonText !== "string" || jsonText.trim() === "")
        return fail("File is empty or could not be read")
    var s
    try {
        s = JSON.parse(jsonText)
    } catch (e) {
        return fail("File is not valid JSON")
    }
    if (!isPlainObject(s))
        return fail("File is not a legacy defaults file")

    var cfg = {}
    if (typeof s["host"] === "string" && s["host"] !== "")
        cfg["proxmoxHost"] = s["host"]
    if (typeof s["port"] === "number" && isFinite(s["port"]) && Math.floor(s["port"]) === s["port"]
            && s["port"] >= 1 && s["port"] <= 65535)
        cfg["proxmoxPort"] = s["port"]
    if (typeof s["tokenId"] === "string" && s["tokenId"] !== "")
        cfg["apiTokenId"] = s["tokenId"]
    if (typeof s["refreshInterval"] === "number" && isFinite(s["refreshInterval"])
            && s["refreshInterval"] >= 5 && s["refreshInterval"] <= 3600)
        cfg["refreshInterval"] = Math.round(s["refreshInterval"])
    if (typeof s["ignoreSsl"] === "boolean")
        cfg["ignoreSsl"] = s["ignoreSsl"]
    if (typeof s["enableNotifications"] === "boolean")
        cfg["enableNotifications"] = s["enableNotifications"]

    if (Object.keys(cfg).length === 0)
        return fail("File is not a legacy defaults file")
    return { "ok": true, "error": "", "needsSecrets": computeNeedsSecrets(cfg), "config": cfg }
}

export {
    APP_ID,
    SCHEMA_VERSION,
    MAX_MULTI_HOSTS,
    whitelistedKeys,
    shq,
    urlToLocalPath,
    utf8ToBase64,
    buildAtomicWriteCommand,
    buildReadCommand,
    findSecretMaterial,
    buildExportEnvelope,
    validateImportFile,
    parseLegacyDefaults,
    computeNeedsSecrets
}
