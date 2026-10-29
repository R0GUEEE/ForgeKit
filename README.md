# ForgeKit

A single self-contained dylib that turns any sideloaded iOS app into a development
workbench: hidden in-app panel, full container/root browser, runtime introspection,
UI automation, and an MCP server for remote control.

Built to be injected into **jailed** (non-jailbroken) apps: no MobileSubstrate,
ElleKit or libhooker linkage — every hook is installed with the Objective-C runtime.
The same binary also works on a jailbroken device.

```
Hold the left side of the status bar  →  panel opens
http://<device-ip>:8787/mcp           →  MCP endpoint (bearer token)
```
