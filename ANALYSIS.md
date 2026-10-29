# libtool → ForgeKit: coverage and audit

Reference binary: `libtool.dylib`, 6,839,232 bytes, Mach-O arm64, stripped.
Method: `strings` extraction (31,293 lines), demangled C++ symbols, and the embedded
agent prompt in the binary (`SECTION 2 — TOOL CATALOG`) which lists every MCP tool
with its semantics. No server schemas are present as literal JSON, so the prompt is
the authoritative surface.

Result: **35 libtool tools implemented** in ForgeKit (83 MCP tools total).
Unity/IL2CPP support is real: every il2cpp entry point is resolved with `dlsym`,
nothing is stubbed to return fake success.

---

## 1. What libtool actually exposes

### 1.1 MCP tools (35)

| # | Tool | Kind |
|---|---|---|
| 1 | `ping` | liveness |
| 2 | `runtime_info` | backend |
| 3 | `list_images` | discovery |
| 4 | `list_classes` | discovery |
| 5 | `class_info` | discovery |
| 6 | `find_field_owners` | cross-class scan |
| 7 | `find_methods_by_pattern` | cross-class scan |
| 8 | `find_classes_inheriting_from` | hierarchy |
| 9 | `find_classes_implementing` | hierarchy |
| 10 | `find_objects` | live instances |
| 11 | `find_singletons` | static scan |
| 12 | `inspect_object` | field snapshot |
| 13 | `inspect_collection` | collection reader |
| 14 | `compare_instances` | batch compare |
| 15 | `read_field` | read |
| 16 | `write_field` | mutate |
| 17 | `invoke_method` | mutate/probe |
| 18 | `watch_field` | sampling |
| 19 | `scan_ui_for_value` | UI verify |
| 20 | `scene_roots` | scene map |
| 21 | `read_player_prefs` | persistence |
| 22 | `write_player_prefs` | persistence |
| 23 | `patch_method` | patcher |
| 24 | `restore_patch` | patcher |
| 25 | `restore_all` | patcher |
| 26 | `patch_status` | patcher |
| 27 | `dump` | static dump |
| 28 | `run_lua` | scripting |
| 29 | `run_ui_lua` | scripting + overlay |
| 30 | `stop_ui_lua` | scripting |
| 31 | `ui_lua_status` | scripting |
| 32 | `lua_help` | scripting |
| 33 | `save_script` | scripting |
| 34 | `list_scripts` | scripting |
| 35 | `toggle_menu` | UI |

### 1.2 Non-MCP utilities found in the binary

| Utility | Evidence | Status in ForgeKit |
|---|---|---|
| Class browser + inspector | `ClassesTab`, `DrawClassInspectorPopup`, `ImGuiObjectSelector`, `CallerView`, `StaticFieldsView` | Implemented as Unity → class list → fields/methods → instances → field navigation |
| Static dumper | `Tool::Dumper`, `handleDump`, `dumps` | `dump` (text, filtered, to Documents) |
| Patcher (return/redirect/nop) | `Patcher::patchReturnPtr`, `patchRedirect`, `STATIC_HOOK_*` | `patch_method` + `restore_*` (method-pointer swap + generated ARM64 stub) |
| Object finder with liveness | `GC::FindObjects`, `FIND_OBJECTS` telemetry | Unity `FindObjectsOfType` + bounded static-field fallback (see limits) |
| Lua 5.4.8 | `$LuaVersion: Lua 5.4.8`, `libtool_script.lua` | JavaScriptCore with a `Class` bridge (see §3) |
| Persistent ImGui menu | ImGui sources, `toggle_menu` | UIKit overlay (1 Hz) + panel |
| ESP / AI tab / auth device flow | `ESPTab`, `AITab`, `/api/auth/device/*` | Not ported — see §4 |

---

## 2. Implementation map

All 35 names are registered by `FKUnityTools` and dispatch to `FKIL2CPP`.

