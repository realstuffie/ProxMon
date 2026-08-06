import QtTest
import QtQuick

// Exercises the shipped export/import module through the real QML JS engine
// (run via qmltestrunner, registered as the "configportability" CTest test).
import "../../ui/components/configportability.mjs" as CP

TestCase {
    name: "ConfigPortability"

    function validEnvelopeWith(cfg) {
        return JSON.stringify({
            "app": "proxmon-plasmoid",
            "schemaVersion": 1,
            "exportedAt": "2026-07-31T12:00:00Z",
            "config": cfg
        })
    }

    function test_exportEnvelopeShape() {
        var res = CP.buildExportEnvelope({ "proxmoxHost": "px.example.com", "proxmoxPort": 8443 })
        verify(res.ok, "export failed: " + res.error)
        var env = JSON.parse(res.jsonText)
        compare(env.app, "proxmon-plasmoid")
        compare(env.schemaVersion, 1)
        verify(typeof env.exportedAt === "string" && env.exportedAt.length > 0, "exportedAt missing")
        compare(env.config.proxmoxHost, "px.example.com")
        compare(env.config.proxmoxPort, 8443)
        // Absent values fall back to the main.xml defaults.
        compare(env.config.refreshInterval, 30)
        compare(env.config.ignoreSsl, false)
        compare(env.config.connectionMode, "single")
        compare(env.config.defaultSorting, "status")
        compare(env.config.terminalSize, "medium")
        compare(env.config.appearanceWindowOpacity, 100)
        verify(Array.isArray(env.config.multiHostsJson), "multiHostsJson must be a nested array")
    }

    function test_exportContainsEveryWhitelistKey() {
        var res = CP.buildExportEnvelope({})
        verify(res.ok, res.error)
        var env = JSON.parse(res.jsonText)
        var keys = CP.whitelistedKeys()
        compare(keys.length, 46) // canary: adding a config key must be a conscious decision
        for (var i = 0; i < keys.length; i++)
            verify(env.config[keys[i]] !== undefined, "export is missing key: " + keys[i])
    }

    function test_exportClampsAndNormalizes() {
        var res = CP.buildExportEnvelope({
            "proxmoxPort": 99999,          // clamped to range max
            "refreshInterval": "abc",      // wrong type -> default
            "defaultSorting": "bogus"      // invalid enum -> default
        })
        verify(res.ok, res.error)
        var env = JSON.parse(res.jsonText)
        compare(env.config.proxmoxPort, 65535)
        compare(env.config.refreshInterval, 30)
        compare(env.config.defaultSorting, "status")
    }

    function test_exportExcludesSecretMaterial() {
        var res = CP.buildExportEnvelope({
            "proxmoxHost": "px.example.com",
            "apiTokenId": "root@pam!mon",
            // Secret cfg_* keys must never be copied even if handed over:
            "apiTokenSecret": "SENTINEL-ONE",
            "pbsTokenSecretBuffer": "SENTINEL-TWO",
            "multiHostSecretsJson": "{\"k\":\"SENTINEL-THREE\"}",
            "someFutureSecretKey": "SENTINEL-FOUR",
            // ... and neither may secret fields smuggled inside multi-host entries:
            "multiHostsJson": JSON.stringify([
                { "host": "pve.lan", "tokenId": "root@pam!mon", "port": 8006,
                  "tokenSecret": "SENTINEL-FIVE", "secret": "SENTINEL-SIX" }
            ])
        })
        verify(res.ok, "export failed: " + res.error)
        verify(res.jsonText.indexOf("SENTINEL") === -1, "sentinel value leaked into export")
        verify(res.jsonText.indexOf("apiTokenSecret") === -1, "secret key name leaked")
        verify(res.jsonText.indexOf("pbsTokenSecretBuffer") === -1, "secret key name leaked")
        verify(res.jsonText.indexOf("multiHostSecretsJson") === -1, "secret key name leaked")
        verify(res.jsonText.indexOf("tokenSecret") === -1, "smuggled entry field leaked")
        var env = JSON.parse(res.jsonText)
        compare(env.config.multiHostsJson.length, 1)
        var entry = env.config.multiHostsJson[0]
        compare(entry.host, "pve.lan")
        verify(entry.tokenSecret === undefined, "smuggled entry field survived sanitizing")
        verify(entry.secret === undefined, "unknown entry field survived sanitizing")
    }

    function test_exportGuardFailsClosed() {
        // Any secret-like marker in the serialized output must abort the write,
        // even when it arrives as an innocent-looking value.
        var res = CP.buildExportEnvelope({ "proxmoxHost": "mytokenSecretHost" })
        verify(!res.ok, "guard did not abort on secret-like substring")
        verify(res.error.length > 0, "guard error should explain the abort")
        compare(res.jsonText, "")
    }

    function test_roundTrip() {
        var hosts = [
            { "name": "Home", "host": "pve.lan", "port": 8006, "tokenId": "root@pam!mon", "enabled": true },
            { "name": "Work", "host": "pve2.lan", "port": 8007, "tokenId": "u@pve!t", "enabled": false,
              "pbsEnabled": true, "pbsHost": "pbs.lan", "pbsPort": 8007, "pbsTokenId": "b@pbs!x" }
        ]
        var values = {
            "proxmoxHost": "px.example.com", "proxmoxPort": 8443, "apiTokenId": "root@pam!mon",
            "trustedCertPem": "-----BEGIN CERTIFICATE-----\nABC\n-----END CERTIFICATE-----\n",
            "trustedCertPath": "/etc/pve/ca.pem",
            "refreshInterval": 15, "ignoreSsl": true,
            "pbsEnabled": true, "pbsHost": "pbs.example.com", "pbsPort": 8007, "pbsTokenId": "b@pbs!t",
            "pbsIgnoreSsl": true, "pbsTrustedCertPem": "PEM2", "pbsTrustedCertPath": "/pbs.pem",
            "pbsBackupWarningDays": 5, "pbsBackupStaleDays": 20, "pbsRefreshInterval": 7200,
            "pbsExcludeTag": "no-pbs", "pbsExcludeVmids": "100,101",
            "connectionMode": "multiHost", "multiHostSharedCert": false,
            "multiHostsJson": JSON.stringify(hosts),
            "consoleEnabled": false, "terminalSize": "large", "powerActionsEnabled": false,
            "defaultSorting": "nameDesc", "compactMode": "running",
            "enableNotifications": false, "notifyMode": "blacklist", "notifyFilter": "web-*",
            "notifyOnStart": false, "notifyOnStop": false, "notifyOnNodeChange": false,
            "notifyRateLimitEnabled": false, "notifyRateLimitSeconds": 30, "redactNotifyIdentities": false,
            "autoRetry": false, "retryStartSeconds": 10, "retryMaxSeconds": 600,
            "lowLatency": true, "debugLogToJournal": true,
            "appearanceRunningColor": "#00ff00", "appearanceStoppedColor": "#ff0000",
            "appearanceNodeColor": "#0000ff",
            "appearanceCardTintOpacity": 25, "appearanceWindowOpacity": 80
        }
        var exp = CP.buildExportEnvelope(values)
        verify(exp.ok, exp.error)

        var imp = CP.validateImportFile(exp.jsonText)
        verify(imp.ok, imp.error)
        verify(imp.needsSecrets, "config with endpoints should flag needsSecrets")

        var cfg = imp.config
        compare(cfg.proxmoxHost, "px.example.com")
        compare(cfg.proxmoxPort, 8443)
        compare(cfg.apiTokenId, "root@pam!mon")
        compare(cfg.trustedCertPem, values.trustedCertPem)
        compare(cfg.trustedCertPath, "/etc/pve/ca.pem")
        compare(cfg.refreshInterval, 15)
        compare(cfg.ignoreSsl, true)
        compare(cfg.pbsEnabled, true)
        compare(cfg.pbsHost, "pbs.example.com")
        compare(cfg.pbsBackupStaleDays, 20)
        compare(cfg.pbsRefreshInterval, 7200)
        compare(cfg.pbsExcludeVmids, "100,101")
        compare(cfg.connectionMode, "multiHost")
        compare(cfg.multiHostSharedCert, false)
        compare(cfg.consoleEnabled, false)
        compare(cfg.terminalSize, "large")
        compare(cfg.defaultSorting, "nameDesc")
        compare(cfg.compactMode, "running")
        compare(cfg.enableNotifications, false)
        compare(cfg.notifyMode, "blacklist")
        compare(cfg.notifyFilter, "web-*")
        compare(cfg.notifyRateLimitSeconds, 30)
        compare(cfg.redactNotifyIdentities, false)
        compare(cfg.autoRetry, false)
        compare(cfg.retryMaxSeconds, 600)
        compare(cfg.lowLatency, true)
        compare(cfg.debugLogToJournal, true)
        compare(cfg.appearanceRunningColor, "#00ff00")
        compare(cfg.appearanceCardTintOpacity, 25)
        compare(cfg.appearanceWindowOpacity, 80)

        // multiHostsJson comes back as the stored (re-encoded string) form.
        compare(typeof cfg.multiHostsJson, "string")
        var arr = JSON.parse(cfg.multiHostsJson)
        compare(arr.length, 2)
        compare(arr[0].name, "Home")
        compare(arr[0].host, "pve.lan")
        compare(arr[0].port, 8006)
        compare(arr[1].enabled, false)
        compare(arr[1].pbsEnabled, true)
        compare(arr[1].pbsTokenId, "b@pbs!x")
    }

    function test_importRejectsInvalidFiles() {
        var cases = [
            "not json at all",
            "",
            "   ",
            "[]",
            "[1,2]",
            JSON.stringify({}),
            JSON.stringify({ "app": "other-app", "schemaVersion": 1, "config": {} }),
            JSON.stringify({ "app": "proxmon-plasmoid", "schemaVersion": 2, "config": {} }),
            JSON.stringify({ "app": "proxmon-plasmoid", "schemaVersion": "1", "config": {} }),
            JSON.stringify({ "app": "proxmon-plasmoid", "schemaVersion": 1 }),
            JSON.stringify({ "app": "proxmon-plasmoid", "schemaVersion": 1, "config": "nope" }),
            validEnvelopeWith({ "proxmoxPort": 70000 }),     // out of range
            validEnvelopeWith({ "proxmoxPort": 0 }),         // out of range
            validEnvelopeWith({ "proxmoxPort": "8006" }),    // wrong type
            validEnvelopeWith({ "refreshInterval": 3 }),     // below min
            validEnvelopeWith({ "refreshInterval": 10.5 }),  // non-integer
            validEnvelopeWith({ "ignoreSsl": "yes" }),       // bool as string
            validEnvelopeWith({ "connectionMode": "multi" }),// invalid enum
            validEnvelopeWith({ "defaultSorting": "bogus" }),
            validEnvelopeWith({ "terminalSize": "huge" }),
            validEnvelopeWith({ "notifyMode": "none" }),
            validEnvelopeWith({ "compactMode": "disk" }),
            validEnvelopeWith({ "appearanceCardTintOpacity": 101 }),
            validEnvelopeWith({ "multiHostsJson": "[{\"host\":\"h\"}]" }), // must be an array
            validEnvelopeWith({ "multiHostsJson": "[] is not json" }),
            validEnvelopeWith({ "multiHostsJson": [{}, {}, {}, {}, {}, {}] }), // > 5 entries
            validEnvelopeWith({ "multiHostsJson": ["not-an-object"] }),
            validEnvelopeWith({ "multiHostsJson": [{ "host": "h", "port": "8006" }] }),
            validEnvelopeWith({ "multiHostsJson": [{ "host": "h", "port": 70000 }] }),
            validEnvelopeWith({ "multiHostsJson": [{ "host": 42 }] }),
            validEnvelopeWith({ "multiHostsJson": [{ "enabled": "yes" }] })
        ]
        for (var i = 0; i < cases.length; i++) {
            var res = CP.validateImportFile(cases[i])
            verify(!res.ok, "case " + i + " must be rejected: " + cases[i])
            verify(res.error.length > 0, "case " + i + " must carry an error message")
            compare(Object.keys(res.config).length, 0, "rejected imports must not produce config (case " + i + ")")
            verify(!res.needsSecrets, "rejected imports must not flag needsSecrets (case " + i + ")")
        }
    }

    function test_importIgnoresUnknownKeys() {
        var res = CP.validateImportFile(validEnvelopeWith({
            "proxmoxHost": "px.example.com",
            "futureSetting": 123,
            "apiTokenSecret": "SMUGGLED",
            "pbsTokenSecretBuffer": "SMUGGLED",
            "multiHostSecretsJson": "{\"a\":\"b\"}"
        }))
        verify(res.ok, res.error)
        compare(res.config.proxmoxHost, "px.example.com")
        verify(res.config.futureSetting === undefined, "unknown key must be ignored")
        verify(res.config.apiTokenSecret === undefined, "secret key must never be applied")
        verify(res.config.pbsTokenSecretBuffer === undefined, "secret key must never be applied")
        verify(res.config.multiHostSecretsJson === undefined, "secret key must never be applied")
        compare(Object.keys(res.config).length, 1)
    }

    function test_partialImportOnlyAppliesPresentKeys() {
        var res = CP.validateImportFile(validEnvelopeWith({ "refreshInterval": 10 }))
        verify(res.ok, res.error)
        compare(Object.keys(res.config).length, 1)
        compare(res.config.refreshInterval, 10)
        verify(!res.needsSecrets)
    }

    function test_needsSecretsMatrix() {
        var ns = function (cfg) {
            var r = CP.validateImportFile(validEnvelopeWith(cfg))
            verify(r.ok, r.error)
            return r.needsSecrets
        }
        compare(ns({}), false)
        compare(ns({ "proxmoxHost": "h" }), false)                          // host without tokenId
        compare(ns({ "apiTokenId": "t" }), false)                           // tokenId without host
        compare(ns({ "proxmoxHost": "h", "apiTokenId": "t" }), true)
        compare(ns({ "pbsEnabled": true, "pbsHost": "b", "pbsTokenId": "t" }), true)
        compare(ns({ "pbsEnabled": false, "pbsHost": "b", "pbsTokenId": "t" }), false)
        compare(ns({ "connectionMode": "multiHost", "multiHostsJson": [] }), false)
        compare(ns({ "connectionMode": "multiHost",
                     "multiHostsJson": [{ "host": "h", "tokenId": "t" }] }), true)
        compare(ns({ "connectionMode": "multiHost",
                     "multiHostsJson": [{ "host": "h", "tokenId": "t", "enabled": false }] }), false)
        compare(ns({ "connectionMode": "multiHost",
                     "multiHostsJson": [{ "host": "h", "tokenId": "t", "enabled": false,
                                          "pbsEnabled": true, "pbsHost": "b", "pbsTokenId": "x" }] }), true)
    }

    function test_utf8ToBase64() {
        compare(CP.utf8ToBase64(""), "")
        compare(CP.utf8ToBase64("hello"), "aGVsbG8=")
        compare(CP.utf8ToBase64("héllo"), "aMOpbGxv")
        compare(CP.utf8ToBase64("✓"), "4pyT")
        compare(CP.utf8ToBase64("line1\nline2"), "bGluZTEKbGluZTI=")
        compare(CP.utf8ToBase64("{\"a\":1}"), "eyJhIjoxfQ==")
    }

    function test_urlToLocalPath() {
        compare(CP.urlToLocalPath("file:///home/u/My File.json"), "/home/u/My File.json")
        compare(CP.urlToLocalPath("file:///home/u/a%20b.json"), "/home/u/a b.json")
        compare(CP.urlToLocalPath("/plain/path.json"), "/plain/path.json")
        compare(CP.urlToLocalPath(""), "")
    }

    function test_buildAtomicWriteCommand() {
        var cmd = CP.buildAtomicWriteCommand("/tmp/a b/it's.json", "{\"k\":1}")
        verify(cmd.indexOf("set -e") !== -1, "command must fail on first error")
        verify(cmd.indexOf("mktemp") !== -1, "command must write a temp file first")
        verify(cmd.indexOf("base64 -d") !== -1, "payload must be base64 encoded")
        verify(cmd.indexOf("chmod 600") !== -1, "command must set owner-only permissions")
        verify(cmd.indexOf("mv -f") !== -1, "command must rename over the target (atomic)")
        verify(cmd.indexOf("sync -f") !== -1, "command must fsync")
        verify(cmd.indexOf("'/tmp/a b/it'\\''s.json'") !== -1, "path must be single-quote escaped")
        // No raw JSON in the command line (defense against shell-escaping bugs).
        verify(cmd.indexOf("{\"k\":1}") === -1, "raw JSON must not appear in the shell command")
    }

    function test_legacyFlatDefaultsRejectedByValidator() {
        // The old flat seed format must NOT pass envelope validation — the
        // dedicated legacy reader below is the only thing that understands it.
        var flat = JSON.stringify({
            "host": "px.old.example", "port": 8006, "tokenId": "root@pam!mon",
            "tokenSecret": "", "refreshInterval": 30, "ignoreSsl": true,
            "enableNotifications": true
        })
        verify(!CP.validateImportFile(flat).ok, "flat legacy file must fail envelope validation")
    }

    function test_parseLegacyDefaults() {
        var res = CP.parseLegacyDefaults(JSON.stringify({
            "host": "px.old.example", "port": 8443, "tokenId": "root@pam!mon",
            "tokenSecret": "LEGACY-SECRET-MUST-STAY-DEAD",
            "refreshInterval": 15, "ignoreSsl": true, "enableNotifications": false,
            "somethingElse": "ignored"
        }))
        verify(res.ok, res.error)
        verify(res.needsSecrets, "legacy seed with host+tokenId should flag needsSecrets")
        compare(res.config.proxmoxHost, "px.old.example")
        compare(res.config.proxmoxPort, 8443)
        compare(res.config.apiTokenId, "root@pam!mon")
        compare(res.config.refreshInterval, 15)
        compare(res.config.ignoreSsl, true)
        compare(res.config.enableNotifications, false)
        // The legacy secret field and unknown keys must never be mapped.
        verify(res.config.apiTokenSecret === undefined, "legacy tokenSecret must never be applied")
        verify(res.config.somethingElse === undefined, "unknown legacy keys must be ignored")
        compare(Object.keys(res.config).length, 6)

        // Partial seeds are fine (only present valid fields are mapped).
        var partial = CP.parseLegacyDefaults(JSON.stringify({ "host": "only-host" }))
        verify(partial.ok, partial.error)
        compare(Object.keys(partial.config).length, 1)
        verify(!partial.needsSecrets, "host without tokenId must not flag needsSecrets")

        // Invalid values are dropped, not mapped.
        var wrongTypes = CP.parseLegacyDefaults(JSON.stringify({ "port": "8006", "ignoreSsl": "yes" }))
        verify(!wrongTypes.ok, "legacy file with no mappable fields must fail")

        // Non-legacy input is rejected.
        verify(!CP.parseLegacyDefaults("not json").ok)
        verify(!CP.parseLegacyDefaults("").ok)
        verify(!CP.parseLegacyDefaults("[1,2]").ok)
        verify(!CP.parseLegacyDefaults(JSON.stringify({ "unrelated": true })).ok)
    }

    function test_buildReadCommand() {
        compare(CP.buildReadCommand("/tmp/simple.json"), "cat -- '/tmp/simple.json'")
        compare(CP.buildReadCommand("/tmp/it\'s.json"), "cat -- '/tmp/it'\\''s.json'")
    }
}
