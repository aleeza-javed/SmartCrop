"""
SmartCrop — Automated tests for the monitoring engine + API.

Run with:  python -m unittest discover -s "fertillizer Alerts" -p "test_*.py" -v
(No running server needed: API tests use the Flask test client.)

Covers:
  normal values, one abnormal reading, repeated abnormal readings,
  persistent deficiency, persistent excess, sensor noise, missing history,
  insufficient history, invalid crop, invalid sensor values, missing required
  parameters, multiple simultaneous deficiencies, trend calculation, health
  score calculation — plus the existing /predict and /predict/batch contract.
"""

from __future__ import annotations

import os
import sys
import unittest

import numpy as np

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

import app as smartcrop_app
import monitoring_engine as engine
from crop_thresholds import get_thresholds, MONITOR_CONFIG

WHEAT_T = get_thresholds("wheat")


# ── helpers ──────────────────────────────────────────────────────────────


def healthy_value(param, center_shift=0.0):
    cfg = WHEAT_T[param]
    center = (cfg["min"] + cfg["max"]) / 2.0 + center_shift
    return round(center, 2)


def make_readings(param, values, other=None):
    """Build [{"N":...}, ...], overriding `param` with `values`."""
    readings = []
    for v in values:
        r = {p: healthy_value(p) for p in WHEAT_T}
        r[param] = v
        if other:
            r.update(other)
        readings.append(r)
    return readings


def low_values(lo=None, n=24):
    lo = lo if lo is not None else WHEAT_T["N"].get("min") - 40
    return [lo] * n


