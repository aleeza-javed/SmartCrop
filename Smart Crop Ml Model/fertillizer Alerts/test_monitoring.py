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

import datetime
import os
import sys
import unittest

import numpy as np

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

import app as smartcrop_app
import monitoring_engine as engine
from crop_thresholds import (get_thresholds, MONITOR_CONFIG, PPM_TO_KG_HA,
                             FERTILIZER_PRODUCTS)

WHEAT_T = get_thresholds("wheat")

# Sentinel meaning "leave this key out of the request entirely", so a test can
# distinguish an absent key from an explicit null.
_OMIT = object()

# Crops exercised by the band-correctness tests.
FERTILIZER_CROPS = ("wheat", "rice", "maize", "tomato", "mango")


# ── helpers ──────────────────────────────────────────────────────────────


def mid_band(crop, nutrient):
    """A reading comfortably inside a crop's configured range."""
    cfg = get_thresholds(crop)[nutrient]
    return round((cfg["min"] + cfg["max"]) / 2.0, 2)


def full_monitor_current(crop, **overrides):
    """A complete, non-faulty `current`/`history` row for a crop.

    Every configured parameter is included at a healthy value so the monitoring
    engine can actually run (it requires the full set), with `overrides` applied
    on top. All values are non-zero so nothing trips the dead-probe guard.
    """
    row = {p: mid_band(crop, p) for p in get_thresholds(crop)}
    row.update(overrides)
    return row


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
        # The monitoring engine states the problem, never a dose. Asserted
        # without naming a unit, because the message carries none.
        self.assertNotRegex(algo[0]["message"], r"[Aa]pply (exactly|about)?")

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


