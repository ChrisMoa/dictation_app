def test_languagetool_installation():
    """Testet LanguageTool Installation"""
    
    print("Teste LanguageTool Installation...")
    
    try:
        import language_tool_python
        print("✅ Import erfolgreich")
    except ImportError as e:
        print(f"❌ Import-Fehler: {e}")
        
        # Alternative Import-Versuche
        try:
            import languagetool
            print("ℹ️  Alternative 'languagetool' gefunden")
        except ImportError:
            print("❌ Kein LanguageTool-Modul gefunden")
            
        # Zeige verfügbare Pakete
        import pkg_resources
        installed_packages = [d.project_name for d in pkg_resources.working_set]
        language_packages = [p for p in installed_packages if 'language' in p.lower()]
        print(f"Gefundene language-Pakete: {language_packages}")
        return False
    
    try:
        # Teste LanguageTool Funktionalität
        tool = language_tool_python.LanguageTool('de-DE')
        
        # Teste mit einfachem Satz
        matches = tool.check("Das ist ein Test")
        print(f"✅ LanguageTool funktioniert, {len(matches)} Matches gefunden")
        
        tool.close()
        return True
        
    except Exception as e:
        print(f"❌ LanguageTool-Laufzeit-Fehler: {e}")
        
        # Häufige Probleme und Lösungen
        if "Java" in str(e) or "JVM" in str(e):
            print("💡 Java-Problem erkannt. Installiere Java:")
            print("   Windows: choco install openjdk")
            print("   macOS: brew install openjdk") 
            print("   Linux: sudo apt install default-jre")
            
        elif "download" in str(e).lower():
            print("💡 Download-Problem. Versuche manuellen Download:")
            print("   LanguageTool lädt beim ersten Start Daten herunter")
            print("   Stelle Internetverbindung sicher")
            
        return False

if __name__ == "__main__":
    test_languagetool_installation()