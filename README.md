# Vriksha Capture

Phone app for the Vriksha Studios shop. It captures a piece (photos or one video), uploads it straight to the shop's private file store, and shows what the workshop PC is doing with it.

- Sign in with your shop username; enter the server address once.
- **New scan**: choose Photos (8 or more, walking around the piece) or one Video (up to 90 s), optionally the real width in mm and a product (owner/manager), then Upload.
- **My scans** (owner/manager: **All scans**): status in plain words, progress while the workshop PC is working, the reason if it failed, Cancel while it is waiting.

Files never pass through the shop server: it hands the phone a short-lived signed address and the phone sends each file there (3 at a time, each retried up to 3 times). The phone holds no cloud keys. The login token is kept in the phone's secure storage.

The previous Kotlin Android app is kept on the `legacy/kotlin` branch of this repository (retired; this Flutter app replaces it).

## Look

Follows the generated Vriksha Studio design (`docs/design/mobile-screens.html` in the backend repo): brown app bars, warm surface, outlined cards and status chips, a bottom bar (Scans, More). Fonts: Cormorant Garamond (headings) and Inter (text) are bundled in `assets/fonts` (SIL Open Font License, source commit in `SOURCE.txt`) and listed on the Licences page.

## Develop

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release    # needs the Android SDK; CI builds it for you
```

CI (`.github/workflows/ci.yml`) runs analyze and tests and attaches an installable APK to every run. The APK is debug-signed and the manifest allows plain `http://` so the app can reach a shop server on the local network; use `https://` for anything on the internet.

## Server contract

Backend `nakamadesk-backend`, scan jobs API (`docs/design/scan-and-lab.md`, sections 4 and 12): `POST /auth/login`, `POST /scans`, `POST /scans/{id}/presign`, `PUT` to each returned address, `POST /scans/{id}/complete`, `GET /scans`, `POST /scans/{id}/cancel`, `GET /items/` (owner/manager).

## Licence

Proprietary software. Copyright (c) 2026 Nakama Nova, all rights reserved. It may not be copied, modified or shared; see `LICENSE`. Third-party packages keep their own licences, listed inside the app (Licences button).

## Alerts and updates

- **Alerts tab.** The app asks the shop's server (`GET /notifications`) every minute while it is open, and about every 15 minutes in the background (Android WorkManager) when it is closed. New website orders, money received, low stock and finished 3D scans show in the list and as phone notifications, depending on the person's role (the server decides). No Google or Firebase account is needed. Android is the limit: the background check cannot run more often than every 15 minutes, and a phone in battery-saver may delay it. Instant push would need a Firebase project.
- **Update alerts.** The app asks the server for the newest published version (`GET /app/updates/mobile/latest`). A newer one shows as a banner and a card on the Alerts tab, with a **Download** button that opens the signed APK link in the browser; Android then offers to install it. "Later" hides it for that version. The background check also sends one notification per new version.
- **Publishing a version.** Push a tag such as `v1.1.0`. The `Release APK` workflow builds `VrikshaCapture-1.1.0.apk` with its `.sha256` and attaches them to a GitHub Release, which is where the server looks. It needs the release key in the repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) and refuses to publish without it, because an APK signed with a different key cannot update an installed app.
