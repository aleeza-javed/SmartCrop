# SmartCrop

Smart farming app with AI-powered crop recommendations, sensor monitoring, irrigation control, and field management.

## Requirements

| Tool    | Version          |
| ------- | ---------------- |
| Flutter | 3.44.x           |
| Dart    | 3.12.x           |
| Java    | 17 (for Android) |
| Android | API 21+          |

## Setup After Cloning

```bash
# 1. Ensure Java 17 is set for Android builds
java -version   # should be 17.x

# 2. Get dependencies
flutter pub get

# 3. Run the app
flutter run              # auto-detect device
flutter run -d chrome    # web
flutter run -d <device>  # specific device
```

## Firebase

This project uses Firebase Authentication (email/password + Google Sign-In).

### Firebase config files

The following Firebase config files are committed to the repo and required to build:

- `lib/firebase_options.dart`
- `android/app/google-services.json`

If you need to regenerate them (e.g., for a different Firebase project):

```bash
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"
firebase login
flutterfire configure --project=smart-crop-ddf69 \
  --platforms=android,web \
  --android-package-name=com.smartcrop.smart_crop \
  --out=lib/firebase_options.dart
```

### Google Sign-In (Android)

If Google Sign-In fails on a new machine, add the debug SHA-1 to the Firebase Console:

```bash
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android \
  | grep SHA1
```

Then go to **Firebase Console → Project Settings → Android app → Add Fingerprint**.

## Project Structure

```
lib/
├── main.dart                     # App entry, Firebase init
├── firebase_options.dart         # Generated Firebase config
├── services/
│   └── auth_service.dart         # Firebase Auth wrapper
├── screens/                      # All UI screens
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── signup_screen.dart
│   ├── forgot_password_screen.dart
│   ├── dashboard_screen.dart
│   ├── profile_screen.dart
│   ├── ... (20+ screens)
└── theme/
    ├── app_colors.dart
    └── app_theme.dart
```

## Troubleshooting

### Gradle build fails with "Unsupported class file major version"

Install JDK 17 and set it as your Android Studio / Gradle JDK:

```bash
brew install openjdk@17
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
flutter clean
flutter pub get
flutter run
```

### iOS build

iOS is not currently configured. To add iOS support, re-run `flutterfire configure` with `--platforms=ios`.
