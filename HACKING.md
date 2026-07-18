# Developing Bobrshot

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- Zig 0.16.0

Run `nix develop` to use the pinned Zig environment. Xcode and the Apple SDK
must come from the host system and should not be installed through Nix.

## Commands

- `zig build` builds the Zig core and native application.
- `zig build test` runs the Zig core and compiled C API tests.
- `zig build xcframework` builds `macos/BobrshotKit.xcframework`.
- `zig build app` builds the native application.
- `zig build run` builds and launches the native application.
- `zig fmt --check .` checks Zig formatting.
- `swift format lint --recursive --strict macos/Sources` checks Swift formatting.

The built application is written to
`zig-out/xcode/Build/Products/Debug/Bobrshot.app`.

## Native Boundary

Public Zig APIs must be declared in `include/bobrshot.h` and implemented in
`src/core`. Swift code must access them through `macos/Sources/CoreBridge`.
SwiftUI feature code should not import `BobrshotKit` directly.

The generated XCFramework is intentionally untracked. Build it before opening
the Xcode project directly:

```sh
zig build xcframework
open macos/Bobrshot.xcodeproj
```
