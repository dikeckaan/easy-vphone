#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BASE="$(cd "$(dirname "$0")" && pwd)"
ACTION="${1:-create}"
case "$ACTION" in create|cfw|dependencies|amfi) ;; *) echo "Bilinmeyen işlem" >&2; exit 1 ;; esac
: "${ROOT:?Kurulum dizini gerekli}"
: "${VM_NAME:=iphone-jb}"
: "${VARIANT:=jb}"
: "${DISK_GB:=64}"
die() { echo "HATA: $*" >&2; exit 1; }
[[ "$(uname -m)" == arm64 ]] || die 'Apple Silicon Mac gerekli.'
[[ "$ROOT" == /* && "$ROOT" != / ]] || die 'Geçerli mutlak kurulum yolu seç.'
[[ "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'VM adı: harf, rakam, _ ve - kullan.'
case "$VARIANT" in regular|dev|jb|exp) ;; *) die 'Desteklenmeyen varyant.' ;; esac
[[ "$DISK_GB" =~ ^[0-9]+$ && "$DISK_GB" -ge 32 && "$DISK_GB" -le 512 ]] || die 'Disk boyutu 32–512 GB olmalı.'
if [[ "$ROOT" == /Volumes/* ]]; then
  volume="${ROOT#/Volumes/}"; volume="${volume%%/*}"
  /sbin/mount | /usr/bin/grep -Fq " on /Volumes/$volume (" || die "Disk bağlı değil: $volume"
fi
if [[ -n "${XCODE_DIR:-}" ]]; then export DEVELOPER_DIR="$XCODE_DIR"; fi
command -v brew >/dev/null || die 'Önce Hazırlık ekranından Homebrew kur.'
xcrun --find clang >/dev/null 2>&1 || die 'Xcode Command Line Tools gerekli.'
if [[ "$ACTION" == dependencies ]]; then
  brew install python@3.13 aria2 wget gnu-tar openssl@3 ldid-procursus sshpass keystone cmake libusb ipsw zstd ipatool ideviceinstaller libusbmuxd
  if [[ ! -x /Applications/vphone-cli.app/Contents/MacOS/vphone-cli ]]; then
    brew install --cask zqxwce/tap/vphone-cli
  fi
  echo 'Bağımlılıklar hazır.'
  exit 0
fi
APP=/Applications/vphone-cli.app
CLI="$APP/Contents/MacOS/vphone-cli"
[[ -x "$CLI" ]] || die 'Önce Hazırlık ekranından bağımlılıkları kur.'
mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
export VPHONE_ROOT="$ROOT" VPHONE_LIBRARY_ROOT="$ROOT/VMs" VPHONE_VENV_DIR="$ROOT/venv"
if [[ "$ACTION" == amfi ]]; then
  PYTHON="$(brew --prefix python@3.13)/bin/python3.13"
  [[ -x "$ROOT/host-tools/bin/python" ]] || "$PYTHON" -m venv "$ROOT/host-tools"
  "$ROOT/host-tools/bin/python" -m pip install amfidont==0.0.3
  export PATH="$ROOT/host-tools/bin:$PATH"
  exec "$APP/Contents/Resources/vphone-amfidont"
fi
"$CLI" --help >/dev/null || die 'vphone-cli çalışmıyor. Hazırlık ekranındaki AMFI düzeltmesini kullan.'
[[ "$ACTION" == create || "$ACTION" == cfw ]] || die 'Bilinmeyen işlem.'
if [[ -n "${XCODE_DIR:-}" ]]; then export DEVELOPER_DIR="$XCODE_DIR"; fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  for candidate in /Applications/Xcode*.app /Volumes/*/Applications/Xcode*.app; do
    [[ -d "$candidate/Contents/Developer/Platforms/iPhoneOS.platform" ]] || continue
    export DEVELOPER_DIR="$candidate/Contents/Developer"
    xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 && break
  done
fi
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 || die 'Tam Xcode ve iOS SDK gerekli. Hazırlık ekranından Xcode seç.'
REPO="$ROOT/vphone-cli"
if [[ ! -e "$REPO" ]]; then
  git clone --recurse-submodules https://github.com/Lakr233/vphone-cli.git "$REPO"
else
  [[ -d "$REPO/.git" ]] || die 'vphone-cli dizini mevcut ama Git deposu değil.'
  [[ "$(git -C "$REPO" remote get-url origin)" == https://github.com/Lakr233/vphone-cli.git ]] || die 'Mevcut repo origin adresi beklenenden farklı.'
  git -C "$REPO" submodule update --init --recursive
fi
echo "Repo commit: $(git -C "$REPO" rev-parse HEAD)"
# Create an isolated runtime per VM. Never edit the signed upstream app.
RUNTIME="$ROOT/easy-runtime/$VM_NAME"
if [[ ! -d "$RUNTIME" ]]; then ditto "$APP/Contents/Resources" "$RUNTIME"; fi
printf '%s\n' "${DEVELOPER_DIR:-$(xcode-select -p)}" > "$RUNTIME/developer-dir"
python3 "$BASE/prepare-runtime.py" "$BASE/patchers" "$RUNTIME"
if [[ "$ACTION" == create ]]; then
python3 - "$RUNTIME/plan.json" <<'PLAN'
import json, os, sys
from pathlib import Path
keys = ('VM_NAME','VARIANT','DISK_GB','IPHONE_SOURCE','CLOUDOS_SOURCE','FRIDA')
Path(sys.argv[1]).write_text(json.dumps({k:os.environ.get(k,'') for k in keys},indent=2))
PLAN
fi
if [[ "$ACTION" == cfw ]]; then
  exec "$CLI" cfw install "$VM_NAME" --variant "$VARIANT" --root-popup --project-root "$RUNTIME" -v
fi
if [[ -e "$ROOT/VMs/$VM_NAME" ]]; then die 'Bu VM adı mevcut. Devam et düğmesini veya farklı bir ad kullan.'; fi
args=(vm create "$VM_NAME" --variant "$VARIANT" --disk-size "$DISK_GB" --root-popup --project-root "$RUNTIME" -v)
[[ -z "${IPHONE_SOURCE:-}" ]] || args+=(--iphone-source "$IPHONE_SOURCE")
[[ -z "${CLOUDOS_SOURCE:-}" ]] || args+=(--cloudos-source "$CLOUDOS_SOURCE")
[[ "${FRIDA:-0}" != 1 ]] || args+=(--frida)
printf 'Kurulum başlıyor: %s / %s\n' "$VM_NAME" "$VARIANT"
exec "$CLI" "${args[@]}"
