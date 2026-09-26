import os
import sys
import numpy as np
import pandas as pd
import joblib
from flask import Flask, request, jsonify
from flask_cors import CORS

# Monitor/alert modules live in the "fertillizer Alerts" folder.
ALERTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fertillizer Alerts")
if ALERTS_DIR not in sys.path:
    sys.path.insert(0, ALERTS_DIR)

from crop_thresholds import CROP_THRESHOLDS, MONITOR_CONFIG, available_crops
from monitoring_engine import (analyze_monitoring, UnknownCropError,
                               InvalidReadingError)

app = Flask(__name__)
CORS(app)

# ── Safe model loading ─────────────────────────────────────────────
# Resolved relative to this file so the server starts from any working
# directory. Regenerate the artifacts with: python train.py
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "smartcrop_rf_model.pkl")
LE_PATH = os.path.join(BASE_DIR, "smartcrop_label_encoder.pkl")

if not os.path.exists(MODEL_PATH):
    raise FileNotFoundError(
        f"Model file not found: {MODEL_PATH}\n"
        "Generate it first:  python train.py"
    )

if not os.path.exists(LE_PATH):
    raise FileNotFoundError(
        f"Label encoder not found: {LE_PATH}\n"
        "Generate it first:  python train.py"
    )

model = joblib.load(MODEL_PATH)
le = joblib.load(LE_PATH)

# ASCII-only: Windows consoles default to cp1252 and raise on emoji.
print("[OK] Model loaded successfully")
print("Classes:", getattr(model, "classes_", None))

# ── Config ─────────────────────────────────────────────────────────
FEATURES = ["N", "P", "K", "temperature", "humidity", "ph", "rainfall"]

