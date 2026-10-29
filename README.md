# ForgeKit

A single self-contained dylib that turns any sideloaded iOS app into a development
workbench: a hidden in-app panel, a full container/root browser, runtime
introspection, UI automation, and an MCP server for remote control.

Designed for **jailed** devices: it links no injection framework (no
MobileSubstrate, ElleKit or libhooker). Every method replacement goes through the
Objective-C runtime, so the same binary also works on a jailbroken device.

```
Long-press the clock, or volume up → down  →   panel opens
http://<device-ip>:8787/mcp            →   MCP endpoint (bearer token)
http://<device-ip>:8787/?token=<token> →   web dashboard
```

Built binary: `ForgeKit.dylib` — arm64 + arm64e, iOS 14.0+, 932,912 bytes.

---

## What is inside

| Area | Capability |
|---|---|
| Hidden panel | **Long-press the time** in the status bar, or press **volume up then volume down**. The clock view is located by its text (12/24-hour and locale formats) or class, so the hot zone tracks the real clock frame; a top-left status rectangle is used when the clock is not rendered. Opens a window above the app at `UIWindowLevelAlert + 100`. |
| File browser | Container/root navigation, search, swipe rename/delete, context menus, text editor with save, hex viewer, image viewer, plist viewer/editor, zip create/extract, share sheet, chmod, POSIX attributes. |
| App root management | Bundle, data container, Documents, Library, tmp, app-group containers, `/`, `/var`, `/var/mobile`, bundle/data container roots, optional `/var/jb`. Container enumeration across the device when the sandbox permits it. |
| App introspection | Info.plist, entitlements from the code signature and embedded profile, URL schemes, Mach-O dependencies/rpaths for the app, Frameworks and PlugIns, loaded images, keychain items, HTTP cookies. |
| Runtime | JavaScriptCore console with `fk.*` filesystem bridge; ObjC class listing and class introspection (methods, ivars, protocols); memory stats; `dlopen` a dylib into the process. |
| UI automation | View-tree dump with frames/text/accessibility, tap by label or point, type into fields, JPEG screenshot, native alert, open URL. |
| Sandbox shell | 44 in-process commands (ls/tree/cat/hexdump/strings/grep/find/stat/md5/sha256/keychain/scp/download/…), terminal screen in the panel, `POST /api/shell`, MCP `shell`, and a loopback TCP listener compatible with iOS-sandbox-explorer's `client.py`. |
| Unity / IL2CPP | 35 libtool-compatible tools: images, classes, fields, methods, live objects, singletons, UI-text scan, PlayerPrefs, dump, method patching, scripting. See [ANALYSIS.md](ANALYSIS.md). |
| Remote access | Embedded HTTP server: MCP (JSON-RPC 2.0, Streamable HTTP) at `/mcp`, REST bridge at `/api/call`, dashboard at `/`, file download/upload at `/api/file`. |

No private frameworks, no CydiaSubstrate symbols, no shell-outs. Everything is
implemented with UIKit/Foundation/Security/JavaScriptCore/CoreImage/zlib.

---

## Build

### Xcode SDK only (what CI does)

```sh
./tools/build-dylib.sh          # → build/ForgeKit.dylib, universal arm64 + arm64e
```

### Theos (library target, no substrate)

```sh
export THEOS=~/theos
make                            # → .theos/obj/.../libForgeKit.dylib
```

CI: `.github/workflows/build.yml` builds the dylib on `macos-15`, verifies the
architectures, asserts the constructor symbol survived optimisation, and fails if
any substrate/MSHook/ellekit symbol appears in the binary.

---

## Inject into a jailed app

The dylib is a plain dynamic library, so the sideloader's normal injection path
works. With **SideInstaller** (same author, on-device):

1. App configuration → **Tweaks & injectors** → **Tweak storage** → import
   `ForgeKit.dylib`.
2. Add it to the target app's tweak list and enable injection.
3. Pick any injector (ElleKit / Substitute / Substrate) — ForgeKit does not call
   into the injector at runtime, so the choice only affects how the loader is
   embedded.
4. Install. The sideloader re-signs the whole bundle, which signs the dylib too.

Manual injection:

```sh
# 1. copy the dylib into the .app
cp ForgeKit.dylib Payload/App.app/Frameworks/ForgeKit.dylib

# 2. add a load command (run on macOS)
insert_dylib --inplace --add-load-cmd \
  @executable_path/Frameworks/ForgeKit.dylib Payload/App.app/App

# 3. re-sign the app and the dylib with the same identity
codesign -f -s "Apple Development: you@example.com" Payload/App.app/Frameworks/ForgeKit.dylib
codesign -f -s "Apple Development: you@example.com" \
  --entitlements entitlements.plist Payload/App.app
```

### One required Info.plist key

