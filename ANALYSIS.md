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
