# SmartCrop

Smart farming mobile app with AI-powered crop recommendation and real-time monitoring.

---

## What is this?

SmartCrop is a Flutter mobile application that helps farmers monitor their crops using IoT sensor data and get AI-powered recommendations. It connects to a Python/Flask backend that runs a Random Forest machine learning model for crop recommendation and a rule-based monitoring engine for continuous crop health tracking.

The app supports 30 crops: apple, banana, blackgram, chickpea, coconut, coffee, cotton, grapes, jute, kidneybeans, lentil, maize, mango, mothbeans, mungbean, muskmelon, mustard, onion, orange, papaya, pigeonpeas, pomegranate, rice, sorghum, sugarcane, sunflower, tobacco, tomato, watermelon, wheat.

---

## Project Structure

```
SmartCrop/
├── lib/
│   ├── main.dart                          # App entry point
│   ├── firebase_options.dart              # Firebase configuration
│   ├── models/
│   │   └── sensor_data.dart               # SensorData model
│   ├── services/
│   │   ├── auth_service.dart              # Firebase authentication
│   │   ├── sensor_service.dart            # Realtime sensor stream
│   │   ├── crop_api_service.dart          # Backend API client (/predict, /fertilizer, /monitor)
│   │   └── active_crop_service.dart       # Persistent active crop storage (SharedPreferences)
│   ├── screens/
│   │   ├── dashboard_screen.dart          # Main dashboard (home, sensors, insights, reports, profile tabs)
│   │   ├── ai_crop_screen.dart            # AI crop recommendation screen
│   │   ├── fertilizer_screen.dart         # Fertilizer recommendations (backend-connected)
│   │   ├── sensors_screen.dart            # Sensor monitoring with alerts (backend-connected)
│   │   ├── sensor_alert_detail_screen.dart # Alert detail view (backend-connected)
│   │   ├── notifications_screen.dart      # Notifications list (backend-connected)
│   │   ├── insights_tab.dart              # Insights tab with fertilizer alerts (backend-connected)
│   │   ├── reports_tab.dart               # Reports tab (currently hardcoded/static)
│   │   └── ...                            # Other screens
│   └── theme/
│       └── app_colors.dart                # Theme colors
├── Smart Crop Ml Model/                   # Python backend
│   ├── app.py                             # Flask REST API
│   ├── Crop_recommendation_extended.csv   # Training dataset (3000 rows, 30 crops)
│   ├── smartcrop_random_forest.ipynb      # Model training notebook
│   ├── smartcrop_rf_model.pkl             # Trained Random Forest model
│   ├── smartcrop_label_encoder.pkl        # Label encoder
│   ├── test_api.py                        # Live API smoke tests
│   └── fertillizer Alerts/
│       ├── crop_thresholds.py             # Crop-specific monitoring thresholds (all 30 crops)
│       ├── monitoring_engine.py           # Rule-based monitoring engine
│       ├── simulate_sensor_data.py        # Simulated IoT data (8 scenarios)
│       └── test_monitoring.py             # Automated tests
└── pubspec.yaml                           # Flutter dependencies
```

---

## How to Run

### Backend (Python/Flask)

```bash
cd "Smart Crop Ml Model"
source venv/bin/activate
python app.py
```

The server starts on `http://localhost:5000`.

### Frontend (Flutter)

```bash
cd SmartCrop
flutter pub get
flutter run
```

For web: `flutter run -d chrome`

---

## API Endpoints

The Flutter app connects to these backend endpoints:

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | Liveness check |
| `/features` | GET | The 7 ML input features |
| `/predict` | POST | Top-3 recommended crops for given soil/weather conditions |
| `/predict/batch` | POST | Batch crop recommendation |
| `/fertilizer` | POST | Per-nutrient (N/P/K) fertilizer advice for a specific crop |
| `/monitor` | POST | Monitoring analysis with crop-specific thresholds |
| `/monitor/config` | GET | Available crops and threshold configuration |

---

## App Features

### Active Crop System

