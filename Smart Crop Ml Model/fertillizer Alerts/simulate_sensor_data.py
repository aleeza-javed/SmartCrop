"""
SmartCrop — Manual/Simulated Sensor Data Generator

The monitoring engine must be testable WITHOUT live ESP32/Firebase hardware.
This script generates realistic (simulated) sensor time-series for a set of
scenarios and runs them through the monitoring engine locally.

Usage
-----
  python "fertillizer Alerts/simulate_sensor_data.py"                 # run all 8 scenarios via the engine
  python "fertillizer Alerts/simulate_sensor_data.py" --scenario 3    # print the /monitor JSON payload (for curl)
  python "fertillizer Alerts/simulate_sensor_data.py" --json 3        # same as --scenario, JSON payload only

Scenario expectations
---------------------
  1 healthy crop                       -> NORMAL, no alerts
  2 temporary abnormal reading         -> WARNING or MONITOR, no fertilizer alert
  3 persistent nitrogen deficiency     -> persistent N deficiency advisory
  4 persistent phosphorus deficiency   -> persistent P deficiency advisory
  5 persistent potassium deficiency    -> persistent K deficiency advisory
  6 excess nutrient                    -> persistent excess advisory
  7 sensor noise                       -> no false persistent alerts
  8 multiple simultaneous issues       -> multiple persistent issues
"""

from __future__ import annotations

import argparse
import datetime as dt
import json

import numpy as np

from crop_thresholds import get_thresholds, MONITOR_CONFIG
from monitoring_engine import analyze_monitoring

HOURS_BACK = MONITOR_CONFIG["window_hours"]
SAMPLES = 24  # hourly-ish readings across the window
SEED = 7


def _rng():
    return np.random.default_rng(SEED)


def _baselines(crop):
    """center value + healthy in-range wobble per parameter."""
    thresholds = get_thresholds(crop)
    base = {p: (c["min"] + c["max"]) / 2.0 for p, c in thresholds.items()}
    return thresholds, base


def _healthy_value(param, cfg, rng):
    lo, hi = cfg["min"], cfg["max"]
    center = (lo + hi) / 2.0
    span = hi - lo
    return round(center + rng.normal(0, 0.15 * span), 2)


def _linspace_series(start, stop, n=SAMPLES):
    return [round(x, 2) for x in np.linspace(start, stop, n)]


def _timestamps(n=SAMPLES, hours=HOURS_BACK):
    end = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0)
    step = hours / (n - 1) if n > 1 else hours
    return [end - dt.timedelta(hours=hours - i * step) for i in range(n)]


def _build(crop, target_values=None, current_override=None):
    """Build (crop, current, history) for a scenario.

    target_values: dict param -> list/ndarray of SAMPLES values.
    All other parameters are kept healthy/in-range.
    """
    thresholds, _ = _baselines(crop)
    rng = _rng()
    timestamps = _timestamps()

    history = []
    latest = {}
    for i in range(SAMPLES):
        entry = {}
        for p, cfg in thresholds.items():
            if target_values and p in target_values:
                val = float(target_values[p][i])
            else:
                val = _healthy_value(p, cfg, rng)
            entry[p] = round(val, 2)
        entry["timestamp"] = timestamps[i].isoformat()
        history.append(entry)
        latest = entry

    current = dict(latest)
    if current_override:
        for k, v in current_override.items():
            current[k] = v

    return crop, current, history


# ── Scenarios ────────────────────────────────────────────────────────────


def scenario_healthy():
    """1 — all values within configured ranges."""
    crop = "wheat"
    return _build(crop), "NORMAL, no alerts"


def scenario_temporary():
    """2 — one or two readings briefly out of range."""
    crop = "wheat"
    thresholds, base = _baselines(crop)
    n_min = thresholds["N"]["min"]
    values = ["healthy"] * SAMPLES  # placeholder, built below
    target_n = [base["N"]] * SAMPLES
    target_n[5] = round(n_min - 2, 2)   # within buffer -> WARNING reading
    target_n[12] = round(n_min - 3, 2)  # within buffer -> WARNING reading
    crop, current, history = _build(crop, {"N": target_n},
                                    current_override={"N": round(n_min - 2, 2)})
    return (crop, current, history), "WARNING or MONITOR, no fertilizer alert"