| libtool | ForgeKit implementation |
|---|---|
| `ping` / `runtime_info` | bridge state, image/class counts, patch capacity |
| `list_images` | `il2cpp_domain_get_assemblies` → image names + class counts |
| `list_classes` | cached class table (image, namespace, short name, pointer) with substring filter |
| `class_info` | fields (type/static/offset), methods (return/params), parent, interfaces |
| `find_field_owners` | every class with a field whose type name matches |
| `find_methods_by_pattern` | name + return-type substring, cross-class |
| `find_classes_inheriting_from` | walks the parent chain (32 levels) |
| `find_classes_implementing` | walks the interface iterator |
| `find_objects` | `UnityEngine.Object.FindObjectsOfType(Type)` (or `FindObjectsByType`), then static-field scan fallback |
| `find_singletons` | static fields named `instance`, `_instance`, `s_instance`, `m_instance`, `shared` |
| `inspect_object` | class chain walk, per-field reads, navigable object pointers |
| `inspect_collection` | arrays (`+32` data offset) and `List<T>` (`_items` + `_size`) |
| `compare_instances` | up to 5 classes → instance count + first-instance field snapshot |
| `read_field` / `write_field` | type-aware reads/writes for primitives, enums, strings, object refs |
| `invoke_method` | arg-count-aware overload resolution, primitives/strings/objects, unboxed returns |
| `watch_field` | N samples with sleep, changed/distinct counts |
| `scan_ui_for_value` | `UnityEngine.UI.Text`, `TMPro.TMP_Text`, `TextMeshProUGUI`; reads `m_Text`/`m_text`/`text` |
| `scene_roots` | Transform objects whose `m_Father`/`m_Parent` is null; name via `Object.get_name` |
| `read_player_prefs` / `write_player_prefs` | `UnityEngine.PlayerPrefs.GetInt/GetFloat/GetString` and setters + `Save` |
| `patch_method` | `return` (int/bool/float/double/pointer/string/nop), `redirect`, `nop` |
| `restore_patch` / `restore_all` / `patch_status` | 64-slot table, original pointer saved, stub unmapped |
| `dump` | filtered text dump with counts and duration |
| `run_lua` / `save_script` / `list_scripts` / `lua_help` | JS engine (§3) |
| `run_ui_lua` / `stop_ui_lua` / `ui_lua_status` | 1 Hz JS tick + non-interactive UIKit overlay |
| `toggle_menu` | panel show/hide |

Correctness details that matter:

* Field reads are type-dispatched from `Il2CppTypeEnum`, not by guessing widths — bool is 1 byte, `int` 4, `long` 8, `float`/`double` native, strings decoded from UTF-16 at `+16` length / `+20` chars.
* Every object pointer is validated against the task's VM regions before dereference, so a stale pointer returns an error instead of crashing the host app.
* Method invocation resolves the overload by matching both name **and** argument count; libtool's own docs warn about overload ambiguity.
* Patches patch the `MethodInfo.methodPointer` slot (offset 0 on all current Unity layouts) and save the original pointer, so restore is exact. Generated stubs live in `mmap`'d pages made RX and instruction-cache-invalidated.
* String return patches create an `Il2CppString` and root it with `il2cpp_gchandle_new(pinned)`, freed on restore — otherwise the GC could collect the constant.

---

## 3. Lua substitution (deliberate)

libtool embeds Lua 5.4.8 with a userdata-heavy API (`__index`, `__newindex`,
`cls.StaticName`, `cls:findObjects()`). ForgeKit ships JavaScriptCore instead and
exposes the same operations as methods:

```js
var cls = Class.fromName("Game.Model.Player");
cls.findObjects(5);            // [{ptr, class}]
cls.read("coins", 0);          // static field
cls.write("coins", 999, 0);
cls.invoke("SetCoins", ptr, [999]);
cls.info();
```

Why: Lua + a full userdata bridge would add ~30 C files and a second runtime to a
dylib whose host apps already carry JSC via WebKit; the tool names and semantics are
preserved, the syntax is not. `lua_help` says this explicitly, and `run_lua`'s
description states it. Saved scripts are `.js`.

`run_ui_lua` keeps libtool's concept (persistent script + on-screen readout) but
renders `uiText` in a UIKit overlay at 1 Hz rather than a Dear ImGui window.

---

## 4. Not ported, and why

