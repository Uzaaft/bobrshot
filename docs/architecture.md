# Architecture

Bobrshot has three implementation layers with explicit responsibilities.

## Native macOS Host

Swift is the thin native application host. It owns SwiftUI and AppKit
presentation, app lifecycle, permissions, pasteboard integration, global
shortcuts, and asynchronous framework objects such as ScreenCaptureKit streams
and AVAssetWriter sessions.

This mirrors Ghostty's macOS boundary: use the platform's native application
frameworks for the user experience, while moving reusable state and expensive
processing behind a Zig-owned C ABI. Rewriting UI orchestration in Zig is not a
performance optimization.

## Core Layer

Zig owns deterministic processing and may call stable Apple C APIs when that
keeps expensive work inside the core. It currently owns format detection,
container validation, metadata policy, and ImageIO-backed image inspection.
Planned responsibilities include crop detection, pixel transforms, encoding
orchestration, hashing, temporary artifact bookkeeping, and bounded processing
queues.

`pkg/apple-sdk` discovers the active Xcode SDK and exposes a deliberately small
set of manual framework bindings. It avoids importing entire Apple headers and
does not expose framework objects through the public ABI.

The core is an independent implementation. It does not link to, invoke, or
vendor Clop.

## ABI Boundary

`include/bobrshot.h` is the complete public boundary between Zig and Swift.
The ABI uses C-compatible values, explicit ownership, bounded buffers, and
status returns. Swift wrappers convert those values into domain types before
the rest of the application can use them.

The ABI must not expose Zig allocators, Swift objects, Apple framework types,
or unstable in-memory layouts. Apple objects created inside Zig are consumed
and released before returning across the boundary.

## Build Ownership

Zig builds the core static library. `xcodebuild -create-xcframework` packages
the library, public header, and Clang module map as `BobrshotKit.xcframework`.
Xcode imports that module and builds the application. The top-level
`build.zig` establishes the dependency order.

Development builds contain only the host architecture. Universal release
artifacts will be added with the distribution and signing pipeline.