OPTIMAL_NPK = {
  "apple": {"N": {"mean": 20.8, "std": 11.9}, "P": {"mean": 134.2, "std": 8.1}, "K": {"mean": 199.9, "std": 3.3}},
  "banana": {"N": {"mean": 100.2, "std": 11.1}, "P": {"mean": 82.0, "std": 7.7}, "K": {"mean": 50.0, "std": 3.4}},
  "blackgram": {"N": {"mean": 40.0, "std": 12.7}, "P": {"mean": 67.5, "std": 7.2}, "K": {"mean": 19.2, "std": 3.2}},
  "chickpea": {"N": {"mean": 40.1, "std": 12.2}, "P": {"mean": 67.8, "std": 7.5}, "K": {"mean": 79.9, "std": 3.3}},
  "coconut": {"N": {"mean": 22.0, "std": 11.8}, "P": {"mean": 16.9, "std": 8.4}, "K": {"mean": 30.6, "std": 3.0}},
  "coffee": {"N": {"mean": 101.2, "std": 12.3}, "P": {"mean": 28.7, "std": 7.3}, "K": {"mean": 29.9, "std": 3.2}},
  "cotton": {"N": {"mean": 117.8, "std": 11.6}, "P": {"mean": 46.2, "std": 7.3}, "K": {"mean": 19.6, "std": 3.2}},
  "grapes": {"N": {"mean": 23.2, "std": 12.5}, "P": {"mean": 132.5, "std": 7.6}, "K": {"mean": 200.1, "std": 3.3}},
  "jute": {"N": {"mean": 78.4, "std": 11.0}, "P": {"mean": 46.9, "std": 7.2}, "K": {"mean": 40.0, "std": 3.3}},
  "kidneybeans": {"N": {"mean": 20.8, "std": 10.8}, "P": {"mean": 67.5, "std": 7.6}, "K": {"mean": 20.0, "std": 3.1}},
  "lentil": {"N": {"mean": 18.8, "std": 12.2}, "P": {"mean": 68.4, "std": 7.3}, "K": {"mean": 19.4, "std": 3.0}},
  "maize": {"N": {"mean": 77.8, "std": 11.9}, "P": {"mean": 48.4, "std": 8.0}, "K": {"mean": 19.8, "std": 2.9}},
  "mango": {"N": {"mean": 20.1, "std": 12.3}, "P": {"mean": 27.2, "std": 7.7}, "K": {"mean": 29.9, "std": 3.1}},
  "mothbeans": {"N": {"mean": 21.4, "std": 11.3}, "P": {"mean": 48.0, "std": 7.5}, "K": {"mean": 20.2, "std": 3.0}},
  "mungbean": {"N": {"mean": 21.0, "std": 11.5}, "P": {"mean": 47.3, "std": 7.9}, "K": {"mean": 19.9, "std": 3.1}},
  "muskmelon": {"N": {"mean": 100.3, "std": 12.2}, "P": {"mean": 17.7, "std": 7.2}, "K": {"mean": 50.1, "std": 3.2}},
  "mustard": {"N": {"mean": 81.5, "std": 12.3}, "P": {"mean": 45.6, "std": 8.5}, "K": {"mean": 28.9, "std": 6.1}},
  "onion": {"N": {"mean": 100.3, "std": 11.4}, "P": {"mean": 55.9, "std": 8.5}, "K": {"mean": 81.0, "std": 11.9}},
  "orange": {"N": {"mean": 19.6, "std": 11.9}, "P": {"mean": 16.6, "std": 7.7}, "K": {"mean": 10.0, "std": 3.1}},
  "papaya": {"N": {"mean": 49.9, "std": 12.2}, "P": {"mean": 59.0, "std": 7.1}, "K": {"mean": 50.0, "std": 3.1}},
  "pigeonpeas": {"N": {"mean": 20.7, "std": 11.8}, "P": {"mean": 67.7, "std": 7.3}, "K": {"mean": 20.3, "std": 2.8}},
  "pomegranate": {"N": {"mean": 18.9, "std": 12.6}, "P": {"mean": 18.8, "std": 7.4}, "K": {"mean": 40.2, "std": 3.0}},
  "rice": {"N": {"mean": 79.9, "std": 11.9}, "P": {"mean": 47.6, "std": 7.9}, "K": {"mean": 39.9, "std": 2.9}},
  "sorghum": {"N": {"mean": 80.6, "std": 11.6}, "P": {"mean": 45.1, "std": 8.8}, "K": {"mean": 36.2, "std": 8.8}},
  "sugarcane": {"N": {"mean": 126.2, "std": 14.8}, "P": {"mean": 53.4, "std": 9.2}, "K": {"mean": 63.8, "std": 9.5}},
  "sunflower": {"N": {"mean": 97.7, "std": 11.4}, "P": {"mean": 54.6, "std": 9.1}, "K": {"mean": 45.4, "std": 8.9}},
  "tobacco": {"N": {"mean": 59.2, "std": 10.6}, "P": {"mean": 43.9, "std": 8.7}, "K": {"mean": 100.7, "std": 12.2}},
  "tomato": {"N": {"mean": 99.7, "std": 11.2}, "P": {"mean": 65.5, "std": 8.9}, "K": {"mean": 98.9, "std": 11.5}},
  "watermelon": {"N": {"mean": 99.4, "std": 12.6}, "P": {"mean": 17.0, "std": 7.5}, "K": {"mean": 50.2, "std": 3.3}},
  "wheat": {"N": {"mean": 118.9, "std": 11.8}, "P": {"mean": 61.2, "std": 12.7}, "K": {"mean": 44.6, "std": 9.6}},
}


# ── Health check ────────────────────────────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "model": "SmartCrop RF",
        "version": "1.0"
    })


# ── Predict endpoint ────────────────────────────────────────────────
@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()

    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    missing = [f for f in FEATURES if f not in data]
    if missing:
        return jsonify({"error": f"Missing fields: {missing}"}), 400

    try:
        sample = pd.DataFrame([{f: float(data[f]) for f in FEATURES}])
    except Exception as e:
        return jsonify({"error": str(e)}), 400

    proba = model.predict_proba(sample)[0]
    classes = model.classes_

    top3_indices = np.argsort(proba)[-3:][::-1]
    return jsonify({
        "recommended_crops": [
            {"crop": str(classes[i]), "confidence": round(float(proba[i]) * 100, 1)}
            for i in top3_indices
        ]
    })


# ── Batch predict ──────────────────────────────────────────────────
@app.route("/predict/batch", methods=["POST"])
def predict_batch():
    data = request.get_json()

    if not data or "samples" not in data:
        return jsonify({"error": "Body must have 'samples' list"}), 400

    results = []

    for i, item in enumerate(data["samples"]):

        missing = [f for f in FEATURES if f not in item]
        if missing:
            results.append({"index": i, "error": f"Missing fields: {missing}"})
            continue

        try:
            row = pd.DataFrame([{f: float(item[f]) for f in FEATURES}])
            proba = model.predict_proba(row)[0]
            classes = model.classes_

            top3_indices = np.argsort(proba)[-3:][::-1]
            top3_crops = [str(classes[i]) for i in top3_indices]

            results.append({
                "index": i,
                "recommended_crops": top3_crops,
            })

        except Exception as e:
            results.append({"index": i, "error": str(e)})

    return jsonify({"results": results, "total": len(results)})


