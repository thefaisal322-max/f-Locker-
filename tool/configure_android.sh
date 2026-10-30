#!/usr/bin/env bash
# Adjusts the Android project that `flutter create` generates.
set -euo pipefail

M=android/app/src/main/AndroidManifest.xml

# Tools namespace (to silence the scoped-storage lint for MANAGE_EXTERNAL_STORAGE).
grep -q 'xmlns:tools' "$M" || \
  sed -i 's|<manifest xmlns:android="http://schemas.android.com/apk/res/android"|<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"|' "$M"

# Permissions:
# - INTERNET: Transfer over the local Wi-Fi.
# - Storage / All files access: move files out of the gallery and put them back.
grep -q 'MANAGE_EXTERNAL_STORAGE' "$M" || sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" tools:ignore="ScopedStorage"/>\
    <application android:usesCleartextTraffic="true" android:requestLegacyExternalStorage="true"|' "$M"

# App name shown under the icon.
sed -i 's|android:label="f_locker"|android:label="F-Locker"|' "$M"

# Our MainActivity with the native helpers.
TARGET=$(find android/app/src/main -name 'MainActivity.kt' | head -1)
cp tool/android/MainActivity.kt "$TARGET"

cat "$M"
echo "MainActivity -> $TARGET"
