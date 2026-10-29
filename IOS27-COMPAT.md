# ForgeKit — iOS 27 compatibility analysis

Subject: ForgeKit 2.0.4 (arm64 + arm64e dylib, min iOS 14.0)
Method: static audit of every source file, Mach-O inspection of the shipped binary, and a
risk review of each non-public surface against the way iOS 24–26 changed the same areas.
There is no iOS 27 SDK on the build host, so "compatibility" here means: the image links
and loads under dyld's documented rules, all APIs used are either public or have a
runtime fallback, and every private surface fails soft instead of crashing.

---

## 1. Build and load

Verified against the shipped image:

| Property | Value | Assessment |
|---|---|---|
| Platform | `LC_BUILD_VERSION platform 2` (iOS), minos 14.0 | correct |
| Architectures | arm64 + arm64e in one fat header | correct |
| Fixups | `LC_DYLD_CHAINED_FIXUPS` present | supported by dyld on iOS 13.4+ (27 included) |
| Install name | `@rpath/ForgeKit.dylib` | injector-friendly |
| Dependencies | 15 system frameworks/libs, no private or substrate libraries | safe |
| Undefined symbols | fully resolved (two-level namespace) | no flat lookups |
| Initializer | `__mod_init_func` **and** `+[FKForgeKitLoader load]` | covers lld's `__DATA_CONST` placement |
| Signature | none (the sideloader signs it with the app) | unchanged from every previous working build |

The one caveat that predates iOS 27: this release was linked with **clang 18 + ld64.lld**
because the macOS runners were unavailable. lld output is structurally valid, but Apple's
`ld64` remains the reference linker; when the macOS workflow runs it produces the same
source with Apple's linker.

---

## 2. API inventory and risk

### 2.1 Public, stable, no action

UIKit/Foundation (`UIWindow`, `UIWindowScene`, `UINavigationController`, `UITableView`,
`UIGestureRecognizer`, `NSInvocation`, `NSFileManager`, `NSJSONSerialization`,
`NSURLSession`, `NSNotificationCenter`), Security (`SecItemCopyMatching`), SQLite,
JavaScriptCore, WebKit `WKWebView.inspectable` (16.4+), MediaPlayer `MPVolumeView`,
AVFoundation `AVAudioSession`, `UIApplicationUserDidTakeScreenshotNotification`.

### 2.2 Deprecated but functional

| API | Status | Mitigation |
|---|---|---|
| `UIScreen.mainScreen` | deprecated in the scene era | only used when no `UIWindowScene` exists |
| `UIApplication.keyWindow` | deprecated | scene windows are preferred; fallback exists |
| `UIViewController.navigationBarHidden` | old pattern | FLEX restores it in `viewWillDisappear` |
| `CC_MD5` | deprecated (cryptographic) | shell `md5` only; SHA-256 is the default digest |
| `MPVolumeView` slider internals | undocumented subview | three independent volume sources |

### 2.3 Private or undocumented surfaces

| Surface | Why it is used | Failure mode | Fallback |
|---|---|---|---|
| `AVSystemController_SystemVolumeDidChangeNotification` | hardware volume events | name removed or not delivered | `AVAudioSession.outputVolume` KVO + `MPVolumeView` slider KVO |
| `MPVolumeView` internal `UISlider` | volume events when the audio session is inactive | slider subview renamed/hidden | notification + session KVO |
| Status-bar clock view (class/text scan) | long-press-the-time trigger | new Liquid Glass status bar class names | text regex, `Time`/`Clock` class match, fixed top-left rectangle |
| `malloc_zone_t->introspect->enumerator` | heap object enumeration (FLEX) | enumerator removed or struct changes | null check; empty result, no crash |
| `vm_read_overwrite` / `vm_protect` | memory tools, hooks | pages not readable/writable (TXM, hardened processes) | OSStatus returned to the caller; nothing is forced |
| `mach-o` `LC_SYMTAB` parsing | library exports | none — file format is stable | — |
| `_setDeveloperExtrasEnabled:` | WebKit inspector below 16.4 | private preference gone | public `inspectable` on 16.4+ (iOS 27 path) |
| `il2cpp_*` `dlsym` | Unity tools | symbols stripped/renamed | bridge reports unavailable; every tool returns that error |

Everything above is wrapped so a missing symbol or selector produces an error dictionary,
not an exception or a crash.

---

## 3. iOS 26/27-specific areas

### 3.1 Status bar (Liquid Glass)

The clock is found by walking windows whose class contains `StatusBar` (or level 1000),
matching a clock-formatted label, then a `*Time*`/`*Clock*` class, then a fixed top-left
rectangle. If the status bar becomes fully out-of-process, the app's own window still
covers the top-left region, and the recognizer on it continues to see touches. The trigger
is intentionally not dependent on a private view class.

### 3.2 Volume buttons