| Feature | Reason |
|---|---|
| ESP / aimbot overlays | Graphics-hook and game-specific world projection; no meaning for a general app toolkit, and it would require hooking Unity's render pipeline. |
| AI chat tab | Product-specific LLM backend (`AITab.mm`); ForgeKit already exposes its tools to any MCP client, which is the same capability without a bundled service. |
| Device auth / licensing (`/api/auth/device/*`, OAuth PKCE) | libtool's commercial licensing, not a development utility. |
| ImGui menu | UIKit panel replaces it; ImGui would add ~1 MB and a render loop to every host app. |
| `STATIC_HOOK_*` inline hook engine | Replaced by method-pointer patches (return value, redirect, nop). Arbitrary instruction-level hooks are not exposed because they cannot be made safe across Unity versions without disassembly. |

---

## 5. Bugs found in ForgeKit during this pass (fixed)

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Keyboard never appeared in panel fields; `ui_screenshot` captured the app behind the panel | Panel window was shown with `hidden = NO` but never became key | `makeKeyAndVisible` on show, previous key window restored on hide |
| 2 | Keychain detail could push onto the host app's navigation stack | Used `FKTopViewController().navigationController` from inside the panel | Uses `self.navigationController` with a weak capture |
| 3 | Empty zip archives failed to list/extract | EOCD scan required `i > 0`, skipping offset 0 | Signed lower bound, scans down to 0 |
| 4 | Array plists opened as hex | Preview only used `dictionaryWithContentsOfFile:` | `NSPropertyListSerialization` |
| 5 | Empty port field started the server on port 1 with a confusing error | `integerValue` of empty string is 0, clamped to 1 | Range validation with alert |
| 6 | Request log always showed 0 bytes | Placeholder value left in the log entry | Measures the actual response payload |
| 7 | Context menu promised "Open in new window" but reused the stack | Mislabeled action | Relabeled "Open in browser" |
| 8 | Jailbreak install pulled in MobileSubstrate | `control` declared it as a dependency | Removed; the dylib links no injection framework |
| 9 | `FKScriptEngine` exception handler dereferenced a weak `self` | Weak capture read through `->` | Strongify before use |
| 10 | Unity object rows could throw while building the menu | `NSDictionary` literal with a possibly-nil `chevron` | Mutable dictionary, conditional assignment |
| 11 | Short class names failed in scripts/tools | Lookup required an exact full name | Unique short-name fallback |
| 12 | Wrong overload invoked for overloaded methods | First name match won | Matches argument count first |
| 13 | Patched string constants could be collected | Unrooted `Il2CppString` stored in a stub | GC handle (pinned), freed on restore |

Previously fixed in 1.2.0: panel activation zone, port polling, HTTP auth, thread-safe
panel visibility, synchronous main-thread UI automation.

---

## 6. Known limits (documented, not bugs)

* `find_objects` on a plain C# class (not a `UnityEngine.Object`) uses a bounded
  static-field scan (6 s budget). libtool additionally walks the GC heap; that needs
  `il2cpp_gc_*` heap iteration which is not part of the public export set.
* `inspect_collection` covers arrays and `List<T>`. `Dictionary`, `HashSet`, `Queue`
  and `Stack` return an explicit unsupported-type error.
* `patch_method` supports constant returns for bool/int/float/double/string, `nop`,
  and redirect. Struct/vector/quaternion returns are rejected with the type name.
* Executable stubs need an RWX/RX `mmap`; a hardened process may deny it (clear error,
  no crash).
* IL2CPP exports must be present. Mono/IL2CPP-stripped apps report the bridge
  unavailable and every Unity tool returns that error.
* `scene_roots` depends on `m_Father`/`m_GameObject`; some Unity versions rename them.
* PlayerPrefs writes go through Unity's setters and are persisted with `Save()`.

---

## 7. Broken-link audit

* **Binary links**: only `/System/Library/Frameworks/{Foundation,UIKit,CoreGraphics,
  QuartzCore,JavaScriptCore,Security,CoreImage}.framework` plus `libz`, `libobjc`,
  `libSystem`, `CoreFoundation`. `nm -u` has no `MSHook*`, `substrate`, `ellekit`,
  `libhooker`. The three substrate-looking strings in the binary are jailbreak-probe
  paths (`/usr/lib/libsubstrate.dylib`, …), not references.
