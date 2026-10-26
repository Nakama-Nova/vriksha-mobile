# Vriksha Capture

Phone app for the Vriksha Studios shop. It captures a piece (photos or one video), uploads it straight to the shop's private file store, and shows what the workshop PC is doing with it.

- Sign in with your shop username; enter the server address once.
- **New scan**: choose Photos (8 or more, walking around the piece) or one Video (up to 90 s), optionally the real width in mm and a product (owner/manager), then Upload.
- **My scans** (owner/manager: **All scans**): status in plain words, progress while the workshop PC is working, the reason if it failed, Cancel while it is waiting.

Files never pass through the shop server: it hands the phone a short-lived signed address and the phone sends each file there (3 at a time, each retried up to 3 times). The phone holds no cloud keys. The login token is kept in the phone's secure storage.

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

MIT, see `LICENSE`. Third-party packages' licences are listed inside the app (Licences button).
