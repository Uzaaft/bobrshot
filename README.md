# Bobrshot

Cuz I was too stingy to pay for cleanshot

## Architecture

- Zig owns performance-sensitive media processing, including selected stable
  Apple C APIs through an in-tree SDK package, and exposes a narrow C ABI.
- Swift owns the native macOS host and wraps the C ABI in safe application types.
- SwiftUI owns application state, presentation, and interaction.
- Xcode owns the application bundle, signing, assets, and Apple platform tests.
- The top-level Zig build coordinates native library and application builds.

See [HACKING.md](HACKING.md) for development commands.

## Status

Bobrshot is in early development. The repository currently provides a working
Zig-to-Swift build path and a native macOS application shell.
