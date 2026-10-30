# F-Locker

An encrypted locker for **Android (.apk)** and **Windows (one F-Locker.exe, no install – like Rufus)**.

## Tabs

| | Tab | What it does |
|---|---|---|
| 0 | Settings | Change password, new recovery key, auto-lock, storage |
| 00 | Transfer | Receive files from another phone or PC on the same Wi‑Fi (or send) |
| 1 | Videos | |
| 2 | Images | Built-in viewer, nothing leaves the app |
| 3 | Music | |
| 4 | Documents | |
| 5 | Apps | App files such as `.apk` / `.exe` |
| 6 | Zips | `.zip`, `.rar`, `.7z` … |

In every content tab you **create a folder first**, then add files into it. There is **no limit** on items.

**Files are moved, not copied:** once added, a file disappears from where it was and exists only inside F-Locker. From F-Locker you can **Restore** it (it goes back to the exact place it came from) or **Delete** it for good. On Android this needs "All files access", which F-Locker asks for the first time.

## Password and recovery key

1. On first start you create a password.
2. F-Locker gives you a **10-letter recovery key**. Save it.
3. Forgot the password? Enter the key → the locker opens → you **must** set a new password, and you get a new key (the old one stops working).

## Security

- A random 256-bit master key encrypts every file (AES-256-GCM, 1 MiB chunks) and the folder list.
- The master key is stored wrapped by keys derived (PBKDF2-HMAC-SHA256, 120 000 rounds) from the password and from the recovery key. Neither is stored.
- Opening a video or document decrypts it into a temp folder that is wiped on lock. Images open in memory only.
- Transfer: both devices derive an AES key from the 6-digit code; files travel encrypted and a wrong code is rejected.

## Download

Every push to `main` builds and publishes a new release (**Releases › latest**):

- `F-Locker.apk` – Android (64-bit phones, about 20 MB)
- `F-Locker-old-phones.apk` – older 32-bit phones
- `F-Locker.exe` – Windows, a single file. Double-click it anywhere (USB too). Your locked data sits next to it in a hidden `FLockerData` folder; the app itself unpacks hidden into `%LOCALAPPDATA%\F-Locker`.

## Build yourself

```bash
flutter create --org com.flocker --project-name f_locker --platforms=android,windows .
bash tool/configure_android.sh      # Android tweaks
pwsh tool/configure_windows.ps1     # Windows tweaks (on Windows)
flutter build apk --release
flutter build windows --release
```

## Known limits

- The Apps tab stores app files (`.apk`, `.exe`); it does not yet lock other installed apps from opening.
- Opening a video or document decrypts a temporary copy (inside the hidden data folder) so the default player can play it; it is wiped when F-Locker locks.