class MonitoringEngineTest(unittest.TestCase):

    def _analyze(self, current, history, crop="wheat"):
        return engine.analyze_monitoring(crop, current, history)

    def test_normal_values(self):
        current = {p: healthy_value(p) for p in WHEAT_T}
        res = self._analyze(current, make_readings("N", [healthy_value("N")] * 24))
        self.assertEqual(res["overall_status"], "NORMAL")
        self.assertEqual(res["health_score"], 100)
        self.assertEqual(res["persistent_issues"], [])
        self.assertEqual(res["alerts"], [])

    def test_single_abnormal_reading(self):
        """One out-of-range reading must not produce a fertilizer alert."""
        current = dict(make_readings("N", [WHEAT_T["N"]["min"] - 2])[0])
        history = make_readings("N", low_values(WHEAT_T["N"]["min"] - 2, n=1)
                                + [healthy_value("N")] * 23)
        res = self._analyze(current, history)
        self.assertEqual(res["persistent_issues"], [])
        self.assertEqual(res["alerts"], [])
        n = res["parameter_results"]["N"]
        self.assertLess(n["abnormal_percentage"], MONITOR_CONFIG["abnormal_monitor_ceiling"])

    def test_repeated_abnormal_readings_warning_only(self):
        """~50% abnormal -> warning level, NOT persistent, no alert."""
        current = dict(make_readings("N", [WHEAT_T["N"]["min"] - 2])[0])
        history = make_readings(
            "N",
            low_values(WHEAT_T["N"]["min"] - 2, n=12) + [healthy_value("N")] * 12,
        )
        res = self._analyze(current, history)
        n = res["parameter_results"]["N"]
        self.assertEqual(n["persistence"], "warning")
        self.assertFalse(n["persistent"])
        self.assertEqual(res["alerts"], [])

    def test_persistent_deficiency(self):
        current = dict(make_readings("N", [WHEAT_T["N"]["min"] - 40])[0])
        history = make_readings("N", low_values(WHEAT_T["N"]["min"] - 40, n=24))
        res = self._analyze(current, history)
        self.assertIn("N", res["persistent_issues"])
        n = res["parameter_results"]["N"]
        self.assertTrue(n["persistent"])
        self.assertGreater(n["abnormal_percentage"], MONITOR_CONFIG["abnormal_persistent_floor"])
        self.assertEqual(res["overall_status"], "CRITICAL")
        algo = [a for a in res["alerts"] if a["parameter"] == "N"]
        self.assertEqual(len(algo), 1)
        self.assertEqual(algo[0]["type"], "deficiency")
        self.assertIn("nitrogen", algo[0]["message"].lower())
        self.assertNotRegex(
            algo[0]["message"], r"Apply exactly .* kg/ha"
        )

    def test_persistent_excess(self):
        current = dict(make_readings("N", [WHEAT_T["N"]["max"] + 30])[0])
        history = make_readings("N", [WHEAT_T["N"]["max"] + 30] * 24)
        res = self._analyze(current, history)
        self.assertIn("N", res["persistent_issues"])
        algo = [a for a in res["alerts"] if a["parameter"] == "N"]
        self.assertEqual(algo[0]["type"], "excess")
        self.assertIn("persistently above", algo[0]["message"].lower())

    def test_sensor_noise_no_false_persistent(self):
        """Healthy readings with small random noise -> no alerts."""
        current = {p: healthy_value(p) for p in WHEAT_T}
        history = []
        for _ in range(24):
            r = {}
            for p, cfg in WHEAT_T.items():
                center = healthy_value(p)
                r[p] = round(float(np.clip(center + np.random.normal(0, 1), cfg["min"], cfg["max"])), 2)
            history.append(r)
        res = self._analyze(current, history)
        self.assertEqual(res["alerts"], [])
        self.assertEqual(res["persistent_issues"], [])

    def test_missing_history(self):
        current = {p: healthy_value(p) for p in WHEAT_T}
        res = self._analyze(current, None)
        self.assertEqual(res["overall_status"], "NORMAL")
        self.assertEqual(res["persistent_issues"], [])
        self.assertEqual(res["parameter_results"]["N"]["trend"], "insufficient_data")

    def test_insufficient_history(self):
        """Fewer readings than required -> never persistent."""
        current = dict(make_readings("N", [WHEAT_T["N"]["min"] - 40])[0])
        history = make_readings("N", low_values(WHEAT_T["N"]["min"] - 40, n=2))
        res = self._analyze(current, history)
        n = res["parameter_results"]["N"]
        self.assertFalse(n["persistent"])
        self.assertEqual(n["persistence"], "insufficient_history")
        self.assertEqual(res["alerts"], [])

    def test_invalid_crop(self):
        with self.assertRaises(KeyError):
            engine.analyze_monitoring("tomato_unknown", {p: 1 for p in WHEAT_T}, [])

    def test_invalid_sensor_values(self):
        current = {p: 1.0 for p in WHEAT_T}
        current["N"] = "not-a-number"
        with self.assertRaises(engine.InvalidReadingError):
            self._analyze(current, [])

    def test_missing_required_parameter(self):
        current = {p: 1.0 for p in WHEAT_T}
        del current["soil_moisture"]
        with self.assertRaises(engine.InvalidReadingError):
            self._analyze(current, [])

    def test_multiple_simultaneous_deficiencies(self):
        def low_param(p, offset):
            return WHEAT_T[p]["min"] - offset

        def row():
            r = {p: healthy_value(p) for p in WHEAT_T}
            r["N"] = low_param("N", 40)
            r["K"] = low_param("K", 15)
            r["soil_moisture"] = low_param("soil_moisture", 15)
            return r

        current = row()
        history = [row() for _ in range(24)]
        res = self._analyze(current, history)
        self.assertIn("N", res["persistent_issues"])
        self.assertIn("K", res["persistent_issues"])
        self.assertIn("soil_moisture", res["persistent_issues"])
        self.assertEqual(len(res["alerts"]), 3)
        self.assertEqual(res["overall_status"], "CRITICAL")

    def test_trend_calculation(self):
        cfg = MONITOR_CONFIG
        self.assertEqual(engine.compute_trend([100, 95, 90, 85, 80], cfg, 24), "decreasing")
        self.assertEqual(engine.compute_trend([80, 85, 90, 95, 100], cfg, 24), "increasing")
        self.assertEqual(engine.compute_trend([90, 91, 89, 90, 91], cfg, 24), "stable")
        self.assertEqual(engine.compute_trend([90], cfg, 24), "insufficient_data")

    def test_health_score_calculation(self):
        cfg = MONITOR_CONFIG

        def param(status="NORMAL", current=0.5, persistent=False,
                  trend="stable", lo=0.0, hi=1.0):
            return {
                "status": status, "current": current, "trend": trend,
                "persistent": persistent, "recommended_range": [lo, hi],
            }

        healthy_res = {p: param() for p in ("N", "P", "K")}
        self.assertEqual(engine.compute_health_score(healthy_res, cfg), 100)

        bad = {
            "N": param(status="CRITICAL", current=-1.0, persistent=True,
                       trend="decreasing"),
            "P": param(),
            "K": param(),
        }
        expected = cfg["scoring"]["base"] - cfg["scoring"]["critical"] \
            - cfg["scoring"]["persistent"] - cfg["scoring"]["aggravating_trend"]
        self.assertEqual(engine.compute_health_score(bad, cfg), expected)

        worse = {p: param(status="CRITICAL", current=-1.0, persistent=True,
                          trend="decreasing")
                 for p in ("N", "P", "K")}
        expected = cfg["scoring"]["base"] - 3 * cfg["scoring"]["critical"] \
            - 3 * cfg["scoring"]["persistent"] \
            - 3 * cfg["scoring"]["aggravating_trend"]
        self.assertEqual(engine.compute_health_score(worse, cfg), expected)

    def test_valid_monitoring_structure(self):
        current = {p: healthy_value(p) for p in WHEAT_T}
        res = engine.analyze_monitoring("wheat", current,
                                        make_readings("N", [healthy_value("N")] * 24))
        for key in ("crop", "overall_status", "health_score",
                    "parameter_results", "persistent_issues", "alerts",
                    "recommendations", "analysis_window"):
            self.assertIn(key, res)
        self.assertTrue(set(current).issubset(res["parameter_results"]))
        self.assertEqual(res["crop"], "wheat")


