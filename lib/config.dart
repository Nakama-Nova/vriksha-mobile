/// The shop server this app talks to, fixed in the app like the desktop's API_BASE_URL,
/// so the sign-in screen never asks for an address. Build for another server with
/// `flutter build apk --dart-define=API_BASE_URL=https://your-server`.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.vrikshastudios.com',
);
