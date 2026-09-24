# SmartCrop

SmartCrop is a machine-learning powered **crop recommendation** system with a
rule-based **crop monitoring / persistent-alert engine** on top.

* The **Random Forest model** answers: *"Which crop is suitable for these field conditions?"*
* The **monitoring engine** answers: *"Is the selected crop currently experiencing abnormal conditions?"*

```text
Existing Random Forest
        |
        v
Crop Recommendation          which crop is suitable?
        |
        v
Selected Crop
        |
        v
Monitoring Engine               is the crop experiencing abnormal conditions?
        +--> Current sensor readings
        +--> Historical readings (72h window)
        +--> Crop-specific acceptable ranges
        |
        v
Persistence / Trend Analysis
        |
        +--> NORMAL
        +--> WARNING
        +--> CRITICAL
        |
        v
Recommendation / Alert
```

---

## 1. Project Structure & File Details

```
Smart Crop Ml Model/
├── Crop_recommendation_extended.csv   # Training dataset (3000 rows, 30 crops)
├── smartcrop_random_forest.ipynb      # Training & evaluation notebook
├── smartcrop_rf_model.pkl             # Trained Random Forest model (saved artifact)
├── smartcrop_label_encoder.pkl        # Saved label encoder (saved artifact)
├── app.py                             # Flask REST API (the running app)
├── test_api.py                        # Live-server API smoke tests
├── fertillizer Alerts/                # NEW monitoring & persistent-alert engine
│   ├── crop_thresholds.py             # Crop-specific monitoring ranges + config
│   ├── monitoring_engine.py           # Rule-based temporal monitoring engine
│   ├── simulate_sensor_data.py        # Simulated IoT data (8 scenarios)
│   └── test_monitoring.py             # Automated engine + API tests
├── README.md
├── venv/                              # Python virtual environment (dependencies)
└── __pycache__/                       # Python byte-code cache (auto-generated)
```

### 1.1 `Crop_recommendation_extended.csv` — Training Dataset
- **Size / shape:** 3000 rows + 1 header, 8 columns, no missing values.
- **Columns:** `N, P, K, temperature, humidity, ph, rainfall` (7 features) + `label` (crop target).
- **Target:** 30 crop classes (`apple, banana, blackgram, chickpea, coconut, coffee, cotton, grapes, jute, kidneybeans, lentil, maize, mango, mothbeans, mungbean, muskmelon, mustard, onion, orange, papaya, pigeonpeas, pomegranate, rice, sorghum, sugarcane, sunflower, tobacco, tomato, watermelon, wheat`).

### 1.2 `smartcrop_random_forest.ipynb` — Training & Evaluation Notebook
Loads the CSV, encodes crop labels, trains a `RandomForestClassifier` (100 trees, `random_state=42`, `n_jobs=-1`), evaluates it (train/test accuracy, overfitting check, learning curve, classification report, confusion matrix, 5-fold CV stability, feature importance), and exports `smartcrop_rf_model.pkl` + `smartcrop_label_encoder.pkl`. **Keep this model unchanged.**

### 1.3/1.4 `smartcrop_rf_model.pkl` & `smartcrop_label_encoder.pkl` — Model Artifacts
Serialized `RandomForestClassifier` (30 classes, 7 features) and its `LabelEncoder`. Loaded once by `app.py`.

### 1.5 `app.py` — Flask REST API
Loads the model and exposes the endpoints below (see §3 for details). The monitoring endpoints reuse `monitoring_engine.py` / `crop_thresholds.py`
(imported from the `fertillizer Alerts/` folder via `sys.path`) — no monitoring
logic lives inside `app.py`.
- Port configurable via `SMARTCROP_PORT` (default `5000`).

### 1.6 `fertillizer Alerts/crop_thresholds.py` — Monitoring Configuration
Crop-specific acceptable ranges + engine configuration, kept **separate from the monitoring logic** so ranges/tolerances can be tuned without touching code.

**Prototype disclaimer:** thresholds are prototype/config values, not validated agronomic prescriptions:
- `N, P, K, temperature, humidity, ph` ranges are derived from the project's **own training dataset** (`mean ± 1 std` per crop) — consistent with the existing model.
- `soil_moisture` is a **prototype placeholder** (not in the dataset), labeled `prototype: True`.
- `rainfall` is intentionally **not** thresholded (a single instantaneous rainfall reading does not represent crop water requirements).

All 30 crops from the training dataset have monitoring thresholds configured. Config values include: analysis window (72h), minimum readings for persistence (3), abnormal-percentage bands (monitor <40%, warning 40–70%, persistent >70%), trend sensitivity, and health-score weights.

