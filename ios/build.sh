#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOL="$ROOT/../toolchain"
SDK="$TOOL/sdk_fixed2"
CLANG="$TOOL/LLVM/bin/clang.exe"
OUT="$ROOT/build"
APP="$OUT/Payload/GDUFQR.app"

rm -rf "$OUT"
mkdir -p "$APP"

echo "[1/3] compile main.m"
"$CLANG" -target arm64-apple-ios15.0 \
  -isysroot "$SDK" \
  -F"$SDK/System/Library/SubFrameworks" \
  -F"$SDK/System/Library/PrivateFrameworks" \
  -I"$SDK/System/Library/SubFrameworks" \
  -I"$SDK/System/Library/PrivateFrameworks" \
  -fobjc-arc -fblocks -O2 -fuse-ld=lld \
  -miphoneos-version-min=15.0 \
  -framework UIKit -framework Foundation -framework WebKit -framework CoreImage -framework CoreGraphics -framework AVFoundation \
  -o "$APP/GDUFQR" "$ROOT/GDUFQR/main.m"

echo "[2/3] bundle"
cp "$ROOT/GDUFQR/Info.plist" "$APP/"
cp "$ROOT/GDUFQR"/AppIcon*.png "$APP/"

echo "[3/3] package ipa"
PYTHONIOENCODING=utf-8 python - "$OUT" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
ipa = os.path.join(out, "GDUFQR.ipa")
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(os.path.join(out, "Payload")):
        for f in files:
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, out).replace("\\", "/"))
print("OK", ipa, os.path.getsize(ipa), "bytes")
PY
