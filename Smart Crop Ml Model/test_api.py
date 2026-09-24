"""
SmartCrop API Test Script
Run: python test_api.py
Make sure the Flask server is running first: python app.py
"""

import os
import sys
import requests
import json
import numpy as np

_ALERTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fertillizer Alerts")
if _ALERTS_DIR not in sys.path:
    sys.path.insert(0, _ALERTS_DIR)

from simulate_sensor_data import payload_for

BASE_URL = os.environ.get("SMARTCROP_BASE_URL", "http://localhost:5000")

def print_response(title, response):
    print(f"\n{'='*55}")
    print(f"  {title}")
    print(f"  Status: {response.status_code}")
    print(f"{'='*55}")
    try:
        print(json.dumps(response.json(), indent=2))
    except Exception:
        print(response.text)

def top_crops(data):
    """Actual API contract: returns {'recommended_crops': [.., .., ..]}."""
    return list(data.get("recommended_crops") or [])

def top1(data):
    crops = top_crops(data)
    return crops[0] if crops else None

def add_noise(base: dict, noise_config: dict) -> dict:
    """Add gaussian noise to sensor readings"""
    noisy = base.copy()
    for key, std in noise_config.items():
        if key in noisy:
            noisy[key] = round(noisy[key] + np.random.normal(0, std), 3)
    return noisy

# ── Noise config per sensor ───────────────────────────────
NOISE = {
    "N":           1.0,    # NPK sensors are noisy
    "P":           1.0,
    "K":           1.0,
    "temperature": 0.3,    # temp sensor slight drift
    "humidity":    0.5,    # humidity sensor slight drift
    "ph":          0.05,   # ph sensor precise
    "rainfall":    1.0     # rainfall moderate noise
}

# ── Base sensor readings (ideal values) ──────────────────
BASE_READINGS = {
    "rice":      {"N": 80,  "P": 48, "K": 40, "temperature": 23.7, "humidity": 82.3, "ph": 6.4, "rainfall": 236.0},
    "wheat":     {"N": 119, "P": 61, "K": 45, "temperature": 17.3, "humidity": 60.0, "ph": 6.8, "rainfall": 49.0},
    "maize":     {"N": 78,  "P": 48, "K": 20, "temperature": 22.0, "humidity": 65.0, "ph": 6.3, "rainfall": 85.0},
    "mango":     {"N": 20,  "P": 27, "K": 30, "temperature": 31.0, "humidity": 50.0, "ph": 5.7, "rainfall": 95.0},
    "coconut":   {"N": 22,  "P": 17, "K": 30, "temperature": 27.0, "humidity": 94.0, "ph": 5.9, "rainfall": 175.0},
    "sugarcane": {"N": 126, "P": 53, "K": 64, "temperature": 27.0, "humidity": 79.6, "ph": 6.7, "rainfall": 174.0},
}

# ── 1. Health Check ───────────────────────────────────────
res = requests.get(f"{BASE_URL}/health")
print_response("GET /health", res)

# ── 2. Feature Info ───────────────────────────────────────
res = requests.get(f"{BASE_URL}/features")
print_response("GET /features", res)

# ── 3. Clean predictions (no noise) ──────────────────────
print(f"\n{'='*55}")
print("  CLEAN PREDICTIONS (no noise)")
print(f"{'='*55}")
for crop, values in BASE_READINGS.items():
    res = requests.post(f"{BASE_URL}/predict", json=values)
    data = res.json()
    predicted  = top1(data)
    matches    = top_crops(data)
    correct    = "✅" if predicted == crop else "❌"
    print(f"  {correct} True: {crop:12} → Top-1: {predicted:12} | top-3: {matches}")

# ── 4. Noisy predictions (single run) ────────────────────
print(f"\n{'='*55}")
print("  NOISY PREDICTIONS (single IoT reading)")
print(f"{'='*55}")
for crop, base in BASE_READINGS.items():
    noisy_sample = add_noise(base, NOISE)
    res  = requests.post(f"{BASE_URL}/predict", json=noisy_sample)
    data = res.json()
    predicted  = top1(data)
    matches    = top_crops(data)
    correct    = "✅" if predicted == crop else "❌"
    print(f"  {correct} True: {crop:12} → Top-1: {predicted:12} | top-3: {matches}")

# ── 5. Noisy batch (10 runs averaged per crop) ────────────
print(f"\n{'='*55}")
print("  NOISE STABILITY TEST (10 runs per crop)")
print(f"{'='*55}")
n_runs = 10
for crop, base in BASE_READINGS.items():
    predictions = []
    for _ in range(n_runs):
        noisy_sample = add_noise(base, NOISE)
        res  = requests.post(f"{BASE_URL}/predict", json=noisy_sample)
        data = res.json()
        pred = top1(data)
        predictions.append(pred)

    correct_count = predictions.count(crop)
    stability     = correct_count / n_runs * 100
    most_common   = max(set(predictions), key=predictions.count)
    icon          = "✅" if stability >= 80 else "⚠️ " if stability >= 50 else "❌"
    print(f"  {icon} {crop:12} → correct {correct_count}/{n_runs} runs ({stability:.0f}% stable) | most common: {most_common}")

# ── 6. Monitor endpoint ───────────────────────────────────
print(f"\n{'='*55}")
print("  POST /monitor — persistent N deficiency (simulated)")
print(f"{'='*55}")
monitor_payload = payload_for(3)  # scenario 3: persistent nitrogen deficiency
res = requests.post(f"{BASE_URL}/monitor", json=monitor_payload)
print_response("POST /monitor — Scenario 3", res)

# ── 7. Error handling ─────────────────────────────────────
res = requests.post(f"{BASE_URL}/predict", json={
    "N": 80, "P": 48,
    "temperature": 24.0, "humidity": 82.0,
    "ph": 6.2
})
print_response("POST /predict — Missing fields (expect 400)", res)

res = requests.post(f"{BASE_URL}/predict", json={
    "N": "abc", "P": 48, "K": 40,
    "temperature": 24.0, "humidity": 82.0,
    "ph": 6.2, "rainfall": 240.0
})
print_response("POST /predict — Invalid value (expect 400)", res)

print(f"\n{'='*55}")
print("  All tests complete.")
print(f"{'='*55}\n")