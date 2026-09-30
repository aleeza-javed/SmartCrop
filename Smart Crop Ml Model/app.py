import os
import sys
import datetime
import math
import numpy as np
import pandas as pd
import joblib
from flask import Flask, request, jsonify
from flask_cors import CORS

# Monitor/alert modules live in the "fertillizer Alerts" folder.
ALERTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fertillizer Alerts")
if ALERTS_DIR not in sys.path:
    sys.path.insert(0, ALERTS_DIR)

from crop_thresholds import (CROP_THRESHOLDS, MONITOR_CONFIG, PPM_TO_KG_HA,
                             available_crops, get_thresholds, get_product,
                             config_for_crop)
from monitoring_engine import (analyze_monitoring, classify_reading,
                                compute_health_score, UnknownCropError,
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

# Nutrients the fertilizer advisor reports on.
FERTILIZER_NUTRIENTS = ("N", "P", "K")

# A client-supplied reading older than this is reported as stale rather than
# rejected: a stale reading is still worth showing, but the UI must not present
# it as live. Overridable for tests / tuning without a code change.
STALE_AFTER_SECONDS = int(os.environ.get("SMARTCROP_STALE_SECONDS", 600))

# Wording used wherever a nutrient reads inside its configured range.
WITHIN_RANGE_ADVICE = "{label} is within the configured range."
NO_READING_ADVICE = "Sensor not reporting"


# ── Probe reading guards ────────────────────────────────────────────────────
# Which readings mean "the probe is dead" depends on the parameter, so the
# rules are keyed by parameter rather than applied blindly. Getting this
# backwards is costly in both directions: a false "sensor not reporting" hides
# a real problem, and a false CRITICAL alert cries wolf.


def _canonical_param(name):
    """Normalise a reading key for the fault-rule lookup.

    Only N, P, K are case-sensitive; every other key is lowercased so 'ph'/'pH'
    and 'EC'/'ec' resolve to the same rule.
    """
    key = str(name)
    return key if key in ("N", "P", "K") else key.lower()


# Parameters where a reading of exactly 0 means the probe is dead rather than
# "measured zero". A soil nutrient or pH concentration of precisely 0 is not a
# real reading. Deliberately EXCLUDES soil_moisture, humidity, temperature and
# EC, all of which have legitimate zero values: 0% soil moisture is bone-dry
# soil and must raise a normal CRITICAL alert, not a sensor fault.
ZERO_FAULT_PARAMS = frozenset({"N", "P", "K", "ph"})

# Parameters where a negative value is a malfunction rather than a
# measurement. Air temperature is explicitly excluded - sub-zero air is normal
# in many climates and must be accepted. EC is included because conductivity
# cannot be negative. Any unlisted parameter defaults to "not negative-fault"
# and is handled by the endpoint's own validation.
NEGATIVE_FAULT_PARAMS = frozenset({
    "N", "P", "K", "ph", "ec", "soil_moisture", "soilmoisturepercent",
    "humidity",
})


def _probe_is_fault(param, value):
    """True when a probe value means 'not reporting' rather than 'measured X'.

    Always a fault: None and non-finite values.
    Zero: a fault only for ZERO_FAULT_PARAMS.
    Negative: a fault only for NEGATIVE_FAULT_PARAMS.
    Garbage (a non-numeric string, a list, a dict): NOT reported here - this is
    a client bug, and the endpoint turns it into a 400 so a broken client is
    never mistaken for a broken sensor.
    """
    if value is None:
        return True
    if isinstance(value, bool):
        return False

    numeric = None
    if isinstance(value, (int, float)):
        numeric = float(value)
    elif isinstance(value, str):
        try:
            numeric = float(value.strip())
        except ValueError:
            return False  # garbage -> let validation return a 400
    else:
        return False  # list/dict -> garbage -> 400

    if not math.isfinite(numeric):
        return True

    key = _canonical_param(param)
    if numeric == 0 and key in ZERO_FAULT_PARAMS:
        return True
    if numeric < 0 and key in NEGATIVE_FAULT_PARAMS:
        return True
    return False


def _parse_probe(raw, parameter):
    """Return ``(value, fault)`` for one probe reading.

    ``fault=True``  -> the probe is not reporting; the caller must not classify.
    ``fault=False`` -> ``value`` is a usable float.

    Raises ValueError for a *malformed request* (garbage that is not a number
    at all), which the endpoints turn into a 400. The split is deliberate:
    "the probe is silent" is a sensor condition to report, "you sent nonsense"
    is a client bug to reject.
    """
    if _probe_is_fault(parameter, raw):
        return None, True
    if isinstance(raw, bool):
        raise ValueError(f"Malformed {parameter} value: {raw!r}")
    try:
        return float(raw), False
    except (TypeError, ValueError):
        raise ValueError(f"Malformed {parameter} value: {raw!r}")


def _parse_client_timestamp(raw):
    """Parse a client-supplied reading timestamp -> aware datetime, or None.

    Accepts ISO 8601 (with or without a trailing Z) and epoch seconds or
    milliseconds.
    """
    if raw is None:
        return None
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        seconds = float(raw)
        if abs(seconds) > 1e11:  # epoch milliseconds
            seconds /= 1000.0
        try:
            return datetime.datetime.fromtimestamp(seconds, tz=datetime.timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    try:
        parsed = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed


def _staleness(raw):
    """Return ``(stale, age_seconds)`` for a client reading timestamp.

    A missing or unparseable timestamp is *not* stale: we simply have nothing
    to compare against, and inventing an age would be dishonest. Never fails.
    """
    parsed = _parse_client_timestamp(raw)
    if parsed is None:
        return False, None
    now = datetime.datetime.now(datetime.timezone.utc)
    age = (now - parsed).total_seconds()
    if age < 0:
        age = 0.0  # clock skew or a reading stamped in the future
    return age > STALE_AFTER_SECONDS, round(age, 1)


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
# Description strings only - this endpoint documents the unit the client
# should send for each feature. It does not affect the model, which is
# unchanged. N/P/K are described in ppm because that is what the SmartCrop
# sensor publishes and what the whole app sends; see the unit-provenance note
# in the /fertilizer docstring before assuming the model's training units
# match.
@app.route("/features", methods=["GET"])
def features():
    return jsonify({
        "features": FEATURES,
        "description": {
            "N": "Nitrogen content in soil (ppm)",
            "P": "Phosphorus content in soil (ppm)",
            "K": "Potassium content in soil (ppm)",
            "temperature": "Temperature in Celsius",
            "humidity": "Relative humidity (%)",
            "ph": "Soil pH value",
            "rainfall": "Annual rainfall (mm)",
        },
    })


# ── Fertilizer advisor ─────────────────────────────────────────────────────
# Rule-based, no ML. Every band, buffer and product class comes from
# crop_thresholds.py via get_thresholds(); severity comes from the same
# classify_reading() the monitoring engine and the notification rules use, so
# this screen cannot disagree with the rest of the app.
#
# `gap` is the distance from the reading to the nearest configured range edge,
# in the sensor's own unit (ppm for N/P/K). For a confirmed deficiency the
# response also carries an ESTIMATED application scale (nutrient_kg_ha /
# product_kg_ha), derived from the PPM_TO_KG_HA rule of thumb in
# crop_thresholds.py. That estimate assumes a conventional depth and bulk
# density that SmartCrop does not measure, so it is advisory scale only - never
# a prescription, and always worded as "estimated". This mirrors the position
# taken in monitoring_engine.build_alerts_and_recommendations.
# UNIT PROVENANCE (read before trusting the numbers)
# ----------------------------------------------------
# N/P/K bands are labelled "ppm" because that is what the SmartCrop sensor
# publishes. But the band *numbers* were derived as mean +/- 1 std of
# Crop_recommendation_extended.csv, a synthetic dataset whose N/P/K columns are
# nominally kg/ha. Relabelling the band as ppm converts nothing - it only makes
# the label match the sensor. Whether the comparison is numerically meaningful
# therefore depends on an assumption nobody has verified: that the sensor's ppm
# scale and the training dataset's units are on the same scale. If they are
# not, every status, gap and estimate below is wrong by that scale factor, and
# the now-consistent labelling will hide the bug rather than reveal it.
# Confirm with one soil test against a known-good sample before relying on this.


@app.route("/fertilizer", methods=["POST"])
def fertilizer():
    """Per-nutrient fertilizer advice for the current N/P/K readings.

    Body: {"crop": str, "N": num, "P": num, "K": num,
           "current": {...optional extra monitored params...},
           "history": [...optional, for persistence...],
           "timestamp": str|num  optional, for the staleness flag}
    """
    data = request.get_json()
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    if "crop" not in data:
        return jsonify({"error": "Missing fields: ['crop']"}), 400

    crop = str(data["crop"]).lower().strip()
    try:
        thresholds = get_thresholds(crop)
    except KeyError as e:
        return jsonify({"error": str(e)}), 400

    config = config_for_crop(crop)
    stale, reading_age_seconds = _staleness(data.get("timestamp"))

    # ── Parse the three nutrient probes ──
    # A silent probe is reported as NO_READING, not as a deficiency. Only
    # genuinely malformed input is a 400.
    readings, faults = {}, []
    for nutrient in FERTILIZER_NUTRIENTS:
        try:
            value, fault = _parse_probe(data.get(nutrient), nutrient)
        except ValueError as e:
            return jsonify({"error": str(e)}), 400
        if fault:
            faults.append(nutrient)
        else:
            readings[nutrient] = value

    monitor_current = dict(readings)

    # ── Optional extra monitored parameters (for persistence) ──
    # /monitor needs the crop's full configured parameter set before it can
    # judge whether a condition persisted, so the client may pass the rest of
    # the reading here. Both shapes are accepted: nested under `current` (the
    # shape /monitor uses) or flat alongside N/P/K (the shape this endpoint has
    # always used). `current` wins on conflict. Without these, every nutrient
    # falls back to confidence="instant".
    extras = data.get("current")
    sources = [extras, data] if isinstance(extras, dict) else [data]
    for param in thresholds:
        if param in monitor_current:
            continue
        for source in sources:
            if param not in source:
                continue
            try:
                value, fault = _parse_probe(source[param], param)
            except ValueError as e:
                return jsonify({"error": str(e)}), 400
            if not fault:
                monitor_current[param] = value
            break

    history = data.get("history")
    history = history if isinstance(history, list) else []
    monitor_results = _persistence_results(crop, monitor_current, history)

    # ── Per-nutrient advice ──
    nutrients = {}
    health_params = {}
    for nutrient in FERTILIZER_NUTRIENTS:
        cfg = thresholds[nutrient]
        label = cfg.get("label", nutrient)
        unit = cfg.get("unit", "")
        band = [cfg["min"], cfg["max"]]
        buffer_ = float(cfg.get("buffer", 0))
        base = {
            "parameter": nutrient,
            "label": label,
            "unit": unit,
            "band": band,
            "buffer": buffer_,
        }

        if nutrient in faults:
            # Not classified at all: `required` is null because we genuinely
            # do not know, which is different from "not required". Every field
            # is present and null so the response shape is uniform.
            nutrients[nutrient] = dict(
                base, current=None, status="NO_READING", required=None,
                direction=None, gap=None, product=None,
                nutrient_kg_ha=None, product_kg_ha=None,
                advice=NO_READING_ADVICE, confidence="instant",
                persistence="unavailable",
            )
            continue

        value = readings[nutrient]
        status = classify_reading(value, cfg)
        required = status != "NORMAL"
        direction = "deficient" if value < band[0] else ("excess" if value > band[1] else None)

        # Distance to the nearest configured range edge. For a NORMAL reading
        # this is 0. The buffer is a severity escalation width and is never
        # subtracted from this number.
        if direction == "deficient":
            gap = round(band[0] - value, 2)
        elif direction == "excess":
            gap = round(value - band[1], 2)
        else:
            gap = 0.0

        # A product class is named only for a confirmed deficiency. `amount`
        # fields are the estimated scale of the top-up, and are null for every
        # other status: there is nothing to estimate for a nutrient that is
        # already in range, over-supplied, or not reporting.
        product = None
        nutrient_kg_ha = None
        product_kg_ha = None

        if direction == "deficient":
            catalog = get_product(nutrient) or {}
            fraction = catalog.get("nutrient_fraction")
            product = {
                "fertilizer": cfg.get("fertilizer"),
                "name": catalog.get("name"),
                "role": catalog.get("role"),
                "nutrient_fraction": fraction,
            }
            # gap is in the sensor's unit (ppm); convert once, to give a sense
            # of application scale. Always surfaced as an estimate.
            nutrient_kg_ha = round(gap * PPM_TO_KG_HA, 1)
            if fraction:
                product_kg_ha = round(nutrient_kg_ha / fraction, 1)

        if direction == "deficient":
            if product_kg_ha is not None:
                advice = (
                    f"{label} is {gap} {unit} below the configured range. "
                    f"Estimated about {product_kg_ha} kg/ha of "
                    f"{product['name']} needed to reach the range."
                )
            else:
                advice = (
                    f"{label} is {gap} {unit} below the configured range. "
                    f"Consider a {cfg.get('fertilizer', '')} fertilizer "
                    f"(e.g. {product['name']}) after field assessment."
                )
        elif direction == "excess":
            advice = (
                f"{label} is {gap} {unit} above the configured range. "
                f"Hold off on applying more {nutrient}; no product is recommended."
            )
        else:
            advice = WITHIN_RANGE_ADVICE.format(label=label)

        pr = monitor_results.get(nutrient)
        nutrients[nutrient] = dict(
            base, current=round(value, 2), status=status, required=required,
            direction=direction, gap=gap, product=product, advice=advice,
            nutrient_kg_ha=nutrient_kg_ha, product_kg_ha=product_kg_ha,
            confidence="persistent" if (pr and pr["persistent"]) else "instant",
            persistence=pr["persistence"] if pr else "unavailable",
        )

        health_params[nutrient] = {
            "status": status,
            "current": value,
            "trend": pr["trend"] if pr else "insufficient_data",
            "persistent": bool(pr["persistent"]) if pr else False,
            "recommended_range": band,
        }

    # ── Health + summary ──
    # Nutrients that are not reporting are excluded from the score inputs, so
    # a dead probe can neither raise nor mask a score. A score built from fewer
    # than all three nutrients is flagged partial rather than presented as
    # comparable to a full evaluation.
    health_score = compute_health_score(health_params, config) if health_params else 0
    partial = len(health_params) < len(FERTILIZER_NUTRIENTS)
    statuses = [r["status"] for r in health_params.values()]
    if not statuses:
        health_status = "NO_READING"
    elif "CRITICAL" in statuses:
        health_status = "CRITICAL"
    elif "WARNING" in statuses:
        health_status = "WARNING"
    else:
        health_status = "NORMAL"

    note = config["health_score_note"]
    # Ordered N, P, K rather than alphabetically - the UI renders these lists.
    evaluated = [n for n in FERTILIZER_NUTRIENTS if n in health_params]
    if partial:
        note += (
            f" Partial: scored on {evaluated or 'no nutrients'} only, "
            f"so it is not comparable to a full evaluation."
        )

    required_count = sum(1 for r in nutrients.values() if r["required"] is True)

    return jsonify({
        "crop": crop,
        "source": "crop_thresholds",
        "stale": stale,
        "reading_age_seconds": reading_age_seconds,
        "stale_after_seconds": STALE_AFTER_SECONDS,
        "health": {
            "score": health_score,
            "score_out_of": config["scoring"]["base"],
            "status": health_status,
            "partial": partial,
            "evaluated": evaluated,
            "label": config["health_score_label"],
            "note": note,
        },
        "summary": {
            "required_count": required_count,
            "within_range": [n for n in FERTILIZER_NUTRIENTS
                             if nutrients[n]["status"] == "NORMAL"],
            "no_reading": [n for n in FERTILIZER_NUTRIENTS
                           if nutrients[n]["status"] == "NO_READING"],
        },
        "nutrients": nutrients,
    })


def _persistence_results(crop, current, history):
    """Run the monitoring engine to decide instantaneous vs persistent advice.

    Returns the engine's ``parameter_results`` keyed by parameter, or an empty
    dict when persistence cannot be judged at all - which happens when the
    client did not send the crop's full configured parameter set. Callers treat
    an empty result as "instant", the conservative end of the two-tier design:
    act on the current reading, but do not claim history backs it up.
    """
    try:
        thresholds = get_thresholds(crop)
    except KeyError:
        return {}
    if not set(thresholds).issubset(current):
        return {}
    try:
        result = analyze_monitoring(crop, current, history)
    except Exception:
        return {}
    return result.get("parameter_results", {})


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

    # Validate the crop up front so a bad crop is always a 400, even when a
    # probe is also dead.
    try:
        get_thresholds(crop)
    except KeyError as e:
        return jsonify({"error": str(e)}), 400

    current = data["current"]
    if not isinstance(current, dict):
        return jsonify({"error": "Field 'current' must be an object"}), 400

    # ── Per-probe fault guard ──
    # Which readings count as a dead probe is parameter-specific: see
    # ZERO_FAULT_PARAMS / NEGATIVE_FAULT_PARAMS. A dead probe means the field
    # is unmeasured, which is a different condition from "measured and wrong",
    # so it is reported as its own status and generates no alerts. Note this
    # deliberately does NOT catch 0% soil moisture or sub-zero air
    # temperature, which are real readings and flow through to normal
    # monitoring.
    sensor_faults = sorted(p for p, v in current.items() if _probe_is_fault(p, v))
    if sensor_faults:
        return jsonify({
            "crop": str(crop).lower(),
            "overall_status": "SENSOR_FAULT",
            "sensor_faults": sensor_faults,
            "alerts": [],
            "recommendations": [],
            "message": (
                "One or more probes are not reporting, so no alert was raised. "
                "Check the sensor wiring and power before trusting this reading."
            ),
        }), 200

    history = data.get("history", [])

    try:
        result = analyze_monitoring(crop, current,
                                    history if isinstance(history, list) else None)
    except (UnknownCropError, KeyError) as e:
        return jsonify({"error": str(e)}), 400
    except InvalidReadingError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": f"Monitoring failed: {e}"}), 400

    result["sensor_faults"] = []
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