* **Tool names**: all 35 libtool tools exist in `tools/list`; unknown names return a
  JSON-RPC tool error, never a silent success. ForgeKit's own 48 remain dispatchable.
* **Documentation**: README build commands, dashboard regeneration snippet, MCP client
  config and endpoint paths were re-checked against the source; no stale paths remain.
* **Packaging**: `control` no longer requires substrate; the Theos `Layout` filter is
  only meaningful for a jailbreak loader and is documented as such.

---

## 8. Verification status

* Compiles clean for `arm64` + `arm64e` with the iPhoneOS SDK; CI asserts the
  constructor symbol and the absence of injection-framework symbols.
* `devkit_selftest` exercises FS, zip, JSC, keychain and the view tree on device.
* IL2CPP paths cannot be executed off-device: they need a live Unity process. The
  bridge reports `il2cpp: unavailable` on non-Unity hosts, which is the expected
  result and the first check to run (`runtime_info`) on a real target.


---

## 9. iOS-sandbox-explorer integration

Source: `github.com/test1ng-guy/iOS-sandbox-explorer` (libShell.dylib + client.py).
Its runtime surface is a loopback TCP server that executes a fixed command set with
Foundation APIs — no `popen`, no `exec`. That surface is now native to ForgeKit as
`FKShell`; the IPA patcher/signing scripts in that repo stay outside the dylib
because ForgeKit is injected after signing.

### Command coverage (44 commands)

| Reference | ForgeKit | Notes |
|---|---|---|
| `ls`, `pwd`, `cd`, `tree` | same | `-a`, `-l`, `-d N` supported |
| `cat`, `head`, `tail`, `hexdump`, `strings`, `base64` | same | binary detection; truncation at 4 MB |
| `cp`, `mv`, `rm`, `mkdir`, `touch`, `chmod` | same | `-r`, `-p` supported; destructive ops require `-r` for directories |
| `stat`, `file`, `md5`, `sha256`, `wc`, `du`, `realpath`, `readlink` | same | `stat(2)` fields; digest via CommonCrypto |
| `find`, `grep` | same | `-name` (glob/substring), `-i`, `-n`; 500 match cap |
| `id`, `uname`, `whoami`, `env`, `date`, `df`, `uptime` | same | |
| `bundle`, `sandbox`, `sysinfo`, `memory` | same | adds IL2CPP state and LAN addresses |
| `keychain` | same | `dump`/`list`, `--class generic/internet/certificate` |
| `scp`, `download` | same | `SCP:` + `FILE;rel;base64` lines, `client.py` compatible |
| `echo`, `help`, `version` | same | |
| — | `containers` | extra: enumerates foreign container metadata when visible |

### Transport

* TCP listener on `127.0.0.1:8080` by default, one command per connection, response
  then close — wire-identical to the reference server, verified against its client
  implementation (send command + `\n`, read to EOF).
* `SO_NOSIGPIPE`, 10 s send/receive timeouts, 64 KB command cap, select-based accept
  loop so `stop` cannot leave a blocked thread.
* `shell_server` can bind `0.0.0.0` (opt-in). The protocol has no authentication, so
  this is documented as trusted-network only; the HTTP/MCP path keeps the bearer token.
* HTTP: `POST /api/shell` `{command,cwd}` and `GET /api/shell?command=`, token-protected.

### Deliberate differences

* No `popen`/`exec` (same as the reference) and no shell metacharacters, pipes or
  redirection. `cp a b` works; `cp a b && rm c` does not.
* Keychain output includes data as base64 and UTF-8 text when decodable, capped by
  the 4 MB response limit.
* `download` caps a single file at 3 MB so the base64 payload cannot blow the
  response limit; the reference has no such guard.
* The reference starts its server from a constructor unconditionally. ForgeKit starts
  it from `shell_server` or the Shell screen, so a host app does not expose a port
  unless asked.


---

## 10. v1.6.0: blank screens, navigation, utilities

### Blank Runtime and Network screens

