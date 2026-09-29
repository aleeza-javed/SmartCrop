import os
import sys
import datetime
import numpy as np
import pandas as pd
import joblib
from flask import Flask, request, jsonify
from flask_cors import CORS

# Monitor/alert modules live in the "fertillizer Alerts" folder.
ALERTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fertillizer Alerts")
if ALERTS_DIR not in sys.path:
    sys.path.insert(0, ALERTS_DIR)

from crop_thresholds import CROP_THRESHOLDS, MONITOR_CONFIG, available_crops, get_thresholds, config_for_crop
from monitoring_engine import (analyze_monitoring, classify_reading, UnknownCropError,
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


# ── Report Endpoints ────────────────────────────────

@app.route("/reports/water", methods=["POST"])
def reports_water():
    """Water/Moisture monitoring report for the active crop.

    Body: {"crop": str, "history": [{...sensor readings...}]}
    Uses soil_moisture data from historical readings and crop-specific thresholds.
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    crop = data.get("crop", "").lower().strip()
    if not crop or crop not in CROP_THRESHOLDS:
        return jsonify({"error": "Valid crop required"}), 400

    history = data.get("history", [])
    if not history:
        return jsonify({"crop": crop, "status": "insufficient_data",
            "message": "No historical readings provided."}), 200

    thresholds = get_thresholds(crop)
    soil_moisture_cfg = thresholds.get("soil_moisture")
    if not soil_moisture_cfg:
        return jsonify({"error": "No soil_moisture threshold configured"}), 400

    lo = soil_moisture_cfg["min"]
    hi = soil_moisture_cfg["max"]
    buf = soil_moisture_cfg.get("buffer", 10)

    moisture_values = []
    for r in history:
        val = r.get('soilMoisturePercent') or r.get('soil_moisture') or r.get('soil_moisture_percent')
        if val is not None:
            try:
                moisture_values.append(float(val))
            except (ValueError, TypeError):
                pass

    if not moisture_values:
        return jsonify({"crop": crop, "status": "insufficient_data",
            "message": "No soil moisture values found in history."}), 200

    moisture_values.sort()
    current_moisture = moisture_values[-1]

    if lo <= current_moisture <= hi:
        current_status = "NORMAL"
    elif (lo - buf) <= current_moisture <= (hi + buf):
        current_status = "WARNING"
    else:
        current_status = "CRITICAL"

    if len(moisture_values) >= 2:
        slope = float(np.polyfit(np.arange(len(moisture_values)), moisture_values, 1)[0])
        if abs(slope) < 0.1:
            trend = "stable"
        elif slope > 0:
            trend = "increasing"
        else:
            trend = "decreasing"
    else:
        trend = "insufficient_data"

    avg_moisture = round(sum(moisture_values) / len(moisture_values), 2)
    warnings = []
    if current_status == "CRITICAL":
        if current_moisture < lo - buf:
            warnings.append({"type": "low_moisture", "severity": "CRITICAL",
                "message": f"Soil moisture is critically low ({current_moisture:.1f}%). Recommended range: {lo}-{hi}%."})
        else:
            warnings.append({"type": "high_moisture", "severity": "CRITICAL",
                "message": f"Soil moisture is critically high ({current_moisture:.1f}%). Recommended range: {lo}-{hi}%."})
    elif current_status == "WARNING":
        warnings.append({"type": "moisture_out_of_range", "severity": "WARNING",
            "message": f"Soil moisture ({current_moisture:.1f}%) is outside optimal range ({lo}-{hi}%)."})

    normal_count = sum(1 for v in moisture_values if lo <= v <= hi)
    warning_count = sum(1 for v in moisture_values if (lo - buf) <= v <= (hi + buf) and not (lo <= v <= hi))
    critical_count = sum(1 for v in moisture_values if v < (lo - buf) or v > (hi + buf))

    return jsonify({
        "crop": crop,
        "parameter": "soil_moisture",
        "status": current_status,
        "current_value": round(current_moisture, 2),
        "recommended_range": [lo, hi],
        "unit": soil_moisture_cfg.get("unit", "%"),
        "statistics": {"average": avg_moisture, "minimum": round(min(moisture_values), 2),
            "maximum": round(max(moisture_values), 2), "total_readings": len(moisture_values)},
        "status_breakdown": {"normal": normal_count, "warning": warning_count, "critical": critical_count},
        "trend": trend,
        "warnings": warnings,
        "note": "Soil moisture percentage is the only measurable water-related metric. Actual water volume requires a flow meter sensor not present in SmartCrop."
    })


@app.route("/reports/nutrients", methods=["POST"])
def reports_nutrients():
    """Soil nutrient health report for the active crop."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400
    crop = data.get("crop", "").lower().strip()
    if not crop or crop not in CROP_THRESHOLDS:
        return jsonify({"error": "Valid crop required"}), 400
    history = data.get("history", [])
    if not history:
        return jsonify({"crop": crop, "status": "insufficient_data", "message": "No historical readings provided."}), 200

    thresholds = get_thresholds(crop)
    config = config_for_crop(crop)
    latest = history[-1]

    current = {}
    for param in ["N", "P", "K"]:
        val = latest.get(param) or latest.get(param.lower())
        if val is not None:
            current[param] = float(val)

    nutrient_results = {}
    for param in ["N", "P", "K"]:
        if param not in current:
            nutrient_results[param] = {"status": "missing", "message": f"No {param} data"}
            continue
        cfg = thresholds[param]
        value = current[param]
        status = classify_reading(value, cfg)
        nutrient_results[param] = {
            "status": status, "current": round(value, 2),
            "optimal_range": [cfg["min"], cfg["max"]],
            "unit": cfg.get("unit", ""), "label": cfg.get("label", param),
            "message": f"{param} level is {'within' if status == 'NORMAL' else 'outside'} the optimal range."
        }

    ph_val = latest.get('pH') or latest.get('ph')
    if ph_val is not None:
        ph_cfg = thresholds["ph"]
        ph_status = classify_reading(float(ph_val), ph_cfg)
        nutrient_results["pH"] = {"status": ph_status, "current": round(float(ph_val), 2), "optimal_range": [ph_cfg["min"], ph_cfg["max"]], "unit": ph_cfg.get("unit", ""), "label": ph_cfg.get("label", "pH")}

    ec_val = latest.get('EC') or latest.get('ec')
    if ec_val is not None:
        nutrient_results["EC"] = {"status": "info", "current": round(float(ec_val), 2), "message": "Electrical conductivity recorded."}

    statuses = [r["status"] for r in nutrient_results.values() if "status" in r]
    if "CRITICAL" in statuses: overall = "CRITICAL"
    elif "WARNING" in statuses: overall = "WARNING"
    elif all(s == "NORMAL" for s in statuses): overall = "NORMAL"
    else: overall = "INSUFFICIENT_DATA"

    scoring = config["scoring"]
    health_score = scoring["base"]
    for param, r in nutrient_results.items():
        if r["status"] == "WARNING": health_score -= scoring["warning"]
        elif r["status"] == "CRITICAL": health_score -= scoring["critical"]
    health_score = max(0, health_score)

    return jsonify({"crop": crop, "status": overall, "health_score": health_score, "nutrients": nutrient_results, "latest_reading_timestamp": latest.get('timestamp')})


@app.route("/reports/monthly-health", methods=["POST"])
def reports_monthly_health():
    """Monthly crop health report aggregating historical sensor data."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400
    crop = data.get("crop", "").lower().strip()
    if not crop or crop not in CROP_THRESHOLDS:
        return jsonify({"error": "Valid crop required"}), 400
    history = data.get("history", [])
    if not history:
        return jsonify({"crop": crop, "months": [], "message": "No historical readings provided."}), 200

    thresholds = get_thresholds(crop)
    config = config_for_crop(crop)

    monthly_data = {}
    for r in history:
        ts = r.get('timestamp', '')
        try:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            month_key = f"{dt.year}-{dt.month:02d}"
        except Exception:
            date_key = r.get('dateKey', '')
            if date_key:
                parts = date_key.split('-')
                if len(parts) >= 2:
                    month_key = f"{parts[0]}-{parts[1]}"
                else:
                    continue
            else:
                continue
        if month_key not in monthly_data:
            monthly_data[month_key] = []
        monthly_data[month_key].append(r)

    months = []
    for month_key in sorted(monthly_data.keys()):
        month_readings = monthly_data[month_key]

        avg_data = {}
        param_counts = {}
        for r in month_readings:
            for key in ["N", "P", "K", "pH", "temperature", "humidity", "soilMoisturePercent", "soilTemp", "EC", "RainPercent"]:
                val = r.get(key)
                if val is not None:
                    if key not in avg_data:
                        avg_data[key] = 0
                        param_counts[key] = 0
                    avg_data[key] += float(val)
                    param_counts[key] += 1
        for key in avg_data:
            avg_data[key] = round(avg_data[key] / param_counts[key], 2)

        alert_count = 0
        deficient_count = 0
        excess_count = 0
        for r in month_readings:
            for param in ["N", "P", "K", "pH", "soilMoisturePercent"]:
                cfg = thresholds.get(param)
                if not cfg:
                    continue
                val = r.get(param)
                if val is None:
                    continue
                try:
                    v = float(val)
                    status = classify_reading(v, cfg)
                    if status in ("CRITICAL", "WARNING"):
                        alert_count += 1
                        if v < cfg["min"]:
                            deficient_count += 1
                        else:
                            excess_count += 1
                except (ValueError, TypeError):
                    continue

        try:
            current = {}
            for param in thresholds:
                val = month_readings[-1].get(param)
                if val is not None:
                    current[param] = float(val)
            if len(current) >= 3:
                monitor_result = analyze_monitoring(crop, current, month_readings if len(month_readings) > 1 else None, config)
                health_score = monitor_result["health_score"]
                overall_status = monitor_result["overall_status"]
                alerts = monitor_result.get("alerts", [])
            else:
                health_score = 0
                overall_status = "INSUFFICIENT_DATA"
                alerts = []
        except Exception:
            health_score = 0
            overall_status = "INSUFFICIENT_DATA"
            alerts = []

        months.append({
            "month": month_key, "readings_count": len(month_readings),
            "averages": avg_data, "health_score": health_score,
            "overall_status": overall_status, "alert_count": alert_count,
            "deficient_count": deficient_count, "excess_count": excess_count,
            "alerts": alerts[:5],
        })

    return jsonify({"crop": crop, "months": months, "total_readings": len(history)})


@app.route("/reports/soil-health", methods=["POST"])
def reports_soil_health():
    """Soil Health Index based on actual soil measurements."""
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400
    crop = data.get("crop", "").lower().strip()
    if not crop or crop not in CROP_THRESHOLDS:
        return jsonify({"error": "Valid crop required"}), 400
    history = data.get("history", [])
    if not history:
        return jsonify({"crop": crop, "status": "insufficient_data", "message": "No historical readings provided."}), 200

    thresholds = get_thresholds(crop)
    config = config_for_crop(crop)
    latest = history[-1]

    soil_params = ["N", "P", "K", "pH", "soilMoisturePercent", "soilTemp"]
    if latest.get('EC') is not None or latest.get('ec') is not None:
        soil_params.append("EC")

    component_scores = {}
    total_score = 0
    max_possible = 0
    warnings = []

    for param in soil_params:
        cfg = thresholds.get(param)
        if not cfg:
            component_scores[param] = {"score": 0, "status": "no_threshold", "message": f"No threshold for {param}."}
            continue
        val = latest.get(param)
        if val is None:
            component_scores[param] = {"score": 0, "status": "missing", "message": f"No {param} data."}
            continue
        try:
            v = float(val)
        except (ValueError, TypeError):
            component_scores[param] = {"score": 0, "status": "invalid", "message": f"{param} is not numeric."}
            continue
        status = classify_reading(v, cfg)
        if status == "NORMAL":
            score = 100
        elif status == "WARNING":
            score = 70
            warnings.append({"parameter": param, "label": cfg.get("label", param), "severity": "WARNING", "value": v, "message": f"{cfg.get('label', param)} outside optimal range."})
        else:
            score = 30
            warnings.append({"parameter": param, "label": cfg.get("label", param), "severity": "CRITICAL", "value": v, "message": f"{cfg.get('label', param)} critically outside optimal range."})
        component_scores[param] = {"score": score, "status": status, "value": v, "optimal_range": [cfg["min"], cfg["max"]], "unit": cfg.get("unit", ""), "label": cfg.get("label", param)}
        total_score += score
        max_possible += 100

    soil_health_index = round((total_score / max_possible), 2) if max_possible > 0 else 0
    statuses = [cs["status"] for cs in component_scores.values() if cs["status"] in ("NORMAL", "WARNING", "CRITICAL")]
    if "CRITICAL" in statuses: overall_status = "CRITICAL"
    elif "WARNING" in statuses: overall_status = "WARNING"
    elif all(s == "NORMAL" for s in statuses): overall_status = "NORMAL"
    elif statuses: overall_status = "INSUFFICIENT_DATA"
    else: overall_status = "NO_DATA"

    return jsonify({"crop": crop, "soil_health_index": soil_health_index, "overall_status": overall_status, "score_out_of": 100, "components": component_scores, "warnings": warnings, "latest_reading_timestamp": latest.get('timestamp')})

# ── Run app ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("Starting Flask server...")
    app.run(debug=True, host="0.0.0.0",
            port=int(os.environ.get("SMARTCROP_PORT", 5000)))