# Vriksha Capture

The phone app for the Vriksha Studios shop (Flutter, Android). It mirrors the staff desk on the desktop, and it is where a piece is captured (photos or one video), uploaded straight to the shop's private file store, and followed while the workshop PC builds the 3D model. It also alerts staff to new orders, payments, low stock and finished scans.

It talks to [nakamadesk-backend](https://github.com/Nakama-Nova/nakamadesk-backend). The workshop PC that turns the uploads into 3D models is [vriksha-scan](https://github.com/Nakama-Nova/vriksha-scan). The staff desk for the counter is [nakama-desktop](https://github.com/Nakama-Nova/nakama-desktop).

This repository continues `furnibiz-android` (same git history, new name). The retired native Kotlin app is kept on the `legacy/kotlin` branch.

## What it does

- **Same side menu as the desktop**, with its headings, order, names and role rules: Home; Selling (New Bill, Bill History, Orders, Buyers, Letters); Stock and buying (Stock, Materials, Purchases, Places); Workshop (3D Lab, scan capture below; Restoration; Designs; Machines and tools); People and pay (Attendance (check yourself in and out with your phone's position, and see your team), Wages, Staff); Money (Expenses, Profit, Budgets, Reports); plus Alerts, About, My password and Sign Out. Not on the phone yet: offline billing, bill PDFs, product photos and website fields, the web 3D viewer.
- Sign in with your shop username and password. The server address is fixed in the app (`lib/config.dart`, like the desktop's `API_BASE_URL`), so sign-in does not ask for it.
- **New scan**: choose Photos (8 or more, walking around the piece) or one Video (up to 90 s), optionally the real width in mm and a product (owner/manager), then Upload.
- **My scans** (owner/manager: **All scans**): status in plain words, progress while the workshop PC is working, the reason if it failed, Cancel while it is waiting.
- **Alerts**: new website orders, money received, low stock and finished 3D scans, depending on the person's role (the server decides).
- **Updates**: tells you when a newer version of the app is published and lets you download it.

Files never pass through the shop server: it hands the phone a short-lived signed address and the phone sends each file there (3 at a time, each retried up to 3 times). The phone remembers which files of an upload are already stored, so if the app is closed, killed or signed out half-way, the Scans tab shows **Unfinished upload** with Resume (sends only what is missing) or Discard; a signed link that runs out mid-upload is replaced automatically. The phone holds no cloud keys. The login token is kept in the phone's secure storage.

## Alerts and updates

- **Alerts tab.** The app asks the server (`GET /notifications`) every minute while it is open, and about every 15 minutes in the background (Android WorkManager) when it is closed. No Google or Firebase account is needed. Android is the limit: the background check cannot run more often than every 15 minutes, and a phone in battery-saver may delay it. Instant push would need a Firebase project.
- **Update alerts.** The app asks the server for the newest published version (`GET /app/updates/mobile/latest`). A newer one shows as a banner and a card on the Alerts tab, with a **Download** button that opens the signed APK link in the browser; Android then offers to install it. "Later" hides it for that version. The background check also sends one notification per new version.

## Develop

You need Flutter 3.47.8 (the version CI pins; Dart SDK `^3.13.7`) and, to build an APK, the Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The app talks to `https://api.vrikshastudios.com` unless you build for another server: `flutter build apk --dart-define=API_BASE_URL=https://your-server` (the same flag works with `flutter run`).

CI (`.github/workflows/ci.yml`) runs analyze and tests and attaches an installable APK to every run. That APK is debug-signed, and the manifest allows plain `http://` so the app can reach a shop server on the local network; use `https://` for anything on the internet.

```text
lib/             app code: config.dart (server address), api.dart (server calls),
                 uploader.dart, alerts.dart, updates.dart, background.dart,
                 session.dart, theme.dart, screens/ (one file per screen)
test/            unit and widget tests
assets/fonts/    bundled fonts (see Look)
android/         Android project
```

## Publishing a version

Push a tag such as `v1.1.0`. The `Release APK` workflow (`.github/workflows/release-apk.yml`) builds `VrikshaCapture-1.1.0.apk` with its `.sha256` and attaches them to a GitHub Release, which is where the server looks. It needs the release key in the repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) and refuses to publish without it, because an APK signed with a different key cannot update an installed app.

## Server contract

Backend `nakamadesk-backend`: the scan jobs API (`docs/design/scan-and-lab.md`, sections 4 and 12) and the notification and update endpoints.

`POST /auth/login`, `POST /scans`, `POST /scans/{id}/presign`, `PUT` to each returned address, `POST /scans/{id}/complete`, `GET /scans`, `POST /scans/{id}/cancel`, `GET /items/` (owner/manager), `GET /notifications`, `GET /app/updates/mobile/latest`.

## Look

Follows the generated Vriksha Studio design (`docs/design/mobile-screens.html` in the backend repo): brown app bars, warm surface, outlined cards and status chips, and a side menu like the desktop's. Fonts: Cormorant Garamond (headings) and Inter (text) are bundled in `assets/fonts` (SIL Open Font License, source commit in `SOURCE.txt`) and listed on the Licences page.

## Licence

Proprietary software. Copyright (c) 2026 Nakama Nova, all rights reserved. It may not be copied, modified or shared; see `LICENSE`. Third-party packages keep their own licences, listed inside the app (Licences button). To report a security problem, see `SECURITY.md`.