Root cause: both screens live in `FKServerScreens.m` and build a `UIStackView` with
`[[UIStackView alloc] init]` (zero frame) then pin it with constraints, without setting
`translatesAutoresizingMaskIntoConstraints = NO`. Auto Layout therefore kept the
autoresizing mask at a zero-sized frame, so the scroll view had empty content — a blank
screen. Fix: the stack is constraint-driven, and the scroll view uses
`contentLayoutGuide` for the stack edges and `frameLayoutGuide` for its width. The same
pattern was corrected in the script console.

### Navigation

`FKTextViewController` and `FKHexViewController` put their Share button in
`leftBarButtonItem`, which **replaces the back button** — the only way out was the edge
swipe. Both now keep the left slot for the system back button and stack their actions on
the right (`Save`/`Share`, `More`/`Share`), with a consistent `largeTitleDisplayMode`
across viewers.

### Utilities

FLEX and the Frida gadget are runtime-loaded (`dlopen`) from bundle `Frameworks/`, the
bundle root, `Documents/ForgeKit/dylibs`, `/usr/lib` or `/var/jb/usr/lib`; a jailed
process can only load signed images, so failures surface the real `dlerror`. The WebKit
inspector is native: the same technique as WebInspectEnabler — swizzle the `WKWebView`
load methods and force `inspectable` (public on iOS 16.4+, private preference fallback).
Four MCP tools were added (`utilities_status`, `web_inspector`, `flex`, `frida`), bringing
the total to 91.


---

## 11. v1.7.0: native FLEX/Frida functionality

No helper dylib is loaded any more. The previous `flex` and `frida` tools were removed;
their capabilities are implemented in `FKRuntimeKit`.

| FLEX / Frida feature | Native implementation |
|---|---|
| FLEX heap explorer | malloc-zone introspection enumerator + registered-class validation, class filter, time/limit caps |
| FLEX object inspector | class chain, instance size, description, ivar decode (object/Class/SEL/C string/numbers/struct) |
| FLEX method calling | `NSInvocation` with type-driven argument and return conversion |
| FLEX network history | `NSURLSession` completion-handler swizzles, ring buffer, headers + previews |
| FLEX file/defaults/keychain | already present (File browser, Defaults, Keychain screens) |
| Frida `Memory` | `mem_read` / `mem_write` / `mem_scan` (text or hex with `??`), bounds and size caps |
| Frida `Module` | dyld image list, Mach-O `LC_SYMTAB` export enumeration, base/slide |
| Frida `Interceptor.replace` | 16-byte ARM64 entry redirect, original bytes saved, `hook_restore` |
| Frida remote control | already present: MCP over HTTP |

Deliberate omissions: no Stalker, no agent protocol, no JS `Interceptor.attach` callbacks
(they require cross-thread calls into JavaScriptCore with register preservation), and no
trampoline for calling the original function after a redirect. All are documented in the
README rather than faked.


---

## 12. v1.8.0: native FLEX explorer UI and auto-fit home

### Explorer

`FKExplorerScreens.m` adds the interactive layer FLEX provides, on top of `FKRuntimeKit`:

* **Hierarchy** — recursive view-tree drill-down with `Highlight` (converted to screen
  coordinates and rendered by the overlay window) and `Inspect` (ivar dump via
  `objectInfo:`).
* **Classes** — `objc_getClassList` list with search; detail splits instance methods,
  class methods, ivars and properties; method rows show type encodings and copy the
  selector; `Instances` runs the malloc-zone heap scan and pushes the object browser.
* **Object browser** — class chain, size, description and every ivar; object-valued
  ivars are navigable.
* **Libraries** — dyld images with base/size and per-module `LC_SYMTAB` exports with
  live filtering.
* **Traffic / Data** — recorded sessions, files, preferences, keychain, cookies,
  application info.

### Home grid

The panel home no longer uses a scroll view. A vertical stack pins a fixed 84 pt header,
a stretchable 4-column grid and a 16 pt footer to the safe area. Rows use
`FillEqually`, tiles carry no fixed height, and `FKTileView.layoutSubviews` derives the
icon size from the tile bounds (`min(width-16, height-26-12, 46)`), so all 13 tiles fit
any height without overlap or scrolling. The last row is padded with clear placeholder
views to keep equal widths.
