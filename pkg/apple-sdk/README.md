# Apple SDK Package

This in-tree Zig package owns Bobrshot's narrow bindings to stable C APIs in
Apple frameworks. Its build helper discovers the active Xcode SDK, configures
framework and system-library paths, and links only the frameworks used by the
core.

Bindings are declared manually rather than importing entire SDK headers. This
keeps the surface auditable, avoids unsupported Objective-C and block syntax in
Zig's C translator, and prevents unrelated SDK declarations from becoming part
of the core's compile-time contract.

Add a declaration only when Zig owns the corresponding operation. Swift should
continue to own native UI and APIs whose lifecycle is fundamentally expressed
through Swift concurrency or Objective-C objects.
