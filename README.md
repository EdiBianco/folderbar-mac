# FolderBar

Menu-bar folder shortcuts for macOS — pick folders, each becomes a status-bar
dropdown listing its contents, click to open.

Rebuilt from the ground up (concept inspired by qfinder/"Folder Bar", no code
or assets reused) with a few deliberate optimizations:

- **Swift + AppKit**, no StoryBoard/XIB — menus built in code.
- **kqueue folder watch** (`DispatchSource.makeFileSystemObjectSource`)
  invalidates a folder's cached listing only when it actually changes,
  instead of re-reading the directory on every menu open.
- **`SMAppService`** for the login item instead of the legacy
  `SMLoginItemSetEnabled` helper-bundle approach.
- Sandboxed, security-scoped bookmarks for persisted folder access.
- No trial/StoreKit gating — free.

## Build

CI builds a universal (arm64 + x86_64) `.app` on every push via GitHub
Actions (`.github/workflows/build.yml`); grab it from the workflow's
Artifacts tab. To build locally:

```bash
swift build -c release --arch arm64 --arch x86_64
```
