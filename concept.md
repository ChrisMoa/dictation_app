# German Grammar Correction (GEC) Project - Roadmap

## 📋 Projekt-Übersicht

Entwicklung eines hybriden deutschen Grammatikkorrektur-Systems mit PyTorch mT5, LanguageTool und Flutter-Integration.

### Aktuelle Status
- ✅ **Training läuft** - Loss bei ~0.08-0.12 (sehr gut!)
- ✅ **Basis-System funktioniert** - Hybrid-Corrector einsatzbereit
- 🔄 **Nächster Schritt**: ONNX/TF-Konvertierung + Server-Deployment

---

## 🏗️ Projekt-Struktur

```
german-gec-project/
├── train_german_gec_mt5_fixed.py     # Training-Script (abgeschlossen)
├── german_hybrid_corrector.py        # Hybrid-System (LanguageTool + mT5)
├── test_german_gec.py                # Tests & Benchmarks
├── setup_and_run.py                  # Automatisches Setup
├── german_gec_mt5/                   # Trainierte Modelle
│   └── final_model/                  # PyTorch-Modell (Loss: ~0.08)
├── requirements_gec.txt              # Python-Dependencies
└── README.md                         # Projekt-Dokumentation
```

---

## 📑 Chat-Aufteilung & Nächste Schritte

### 🎯 **Chat 1: Training & Basis-System** ✅ ABGESCHLOSSEN
**Status**: Training erfolgreich, Loss bei 0.08-0.12
- [x] mT5-Training mit synthetischen Daten
- [x] Hybrid-Corrector (LanguageTool + mT5)
- [x] Tests & Benchmarks
- [x] Performance-Optimierung

**Ergebnis**: Funktionierendes Modell in `./german_gec_mt5/final_model/`

---

### 🔥 **Chat 2: Server-Deployment & ONNX-Konvertierung** 🚀 HEUTE
**Ziel**: Modell als Server-API verfügbar machen

#### Aufgaben:
- [ ] **ONNX-Konvertierung**: PyTorch → ONNX
- [ ] **TensorFlow-Konvertierung**: ONNX → TF SavedModel  
- [ ] **FastAPI-Server**: REST-API für Grammatikkorrektur
- [ ] **Docker-Container**: Deployment-ready
- [ ] **Flutter HTTP-Client**: Theoretische Integration

#### Technische Details:
```python
# Conversion Pipeline
PyTorch (.bin) → ONNX (.onnx) → TensorFlow (SavedModel) → TFLite (.tflite)

# Server Stack
FastAPI + uvicorn
Docker + nginx (optional)
RESTful API: POST /correct {"text": "..."}
```

#### Deliverables:
- `convert_to_onnx.py` - Konvertierungs-Script
- `gec_server.py` - FastAPI-Server
- `Dockerfile` - Container-Setup
- `flutter_client_example.dart` - HTTP-Integration

---

### 📱 **Chat 3: TFLite-Optimierung** 
**Ziel**: Mobile-optimiertes Modell

#### Aufgaben:
- [ ] **TFLite-Konvertierung**: TF → TFLite
- [ ] **Quantisierung**: FP32 → INT8 (Größenreduktion)
- [ ] **Pruning**: Unwichtige Gewichte entfernen
- [ ] **Benchmark**: Modellgröße & Latenz

#### Technische Details:
```python
# Target Specifications
Model Size: <50MB (für Mobile)
Latency: <500ms (Satz-Korrektur)
Accuracy: >85% (vs. Desktop-Version)
```

---

### 🚀 **Chat 4: Flutter-Integration**
**Ziel**: Vollständige Mobile-App

#### Aufgaben:
- [ ] **TFLite-Flutter**: On-Device Inferenz
- [ ] **Tokenizer-Port**: MT5Tokenizer in Dart
- [ ] **UI-Implementation**: Eingabe, Korrektur, Vorschläge
- [ ] **Hybrid-Mode**: Online/Offline-Fallback

#### App-Features:
- Echtzeit-Grammatikkorrektur
- Offline-Funktionalität (TFLite)
- Online-Backup (Server-API)
- Korrektur-Highlighting

---