class MonitorEndpointTest(unittest.TestCase):
    """API-level tests via the Flask test client (no running server)."""

    @classmethod
    def setUpClass(cls):
        cls.client = smartcrop_app.app.test_client()

    def _payload(self, **kw):
        payload = {
            "crop": kw.get("crop", "wheat"),
            "current": {p: healthy_value(p) for p in WHEAT_T},
            "history": make_readings("N", [healthy_value("N")] * 24),
        }
        payload["current"].update(kw.get("current", {}))
        if kw.get("history") is not None:
            payload["history"] = kw["history"]
        if kw.get("crop") is not None:
            payload["crop"] = kw["crop"]
        return payload

    def test_monitor_healthy(self):
        r = self.client.post("/monitor", json=self._payload())
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body["overall_status"], "NORMAL")
        self.assertEqual(body["alerts"], [])

    def test_monitor_persistent_deficiency(self):
        payload = self._payload(
            current={"N": WHEAT_T["N"]["min"] - 40},
            history=make_readings("N", low_values(WHEAT_T["N"]["min"] - 40)),
        )
        r = self.client.post("/monitor", json=payload)
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertIn("N", body["persistent_issues"])
        self.assertIn("health_score", body)
        self.assertIn("analysis_window", body)

    def test_monitor_invalid_crop(self):
        r = self.client.post("/monitor", json=self._payload(crop=("not_a_crop",)))
        self.assertEqual(r.status_code, 400)

    def test_monitor_missing_fields(self):
        r = self.client.post("/monitor", json={"crop": "wheat"})
        self.assertEqual(r.status_code, 400)

    def test_monitor_invalid_values(self):
        payload = self._payload(current={"N": "abc"})
        r = self.client.post("/monitor", json=payload)
        self.assertEqual(r.status_code, 400)

    def test_monitor_missing_parameter(self):
        payload = self._payload()
        payload["current"] = {p: healthy_value(p) for p in WHEAT_T}
        del payload["current"]["soil_moisture"]
        r = self.client.post("/monitor", json=payload)
        self.assertEqual(r.status_code, 400)

    def test_monitor_config(self):
        r = self.client.get("/monitor/config")
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertIn("wheat", body["monitored_crops"])
        self.assertIn("scoring", body["monitoring_config"])


class ExistingApiContractTest(unittest.TestCase):
    """Make sure the pre-existing endpoints still conform to their contract."""

    @classmethod
    def setUpClass(cls):
        cls.client = smartcrop_app.app.test_client()

    SAMPLE = {"N": 80, "P": 48, "K": 40, "temperature": 23.7,
              "humidity": 82.3, "ph": 6.4, "rainfall": 236.0}

    def test_predict_returns_recommended_crops(self):
        r = self.client.post("/predict", json=dict(self.SAMPLE))
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertIn("recommended_crops", body)
        self.assertEqual(len(body["recommended_crops"]), 3)

    def test_predict_batch(self):
        r = self.client.post("/predict/batch",
                             json={"samples": [self.SAMPLE, self.SAMPLE]})
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body["total"], 2)
        for item in body["results"]:
            self.assertIn("recommended_crops", item)

    def test_predict_missing_field_is_400(self):
        r = self.client.post("/predict",
                             json={k: v for k, v in self.SAMPLE.items() if k != "K"})
        self.assertEqual(r.status_code, 400)

    def test_health(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.get_json()["status"], "ok")


if __name__ == "__main__":
    unittest.main(verbosity=2)