### 1.7 `fertillizer Alerts/monitoring_engine.py` — Monitoring Engine
The reusable analysis engine (see §4). Source-agnostic: it does not care whether readings came from ESP32 → Firebase, a simulator, or manual entry.

### 1.8 `fertillizer Alerts/simulate_sensor_data.py` — Simulated IoT Data
Generates the 8 test scenarios (§6) so the system is fully testable **without hardware**.

### 1.9 `fertillizer Alerts/test_monitoring.py` — Automated Tests
26 unittest tests for the engine + API (Flask test client, no running server needed). See §6.

### 1.10 `test_api.py` — Live-Server Smoke Tests
Runs against a running server (`BASE_URL` configurable via `SMARTCROP_BASE_URL`, default `http://localhost:5000`). Tests `/health`, `/features`, clean/noisy/stable predictions using the **actual API contract** (`recommended_crops`), `/monitor`, and HTTP 400 error handling.

### 1.11 `venv/` & `__pycache__/`
Python 3.11 virtual environment (Flask, scikit-learn, pandas, numpy, joblib, requests, matplotlib, seaborn) and auto-generated byte-code cache.

---

## 2. API Endpoints

| Endpoint            | Method | Purpose                                                              |
|---------------------|--------|----------------------------------------------------------------------|
| `/health`           | GET    | Liveness check.                                                      |
| `/features`         | GET    | The 7 ML input features + descriptions.                              |
| `/predict`          | POST   | Top-3 recommended crops for one soil/weather sample.                 |
| `/predict/batch`    | POST   | Top-3 crops for many samples in one call.                            |
| `/fertilizer`       | POST   | Per-nutrient (N/P/K) advice for a chosen crop.                       |
| `/monitor`          | POST   | Monitoring analysis (current + historical readings).                 |
| `/monitor/config`   | GET    | Monitoring crops, thresholds and configuration.                      |

Backward compatibility: the existing endpoint contracts are unchanged.

---

## 3. How the App Works

### 3.1 Existing workflow (unchanged)
```bash
cd "Smart Crop Ml Model"
source venv/bin/activate
python app.py            # starts server on 0.0.0.0:<SMARTCROP_PORT or 5000>
python test_api.py       # optional: live-server smoke tests
```
Clients POST all 7 readings to `/predict` and get `{"recommended_crops": ["wheat", ...]}`.

### 3.2 Monitoring workflow

```bash
curl -X POST http://localhost:5000/monitor -H "Content-Type: application/json" -d '{
  "crop": "wheat",
  "current": {
    "N": 32, "P": 30, "K": 43,
    "temperature": 24, "humidity": 62, "ph": 6.8,
    "soil_moisture": 38
  },
  "history": [
    {"timestamp": "2026-08-16T08:00:00", "N": 31, "P": 30, "K": 43,
     "temperature": 24, "humidity": 62, "ph": 6.8, "soil_moisture": 37},
    ...
  ]
}'
```

Response includes:
```json
{
  "crop": "wheat",
  "overall_status": "WARNING",
  "health_score": 82,
  "health_score_label": "SmartCrop Monitoring Health Score",
  "analysis_window": { "window_hours": 72, "...": "..." },
  "parameter_results": {
    "N": {
      "status": "WARNING",
      "current": 32,
      "recommended_range": [107, 131],
      "abnormal_percentage": 83.3,
      "persistent": true,
      "trend": "declining"
    }
  },
  "persistent_issues": ["N"],
  "alerts": [{ "severity": "WARNING", "parameter": "N",
               "type": "deficiency", "message": "..." }],
  "recommendations": ["..."]
}
```

The engine runs entirely server-side; the client only supplies `crop`, `current`, and optional `history`.

---

## 4. Monitoring Engine Design

### 4.1 Design decision

> SmartCrop uses **machine learning** for crop suitability prediction and a
> **transparent rule-based temporal monitoring engine** for continuous crop
> monitoring. The monitoring engine analyzes crop-specific thresholds over
> historical sensor observations rather than generating alerts from a single
> noisy reading.

### 4.2 Status classification (NORMAL / WARNING / CRITICAL)
Every parameter is classified from its **current** reading using configurable
ranges + a warning buffer:
* `NORMAL`   — within `[min, max]`
* `WARNING`  — outside the range but within `buffer` of it
* `CRITICAL` — farther than `buffer` from the range

### 4.3 Historical / persistence analysis (the core feature)
The engine does **not** alert on a single abnormal reading. Across a
configurable **72-hour window** (default) it computes, for each parameter:
1. number of readings analyzed,
2. how many are outside the recommended range,
3. `abnormal_percentage = abnormal / total × 100`,
4. the trend (stable / increasing / decreasing),
5. whether the abnormal condition has **persisted** long enough,
6. severity.