iOS gates inbound LAN connections behind local-network privacy. Add to the host
app's `Info.plist` before signing:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>ForgeKit exposes a local development server on your network.</string>
```

Without it the server still binds and works from Safari on the device
(`http://127.0.0.1:8787`), but LAN clients may be refused.

---

## Using the panel

* **Trigger** — long-press the time in the status bar (~0.5 s). The clock frame is
  resolved on every touch by walking the status-bar window for a clock-formatted
  label (`9:41`, `09:41`, `9:41 AM`) or a `*Time*` view, then converted to screen
  coordinates and inset by 4 pt. If the app hides the status bar, the top-left
  status-area rectangle is used instead (can be disabled in Settings). Hold
  duration, haptics and the fallback are configurable.
* **Volume gesture** — press volume up, then volume down, within 1.2 s (0.8 / 1.2 / 2.0
  selectable). Uses the ambient audio session, so it never interrupts playback. If the
  trigger arms while volume is at 0 % or 100 % it nudges the level to the middle once,
  because an already-maxed "up" press emits no change event.
* **Files** — starts in the app container. Toolbar: roots, go-to-path, hidden
  files, sort. Long-press a row for open / rename / duplicate / compress / share /
  info / delete. Text-like files open in an editor with Save; everything else
  opens in a hex viewer; images open with pinch-zoom.
* **Network** — start/stop the server, change the port, copy or regenerate the
  token, scan the QR code, open the dashboard, inspect the request log.
* **Runtime** — evaluate JavaScript with `fk.read`, `fk.write`, `fk.list`,
  `fk.stat`, `fk.info`, `fk.log`, `fk.sleep`.
* **Settings** — hold duration, haptics, volume trigger + window, clock-area fallback, token requirement,
  start-on-launch, port, token regeneration, log clearing.

---

## MCP server

Transport: **Streamable HTTP**, single POST endpoint, JSON-RPC 2.0.

* Endpoint: `http://<device-ip>:8787/mcp`
* Auth: `Authorization: Bearer <token>` (token shown in Network; requirement can be
  switched off in Settings)
* Protocol versions: `2025-06-18`, `2025-03-26`, `2024-11-05`
* Methods: `initialize`, `notifications/*`, `ping`, `tools/list`, `tools/call`,
  `resources/list`, `prompts/list`, `logging/setLevel`

Client configuration:

```json
{
  "mcpServers": {
    "forgekit": {
      "type": "http",
      "url": "http://192.168.1.42:8787/mcp",
      "headers": { "Authorization": "Bearer 3f9c1d7a..." }
    }
  }
}
```

Stdio-only clients can bridge with `npx mcp-remote http://192.168.1.42:8787/mcp --header "Authorization: Bearer <token>"`.

Smoke test:

```sh
curl -s http://192.168.1.42:8787/mcp \
  -H "Authorization: Bearer $FK_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"devkit_selftest","arguments":{}}}'
```

### Tools (87)

**Filesystem** — `fs_roots`, `fs_list`, `fs_stat`, `fs_read`, `fs_write`,
`fs_mkdir`, `fs_delete`, `fs_move`, `fs_copy`, `fs_search`, `fs_chmod`,
`fs_zip`, `fs_unzip`, `fs_zip_list`

**Application** — `app_info`, `app_paths`, `app_info_plist`, `app_plist_get`,
`app_plist_set`, `app_defaults_list`, `app_defaults_get`, `app_defaults_set`,
`app_entitlements`, `app_url_schemes`, `app_binaries`, `app_loaded_images`,
`app_keychain`, `app_cookies`, `app_dylib_load`, `app_containers`

**Runtime** — `runtime_eval`, `runtime_classes`, `runtime_class_info`,
`runtime_memory`

**UI** — `ui_tree`, `ui_tap`, `ui_type`, `ui_screenshot`, `ui_alert`,
`ui_open_url`

**Control** — `devkit_status`, `devkit_log`, `devkit_selftest`, `panel_open`,
`panel_close`, `server_start`, `server_stop`, `server_log`

**Unity / IL2CPP (35)** — `ping`, `runtime_info`, `list_images`, `list_classes`,
`class_info`, `find_field_owners`, `find_methods_by_pattern`,
`find_classes_inheriting_from`, `find_classes_implementing`, `find_objects`,
`inspect_object`, `inspect_collection`, `read_field`, `write_field`,
`invoke_method`, `patch_method`, `restore_patch`, `restore_all`, `patch_status`,
`watch_field`, `scan_ui_for_value`, `find_singletons`, `scene_roots`,
`read_player_prefs`, `write_player_prefs`, `compare_instances`, `dump`,
`run_lua`, `save_script`, `list_scripts`, `lua_help`, `run_ui_lua`,
`stop_ui_lua`, `ui_lua_status`, `toggle_menu`

**Shell (4)** — `shell`, `shell_help`, `shell_status`, `shell_server`

