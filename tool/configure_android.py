"""Adjusts the Android project that `flutter create` generates."""

import glob
import os
import shutil

M = "android/app/src/main/AndroidManifest.xml"

with open(M, encoding="utf-8") as f:
    s = f.read()

# Tools namespace (to silence the scoped-storage lint for MANAGE_EXTERNAL_STORAGE).
if "xmlns:tools" not in s:
    s = s.replace(
        'xmlns:android="http://schemas.android.com/apk/res/android"',
        'xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

# Permissions:
# - INTERNET: Transfer over the local Wi-Fi.
# - Storage / All files access: move files out of the gallery and put them back.
if "MANAGE_EXTERNAL_STORAGE" not in s:
    perms = (
        '<uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n'
        '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n'
        '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" tools:ignore="ScopedStorage"/>\n'
        '    <application android:usesCleartextTraffic="true" android:requestLegacyExternalStorage="true"'
    )
    if "<application" not in s:
        raise SystemExit("No <application> tag in " + M)
    s = s.replace("<application", perms, 1)

# App name shown under the icon.
s = s.replace('android:label="f_locker"', 'android:label="F-Locker"')

with open(M, "w", encoding="utf-8") as f:
    f.write(s)

# Our MainActivity with the native helpers (replaces the generated one).
for old in glob.glob("android/app/src/main/**/MainActivity.*", recursive=True):
    print("removing", old)
    os.remove(old)
target = "android/app/src/main/kotlin/com/flocker/f_locker/MainActivity.kt"
os.makedirs(os.path.dirname(target), exist_ok=True)
shutil.copy("tool/android/MainActivity.kt", target)

print(s)
print("MainActivity ->", target)
