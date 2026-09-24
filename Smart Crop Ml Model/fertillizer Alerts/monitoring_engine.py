"""
SmartCrop — Monitoring Engine

A transparent, rule-based, temporal monitoring engine that sits on top of the
existing ML crop recommendation system.

Division of responsibility
--------------------------
* Random Forest (existing, unchanged):
      "Which crop is suitable for these field conditions?"
* This monitoring engine:
      "Is the selected crop currently experiencing abnormal conditions?"

The engine accepts:
    crop, current sensor readings, historical sensor readings
and returns a structured monitoring result (per-parameter status, persistence
analysis, trend, health score, alerts and advisory recommendations).

Key design points
-----------------
* Status classification (NORMAL / WARNING / CRITICAL) is fully configurable in
  crop_thresholds.py — nothing is hardcoded here.
* Alerts are NOT produced from a single noisy reading. A parameter only
  generates an advisory when the abnormal condition has PERSISTED across the
  configured analysis window (percent of abnormal readings over a threshold).
* Trend is a simple statistical slope over recent history (no ML).
* The engine is source-agnostic: it does not care whether readings came from
  ESP32 -> Firebase, a simulator, or manual entry. This keeps live IoT
  integration a later, separate concern.
"""

from __future__ import annotations

import datetime as _dt
from typing import List, Optional

import numpy as np

from crop_thresholds import get_thresholds, config_for_crop


class UnknownCropError(ValueError):
    """Raised when a crop has no monitoring thresholds configured."""


class InvalidReadingError(ValueError):
    """Raised when a sensor value is missing or not numeric."""


# ── Small helpers ────────────────────────────────────────────────────────


def _safe_float(value):
    try:
        out = float(value)
    except (TypeError, ValueError):
        raise InvalidReadingError(f"Non-numeric sensor value: {value!r}")
    if not np.isfinite(out):
        raise InvalidReadingError(f"Non-finite sensor value: {value!r}")
    return out


def _parse_timestamp(ts):
    """Parse a timestamp string to datetime; return None if unparseable."""
    if ts is None:
        return None
    try:
        return _dt.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def _window_history(history, config):
    """Filter history entries to the configured analysis window.

    Windowing is applied only when at least one entry has a parseable
    timestamp; otherwise all readings are used (manual/simulated data).
    Returns (entries, start, end, used_timestamps).
    """
    if not history:
        return [], None, None, None

    dates = [_parse_timestamp(h.get("timestamp")) for h in history]
    valid = [d for d in dates if d is not None]
    if not valid:
        return history, None, None, None

    end = max(valid)
    start = end - _dt.timedelta(hours=config["window_hours"])
    kept, kept_dates = [], []
    for i, h in enumerate(history):
        d = dates[i]
        if d is not None and d < start:
            continue  # older than the analysis window
        kept.append(h)
        kept_dates.append(d)
    return kept, start, end, kept_dates


def _history_values(entries, param):
    """Collect numeric values for `param` across history entries."""
    values = []
    for h in entries:
        if param in h and h[param] is not None:
            try:
                values.append(_safe_float(h[param]))
            except InvalidReadingError:
                continue  # skip unparseable readings for this parameter
    return values


# ── Status classification ────────────────────────────────────────────────


def classify_reading(value, threshold_cfg):
    """Classify a single reading: NORMAL / WARNING / CRITICAL.

    NORMAL   : within [min, max]
    WARNING  : outside [min, max] but within `buffer` of it
    CRITICAL : farther than `buffer` from the range
    """
    lo, hi = threshold_cfg["min"], threshold_cfg["max"]
    buf = float(threshold_cfg.get("buffer", 0))
    if lo <= value <= hi:
        return "NORMAL"
    if (lo - buf) <= value <= (hi + buf):
        return "WARNING"
    return "CRITICAL"


def classify_persistence(abnormal_pct, n_readings, config):
    """Classify persistence from the % of abnormal readings.

    Returns (persistence_level, persistent_bool)
      persistence_level:
        "insufficient_history"   fewer readings than required
        "monitor"                < abnorm_monitor_ceiling% abnormal
        "warning"                abnorm_monitor_ceiling% .. warning_ceiling%
        "persistent"             > abnormal_persistent_floor% abnormal
    """
    if n_readings < config["min_readings_for_persistence"]:
        return "insufficient_history", False
    if abnormal_pct is None:
        return "insufficient_history", False
    if abnormal_pct > config["abnormal_persistent_floor"]:
        return "persistent", True
    if abnormal_pct >= config["abnormal_monitor_ceiling"]:
        return "warning", False
    return "monitor", False


