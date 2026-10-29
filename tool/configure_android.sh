#!/usr/bin/env bash
# Adjusts the Android project that `flutter create` generates.
set -euo pipefail

M=android/app/src/main/AndroidManifest.xml

# Transfer needs the network; it talks plain HTTP on the local Wi-Fi
# (the files themselves are AES-encrypted with the transfer code).
grep -q 'android.permission.INTERNET' "$M" || \
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"
grep -q 'usesCleartextTraffic' "$M" || \
  sed -i 's|<application|<application android:usesCleartextTraffic="true"|' "$M"

# App name shown under the icon.
sed -i 's|android:label="f_locker"|android:label="F-Locker"|' "$M"

cat "$M"