The dashboard has a dedicated Active Crop section where the user selects their current crop. This crop is persisted across app restarts using SharedPreferences and drives all crop-specific logic throughout the app. When the user changes the active crop, all connected screens (Sensors, Insights, Fertilizer, Notifications) immediately update to use the new crop.

### Dashboard Structure

The main Dashboard has five tabs:

1. **Home** - Active Crop selector, AI Crop Recommendation card, Field Overview, and Status Alerts
2. **Sensors** - Real-time sensor readings with monitoring alerts (connected to /monitor endpoint)
3. **Insights** - Fertilizer recommendations and crop-specific alerts (connected to /fertilizer and /monitor endpoints)
4. **Reports** - Analytical insights, growth trends, and report downloads (currently hardcoded/mock data)
5. **Profile** - User profile and settings

### AI Crop Recommendation

The AI recommendation screen calls the backend `/predict` endpoint with 7 soil and weather parameters (N, P, K, temperature, humidity, pH, rainfall) and returns the top-3 recommended crops. The user can accept any recommended crop to set it as the Active Crop.

### Real-time Monitoring

The Sensors tab receives live sensor data via a Firebase Realtime Database stream. The monitoring engine on the backend analyzes current readings against crop-specific thresholds derived from the training dataset (mean +/- 1 std). It tracks historical readings over a 72-hour window to distinguish transient noise from persistent issues.

### Fertilizer Recommendations

The Insights tab and Fertilizer screen call the backend `/fertilizer` endpoint with the active crop and current N/P/K sensor values. The backend returns specific fertilizer recommendations based on which nutrients are deficient or excessive for the selected crop.

---

## Supported Crops (30)

All 30 crops from the ML training dataset are supported across the entire stack:

**Fruits:** apple, banana, coconut, grapes, mango, muskmelon, orange, papaya, pomegranate, watermelon

**Grains/Cereals:** barley (via maize), jute, maize, millet (via sorghum), mustard, rice, sorghum, wheat

**Legumes:** blackgram, chickpea, kidneybeans, lentil, mothbeans, mungbean, pigeonpeas

**Other:** coffee, cotton, onion, sugarcane, sunflower, tobacco, tomato

Each crop has monitoring thresholds (N, P, K, temperature, humidity, pH, soil moisture) derived from the project's own training dataset.

---

## Tech Stack

- **Frontend:** Flutter/Dart, Google Fonts, SharedPreferences
- **Backend:** Python, Flask, scikit-learn (Random Forest), pandas, numpy
- **Authentication:** Firebase Auth (Google Sign-In + Email/Password)
- **Database:** Firebase Realtime Database (sensor data stream)
- **ML Model:** Random Forest Classifier (30 classes, 7 features)

---

## Common Problems

| Problem | Solution |
|---|---|
| `flutter: command not found` | Install Flutter from https://docs.flutter.dev/get-started/install |
| `flutter pub get` fails | Run `flutter pub upgrade --major-versions` then `flutter pub get` again |
| `java: command not found` | Install Java 17: `brew install openjdk@17` (macOS) |
| Gradle build fails | Ensure Java 17 is installed and JAVA_HOME is set |
| "Google sign-in failed" | Add your SHA-1 fingerprint to Firebase (see below) |
| App crashes on launch | Run `flutter clean && flutter pub get && flutter run` |
| Backend connection refused | Ensure Flask server is running on localhost:5000 |

---

## Firebase Setup

```bash
dart pub global activate flutterfire_cli
export PATH="$PATH":"$HOME/.pub-cache/bin"
firebase login
flutterfire configure --project=smart-crop-ddf69 --platforms=android,web --android-package-name=com.smartcrop.smart_crop --out=lib/firebase_options.dart
```

### SHA-1 for Android

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep "SHA1"
```

Add the SHA-1 to Firebase Console > Project Settings > Android app > Add Fingerprint.

---

## Platforms

| Platform | Status |
|---|---|
| Android | Supported |
| Web | Supported |
| iOS | Not yet configured |
