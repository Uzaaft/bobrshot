#!/bin/sh

set -eu

library_path="$1"
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_path="$script_directory/BobrshotKit.xcframework"

rm -rf "$output_path"
xcodebuild -create-xcframework \
  -library "$library_path" \
  -headers "$script_directory/../include" \
  -output "$output_path"