def scenario_n_deficiency():
    """3 — persistent nitrogen deficiency (below configuration range)."""
    crop = "wheat"
    n_min = get_thresholds(crop)["N"]["min"]
    target_n = _linspace_series(n_min - 10, n_min - 55)
    return _build(crop, {"N": target_n}), "persistent N deficiency advisory"


def scenario_p_deficiency():
    """4 — persistent phosphorus deficiency."""
    crop = "wheat"
    p_min = get_thresholds(crop)["P"]["min"]
    target_p = _linspace_series(p_min - 8, p_min - 30)
    return _build(crop, {"P": target_p}), "persistent P deficiency advisory"


def scenario_k_deficiency():
    """5 — persistent potassium deficiency."""
    crop = "wheat"
    k_min = get_thresholds(crop)["K"]["min"]
    target_k = _linspace_series(k_min - 6, k_min - 22)
    return _build(crop, {"K": target_k}), "persistent K deficiency advisory"


def scenario_excess():
    """6 — persistent nutrient excess (N above configured range)."""
    crop = "wheat"
    n_max = get_thresholds(crop)["N"]["max"]
    target_n = _linspace_series(n_max + 15, n_max + 35)
    return _build(crop, {"N": target_n}), "persistent excess advisory"


def scenario_noise():
    """7 — healthy readings with small random fluctuation."""
    crop = "maize"
    return _build(crop), "no false persistent alerts"


def scenario_multiple():
    """8 — multiple simultaneous issues (N low, K low, soil moisture low)."""
    crop = "wheat"
    t = get_thresholds(crop)
    target_n = _linspace_series(t["N"]["min"] - 12, t["N"]["min"] - 50)
    target_k = _linspace_series(t["K"]["min"] - 8, t["K"]["min"] - 25)
    target_m = _linspace_series(t["soil_moisture"]["min"] - 5,
                                 t["soil_moisture"]["min"] - 22)
    return _build(crop, {"N": target_n, "K": target_k,
                         "soil_moisture": target_m}), \
        "multiple persistent issues"


SCENARIOS = [
    ("1  healthy", scenario_healthy),
    ("2  temporary abnormal", scenario_temporary),
    ("3  persistent N deficiency", scenario_n_deficiency),
    ("4  persistent P deficiency", scenario_p_deficiency),
    ("5  persistent K deficiency", scenario_k_deficiency),
    ("6  excess nutrient", scenario_excess),
    ("7  sensor noise", scenario_noise),
    ("8  multiple issues", scenario_multiple),
]


def run_all():
    print("SmartCrop — simulated sensor monitoring scenarios\n")
    for name, fn in SCENARIOS:
        (crop, current, history), expectation = fn()
        result = analyze_monitoring(crop, current, history)
        alerts = [a["parameter"] + ":" + a["type"] for a in result["alerts"]]
        pers = result["persistent_issues"]
        print(f"== {name} ==  expect: {expectation}")
        print(f"   crop={crop}  status={result['overall_status']:9}  "
              f"health={result['health_score']}"
              f"  persistent={pers}")
        print(f"   alerts      : {alerts}")
        print()


def payload_for(index):
    name, fn = SCENARIOS[index - 1]
    (crop, current, history), _ = fn()
    return {
        "crop": crop,
        "current": current,
        "history": history,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scenario", "--json", type=int, default=None, dest="scenario",
        help="Print the /monitor JSON payload for scenario 1..8",
    )
    args = parser.parse_args()

    if args.scenario:
        if not 1 <= args.scenario <= len(SCENARIOS):
            raise SystemExit(f"Scenario must be 1..{len(SCENARIOS)}")
        print(json.dumps(payload_for(args.scenario), indent=2))
        return

    run_all()


if __name__ == "__main__":
    main()