### 🧪 **Chat 5: Testing & Production**
**Ziel**: Production-ready System

#### Aufgaben:
- [ ] **Load-Testing**: Server-Performance
- [ ] **A/B-Testing**: Korrektur-Qualität
- [ ] **CI/CD-Pipeline**: Automated Deployment
- [ ] **Monitoring**: Error-Tracking & Metrics

---

## 🎯 Heutige Prioritäten (Chat 2)

### 1. **ONNX-Konvertierung** (Höchste Priorität)
```bash
# Erwartete Outputs
./models/
├── german_gec_model.onnx        # ONNX-Export
├── german_gec_tf/               # TF SavedModel
└── conversion_log.txt           # Konvertierungs-Details
```

### 2. **Server-Setup**
```bash
# API-Endpunkte
POST /api/v1/correct
GET  /api/v1/health
GET  /api/v1/models/info
```

### 3. **Flutter HTTP-Integration** (Theoretisch)
```dart
// Beispiel-Integration
Future<String> correctText(String text) async {
  final response = await http.post(
    Uri.parse('$serverUrl/api/v1/correct'),
    body: jsonEncode({'text': text}),
  );
  return response.body['corrected_text'];
}
```

---

## 🔧 Technische Anforderungen

### Server-Requirements:
- **RAM**: 4GB+ (für mT5-small)
- **CPU**: 2+ Cores (ARM64/x86_64)
- **Storage**: 2GB+ (Modell + Dependencies)
- **Python**: 3.8+ mit PyTorch/ONNX/TF

### Mobile-Requirements:
- **Flutter**: 3.0+
- **Android**: API 21+ (Android 5.0)
- **iOS**: 11.0+
- **App-Size**: <100MB (mit TFLite-Modell)

---

## 📊 Performance-Ziele

| Metrik | Server | Mobile (TFLite) |
|--------|--------|-----------------|
| **Latenz** | <200ms | <500ms |
| **Accuracy** | >90% | >85% |
| **Modellgröße** | ~300MB | <50MB |
| **Durchsatz** | 100+ req/s | N/A |

---

## 🚨 Bekannte Herausforderungen

### 1. **Tokenizer-Kompatibilität**
- MT5Tokenizer → ONNX/TFLite ist komplex
- **Lösung**: Separate Tokenizer-Implementation oder Pre/Post-Processing

### 2. **Modell-Größe**
- mT5-small: ~300MB → Zu groß für Mobile
- **Lösung**: Aggressive Quantisierung + Pruning

### 3. **Inference-Performance**
- mT5 ist transformer-basiert → Langsam auf Mobile
- **Lösung**: Server-Hybrid + Caching

---

## 📋 Nächste Aktionen (Heute)

1. **Konvertierungs-Pipeline aufsetzen**
2. **FastAPI-Server implementieren** 
3. **Docker-Container erstellen**
4. **Flutter HTTP-Client testen**
5. **Performance-Benchmarks durchführen**

---

## 📞 Chat-Kontext für neue Sessions

**Aktueller Stand beim Start von Chat 2:**
- Training abgeschlossen, Modell bei `./german_gec_mt5/final_model/`
- Loss: ~0.08-0.12 (sehr gut)
- Hybrid-Corrector funktioniert lokal
- Ziel: Server-API + ONNX-Konvertierung

**Benötigte Informationen:**
- PyTorch-Modell-Pfad: `./german_gec_mt5/final_model/`
- Tokenizer: MT5Tokenizer
- Input-Format: `"Korrigiere: " + text`
- Max-Length: 64 tokens

---

## 🎉 Erfolgs-Metriken

**Chat 2 erfolgreich wenn:**
- [x] ONNX-Modell exportiert
- [x] FastAPI-Server läuft
- [x] Docker-Container funktioniert  
- [x] Flutter kann Server erreichen
- [x] Korrektur-API antwortet korrekt

**Projekt erfolgreich wenn:**
- [x] Mobile App korrigiert deutsche Texte
- [x] <500ms Latenz on-device
- [x] >85% Korrektur-Accuracy
- [x] Offline-Funktionalität

---

*Letzte Aktualisierung: 15.06.2025 - Training Phase abgeschlossen*