Persistence bands (configurable, in `crop_thresholds.py`):

| Abnormal % | Classification | Watch                            |
|------------|----------------|----------------------------------|
| < 40%      | `monitor`      | noise / transient, no alert      |
| 40–70%     | `warning`      | elevated, watch but no fertilizer alert |
| > 70%      | `persistent`   | persistent problem → advisory    |

Fewer than `min_readings_for_persistence` (default 3) readings →
`insufficient_history` and **never** persistent.

### 4.4 Noise protection (no false alerts)
Transient readings (e.g. `N: 32 → 36 → 34 → 37`) produce `monitor` status with
**no fertilizer alert**. Only a condition that persists above the configured
abnormal-percentage floor (and whose current reading is still abnormal)
generates an advisory.

### 4.5 Alert / recommendation language
Advisories are **decision-support language only** — no scientifically precise
dosage claims (the project contains no validated dosage model):
* Deficiency: *"Persistent nitrogen deficiency detected for wheat. Current N is
  below the configured range. Inspect soil/crop condition and consider an
  appropriate nitrogen-based fertilizer after field/soil assessment."*
* Excess: *"Nitrogen level is persistently above the configured range for
  wheat. Avoid unnecessary additional N application and inspect field
  conditions."*
* For non-NPK parameters (e.g. soil moisture): generic field-inspection /
  water-management advisories, no fertilizer dosage.

### 4.6 Trend analysis
Simple statistical slope over recent history (no ML). For a persistently low
parameter that is also trending down, severity aggravates (extra health-score
deduction) — e.g. `42 → 40 → 38 → 36 → 34` = `decreasing`.

### 4.7 Health score
`SmartCrop Monitoring Health Score` — a **prototype** decision-support metric,
explicitly **not** a validated crop-health index. Starts at 100 and deducts
points for warning/critical readings, persistent issues, and aggravating
trends (weights in `crop_thresholds.py['scoring']`), clamped to 0–100.

---

## 5. Simulated Sensor Data (no hardware required)

```bash
python "fertillizer Alerts/simulate_sensor_data.py"            # run all 8 scenarios through the engine
python "fertillizer Alerts/simulate_sensor_data.py" --json 3   # dump the /monitor JSON payload for scenario
```

| # | Scenario                          | Expected outcome                                  |
|---|-----------------------------------|---------------------------------------------------|
| 1 | Healthy crop                      | `NORMAL`, no alerts                               |
| 2 | Temporary abnormal reading       | `WARNING`/`MONITOR`, **no** fertilizer alert     |
| 3 | Persistent N deficiency (2–3 days)| persistent nitrogen deficiency advisory          |
| 4 | Persistent P deficiency           | persistent phosphorus deficiency advisory         |
| 5 | Persistent K deficiency           | persistent potassium deficiency advisory          |
| 6 | Excess nutrient (persistent)      | persistent excess advisory                        |
| 7 | Sensor noise                      | no false persistent alerts                        |
| 8 | Multiple simultaneous issues      | multiple persistent issues                        |

---

## 6. Tests

Automated (no running server — uses the Flask test client):

```bash
source venv/bin/activate
python -m unittest discover -s "fertillizer Alerts" -p "test_*.py" -v
# or from inside the folder: cd "fertillizer Alerts" && python -m unittest test_monitoring -v
```

Covers: normal values, a single abnormal reading, repeated abnormal readings,
persistent deficiency, persistent excess, sensor noise, missing history,
insufficient history, invalid crop, invalid sensor values, missing required
parameters, multiple simultaneous deficiencies, trend calculation, health
score calculation, plus the existing `/predict` and `/predict/batch` contract.

Live-server smoke test (start the server first):

```bash
SMARTCROP_PORT=5001 python app.py           # if 5000 is busy
SMARTCROP_BASE_URL=http://localhost:5001 python test_api.py
```

---

## 7. Connecting Live IoT / Firebase Later

The monitoring engine is **source-agnostic** — it accepts plain
`{crop, current, history}` dicts and has no knowledge of where readings came
from. This keeps ESP32/Firebase integration a separate concern.

A future pipeline can operate unchanged:

```text
ESP32 sensors --> Firebase/Cloud --> read latest N readings (current)
                                  --> read last 72h of readings (history)
                                                             |
                                                             v
                          POST /monitor {crop, current, history} --> alert/recommendation
```

The project currently ships only the **simulated/manual** path
(`fertillizer Alerts/simulate_sensor_data.py`) so everything is testable
offline. No live IoT hardware is connected, and none is claimed.