class FertilizerAdvisorTest(unittest.TestCase):
    """POST /fertilizer — rule-based advice built on crop_thresholds.py.

    The point of these tests is that the endpoint derives every band, buffer
    and unit from the threshold table, and that a dead probe is never
    mistaken for a deficiency.
    """

    @classmethod
    def setUpClass(cls):
        cls.client = smartcrop_app.app.test_client()

    def _post(self, **kw):
        crop = kw.pop("crop", "wheat")
        # An unknown crop must still be postable, so fall back to wheat bands
        # for the default readings rather than raising in the helper.
        def default(nutrient):
            try:
                return mid_band(crop, nutrient)
            except KeyError:
                return mid_band("wheat", nutrient)

        payload = {
            "crop": crop,
            "N": kw.pop("N", default("N")),
            "P": kw.pop("P", default("P")),
            "K": kw.pop("K", default("K")),
        }
        payload.update(kw)
        for key in [k for k, v in payload.items() if v is _OMIT]:
            del payload[key]
        return self.client.post("/fertilizer", json=payload)

    def _nutrient(self, symbol, **kw):
        r = self._post(**kw)
        self.assertEqual(r.status_code, 200, r.get_data(as_text=True))
        return r.get_json()["nutrients"][symbol]

    # ── bands come from the threshold table, not a duplicate ──

    def test_band_matches_thresholds_for_several_crops(self):
        for crop in FERTILIZER_CROPS:
            with self.subTest(crop=crop):
                r = self._post(crop=crop)
                self.assertEqual(r.status_code, 200)
                body = r.get_json()
                self.assertEqual(body["source"], "crop_thresholds")
                thresholds = get_thresholds(crop)
                for symbol in ("N", "P", "K"):
                    nutrient = body["nutrients"][symbol]
                    self.assertEqual(nutrient["band"],
                                     [thresholds[symbol]["min"],
                                      thresholds[symbol]["max"]])
                    self.assertEqual(nutrient["buffer"],
                                     float(thresholds[symbol]["buffer"]))

    def test_unit_is_ppm(self):
        """The N/P/K sensor reports in ppm, and the bands are compared in ppm."""
        for symbol in ("N", "P", "K"):
            with self.subTest(nutrient=symbol):
                self.assertEqual(self._nutrient(symbol)["unit"], "ppm")

    def test_wheat_band_is_107_to_131(self):
        """Concrete regression check on the wheat nitrogen band."""
        nutrient = self._nutrient("N")
        self.assertEqual(nutrient["band"], [107, 131])
        self.assertEqual(nutrient["buffer"], 12.0)
        self.assertEqual(nutrient["label"], "Nitrogen")

    # ── status classification ──

    def test_normal_status(self):
        nutrient = self._nutrient("N", N=119)
        self.assertEqual(nutrient["status"], "NORMAL")
        self.assertFalse(nutrient["required"])
        self.assertIsNone(nutrient["direction"])
        self.assertEqual(nutrient["gap"], 0.0)
        self.assertIn("within the configured range", nutrient["advice"])

    def test_warning_deficient_status(self):
        # wheat N band 107-131, buffer 12 -> WARNING zone is 95..106
        nutrient = self._nutrient("N", N=100)
        self.assertEqual(nutrient["status"], "WARNING")
        self.assertTrue(nutrient["required"])
        self.assertEqual(nutrient["direction"], "deficient")
        self.assertEqual(nutrient["gap"], 7.0)

    def test_critical_deficient_status(self):
        # 90 is below 107 - 12 = 95
        nutrient = self._nutrient("N", N=90)
        self.assertEqual(nutrient["status"], "CRITICAL")
        self.assertTrue(nutrient["required"])
        self.assertEqual(nutrient["direction"], "deficient")
        self.assertEqual(nutrient["gap"], 17.0)

    def test_warning_and_critical_excess(self):
        # wheat K band 35-54, buffer 5 -> WARNING zone above 54 is 55..59
        warning = self._nutrient("K", K=56)
        self.assertEqual(warning["status"], "WARNING")
        self.assertTrue(warning["required"])
        self.assertEqual(warning["direction"], "excess")
        self.assertEqual(warning["gap"], 2.0)

        critical = self._nutrient("K", K=62)
        self.assertEqual(critical["status"], "CRITICAL")
        self.assertEqual(critical["direction"], "excess")
        self.assertEqual(critical["gap"], 8.0)

    def test_band_edges_are_normal(self):
        """Exactly on the edge is still NORMAL — the range is inclusive."""
        self.assertEqual(self._nutrient("N", N=107)["status"], "NORMAL")
        self.assertEqual(self._nutrient("N", N=131)["status"], "NORMAL")

    def test_buffer_edges_classify_as_warning(self):
        """Exactly `buffer` outside the band is still WARNING, not CRITICAL."""
        self.assertEqual(self._nutrient("N", N=95)["status"], "WARNING")
        self.assertEqual(self._nutrient("N", N=143)["status"], "WARNING")

    # ── gap semantics ──

    def test_gap_is_distance_to_edge_not_minus_buffer(self):
        """`gap` is the distance to the configured range edge.

        It is NOT `gap - buffer`. The buffer is a severity escalation width, not
        an offset of the band. Subtracting it is wrong in both directions: for
        a WARNING reading it goes negative (100 vs a 107 floor, buffer 12 ->
        7 - 12 = -5), and for a CRITICAL reading it understates the distance
        back into range by exactly one buffer (90 vs a 107 floor -> 17 - 12 =
        5, when 17 is the real distance).
        """
        warning = self._nutrient("N", N=100)
        self.assertEqual(warning["gap"], 7.0)
        self.assertLess(warning["gap"] - warning["buffer"], 0)

        critical = self._nutrient("N", N=90)
        self.assertEqual(critical["gap"], 17.0)
        self.assertNotEqual(critical["gap"] - critical["buffer"], critical["gap"])
        # gap is exactly what has to change for the reading to re-enter range.
        self.assertEqual(90 + critical["gap"], critical["band"][0])

    def test_advice_reports_ppm_gap_and_labels_the_amount_estimated(self):
        """Advice states the gap in the sensor's unit, and hedges the amount."""
        for value in (100, 90):
            with self.subTest(N=value):
                nutrient = self._nutrient("N", N=value)
                advice = nutrient["advice"]
                self.assertIn("below the configured range", advice)
                self.assertIn("ppm", advice)
                self.assertIn("estimated", advice.lower())
                # An estimate, never an instruction to apply a set dose.
                self.assertNotRegex(advice, r"[Aa]pply ")
                self.assertNotIn("kg/acre", advice)

    def test_nitrogen_estimate_chain(self):
        """7 ppm short -> 14.0 kg/ha of nutrient -> about 30.4 kg/ha of urea."""
        nutrient = self._nutrient("N", N=100)
        self.assertEqual(nutrient["direction"], "deficient")
        self.assertEqual(nutrient["gap"], 7.0)
        self.assertEqual(nutrient["unit"], "ppm")
        self.assertEqual(nutrient["nutrient_kg_ha"], 14.0)
        self.assertEqual(nutrient["product_kg_ha"], 30.4)
        self.assertEqual(nutrient["product"]["nutrient_fraction"], 0.46)
        self.assertIn("30.4 kg/ha of Urea (46-0-0)", nutrient["advice"])

    def test_phosphorus_estimate_chain(self):
        """4 ppm short -> 8.0 kg/ha of P -> 40.0 kg/ha of DAP at 20% P."""
        nutrient = self._nutrient("P", P=44)
        self.assertEqual(nutrient["gap"], 4.0)
        self.assertEqual(nutrient["nutrient_kg_ha"], 8.0)
        self.assertEqual(nutrient["product"]["nutrient_fraction"], 0.20)
        self.assertEqual(nutrient["product_kg_ha"], 40.0)

    def test_potassium_estimate_chain(self):
        """2 ppm short -> 4.0 kg/ha of K -> 8.0 kg/ha of MOP at 50% K."""
        nutrient = self._nutrient("K", K=33)
        self.assertEqual(nutrient["gap"], 2.0)
        self.assertEqual(nutrient["nutrient_kg_ha"], 4.0)
        self.assertEqual(nutrient["product"]["nutrient_fraction"], 0.50)
        self.assertEqual(nutrient["product_kg_ha"], 8.0)

    def test_estimate_uses_the_configured_rule_of_thumb(self):
        for symbol, value in (("N", 100), ("P", 44), ("K", 33)):
            with self.subTest(symbol=symbol):
                nutrient = self._nutrient(symbol, **{symbol: value})
                expected_nutrient = round(nutrient["gap"] * PPM_TO_KG_HA, 1)
                self.assertEqual(nutrient["nutrient_kg_ha"], expected_nutrient)
                expected_product = round(
                    expected_nutrient / nutrient["product"]["nutrient_fraction"], 1
                )
                self.assertEqual(nutrient["product_kg_ha"], expected_product)

    def test_every_nutrient_exposes_the_same_fields(self):
        """Uniform response shape, so the client can parse without special cases.

        Every nutrient must carry every key, null where it does not apply -
        a missing key and an explicit null are not interchangeable here.
        """
        expected = {
            "parameter", "label", "unit", "band", "buffer", "current",
            "status", "required", "direction", "gap", "product",
            "nutrient_kg_ha", "product_kg_ha", "advice", "confidence",
            "persistence",
        }
        for label, payload in (
            ("deficient", {"N": 100, "P": 61, "K": 45}),
            ("excess", {"N": 119, "P": 61, "K": 62}),
            ("normal", {"N": 119, "P": 61, "K": 45}),
            ("no_reading", {"N": 0, "P": 61, "K": 45}),
        ):
            with self.subTest(case=label):
                body = self._post(**payload).get_json()
                for symbol in ("N", "P", "K"):
                    self.assertEqual(set(body["nutrients"][symbol]), expected,
                                     f"{label}/{symbol}")

    def test_no_estimate_for_excess_normal_or_no_reading(self):
        cases = {
            "excess": ("K", 62),
            "normal": ("K", mid_band("wheat", "K")),
            "no_reading": ("K", 0),
        }
        for name, (symbol, value) in cases.items():
            with self.subTest(case=name):
                nutrient = self._nutrient(symbol, **{symbol: value})
                self.assertIsNone(nutrient["product_kg_ha"])
                self.assertIsNone(nutrient["nutrient_kg_ha"])
                self.assertIsNone(nutrient["product"])
                self.assertNotIn("kg/ha", nutrient["advice"])

    def test_excess_advice_names_no_product(self):
        advice = self._nutrient("N", N=150)["advice"]
        self.assertIn("above the configured range", advice)
        self.assertIn("Hold off", advice)
        self.assertNotIn("Urea", advice)
        self.assertNotIn("kg/ha", advice)

    # ── product catalog ──

    def test_product_present_only_for_deficient(self):
        deficient = self._nutrient("N", N=90)
        self.assertIsNotNone(deficient["product"])
        self.assertEqual(deficient["product"]["name"], "Urea (46-0-0)")
        self.assertEqual(deficient["product"]["role"], "Quick top-up")
        self.assertEqual(deficient["product"]["fertilizer"], "nitrogen-based")

        for value, symbol in ((150, "N"), (mid_band("wheat", "P"), "P")):
            with self.subTest(symbol=symbol, value=value):
                self.assertIsNone(self._nutrient(symbol, **{symbol: value})["product"])

    def test_all_three_products(self):
        cases = {"N": 90, "P": 40, "K": 20}
        expected = {
            "N": "Urea (46-0-0)",
            "P": "DAP (18-46-0)",
            "K": "Muriate of Potash (0-0-60)",
        }
        for symbol, value in cases.items():
            with self.subTest(symbol=symbol):
                nutrient = self._nutrient(symbol, **{symbol: value})
                self.assertEqual(nutrient["direction"], "deficient")
                self.assertEqual(nutrient["product"]["name"], expected[symbol])

    def test_product_catalog_has_no_conversion_factor(self):
        """The catalog carries a nutrient fraction and nothing else numeric.

        A per-unit dose factor must never appear here: the only conversion in
        the system is the single PPM_TO_KG_HA rule of thumb.
        """
        expected = {"N": 0.46, "P": 0.20, "K": 0.50}
        self.assertEqual(set(FERTILIZER_PRODUCTS), set(expected))
        for symbol, entry in FERTILIZER_PRODUCTS.items():
            self.assertEqual(set(entry), {"name", "role", "nutrient_fraction"}, symbol)
            self.assertIsInstance(entry["name"], str)
            self.assertIsInstance(entry["role"], str)
            self.assertEqual(entry["nutrient_fraction"], expected[symbol])

    # ── dead probes must not become deficiencies ──

    def test_zero_reading_is_no_reading(self):
        nutrient = self._nutrient("N", N=0)
        self.assertEqual(nutrient["status"], "NO_READING")
        self.assertIsNone(nutrient["required"])
        self.assertIsNone(nutrient["product"])
        self.assertIsNone(nutrient["gap"])
        self.assertEqual(nutrient["advice"], "Sensor not reporting")

    def test_missing_and_null_readings_are_no_reading(self):
        for marker in (_OMIT, None):
            with self.subTest(marker=marker):
                nutrient = self._nutrient("N", N=marker)
                self.assertEqual(nutrient["status"], "NO_READING")
                self.assertIsNone(nutrient["required"])

    def test_no_reading_excluded_from_required_count_and_health(self):
        body = self._post(N=0, P=mid_band("wheat", "P"), K=mid_band("wheat", "K")).get_json()
        self.assertEqual(body["summary"]["required_count"], 0)
        self.assertEqual(body["summary"]["no_reading"], ["N"])
        self.assertEqual(body["summary"]["within_range"], ["P", "K"])
        self.assertEqual(body["health"]["evaluated"], ["P", "K"])
        self.assertTrue(body["health"]["partial"])
        # A dead probe must not drag the score down either.
        self.assertEqual(body["health"]["score"], 100)

    def test_negative_reading_is_treated_as_a_fault(self):
        self.assertEqual(self._nutrient("N", N=-5)["status"], "NO_READING")

    def test_partial_health_note_is_explicit(self):
        body = self._post(N=0).get_json()
        self.assertIn("Partial", body["health"]["note"])

    # ── summary / health ──

    def test_health_score_changes_when_a_reading_moves(self):
        healthy = self._post().get_json()
        self.assertEqual(healthy["health"]["score"], 100)
        self.assertEqual(healthy["health"]["status"], "NORMAL")
        self.assertFalse(healthy["health"]["partial"])

        moved = self._post(N=90).get_json()
        self.assertLess(moved["health"]["score"], 100)
        self.assertEqual(moved["health"]["status"], "CRITICAL")
        self.assertEqual(moved["summary"]["required_count"], 1)

    def test_required_count_counts_only_actionable_nutrients(self):
        body = self._post(N=90, P=40, K=mid_band("wheat", "K")).get_json()
        self.assertEqual(body["summary"]["required_count"], 2)
        self.assertEqual(body["summary"]["within_range"], ["K"])

    # ── two-tier confidence ──

    def test_confidence_is_instant_without_history(self):
        nutrient = self._nutrient("N", N=90)
        self.assertEqual(nutrient["confidence"], "instant")
        self.assertEqual(nutrient["persistence"], "unavailable")

    def test_confidence_is_persistent_with_backing_history(self):
        low = WHEAT_T["N"]["min"] - 40
        current = full_monitor_current("wheat", N=low)
        history = [full_monitor_current("wheat", N=low) for _ in range(24)]
        body = self._post(**current, history=history).get_json()
        self.assertEqual(body["nutrients"]["N"]["confidence"], "persistent")
        self.assertEqual(body["nutrients"]["N"]["persistence"], "persistent")

    def test_confidence_stays_instant_when_history_disagrees(self):
        current = full_monitor_current("wheat", N=90)
        history = [full_monitor_current("wheat", N=119) for _ in range(24)]
        body = self._post(**current, history=history).get_json()
        self.assertEqual(body["nutrients"]["N"]["confidence"], "instant")
        self.assertNotEqual(body["nutrients"]["N"]["persistence"], "persistent")

    # ── staleness ──

    def test_stale_flag_for_old_timestamp(self):
        old = (datetime.datetime.now(datetime.timezone.utc)
               - datetime.timedelta(seconds=smartcrop_app.STALE_AFTER_SECONDS + 60))
        body = self._post(timestamp=old.isoformat()).get_json()
        self.assertTrue(body["stale"])
        self.assertGreater(body["reading_age_seconds"],
                           smartcrop_app.STALE_AFTER_SECONDS)

    def test_fresh_timestamp_is_not_stale(self):
        now = datetime.datetime.now(datetime.timezone.utc)
        body = self._post(timestamp=now.isoformat()).get_json()
        self.assertFalse(body["stale"])
        self.assertLess(body["reading_age_seconds"], 60)

    def test_epoch_timestamp_is_accepted(self):
        old = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)
        body = self._post(timestamp=old.timestamp()).get_json()
        self.assertTrue(body["stale"])

    def test_absent_or_unparseable_timestamp_is_not_stale(self):
        for marker in (_OMIT, None, "not-a-timestamp"):
            with self.subTest(marker=marker):
                body = self._post(timestamp=marker).get_json()
                self.assertFalse(body["stale"])
                self.assertIsNone(body["reading_age_seconds"])

    def test_stale_does_not_fail_the_request(self):
        old = (datetime.datetime.now(datetime.timezone.utc)
               - datetime.timedelta(hours=3))
        r = self._post(N=90, timestamp=old.isoformat())
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.get_json()["stale"])
        self.assertEqual(r.get_json()["nutrients"]["N"]["direction"], "deficient")

    # ── malformed requests stay 400 ──

    def test_unknown_crop_is_400(self):
        r = self._post(crop="not_a_crop")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Unknown crop", r.get_json()["error"])

    def test_non_numeric_reading_is_400(self):
        r = self._post(N="abc")
        self.assertEqual(r.status_code, 400)
        self.assertIn("Malformed N", r.get_json()["error"])

    def test_missing_crop_is_400(self):
        r = self.client.post("/fertilizer", json={"N": 100, "P": 60, "K": 40})
        self.assertEqual(r.status_code, 400)

    def test_no_body_is_400(self):
        self.assertEqual(self.client.post("/fertilizer", json={}).status_code, 400)


