#!/usr/bin/env bash
# Adjusts the Android project that `flutter create` generates.
set -eux

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

# Our MainActivity with the native helpers (replaces the generated one,
# whether it was Kotlin or Java).
find android/app/src/main -name 'MainActivity.*' -print -delete || true
TARGET=android/app/src/main/kotlin/com/flocker/f_locker/MainActivity.kt
mkdir -p "$(dirname "$TARGET")"
cp tool/android/MainActivity.kt "$TARGET"

cat "$M"
echo "MainActivity -> $TARGET"
