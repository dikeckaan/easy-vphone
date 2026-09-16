#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
mkdir -p .build
xcrun swiftc Sources/Localization.swift tests/LocalizationTests.swift -o .build/localization-tests -module-cache-path "$PWD/.build"
.build/localization-tests "$PWD/Resources/i18n"