# ── Feature info ───────────────────────────────────────────────────
@app.route("/features", methods=["GET"])
def features():
    return jsonify({
        "features": FEATURES,
        "description": {
            "N": "Nitrogen content in soil (kg/ha)",
            "P": "Phosphorus content in soil (kg/ha)",
            "K": "Potassium content in soil (kg/ha)",
            "temperature": "Temperature in Celsius",
            "humidity": "Relative humidity (%)",
            "ph": "Soil pH value",
            "rainfall": "Annual rainfall (mm)",
        },
    })


# ── Fertilizer recommendation ──────────────────────────────────────
@app.route("/fertilizer", methods=["POST"])
def fertilizer():
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    missing = [f for f in ["crop", "N", "P", "K"] if f not in data]
    if missing:
        return jsonify({"error": f"Missing fields: {missing}"}), 400

    crop = str(data["crop"]).lower()
    if crop not in OPTIMAL_NPK:
        return jsonify({"error": f"Unknown crop '{crop}'. Must be one of: {list(OPTIMAL_NPK.keys())}"}), 400

    try:
        current_n = float(data["N"])
        current_p = float(data["P"])
        current_k = float(data["K"])
    except Exception as e:
        return jsonify({"error": str(e)}), 400

    recommendations = {}
    for nutrient in ["N", "P", "K"]:
        curr = {"N": current_n, "P": current_p, "K": current_k}[nutrient]
        opt = OPTIMAL_NPK[crop][nutrient]
        low = round(opt["mean"] - opt["std"], 1)
        high = round(opt["mean"] + opt["std"], 1)

        if curr < low:
            deficit = round(low - curr, 1)
            recommendations[nutrient] = {
                "status": "deficient",
                "current": curr,
                "optimal_range": [low, high],
                "deficit": deficit,
                "advice": f"Add ~{deficit} kg/ha of {nutrient} fertilizer"
            }
        elif curr > high:
            surplus = round(curr - high, 1)
            recommendations[nutrient] = {
                "status": "excess",
                "current": curr,
                "optimal_range": [low, high],
                "surplus": surplus,
                "advice": f"Reduce {nutrient} by ~{surplus} kg/ha. Consider leaching or switching crop"
            }
        else:
            recommendations[nutrient] = {
                "status": "sufficient",
                "current": curr,
                "optimal_range": [low, high],
                "advice": f"{nutrient} level is adequate. No extra needed"
            }

    return jsonify({
        "crop": crop,
        "recommendations": recommendations
    })


# ── Monitoring ─────────────────────────────────────────────────────────
@app.route("/monitor", methods=["POST"])
def monitor():
    """Analyze a crop's current + historical sensor readings.

    Body: {"crop": str, "current": {...}, "history": [ {...}, ... ]}

    current must include every configured monitoring parameter for the crop.
    history is optional. Returns structured monitoring results with status,
    persistence/trend analysis, health score, alerts and recommendations.
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    crop = data.get("crop")
    if not crop:
        return jsonify({"error": "Missing field: crop"}), 400

    if "current" not in data:
        return jsonify({"error": "Missing field: current"}), 400

    history = data.get("history", [])

    try:
        result = analyze_monitoring(crop, data["current"],
                                    history if isinstance(history, list) else None)
    except (UnknownCropError, KeyError) as e:
        return jsonify({"error": str(e)}), 400
    except InvalidReadingError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": f"Monitoring failed: {e}"}), 400

    return jsonify(result)


@app.route("/monitor/config", methods=["GET"])
def monitor_config():
    """Return the monitoring configuration (crops + thresholds + settings)."""
    return jsonify({
        "monitored_crops": available_crops(),
        "monitoring_config": MONITOR_CONFIG,
        "thresholds": CROP_THRESHOLDS,
    })


# ── Run app ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("Starting Flask server...")
    app.run(debug=True, host="0.0.0.0",
            port=int(os.environ.get("SMARTCROP_PORT", 5000)))