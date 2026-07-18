#!/bin/sh

set -eu

library_directory=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
library_path="$library_directory/$(basename -- "$1")"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_path="$script_directory/BobrshotKit.xcframework"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bobrshot-xcframework.XXXXXX")
normalized_library="$temporary_directory/libbobrshot.a"
trap 'rm -rf "$temporary_directory"' EXIT

# Darwin archives only guarantee two-byte member alignment, while Apple's
# linker requires embedded 64-bit Mach-O objects to begin on an eight-byte
# boundary. Rebuild from the extracted object so libtool can add that padding.
(cd "$temporary_directory" && ar -x "$library_path")
find "$temporary_directory" -type f -name '*.o' -exec chmod u+r {} +
xcrun libtool -static -o "$normalized_library" "$temporary_directory"/*.o

rm -rf "$output_path"
xcodebuild -create-xcframework \
  -library "$normalized_library" \
  -headers "$script_directory/../include" \
  -output "$output_path"
