#!/bin/bash
set -euo pipefail
if [[ -x /opt/homebrew/bin/brew ]]; then echo 'Homebrew zaten kurulu.'; exit 0; fi
installer="$(mktemp -t easy-vphone-brew)"
trap 'rm -f "$installer"' EXIT
/usr/bin/curl --fail --location --retry 3 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
/bin/bash "$installer"
