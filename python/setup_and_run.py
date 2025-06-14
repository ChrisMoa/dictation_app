"""
Automatisiertes Setup und Ausführung des deutschen Grammatikkorrektur-Systems
Führt Installation, Training und Tests durch
"""

import os
import sys
import subprocess
import time
import platform
from pathlib import Path

def run_command(command, description="", check=True):
    """Führt Kommandozeilen-Befehl aus"""
    print(f"\n{'='*60}")
    print(f"Ausführung: {description or command}")
    print(f"{'='*60}")
    
    try:
        result = subprocess.run(command, shell=True, check=check, 
                              capture_output=True, text=True)
        
        if result.stdout:
            print("STDOUT:", result.stdout)
        if result.stderr and result.returncode != 0:
            print("STDERR:", result.stderr)
            
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        print(f"Fehler beim Ausführen von '{command}': {e}")
        return False

def check_system_requirements():
    """Prüft System-Anforderungen"""
    print("Prüfe System-Anforderungen...")
    
    # Python-Version
    python_version = sys.version_info
    if python_version < (3, 8):
        print(f"❌ Python 3.8+ erforderlich, gefunden: {python_version}")
        return False
    print(f"✅ Python {python_version.major}.{python_version.minor}.{python_version.micro}")
    
    # Verfügbarer RAM
    import psutil
    total_ram = psutil.virtual_memory().total / (1024**3)  # GB
    if total_ram < 8:
        print(f"⚠️  Wenig RAM verfügbar: {total_ram:.1f}GB (empfohlen: 8GB+)")
    else:
        print(f"✅ RAM: {total_ram:.1f}GB")
    
    # Freier Speicherplatz
    free_space = psutil.disk_usage('.').free / (1024**3)  # GB
    if free_space < 10:
        print(f"❌ Zu wenig Speicherplatz: {free_space:.1f}GB (benötigt: 10GB+)")
        return False
    print(f"✅ Freier Speicherplatz: {free_space:.1f}GB")
    
    # GPU-Verfügbarkeit
    try:
        import torch
        import tensorflow as tf
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            gpu_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            print(f"✅ GPU verfügbar: {gpu_name} ({gpu_memory:.1f}GB)")
        else:
            # Configure GPU memory growth
            gpus = tf.config.experimental.list_physical_devices('GPU')
            if gpus:
                try:
                    for gpu in gpus:
                        tf.config.experimental.set_memory_growth(gpu, True)
                    print(f"Configured {len(gpus)} GPU(s) for memory growth")
                except RuntimeError as e:
                    print(f"GPU configuration error: {e}")
            
            print("ℹ️  Keine GPU verfügbar - Training wird auf CPU durchgeführt")
    except ImportError:
        print("ℹ️  PyTorch noch nicht installiert")
    
    return True

def install_dependencies():
    """Installiert alle erforderlichen Abhängigkeiten"""
    print("\nInstalliere Python-Pakete...")
    
    # Basis-Pakete installieren
    commands = [
        "pip install --upgrade pip",
        "python -m pip install -r requirements_gec.txt --break-system-packages",
        "python -m spacy download de_core_news_lg",
        "python -c \"import nltk; nltk.download('punkt')\"",
        "python -c \"import nltk; nltk.download('punkt_tab')\""
    ]
    
    for cmd in commands:
        if not run_command(cmd, f"Installiere: {cmd.split()[2] if len(cmd.split()) > 2 else cmd}"):
            print(f"❌ Installation fehlgeschlagen: {cmd}")
            return False
    
    print("✅ Alle Abhängigkeiten installiert")
    return True

def download_base_models():
    """Lädt Basis-Modelle herunter"""
    print("\nLade Basis-Modelle...")
    
    # Erstelle Modell-Verzeichnis
    os.makedirs("models", exist_ok=True)
    
    # Test ob LanguageTool funktioniert
    try:
        import language_tool_python
        tool = language_tool_python.LanguageTool('de-DE')
        tool.close()
        print("✅ LanguageTool funktioniert")
    except Exception as e:
        print(f"❌ LanguageTool-Fehler: {e}")
        return False
    
    # Test ob SpaCy-Modell verfügbar ist
    try:
        import spacy
        nlp = spacy.load("de_core_news_lg")
        print("✅ SpaCy deutsches Modell geladen")
    except Exception as e:
        print(f"❌ SpaCy-Modell-Fehler: {e}")
        return False
    
    return True

def run_training():
    """Führt das dreistufige Training durch"""
    print("\nStarte dreistufiges Training...")
    
    # Prüfe ob bereits trainiertes Modell existiert
    model_path = "./german_gec_mt5/final_model"
    if os.path.exists(model_path):
        response = input(f"Trainiertes Modell bereits vorhanden in {model_path}. Neu trainieren? (j/N): ")
        if response.lower() not in ['j', 'ja', 'y', 'yes']:
            print("Training übersprungen - verwende vorhandenes Modell")
            return True
    
    # Starte Training
    try:
        from train_german_gec_mt5 import main as train_main
        print("Starte Training...")
        train_main()
        print("✅ Training erfolgreich abgeschlossen")
        return True
    except Exception as e:
        print(f"❌ Training fehlgeschlagen: {e}")
        return False