# ── Trend analysis ───────────────────────────────────────────────────────


def compute_trend(values, config, range_width):
    """Return a simple trend label for a sequence of values.

    Uses a least-squares slope over the readings. If the total change across
    the window is within `trend_sensitivity` of the recommended range width,
    the trend is "stable"; otherwise "increasing"/"decreasing".
    """
    if len(values) < 2:
        return "insufficient_data"
    slope = float(np.polyfit(np.arange(len(values)), values, 1)[0])
    total_change = slope * (len(values) - 1)
    if range_width <= 0:
        range_width = 1.0
    if abs(total_change) <= config["trend_sensitivity"] * range_width:
        return "stable"
    return "increasing" if slope > 0 else "decreasing"


# ── Per-parameter analysis ───────────────────────────────────────────────


def analyze_parameter(param, current_value, history_values, threshold_cfg, config):
    """Analyze one parameter: status, persistence, trend."""
    lo = threshold_cfg["min"]
    hi = threshold_cfg["max"]
    range_width = hi - lo

    status = classify_reading(current_value, threshold_cfg)

    n_total = len(history_values)
    n_abnormal = sum(1 for v in history_values if not (lo <= v <= hi))
    abnormal_pct = round(n_abnormal / n_total * 100, 1) if n_total else None

    persistence_level, persistent = classify_persistence(
        abnormal_pct, n_total, config
    )
    trend = compute_trend(history_values, config, range_width)

    note = None
    if persistence_level == "insufficient_history":
        note = (
            f"Only {n_total} historical reading(s) analyzed; at least "
            f"{config['min_readings_for_persistence']} are required to "
            f"declare a persistent condition."
        )

    return {
        "status": status,
        "current": round(float(current_value), 3),
        "recommended_range": [lo, hi],
        "unit": threshold_cfg.get("unit"),
        "abnormal_count": n_abnormal,
        "total_readings": n_total,
        "abnormal_percentage": abnormal_pct,
        "persistence": persistence_level,
        "persistent": persistent,
        "trend": trend,
        "note": note,
    }


# ── Health score ─────────────────────────────────────────────────────────


def compute_health_score(parameter_results, config):
    """SmartCrop Monitoring Health Score (prototype).

    100 baseline; deducts for abnormal readings, persistent issues and
    aggravating trends. Clamped to [0, 100]. Transparent, not validated.
    """
    scoring = config["scoring"]
    points = 0
    for r in parameter_results.values():
        if r["status"] == "WARNING":
            points += scoring["warning"]
        elif r["status"] == "CRITICAL":
            points += scoring["critical"]
        if r["persistent"]:
            points += scoring["persistent"]
        below = r["current"] < r["recommended_range"][0]
        above = r["current"] > r["recommended_range"][1]
        if (below and r["trend"] == "decreasing") or (
            above and r["trend"] == "increasing"
        ):
            points += scoring["aggravating_trend"]
    return max(0, scoring["base"] - points)


def compute_overall_status(parameter_results):
    """Combine per-parameter monitoring results into one overall status.

    A non-persistent abnormal reading is at most WARNING (monitor).
    A PERSISTENT abnormal condition escalates: warning -> WARNING,
    critical -> CRITICAL.
    """
    ordered = ["NORMAL", "WARNING", "CRITICAL"]

    def level(s):
        return ordered.index(s)

    overall = "NORMAL"
    for r in parameter_results.values():
        inst = r["status"]
        if inst == "NORMAL":
            continue
        candidate = inst if r["persistent"] else "WARNING"
        if level(candidate) > level(overall):
            overall = candidate
    return overall


# ── Alerts & recommendations ─────────────────────────────────────────────


