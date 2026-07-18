# Architecture

Bobrshot has three implementation layers with explicit responsibilities.

## Native macOS Layer

Swift integrates ScreenCaptureKit, CoreGraphics, AVFoundation, AppKit, and
other Apple frameworks. This layer owns authorization, display and window
discovery, capture sessions, global shortcuts, pasteboard behavior, and app
lifecycle integration.

SwiftUI owns capture controls, overlays, the editor, history, settings, and
other user-facing workflows. Native framework objects do not cross into Zig.

## Core Layer

Zig owns deterministic, platform-independent processing where it provides a
clear safety or performance benefit. Planned responsibilities include image
analysis, crop detection, encoding orchestration, metadata policy, temporary
artifact bookkeeping, and bounded processing queues.

The core is an independent implementation. It does not link to, invoke, or
vendor Clop.

## ABI Boundary

`include/bobrshot.h` is the complete public boundary between Zig and Swift.
The ABI uses C-compatible values, explicit ownership, bounded buffers, and
status returns. Swift wrappers convert those values into domain types before
the rest of the application can use them.

The ABI must not expose Zig allocators, Swift objects, Apple framework types,
or unstable in-memory layouts.

## Build Ownership

Zig builds the core static library. `xcodebuild -create-xcframework` packages
the library, public header, and Clang module map as `BobrshotKit.xcframework`.
Xcode imports that module and builds the application. The top-level
`build.zig` establishes the dependency order.

Development builds contain only the host architecture. Universal release
artifacts will be added with the distribution and signing pipeline.