def run_tests():
    """Führt Tests durch"""
    print("\nFühre Tests durch...")
    
    try:
        # Import-Test
        from german_hybrid_corrector import HybridGermanGrammarCorrector
        from test_german_gec import TestGermanGrammarCorrection
        
        print("✅ Alle Module erfolgreich importiert")
        
        # Schnelltest
        corrector = HybridGermanGrammarCorrector(
            mt5_model_path="./german_gec_mt5/final_model",
            use_gpu=True #GPU - # CPU für Schnelltest
        )
        
        test_result = corrector.correct_text("Das ist ein Test", method="hybrid")
        print(f"✅ Schnelltest erfolgreich: '{test_result.corrected_text}'")
        
        return True
    except Exception as e:
        print(f"❌ Test fehlgeschlagen: {e}")
        return False

def run_demo():
    """Führt Demo durch"""
    print("\nStarte Demo...")
    
    try:
        # Demo ausführen
        from test_german_gec import run_demo
        run_demo()
        return True
    except Exception as e:
        print(f"❌ Demo fehlgeschlagen: {e}")
        return False

def run_benchmark():
    """Führt Performance-Benchmark durch"""
    print("\nStarte Performance-Benchmark...")
    
    try:
        from test_german_gec import run_performance_suite
        results = run_performance_suite()
        
        # Speichere Benchmark-Ergebnisse
        import json
        with open("benchmark_results.json", "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        
        print("✅ Benchmark abgeschlossen, Ergebnisse in benchmark_results.json")
        return True
    except Exception as e:
        print(f"❌ Benchmark fehlgeschlagen: {e}")
        return False

def create_model_info():
    """Erstellt Modell-Informationsdatei"""
    model_info = {
        "model_name": "German Grammar Correction mT5",
        "version": "1.0.0",
        "training_stages": 3,
        "base_model": "google/mt5-base",
        "languages": ["de"],
        "capabilities": [
            "Kasuskorrektur",
            "Verbkonjugation", 
            "Artikelkorrektur",
            "Alltagssprache-Normalisierung",
            "Rechtschreibkorrektur"
        ],
        "performance": {
            "target_latency_ms": 500,
            "target_accuracy": 0.9,
            "max_memory_gb": 3
        },
        "deployment": {
            "mobile_ready": True,
            "offline_capable": True,
            "hybrid_mode": True
        }
    }
    
    import json
    with open("model_info.json", "w", encoding="utf-8") as f:
        json.dump(model_info, f, indent=2, ensure_ascii=False)
    
    print("✅ Modell-Info erstellt: model_info.json")

def main():
    """Hauptfunktion für Setup und Ausführung"""
    print("="*80)
    print("    DEUTSCHES GRAMMATIKKORREKTUR-SYSTEM")
    print("    Automatisiertes Setup und Training")
    print("="*80)
    
    # Kommandozeilen-Argumente
    if len(sys.argv) > 1:
        mode = sys.argv[1].lower()
    else:
        print("\nVerfügbare Modi:")
        print("  full     - Vollständiges Setup (Installation + Training + Tests)")
        print("  install  - Nur Installation")
        print("  train    - Nur Training")
        print("  test     - Nur Tests")
        print("  demo     - Nur Demo")
        print("  benchmark - Nur Benchmark")
        
        mode = input("\nModus wählen [full]: ").lower() or "full"
    
    start_time = time.time()
    success = True
    
    try:
        # 1. System-Check
        if not check_system_requirements():
            print("❌ System-Anforderungen nicht erfüllt")
            return False
        
        # 2. Installation (falls erforderlich)
        if mode in ["full", "install"]:
            if not install_dependencies():
                success = False
                
            if not download_base_models():
                success = False
                
        # 3. Training (falls erforderlich)
        if mode in ["full", "train"] and success:
            if not run_training():
                success = False
                
        # 4. Tests (falls erforderlich)
        if mode in ["full", "test"] and success:
            if not run_tests():
                success = False
                
        # 5. Demo (falls erforderlich)
        if mode in ["full", "demo"] and success:
            if not run_demo():
                success = False
                
        # 6. Benchmark (falls erforderlich)
        if mode in ["full", "benchmark"] and success:
            if not run_benchmark():
                success = False
                
        # 7. Modell-Info erstellen
        if success and mode in ["full", "train"]:
            create_model_info()
            
    except KeyboardInterrupt:
        print("\n\n❌ Setup durch Benutzer abgebrochen")
        return False
    except Exception as e:
        print(f"\n\n❌ Unerwarteter Fehler: {e}")
        return False
    
    # Zusammenfassung
    duration = time.time() - start_time
    print(f"\n{'='*80}")
    
    if success:
        print("✅ SETUP ERFOLGREICH ABGESCHLOSSEN!")
        print(f"⏱️  Gesamtdauer: {duration/60:.1f} Minuten")
        
        if mode in ["full", "train"]:
            print(f"\n📁 Trainiertes Modell: ./german_gec_mt5/final_model")
            print(f"📊 Modell-Info: model_info.json")
            
        if mode in ["full", "benchmark"]:
            print(f"📈 Benchmark-Ergebnisse: benchmark_results.json")
            
        print(f"\n🚀 Nächste Schritte:")
        print(f"   - Demo ausführen: python test_german_gec.py demo")
        print(f"   - Tests ausführen: python test_german_gec.py test")
        print(f"   - Benchmark: python test_german_gec.py performance")
        print(f"   - Python verwenden:")
        print(f"     from german_hybrid_corrector import HybridGermanGrammarCorrector")
        print(f"     corrector = HybridGermanGrammarCorrector()")
        print(f"     result = corrector.correct_text('Ihr Text hier')")
        
    else:
        print("❌ SETUP FEHLGESCHLAGEN")
        print("Prüfen Sie die Fehlermeldungen oben für Details")
        
    print(f"{'='*80}")
    return success

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)