class MonitorSensorFaultTest(unittest.TestCase):
    """/monitor must not raise an advisory from a dead probe."""

    @classmethod
    def setUpClass(cls):
        cls.client = smartcrop_app.app.test_client()

    def _payload(self, **overrides):
        payload = {"crop": "wheat",
                   "current": {p: healthy_value(p) for p in WHEAT_T}}
        payload["current"].update(overrides)
        return payload

    def test_zero_probe_produces_sensor_fault_not_alerts(self):
        r = self.client.post("/monitor", json=self._payload(N=0))
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body["overall_status"], "SENSOR_FAULT")
        self.assertEqual(body["sensor_faults"], ["N"])
        self.assertEqual(body["alerts"], [])
        self.assertEqual(body["recommendations"], [])

    def test_zero_probe_never_lowers_the_health_score(self):
        """A dead probe must not drag the health score down to CRITICAL."""
        r = self.client.post("/monitor", json=self._payload(N=0))
        self.assertNotIn("health_score", r.get_json())

    def test_zero_is_a_fault_for_npk_and_ph_only(self):
        """N, P, K and pH: exactly 0 is not a real reading."""
        for param in ("N", "P", "K", "ph"):
            with self.subTest(param=param):
                r = self.client.post("/monitor", json=self._payload(**{param: 0}))
                body = r.get_json()
                self.assertEqual(body["overall_status"], "SENSOR_FAULT")
                self.assertEqual(body["sensor_faults"], [param])

    def test_zero_is_a_real_reading_for_moisture_humidity_temp_and_ec(self):
        """0% moisture, 0% humidity and 0 degC are real, not a dead probe.

        They must flow through to normal monitoring rather than be swallowed by
        the fault guard.
        """
        for param in ("soil_moisture", "humidity", "temperature", "ec"):
            with self.subTest(param=param):
                r = self.client.post("/monitor", json=self._payload(**{param: 0}))
                self.assertEqual(r.status_code, 200)
                body = r.get_json()
                self.assertNotEqual(body["overall_status"], "SENSOR_FAULT")
                self.assertEqual(body["sensor_faults"], [])

    def test_zero_soil_moisture_raises_a_normal_critical_alert(self):
        """0% moisture is bone-dry soil: a real CRITICAL alert, persistently."""
        dry = {p: healthy_value(p) for p in WHEAT_T}
        dry["soil_moisture"] = 0
        history = [dict(dry) for _ in range(24)]
        r = self.client.post("/monitor", json={
            "crop": "wheat", "current": dry, "history": history})
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertNotEqual(body["overall_status"], "SENSOR_FAULT")
        self.assertIn("soil_moisture", body["persistent_issues"])
        self.assertEqual(body["overall_status"], "CRITICAL")
        alerts = [a for a in body["alerts"] if a["parameter"] == "soil_moisture"]
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]["severity"], "CRITICAL")

    def test_negative_is_a_fault_for_the_nutrient_and_percentage_probes(self):
        """A negative concentration is a malfunction, not a measurement."""
        for param in ("N", "P", "K", "ph", "ec", "soil_moisture", "humidity"):
            with self.subTest(param=param):
                r = self.client.post("/monitor", json=self._payload(**{param: -5}))
                body = r.get_json()
                self.assertEqual(body["overall_status"], "SENSOR_FAULT")
                self.assertEqual(body["sensor_faults"], [param])
                self.assertEqual(body["alerts"], [])

    def test_negative_air_temperature_is_accepted(self):
        """Sub-zero air is normal in many climates and must not be faulted."""
        payload = self._payload(temperature=-7.5)
        payload["history"] = make_readings("N", [healthy_value("N")] * 24)
        for h in payload["history"]:
            h["temperature"] = -7.5
        r = self.client.post("/monitor", json=payload)
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body["sensor_faults"], [])
        self.assertEqual(body["parameter_results"]["temperature"]["current"], -7.5)

    def test_negative_reading_is_a_fault_not_a_400(self):
        for param in ("N", "ph", "ec", "soil_moisture"):
            with self.subTest(param=param):
                r = self.client.post("/monitor", json=self._payload(**{param: -1}))
                self.assertEqual(r.status_code, 200)
                self.assertEqual(r.get_json()["overall_status"], "SENSOR_FAULT")

    def test_numeric_string_zero_is_still_a_fault(self):
        """A zero sent as "0" must not slip past the guard as a string."""
        r = self.client.post("/monitor", json=self._payload(N="0"))
        self.assertEqual(r.get_json()["overall_status"], "SENSOR_FAULT")

    def test_healthy_payload_reports_no_faults(self):
        r = self.client.post("/monitor", json=self._payload())
        body = r.get_json()
        self.assertEqual(body["overall_status"], "NORMAL")
        self.assertEqual(body["sensor_faults"], [])

    def test_a_missing_key_is_still_400_not_a_fault(self):
        """'You did not send it' (client bug) stays distinct from 'it reads 0'."""
        payload = self._payload()
        del payload["current"]["soil_moisture"]
        self.assertEqual(self.client.post("/monitor", json=payload).status_code, 400)

    def test_a_bad_crop_with_a_dead_probe_is_still_400(self):
        payload = self._payload(N=0)
        payload["crop"] = "not_a_crop"
        self.assertEqual(self.client.post("/monitor", json=payload).status_code, 400)


if __name__ == "__main__":
    unittest.main(verbosity=2)
