#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc scripts/icon.swift -o .build/make-icon -module-cache-path "$PWD/.build" -framework AppKit
.build/make-icon "$PWD/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
