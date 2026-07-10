# SmartCrop

Smart farming app with AI-powered crop recommendations, real-time sensor monitoring, irrigation control, and field management.

Built with Flutter + Firebase Auth (email/password + Google Sign-In).

## Requirements

| Tool      | Version   | How to Check          |
| --------- | --------- | --------------------- |
| Flutter   | 3.44.x    | `flutter --version`   |
| Dart      | 3.12.x    | `dart --version`      |
| Java      | 17        | `java -version`       |
| Android   | API 21+   | —                     |

> **Java 17 is required for Android builds.** If you have a different JDK, set `JAVA_HOME`:
> ```bash
> export JAVA_HOME=/opt/homebrew/opt/openjdk@17  # macOS (Homebrew)
> ```
> Or configure it in Android Studio → File → Project Structure → SDK Location → Gradle JDK.

## Setup After Cloning

### 1. Clone & branch

```bash
git clone https://github.com/aleeza-javed/SmartCrop.git
cd SmartCrop
git checkout mobile-app-frontend
```

### 2. Install dependencies

```bash
flutter pub get
```

If you get a version conflict, run:
```bash
flutter pub upgrade --major-versions
```

### 3. Run the app

```bash
flutter run                    # auto-select Android device
flutter run -d chrome          # web
flutter run -d <device-id>     # specific device
```

---

## Firebase

This project is configured for Firebase project **smart-crop-ddf69**.

### Config files (committed, no action needed)

The following files are already in the repo — you don't need to generate them:

- `lib/firebase_options.dart` — Firebase SDK config per platform
- `android/app/google-services.json` — Android Google Services
- `firebase.json` — FlutterFire CLI metadata

### If you want to use your own Firebase project

```bash
# 1. Install flutterfire CLI
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"

# 2. Log in to Firebase
firebase login

# 3. Create a Firebase project in the console, then run:
flutterfire configure \
  --project=<your-project-id> \
  --platforms=android,web \
  --android-package-name=com.smartcrop.smart_crop \
  --out=lib/firebase_options.dart
```

### Enable Authentication in Firebase Console

1. Go to **Firebase Console** → **Authentication** → **Sign-in method**
2. Enable **Email/Password**
3. Enable **Google**
4. Configure OAuth consent screen if prompted

### Google Sign-In (Android)

If Google Sign-In fails on your machine, your debug keystore SHA-1 isn't registered in Firebase:

```bash
# Get your debug SHA-1
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android \
  | grep SHA1
```

If the keystore doesn't exist, create it:
```bash
keytool -genkey -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US" \
  -storepass android -keypass android
```

Then paste the SHA-1 at:
**Firebase Console** → **Project Settings** → **Your apps** → **Android app** → **Add Fingerprint**

---

## Project Structure

```
SmartCrop/
├── lib/
│   ├── main.dart                     # Entry point, Firebase init
│   ├── firebase_options.dart         # Firebase per-platform config
│   ├── services/
│   │   └── auth_service.dart         # Firebase Auth (email + Google)
│   ├── screens/                      # 23 UI screens
│   │   ├── splash_screen.dart        # Animated splash + auth check
│   │   ├── login_screen.dart         # Email/password + Google login
│   │   ├── signup_screen.dart        # Sign up with validation
│   │   ├── forgot_password_screen.dart
│   │   ├── dashboard_screen.dart     # Main dashboard (5 tabs)
│   │   ├── profile_screen.dart       # User profile + logout
│   │   ├── my_fields_screen.dart
│   │   ├── add_field_screen.dart
│   │   ├── field_detail_screen.dart
│   │   ├── sensors_screen.dart
│   │   ├── connected_sensors_screen.dart
│   │   ├── device_pairing_screen.dart
│   │   ├── sensor_alert_detail_screen.dart
│   │   ├── irrigation_screen.dart
│   │   ├── irrigation_schedule_screen.dart
│   │   ├── insights_tab.dart
│   │   ├── reports_tab.dart
│   │   ├── ai_crop_screen.dart
│   │   ├── fertilizer_screen.dart
│   │   ├── notifications_screen.dart
│   │   ├── edit_profile_screen.dart
│   │   └── help_center_screen.dart
│   └── theme/
│       ├── app_colors.dart
│       └── app_theme.dart
├── android/                          # Android platform files
├── web/                              # Web platform files
├── pubspec.yaml                      # Dependencies
└── pubspec.lock                      # Locked versions
```

---

## Troubleshooting

### `flutter pub get` fails with version conflict

```bash
flutter pub upgrade --major-versions
```

### Gradle build fails with "Unsupported class file major version"

Your JDK is too new. Install JDK 17:

```bash
# macOS
brew install openjdk@17
export JAVA_HOME=/opt/homebrew/opt/openjdk@17

# Then clean and rebuild
flutter clean
flutter pub get
flutter run
```

### Google Sign-In shows "Google sign-in failed" on Android

See the **Google Sign-In (Android)** section above — your debug SHA-1 needs to be in the Firebase Console.

### Google Sign-In shows "origin_mismatch" on Web

The OAuth client ID needs `http://localhost` as an authorized JavaScript origin:
1. Go to **Google Cloud Console** → **APIs & Services** → **Credentials**
2. Find the OAuth 2.0 Web Client ID
3. Add `http://localhost` to **Authorized JavaScript origins**

### iOS builds

iOS is **not configured**. To add iOS support:
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=smart-crop-ddf69 --platforms=ios \
  --ios-bundle-id=com.smartcrop.smartCrop
```

### App crashes on launch with "Firebase not initialized"

Run `flutter clean && flutter pub get && flutter run` to regenerate platform plugins.

---

## Platform Support

| Platform | Status       |
| -------- | ------------ |
| Android  | ✅ Working   |
| Web      | ✅ Working   |
| iOS      | ❌ Not configured |
| macOS    | ⚠️ Partial (not tested) |
