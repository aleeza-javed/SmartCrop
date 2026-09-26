"""
SmartCrop Model Training
Run: python train.py

Regenerates the two artifacts app.py loads:
    smartcrop_rf_model.pkl
    smartcrop_label_encoder.pkl

Hyperparameters mirror smartcrop_random_forest.ipynb exactly so the
exported model matches the documented evaluation results.
"""

import os

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH = os.path.join(BASE_DIR, "Crop_recommendation_extended.csv")
MODEL_PATH = os.path.join(BASE_DIR, "smartcrop_rf_model.pkl")
LE_PATH = os.path.join(BASE_DIR, "smartcrop_label_encoder.pkl")

FEATURES = ["N", "P", "K", "temperature", "humidity", "ph", "rainfall"]
TARGET = "label"


def main():
    df = pd.read_csv(DATASET_PATH)

    X = df[FEATURES]
    y = df[TARGET]

    le = LabelEncoder()
    le.fit(y)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    rf = RandomForestClassifier(
        n_estimators=100,
        max_depth=None,
        min_samples_split=2,
        min_samples_leaf=1,
        random_state=42,
        n_jobs=-1,
    )
    rf.fit(X_train, y_train)

    y_pred = rf.predict(X_test)
    train_acc = rf.score(X_train, y_train) * 100
    test_acc = accuracy_score(y_test, y_pred) * 100

    joblib.dump(rf, MODEL_PATH)
    joblib.dump(le, LE_PATH)

    print("Model saved:  %s" % MODEL_PATH)
    print("Encoder saved: %s" % LE_PATH)
    print("Rows: %d  |  Crop classes: %d" % (len(df), len(le.classes_)))
    print("Train accuracy: %.2f%%" % train_acc)
    print("Test accuracy:  %.2f%%" % test_acc)
    print("Generalization gap: %.2f%%" % (train_acc - test_acc))


if __name__ == "__main__":
    main()
