#include <ModbusMaster.h>
#include "DHT.h"
#include <WiFi.h>
#include <FirebaseESP32.h>
ModbusMaster node;
#define MAX485_DE_RE 4
#define SOIL_ANALOG_PIN 35  
#define RAIN_ANALOG_PIN 34   
#define DHTPIN 27            
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);
#define WIFI_SSID "ANGRY BIRD"
#define WIFI_PASSWORD "1234432155"
#define FIREBASE_HOST "https://smart-crop-ddf69-default-rtdb.firebaseio.com/"  
#define FIREBASE_AUTH "nfhuL45bzJy4A5A8lu1Kaw2uqgKRYCrRFyCJPsG2"                    
FirebaseData fbData;
void preTransmission() {
  digitalWrite(MAX485_DE_RE, HIGH);
}
void postTransmission() {
  digitalWrite(MAX485_DE_RE, LOW);
}
void setup() {
  Serial.begin(115200);
  pinMode(MAX485_DE_RE, OUTPUT);
  digitalWrite(MAX485_DE_RE, LOW);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);
  node.begin(1, Serial2);
  node.preTransmission(preTransmission);
  node.postTransmission(postTransmission);
  dht.begin();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected to WiFi!");
  Firebase.begin(FIREBASE_HOST, FIREBASE_AUTH);
  Firebase.reconnectWiFi(true);
  Serial.println("Firebase connected!");
}
void loop() {
  uint8_t result = node.readHoldingRegisters(0x0000, 7);
  float soilTemp = NAN;
  float soilHum = NAN;
  int ec = NAN, N = NAN, P = NAN, K = NAN;
  float ph = NAN;
  if(result == node.ku8MBSuccess) {
    soilTemp = node.getResponseBuffer(0) / 10.0;   
    soilHum  = node.getResponseBuffer(1) / 10.0;  
    ec       = node.getResponseBuffer(2);
    ph       = node.getResponseBuffer(3) / 10.0;
    N        = node.getResponseBuffer(4);
    P        = node.getResponseBuffer(5);
    K        = node.getResponseBuffer(6);
    Serial.println("----- NPK Sensor -----");
    Serial.printf("Soil Temp: %.1f °C\n", soilTemp);
    Serial.printf("Soil Humidity: %.1f %%\n", soilHum);
    Serial.printf("EC: %d\n", ec);
    Serial.printf("pH: %.1f\n", ph);
    Serial.printf("N: %d\n", N);
    Serial.printf("P: %d\n", P);
    Serial.printf("K: %d\n", K);
  } else {
    Serial.print("NPK Error: ");
    Serial.println(result);
  }
  //Soil Moisture Sensor
  int soilRaw = analogRead(SOIL_ANALOG_PIN);
  int soilPercent = map(soilRaw, 0, 4095, 100, 0); 
  Serial.println("----- Soil Moisture -----");
  Serial.printf("Raw: %d\n", soilRaw);
  Serial.printf("Moisture: %d %%\n", soilPercent);
  //Rain Sensor 
  int rainRaw = analogRead(RAIN_ANALOG_PIN);
  int rainPercent = map(rainRaw, 0, 4095, 100, 0); 
  Serial.println("----- Rain Sensor -----");
  Serial.printf("Raw: %d\n", rainRaw);
  Serial.printf("Rain Intensity: %d %%\n", rainPercent);
  float dhtTemp = dht.readTemperature();
  float dhtHum = dht.readHumidity();
  Serial.println("----- DHT11 -----");
  if (isnan(dhtTemp) || isnan(dhtHum)) {
    Serial.println("DHT11 Error: No data");
  } else {
    Serial.printf("Air Temp: %.1f °C\n", dhtTemp);
    Serial.printf("Air Humidity: %.1f %%\n", dhtHum);
  }

  Firebase.setFloat(fbData, "/SoilTemp", soilTemp);
  Firebase.setFloat(fbData, "/SoilHumidity", soilHum);
  Firebase.setInt(fbData, "/EC", ec);
  Firebase.setFloat(fbData, "/pH", ph);
  Firebase.setInt(fbData, "/N", N);
  Firebase.setInt(fbData, "/P", P);
  Firebase.setInt(fbData, "/K", K);
  Firebase.setInt(fbData, "/SoilMoisturePercent", soilPercent);
  Firebase.setInt(fbData, "/RainPercent", rainPercent);
  Firebase.setFloat(fbData, "/AirTemp", dhtTemp);
  Firebase.setFloat(fbData, "/AirHumidity", dhtHum);
  Serial.println("Data pushed to Firebase!");

  delay(5000);
}