def build_alerts_and_recommendations(crop, parameter_results, thresholds):
    """Build advisory alerts for persistent, non-resolved abnormal conditions.

    Advisories are decision-support language only. No scientifically precise
    dosages are proposed (the project contains no validated dosage model).
    """
    alerts = []
    recommendations = []

    for param, r in parameter_results.items():
        if not (r["persistent"] and r["status"] != "NORMAL"):
            continue
        cfg = thresholds[param]
        label = cfg.get("label", param)
        lo, hi = r["recommended_range"]
        below = r["current"] < lo
        above = r["current"] > hi

        direction = {"decreasing": "downward", "increasing": "upward"}.get(
            r["trend"]
        )
        trend_note = (
            f" It is trending {direction}."
            if direction
            else ""
        )

        if below:
            if param in ("N", "P", "K"):
                message = (
                    f"Persistent {label.lower()} deficiency detected for {crop}. "
                    f"Current {param} is below the configured range. "
                    f"Inspect soil/crop condition and consider an appropriate "
                    f"{cfg.get('fertilizer', '')} fertilizer after field/soil "
                    f"assessment.{trend_note}"
                )
                alert_type = "deficiency"
            else:
                message = (
                    f"Persistent {label.lower()} deficit detected for {crop}. "
                    f"Current {param} is below the configured range. Inspect "
                    f"field conditions; for soil moisture, review water "
                    f"management / irrigation after field assessment.{trend_note}"
                )
                alert_type = "deficiency"
        elif above:
            if param in ("N", "P", "K"):
                message = (
                    f"{label} level is persistently above the configured "
                    f"range for {crop}. Avoid unnecessary additional {param} "
                    f"application and inspect field conditions.{trend_note}"
                )
                alert_type = "excess"
            else:
                message = (
                    f"{label} is persistently above the configured range for "
                    f"{crop}. Inspect field conditions; for soil moisture, "
                    f"review drainage / water management.{trend_note}"
                )
                alert_type = "excess"
        else:
            continue

        alerts.append(
            {
                "severity": r["status"],
                "parameter": param,
                "type": alert_type,
                "message": message,
            }
        )
        recommendations.append(message)

    return alerts, recommendations


# ── Public entry point ───────────────────────────────────────────────────


def analyze_monitoring(crop, current, history=None, config=None):
    """Analyze a crop's current and historical sensor readings.

    Args:
        crop: crop name string (case-insensitive).
        current: dict of current sensor readings. Must include every
            configured parameter for the crop.
        history: optional list of dicts (timestamp + readings). Readings
            older than the configured window are ignored when timestamps are
            available.
        config: optional dict overriding MONITOR_CONFIG defaults.

    Returns:
        A structured monitoring result dict (see doc comment / README).
    """
    thresholds = get_thresholds(crop)  # raises KeyError for unknown crops
    cfg = config_for_crop(crop, config)

    if not isinstance(current, dict) or not current:
        raise InvalidReadingError("'current' must be a non-empty dict of readings")

    missing = [p for p in thresholds if p not in current]
    if missing:
        raise InvalidReadingError(
            f"Missing required monitoring parameters: {missing}. "
            f"Required: {list(thresholds.keys())}"
        )

    current_float = {}
    for p, v in current.items():
        if p in thresholds:
            current_float[p] = _safe_float(v)

    history = history or []
    entries, start, end, _ = _window_history(history, cfg)

    parameter_results = {}
    for param, threshold_cfg in thresholds.items():
        hist_vals = _history_values(entries, param)
        parameter_results[param] = analyze_parameter(
            param, current_float[param], hist_vals, threshold_cfg, cfg
        )

    overall_status = compute_overall_status(parameter_results)
    health_score = compute_health_score(parameter_results, cfg)
    alerts, recommendations = build_alerts_and_recommendations(
        crop, parameter_results, thresholds
    )

    persistent_issues = [
        p for p, r in parameter_results.items() if r["persistent"]
    ]

    window_note = (
        f"History filtered to the last {cfg['window_hours']}h when timestamps "
        "are available. Manual/simulated readings without timestamps are all "
        "included."
    )
    if start is None and history:
        window_note = (
            "No parseable timestamps in history; all historical readings "
            "were analyzed within the configured window concept."
        )

    return {
        "crop": str(crop).lower(),
        "overall_status": overall_status,
        "health_score": health_score,
        "health_score_label": cfg["health_score_label"],
        "health_score_note": cfg["health_score_note"],
        "analysis_window": {
            "window_hours": cfg["window_hours"],
            "history_readings": len(history),
            "readings_analyzed": {
                p: r["total_readings"] for p, r in parameter_results.items()
            },
            "window_start": start.isoformat() if start else None,
            "window_end": end.isoformat() if end else None,
            "note": window_note,
        },
        "parameter_results": parameter_results,
        "persistent_issues": persistent_issues,
        "alerts": alerts,
        "recommendations": recommendations,
    }