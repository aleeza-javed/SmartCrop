import os
import numpy as np
import pandas as pd
import joblib
from flask import Flask, request, jsonify

app = Flask(__name__)

# ── Safe model loading ─────────────────────────────────────────────
MODEL_PATH = "smartcrop_rf_model.pkl"
LE_PATH = "smartcrop_label_encoder.pkl"

if not os.path.exists(MODEL_PATH):
    raise FileNotFoundError(f"Model file not found: {MODEL_PATH}")

if not os.path.exists(LE_PATH):
    raise FileNotFoundError(f"Label encoder not found: {LE_PATH}")

model = joblib.load(MODEL_PATH)
le = joblib.load(LE_PATH)

print("✅ Model loaded successfully")
print("Classes:", getattr(model, "classes_", None))

# ── Config ─────────────────────────────────────────────────────────
FEATURES = ["N", "P", "K", "temperature", "humidity", "ph", "rainfall"]
CONFIDENCE_THRESHOLD = 0.70


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

    # ── Co-equal: return ALL crops above the confidence threshold ──
    crop_probs = sorted(
        [
            {"crop": str(c), "probability": round(float(p), 4)}
            for c, p in zip(classes, proba)
        ],
        key=lambda x: x["probability"],
        reverse=True,
    )

    top_prob = float(np.max(proba))

    if top_prob < CONFIDENCE_THRESHOLD:
        above_threshold = [c for c in crop_probs if c["probability"] >= CONFIDENCE_THRESHOLD]
        return jsonify({
            "status": "low_confidence",
            "co_equal_crops": above_threshold if above_threshold else crop_probs[:3],
            "all_crops": crop_probs,
        })

    # Co-equal: all crops within 10% of the top probability
    co_equal = [c for c in crop_probs if c["probability"] >= top_prob - 0.10]

    return jsonify({
        "status": "success",
        "co_equal_crops": co_equal,
        "all_crops": crop_probs,
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

            crop_probs = sorted(
                [{"crop": str(c), "probability": round(float(p), 4)}
                 for c, p in zip(classes, proba)],
                key=lambda x: x["probability"], reverse=True,
            )
            top_prob = float(np.max(proba))
            co_equal = [c for c in crop_probs if c["probability"] >= top_prob - 0.10]

            results.append({
                "index": i,
                "co_equal_crops": co_equal,
                "status": "success" if top_prob >= CONFIDENCE_THRESHOLD else "low_confidence",
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
        "confidence_threshold": CONFIDENCE_THRESHOLD,
    })


# ── Run app ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("🚀 Starting Flask server...")
    app.run(debug=True, host="0.0.0.0", port=5000)