Paths accept `~`, `$APP`, `$CONTAINER`, `$DOCS`, `$LIB`, `$TMP`, or relative
paths (resolved against the app container).

### REST bridge

| Route | Purpose |
|---|---|
| `GET /` | dashboard (token prompt embedded) |
| `GET /health` | liveness |
| `POST /mcp` | MCP JSON-RPC |
| `POST /api/call` | `{"tool":"fs_list","arguments":{...}}` |
| `GET /api/call?tool=fs_list&path=/` | query-string form |
| `GET /api/file?path=` | raw download |
| `POST /api/file?path=` | raw upload |
| `GET /api/status` / `GET /api/log` / `GET /api/screenshot` | shortcuts |

---

## Sandbox shell

A second access path for people who prefer a terminal to MCP. It is the
functionality of `test1ng-guy/iOS-sandbox-explorer` rebuilt in-process: **no popen,
no exec, no shell expansion**, so it works in a jailed app and never escalates.

```
shell "ls -l"                       # MCP
curl -s http://device:8787/api/shell \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"command":"tree -d 2 Documents"}'
```

Panel → **Shell** opens a terminal with a command bar, shortcuts (`help`, `ls -l`,
`sandbox`, `containers`, `sysinfo`, `clear`) and a TCP server menu.

The TCP listener speaks the same one-command-per-connection protocol as the
reference project, so its Python client works unchanged:

```sh
iproxy 8080 8080            # USB tunnel
python3 client.py "sandbox" --host 127.0.0.1 --port 8080
```

It binds `127.0.0.1` by default. A LAN-bind toggle exists (Shell menu), but the
protocol itself has no authentication — leave it loopback-only unless the network
is trusted, or use the token-protected HTTP/MCP path instead.

| Group | Commands |
|---|---|
| Navigation | `ls [-a] [-l]`, `pwd`, `cd`, `tree [-d N]` |
| Read | `cat`, `head [-n]`, `tail [-n]`, `hexdump [-n]`, `strings [-n]`, `base64 [-d]` |
| Modify | `cp [-r]`, `mv`, `rm [-r]`, `mkdir [-p]`, `touch`, `chmod` |
| Inspect | `stat`, `file`, `md5`, `sha256`, `wc`, `du [-h]`, `realpath`, `readlink` |
| Search | `find [-name]`, `grep [-i] [-n]` |
| System | `id`, `uname`, `whoami`, `env`, `date`, `df`, `uptime`, `bundle`, `sandbox`, `sysinfo`, `memory`, `containers` |
| Secrets | `keychain [dump] [--class generic|internet|certificate]` |
| Transfer | `download <path> [host_path]`, `scp -r <path> host:./dir` → `SCP:` + base64 lines |

`containers` lists other apps' data/bundle containers when the sandbox exposes
their metadata. Transfers cap a single file at 3 MB and the whole response at 4 MB.

---

## Unity / IL2CPP

ForgeKit resolves the IL2CPP API with `dlsym` at runtime; nothing is linked and
non-Unity apps simply report `il2cpp: unavailable` (`runtime_info`).

```
runtime_info                         → backend, assemblies, classes, patch slots
list_classes {filter:"Player"}       → candidate classes
class_info {class:"Game.Model.Player"} → fields, methods, parent, interfaces
find_objects {class:"Game.Model.Player"} → live pointers
read_field / write_field             → static (object 0) or instance
invoke_method {class, method, object, args}
patch_method {class, method, mode:"return"|"nop"|"redirect", value}
restore_patch / restore_all / patch_status
dump {filter, path}                  → Documents/forgekit-dump-*.txt
```

Patching swaps `MethodInfo.methodPointer` and saves the original, so restore is
exact. Constant returns support bool, integers, float, double, string and `nop`;
`redirect` points one method at another. Slots: 64. Stubs need executable `mmap`;
a hardened process that denies it gets a clear error.

### Scripting

The tool names are libtool's, the engine is JavaScriptCore:

```js
var cls = Class.fromName("Game.Model.Player");
cls.findObjects(5);
cls.read("coins", 0);
cls.write("coins", 999, 0);
cls.invoke("SetCoins", ptr, [999]);
```

`run_ui_lua` runs the script once per second and renders its `uiText` in a
non-interactive overlay. `save_script` persists `.js` files under
`Documents/ForgeKit/scripts`.

Coverage, substitutions and the full bug audit: **[ANALYSIS.md](ANALYSIS.md)**.

---

## Architecture