Three sources feed one state machine: the AVSystemController notification, KVO on
`AVAudioSession.outputVolume`, and KVO on a hidden `MPVolumeView` slider. The session is
`Playback + MixWithOthers`, re-armed on foreground. The up→down sequence and the
simultaneous chord use 1.2 s and 200 ms windows respectively. The chord is consumed by iOS
as a screenshot, so `UIApplicationUserDidTakeScreenshotNotification` is the primary signal;
if iOS 27 gates that notification, the opposing-events detector still fires when the chord
moves the volume.

### 3.3 Class clusters

`NSNotificationCenter` is a class cluster and its concrete class has changed across
releases. The recorder now swizzles **the class of `defaultCenter`** instead of the
abstract class, so posts are captured regardless of which private subclass is used.
`NSURLSession` methods are implemented on the public class; if iOS 27 moves them to a
subclass, capture degrades to no records (no crash).

### 3.4 Code pages and hooks

`hook_redirect` and `mem_write` need writable code pages. On devices with TXM / enhanced
security, `vm_protect` returns `KERN_PROTECTION_FAILURE`; the tool reports the OSStatus and
leaves the function untouched. No bypass is attempted.

### 3.5 Privacy

`NSLocalNetworkUsageDescription` is required in the host app for the MCP server; the dylib
cannot add it at runtime. `Resources/PrivacyInfo.xcprivacy` covers the required-reason APIs
ForgeKit uses (user defaults, file timestamps, boot time, disk space). A dylib's manifest is
not read by the system — the **host app's** `PrivacyInfo.xcprivacy` must include these
entries. The template is provided for that merge.

### 3.6 Windows and scenes

The panel and overlays are created with `UIWindowScene` when one exists. If the trigger
fires before the scene is ready, the panel retries for up to 2 seconds instead of creating
an orphan window. Key-window restoration on close is preserved.

---

## 4. Residual risks (ranked)

1. **lld-linked image rejected by dyld.** No functional cause found; Apple-`ld64` build is
   the reference. Keep the thin `ForgeKit-arm64.dylib` as fallback.
2. **Status bar fully out-of-process.** The clock trigger degrades to the top-left rectangle;
   the volume gestures are unaffected.
3. **Screenshot notification suppressed in iOS 27.** Chord detection falls back to opposing
   volume events within 200 ms; if both are gone, the chord cannot be observed with public
   APIs.
4. **MPVolumeView slider internals.** Without the slider, volume events depend on the audio
   session staying active.
5. **Heap enumeration under a future allocator.** `enumerator` is checked for null; a
   removed callback yields an empty list rather than a crash.
6. **TXM-protected code pages.** Hooks refuse to install; memory reads/writes to data pages
   still work.

---

## 5. On-device test plan (iOS 27)

1. Launch → `Console` shows `[ForgeKit] start v…`, `setup-start`, `setup-done`; check
   `Documents/ForgeKit/load.log`.
2. Open the panel: clock long-press, volume up→down, volume up+down chord.
3. FLEX: hierarchy, heap scan (non-zero counts), classes, libraries, network, SQLite.
4. Keychain: generic/internet/certificate lists, no crash (status text if denied).
5. MCP: `curl http://127.0.0.1:8787/health`, `tools/list` returns 106 tools.
6. Shell: `help`, `ls -l`, `sysinfo`, `keychain`, `download`.
7. Inspector: `web_inspector {enabled:true}` then Safari → Develop → device.
8. Hooks: `hook_redirect` on a private symbol, `hook_list`, `hook_restore`; confirm the
   error path on a protected page.
9. Privacy: confirm the host app's Info.plist has `NSLocalNetworkUsageDescription` and its
   privacy manifest contains the four reasons above.

---

## 6. Bottom line

Nothing in the image depends on an iOS 24–26 shape that iOS 27 is likely to remove without
a documented replacement. The fragile parts are the status bar view scan, the volume
notification name, and the MPVolumeView slider — each has at least one fallback, and each
fails soft. The two items that need attention outside the dylib are the host app's local
network usage string and its privacy manifest; both are documented and templated.


---

## 7. v2.2.0 addendum — rootless rebuild

* Packaged as a rootless Debian package (`/var/jb/usr/lib/ForgeKit.dylib` plus filter
  plist). Install path is scheme-aware; `FKJailbreakPrefix()` feeds the runtime search
  paths for FLEX/Frida helpers.
* `FKForgeKitConstructor` is `__attribute__((constructor, used))`; `+[FKForgeKitLoader load]`
  remains the second start path. In the arm64 slice lld still omits `__mod_init_func`, so
  `+load` is the effective path there — verified present in the shipped image.
* On iOS 26+ the panel refuses to create a `UIScreen`-backed window and retries until a
  `UIWindowScene` exists.
* No substrate/ElleKit/libhooker symbols are referenced, so any jailbreak loader can
  inject it.
* Remaining unverifiable item: iOS 27 device behaviour. Everything above is static
  verification plus documented fallbacks; the on-device test plan in §5 still applies.
