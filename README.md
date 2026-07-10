# SmartCrop

Smart farming mobile app.

---

## 📱 What is this?

An app for farmers to monitor crops, sensors, irrigation, and get AI-powered recommendations.

---

## 🚀 How to Run This Project (Step by Step)

> **No coding knowledge needed.** Just follow these commands in order.

---

### Step 1: Install Flutter

Download and install Flutter from here:
https://docs.flutter.dev/get-started/install

Choose your operating system (macOS / Windows / Linux) and follow the instructions.

After installation, open **Terminal** (macOS/Linux) or **Command Prompt** (Windows) and run:

```bash
flutter doctor
```

Make sure everything has a green checkmark ✅. If something is missing, the doctor will tell you what to install.

---

### Step 2: Clone the Project

```bash
git clone https://github.com/aleeza-javed/SmartCrop.git
cd SmartCrop
git checkout mobile-app-frontend
```

---

### Step 3: Install Dependencies

```bash
flutter pub get
```

Wait for it to finish. You should see `Got dependencies!` at the end.

---

### Step 4: Set Up Java (For Android Only)

The app needs **Java 17** to build for Android.

**Check your Java version:**
```bash
java -version
```

If it's NOT version 17, do one of these:

**macOS (Homebrew):**
```bash
brew install openjdk@17
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
```

**Windows / Linux:** Download JDK 17 from https://adoptium.net/ and set `JAVA_HOME`.

---

### Step 5: Connect Your Phone or Start Emulator

**Option A — Physical Android phone:**
1. Enable **Developer Options** on your phone (Settings → About Phone → Tap "Build Number" 7 times)
2. Enable **USB Debugging** (Settings → Developer Options)
3. Plug your phone into your computer via USB
4. Run `flutter devices` — your phone should appear

**Option B — Android Emulator:**
1. Open Android Studio
2. Click "More Actions" → "Virtual Device Manager"
3. Create a new device and start it

**Option C — Web browser:**
No setup needed. Just use `flutter run -d chrome` in Step 6.

---

### Step 6: Run the App

```bash
flutter run
```

If you have multiple devices, it will ask you to pick one. Select the number of your device and press Enter.

**To run on web instead:**
```bash
flutter run -d chrome
```

The app will open. You'll see the login screen.

---

### Step 7: Fix Google Sign-In (One-Time Setup)

The first time you tap "Continue with Google", it will fail. Fix it by adding your **SHA-1 fingerprint**:

**Get your SHA-1:**
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep "SHA1"
```

You'll see something like: `SHA1: 8F:9D:D6:26:FA:51:F5:00:65:78:F8:DC:31:20:2E:D2:F4:D0:92:AC`

**Now add it to Firebase:**
1. Go to https://console.firebase.google.com/project/smart-crop-ddf69/settings/general
2. Scroll down to **Your apps** → click the Android app
3. Click **Add Fingerprint**
4. Paste the SHA-1 you copied
5. Click **Save**

If you don't have a debug keystore yet (error: `keytool error`), create one first:

```bash
keytool -genkey -v -keystore ~/.android/debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" -storepass android -keypass android
```

Then run the SHA-1 command again.

---

### Step 8: Create an Account

1. Open the app
2. Tap **Sign Up**
3. Enter your name, email, and password
4. Accept the terms and tap **Create Account**
5. Go back to login and sign in

---

## ❓ Common Problems

| Problem | Solution |
|---------|----------|
| `flutter: command not found` | Flutter is not installed. Go back to Step 1. |
| `flutter pub get` fails | Run `flutter pub upgrade --major-versions` then `flutter pub get` again |
| `java: command not found` | Install Java 17 (Step 4) |
| Gradle build fails with "Unsupported class file major version" | Your Java version is too new. Install Java 17 (Step 4) |
| "Google sign-in failed" | You skipped Step 7 — add your SHA-1 to Firebase |
| `error: src refspec` when pushing | You don't have write access to the repo |
| App crashes on launch | Run `flutter clean && flutter pub get && flutter run` |

---

## 📁 Project Structure (For Reference)

```
lib/
├── main.dart              # App start
├── firebase_options.dart   # Firebase settings
├── services/               # Auth logic
├── screens/                # All app screens
└── theme/                  # Colors and styling
```

---

## 🔧 For Developers (Advanced)

### Firebase Setup (Only if using a different project)

```bash
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"
firebase login
flutterfire configure --project=smart-crop-ddf69 --platforms=android,web --android-package-name=com.smartcrop.smart_crop --out=lib/firebase_options.dart
```

### Branch Info

- Branch: `mobile-app-frontend`
- Remote: `https://github.com/aleeza-javed/SmartCrop.git`

---

## ✅ Platforms

| Platform | Works? |
|----------|--------|
| Android  | ✅ Yes |
| Web      | ✅ Yes |
| iPhone   | ❌ Not yet |