```
Sources/
  ForgeKit.h          public API surface (all FK* classes and helpers)
  FKUtil.m            paths, sandbox probes, entitlements, Mach-O deps, keychain,
                      cookies, formatting, swizzling, window helpers, preferences
  FKHooks.m           constructor, UIWindow swizzles, notification observers
  FKPanel.m           panel lifecycle, status-bar clock gesture, home screen
  FKPanelScreens.h    internal screen declarations
  FKPanelScreens.m    defaults, keychain, settings, log
  FKServerScreens.m   network console, JavaScript console
  FKFileBrowser.m     file browser, previews, file operations
  FKUI.m              list/text/hex/image controllers
  FKZip.m             zip writer + extractor (zlib, traversal-safe)
  FKRuntime.m         JSC evaluation, ObjC introspection, UI automation
  FKTools.m           tool catalogue, dispatch, filesystem tools
  FKToolsApp.m        application/runtime/UI/server tools (category)
  FKIL2CPP.h/.m       IL2CPP bridge: dlsym table, class cache, fields, invoke,
                      patcher (method-pointer swap + ARM64 stubs)
  FKUnityTools.m      35 Unity tools + JS Class bridge + UI overlay
  FKUnityScreens.m    class browser, object inspector, patch screen, script console
  FKShell.h/.m        sandbox shell: 46 commands, no popen/exec
  FKShellServer.m     loopback TCP transport (client.py compatible)
  FKShellTools.m      4 shell MCP tools
  FKShellScreens.m    terminal UI
  FKToolsPrivate.h    shared internal declarations
  FKHTTPServer.m      socket server, routing, auth, request log
  FKMCP.m             JSON-RPC 2.0 / MCP semantics
  FKWebUI.m           dashboard HTML compiled into the binary
Resources/dashboard.html  source of the dashboard (regenerate FKWebUI.m)
```

Panel window is created lazily and never touches the app's view hierarchy.
A `UILongPressGestureRecognizer` is added to every window at or below
`UIWindowLevelAlert`, including the app's own status-bar window. Its delegate
returns `YES` only for touches inside the clock frame, `cancelsTouchesInView` is
`NO`, and simultaneous recognition is allowed, so the rest of the status bar and
the app's touch handling are untouched.

---

## Limits worth knowing

* **Sandbox.** In a jailed app ForgeKit sees the same filesystem the app does:
  its own container, its group containers, and read-only system paths. Other apps'
  containers (`app_containers`) only enumerate on a jailbroken device or with
  container entitlements.
* **Dylib loading.** `app_dylib_load` calls `dlopen`; a jailed process only loads
  images that are already signed into the bundle. On a jailbroken device
  (or with a get-task-allow debugger attached) unsigned libraries load normally.
* **JavaScript has no watchdog.** An infinite loop in `runtime_eval` blocks that
  HTTP worker thread (not the app's UI, unless invoked from the panel console).
* **Screenshots** capture the key window. When the panel is open, that is the
  panel.
* **Local network privacy** needs `NSLocalNetworkUsageDescription` in the host
  app, as above.
* **MCP token** is enabled by default; the server binds `0.0.0.0`, so treat the
  token like a password. Regenerate it from Network or Settings.
* **iOS 14+**. `UIScene` is required for window placement; apps that still run a
  single legacy window fall back to `UIScreen` bounds.
* **Volume events are not a public API.** The trigger observes the system's
  AVSystemController change notification (by string name) with a KVO fallback on
  `AVAudioSession.outputVolume`; both are best-effort and can be muted by other audio
  routes. It defaults on; the Settings toggle disarms it and deactivates the session.
* **Shell scope.** The shell sees exactly what the app sees; `containers` only
  enumerates other apps on a jailbroken device or with container entitlements.
  The TCP listener is unauthenticated by design (loopback default); LAN binding is
  opt-in and should be treated as trusted-network only.
* **IL2CPP only.** The Unity tools need exportable `il2cpp_*` symbols. Stripped or
  Mono backends report unavailable. `find_objects` on plain C# classes uses a
  bounded static-field scan, not a GC heap walk; `inspect_collection` supports
  arrays and `List<T>`. Details in ANALYSIS.md.

---

## Regenerating the dashboard

```sh
python3 - <<'PY'
html = open('Resources/dashboard.html').read().split('\n')
out = ['//\n//  FKWebUI.m — generated from Resources/dashboard.html. Do not edit by hand.\n//\n',
       '#import <Foundation/Foundation.h>\nstatic const char *FKWebDashboardSource =\n']
out += ['    "%s\\n"\n' % l.replace('\\', '\\\\').replace('"', '\\"') for l in html[:-1]]
out += ['    "%s"\n;\n\n' % html[-1].replace('\\', '\\\\').replace('"', '\\"'),
        'NSString *FKWebDashboardHTML(void) {\n    static NSString *html;\n    static dispatch_once_t once;\n'
        '    dispatch_once(&once, ^{ html = [NSString stringWithUTF8String:FKWebDashboardSource]; });\n'
        '    return html ?: @"";\n}\n']
open('Sources/FKWebUI.m', 'w').write(''.join(out))
PY
```

## License

MIT.
