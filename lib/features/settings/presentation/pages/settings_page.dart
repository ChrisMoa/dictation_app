import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/ollama_grammar_provider.dart';
import 'package:dictation_app/core/services/whisper_download_service.dart';
import 'package:dictation_app/core/dependency_injection.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsService _settingsService;

  // STT Settings
  SttEngine _currentSttEngine = SttEngine.whisper;
  WhisperModelSize _currentWhisperModel = WhisperModelSize.base;

  // Text Processing Settings
  TextProcessingMode _textProcessingMode = TextProcessingMode.disabled;
  String _ollamaUrl = '';
  String _ollamaModel = '';
  OllamaPromptTemplate _currentTemplate = OllamaPromptTemplate.grammarCorrection;
  bool _isOllamaHealthy = false;
  bool _isCheckingHealth = false;
  bool _isLoadingModels = false;
  List<String> _availableModels = [];

  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _ollamaModelController = TextEditingController();
  final TextEditingController _ollamaPromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsService = getIt<SettingsService>();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _currentSttEngine = _settingsService.sttEngine;
      _currentWhisperModel = _settingsService.whisperModelSize;
      _textProcessingMode = _settingsService.textProcessingMode;
      _ollamaUrl = _settingsService.ollamaUrl;
      _ollamaModel = _settingsService.ollamaModel;
      _currentTemplate = _settingsService.ollamaPromptTemplate;
      _ollamaUrlController.text = _ollamaUrl;
      _ollamaModelController.text = _ollamaModel;
      _ollamaPromptController.text = _settingsService.getPromptForTemplate(_currentTemplate);
    });

    if (_textProcessingMode == TextProcessingMode.ollamaEnabled) {
      _checkOllamaHealth();
      _loadAvailableModels();
    }
  }

  Future<void> _checkOllamaHealth() async {
    setState(() {
      _isCheckingHealth = true;
    });

    try {
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: _ollamaUrl,
        modelName: _ollamaModel,
        customPrompt: _ollamaPromptController.text,
      );

      final isHealthy = await testProvider.isServerHealthy();
      setState(() {
        _isOllamaHealthy = isHealthy;
      });
    } catch (e) {
      setState(() {
        _isOllamaHealthy = false;
      });
    } finally {
      setState(() {
        _isCheckingHealth = false;
      });
    }
  }

  Future<void> _loadAvailableModels() async {
    final url = _ollamaUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoadingModels = true;
    });

    try {
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: url,
        modelName: 'dummy',
      );

      final models = await testProvider.getAvailableModels();
      setState(() {
        _availableModels = models;
        _isLoadingModels = false;
      });
    } catch (e) {
      setState(() {
        _availableModels = [];
        _isLoadingModels = false;
      });
    }
  }

  Future<void> _updateTextProcessingMode(TextProcessingMode newMode) async {
    await _settingsService.setTextProcessingMode(newMode);
    setState(() {
      _textProcessingMode = newMode;
    });

    if (newMode == TextProcessingMode.ollamaEnabled) {
      _checkOllamaHealth();
      _loadAvailableModels();
    }

    _showSnackBar('Textverarbeitung: ${newMode == TextProcessingMode.disabled ? "Deaktiviert" : "Ollama aktiviert"}');
  }

  Future<void> _updateSttEngine(SttEngine newEngine) async {
    await _settingsService.setSttEngine(newEngine);
    setState(() {
      _currentSttEngine = newEngine;
    });

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restart_alt, color: Colors.orange),
              SizedBox(width: 8),
              Text('App-Neustart erforderlich'),
            ],
          ),
          content: Text(
            'Die STT-Engine wurde auf ${newEngine == SttEngine.whisper ? "Whisper (Offline)" : "Google STT (Online)"} umgestellt.\n\n'
            'Bitte starte die App neu, damit die Änderung wirksam wird.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK - App schließen'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _updateWhisperModel(WhisperModelSize newModel) async {
    await _settingsService.setWhisperModelSize(newModel);
    setState(() {
      _currentWhisperModel = newModel;
    });

    _showSnackBar('Modell auf ${_getModelInfo(newModel)['title']} geändert. Nutze "Modell laden" um es herunterzuladen.');
  }

  Future<void> _updatePromptTemplate(OllamaPromptTemplate newTemplate) async {
    final templatePrompt = _settingsService.getPromptForTemplate(newTemplate);

    setState(() {
      _currentTemplate = newTemplate;
      if (newTemplate != OllamaPromptTemplate.custom) {
        _ollamaPromptController.text = templatePrompt;
      }
    });

    await _settingsService.setOllamaPromptTemplate(newTemplate);
    if (newTemplate != OllamaPromptTemplate.custom) {
      await _settingsService.setOllamaPrompt(templatePrompt);
    }

    _showSnackBar(newTemplate == OllamaPromptTemplate.custom
      ? 'Benutzerdefinierter Modus aktiviert'
      : 'Template: "${_settingsService.getTemplateDisplayName(newTemplate)}"');
  }

  Future<void> _saveOllamaUrl() async {
    final newUrl = _ollamaUrlController.text.trim();

    if (newUrl.isEmpty) {
      _showSnackBar('Ollama URL darf nicht leer sein', isError: true);
      return;
    }

    await _settingsService.setOllamaUrl(newUrl);
    setState(() {
      _ollamaUrl = newUrl;
    });

    _showSnackBar('URL gespeichert - teste Verbindung...');

    // Automatically test connection and load models
    await _testOllamaConnection();
    if (_isOllamaHealthy) {
      await _loadAvailableModels();
    }
  }

  Future<void> _saveOllamaModel() async {
    final newModel = _ollamaModelController.text.trim();

    if (newModel.isEmpty) {
      _showSnackBar('Ollama Modell darf nicht leer sein', isError: true);
      return;
    }

    await _settingsService.setOllamaModel(newModel);
    setState(() {
      _ollamaModel = newModel;
    });

    _showSnackBar('Modell gespeichert');
  }

  Future<void> _saveOllamaPrompt() async {
    final newPrompt = _ollamaPromptController.text.trim();

    if (newPrompt.isEmpty) {
      _showSnackBar('Ollama Prompt darf nicht leer sein', isError: true);
      return;
    }

    if (!newPrompt.contains('{TEXT}')) {
      _showSnackBar('Prompt muss {TEXT} Platzhalter enthalten', isError: true);
      return;
    }

    await _settingsService.setOllamaPrompt(newPrompt);
    _showSnackBar('Prompt gespeichert');
  }

  void _resetPromptToDefault() {
    final defaultPrompt = _settingsService.getPromptForTemplate(_currentTemplate);
    setState(() {
      _ollamaPromptController.text = defaultPrompt;
    });
    _showSnackBar('Prompt wiederhergestellt');
  }

  Future<void> _testOllamaConnection() async {
    final url = _ollamaUrlController.text.trim();

    if (url.isEmpty) {
      _showSnackBar('Bitte URL eingeben', isError: true);
      return;
    }

    setState(() {
      _isCheckingHealth = true;
    });

    try {
      // Test connection by fetching available models
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: url,
        modelName: 'dummy', // Dummy model just to create provider
      );

      final models = await testProvider.getAvailableModels();

      setState(() {
        _isOllamaHealthy = models.isNotEmpty;
        _isCheckingHealth = false;
        _availableModels = models;
      });

      if (models.isNotEmpty) {
        _showSnackBar('✅ Ollama verbunden! ${models.length} Modelle gefunden.');
      } else {
        _showSnackBar('❌ Keine Modelle gefunden', isError: true);
      }
    } catch (e) {
      setState(() {
        _isOllamaHealthy = false;
        _isCheckingHealth = false;
        _availableModels = [];
      });
      _showSnackBar('❌ Verbindung fehlgeschlagen: $e', isError: true);
    }
  }

  Future<void> _downloadWhisperModel() async {
    final modelSize = _currentWhisperModel;
    final modelInfo = _getModelInfo(modelSize);
    String modelName;

    switch (modelSize) {
      case WhisperModelSize.tiny:
        modelName = 'tiny';
        break;
      case WhisperModelSize.base:
        modelName = 'base';
        break;
      case WhisperModelSize.small:
        modelName = 'small';
        break;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = '${appDir.path}/whisper_models';

    final dir = Directory(modelDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final modelExists = await WhisperDownloadService.modelExists(modelName, modelDir);

    if (modelExists) {
      final size = await WhisperDownloadService.getModelSize(modelName, modelDir);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Modell vorhanden'),
              ],
            ),
            content: Text(
              'Das ${modelInfo['title']} Modell ist bereits heruntergeladen.\n\n'
              'Größe: ${(size! / 1024 / 1024).toStringAsFixed(1)} MB\n\n'
              'Möchtest du es erneut herunterladen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Abbrechen'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _startDownload(modelName, modelDir, modelInfo);
                },
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        );
      }
      return;
    }

    _startDownload(modelName, modelDir, modelInfo);
  }

  Future<void> _startDownload(String modelName, String modelDir, Map<String, String> modelInfo) async {
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WhisperDownloadDialog(
        modelName: modelName,
        modelDir: modelDir,
      ),
    );

    if (result == true && mounted) {
      _showSnackBar('✅ ${modelInfo['title']} erfolgreich heruntergeladen!');
    } else if (result == false && mounted) {
      _showSnackBar('❌ Download fehlgeschlagen', isError: true);
    }
  }

  Map<String, String> _getModelInfo(WhisperModelSize size) {
    switch (size) {
      case WhisperModelSize.tiny:
        return {
          'title': 'Tiny (~75 MB)',
          'subtitle': 'Schnell, niedrige Qualität. Gut zum Testen.',
        };
      case WhisperModelSize.base:
        return {
          'title': 'Base (~150 MB) - EMPFOHLEN',
          'subtitle': 'Gute Balance zwischen Qualität und Geschwindigkeit.',
        };
      case WhisperModelSize.small:
        return {
          'title': 'Small (~500 MB)',
          'subtitle': 'Sehr gute Qualität. ⚠️ Könnte instabil sein.',
        };
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ============ UI WIDGETS ============

  Widget _buildSttSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Spracherkennung (STT)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Wähle die Engine für Speech-to-Text',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            RadioListTile<SttEngine>(
              title: const Text('Whisper (Offline) - EMPFOHLEN ✅'),
              subtitle: const Text('Lokales Whisper-Modell. Funktioniert offline.'),
              value: SttEngine.whisper,
              groupValue: _currentSttEngine,
              onChanged: (value) {
                if (value != null) {
                  _updateSttEngine(value);
                }
              },
            ),
            if (_currentSttEngine == SttEngine.whisper) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Whisper Modell-Größe:',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _downloadWhisperModel(),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Laden', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...WhisperModelSize.values.map((size) {
                      final info = _getModelInfo(size);
                      return RadioListTile<WhisperModelSize>(
                        dense: true,
                        title: Text(info['title']!),
                        subtitle: Text(info['subtitle']!),
                        value: size,
                        groupValue: _currentWhisperModel,
                        onChanged: (value) {
                          if (value != null) {
                            _updateWhisperModel(value);
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            RadioListTile<SttEngine>(
              title: const Text('Google Speech-to-Text (Online)'),
              subtitle: const Text('Google Cloud STT. Benötigt Internet.'),
              value: SttEngine.googleStt,
              groupValue: _currentSttEngine,
              onChanged: (value) {
                if (value != null) {
                  _updateSttEngine(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextProcessingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Textverarbeitung',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Text nach der Spracherkennung automatisch verarbeiten',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Ollama Textverarbeitung'),
              subtitle: Text(_textProcessingMode == TextProcessingMode.ollamaEnabled
                ? 'Aktiviert - Text wird mit Ollama verarbeitet'
                : 'Deaktiviert - Nur Spracherkennung'),
              value: _textProcessingMode == TextProcessingMode.ollamaEnabled,
              onChanged: (value) {
                _updateTextProcessingMode(
                  value ? TextProcessingMode.ollamaEnabled : TextProcessingMode.disabled
                );
              },
            ),
            if (_textProcessingMode == TextProcessingMode.ollamaEnabled) ...[
              const Divider(height: 32),
              _buildOllamaConfiguration(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOllamaConfiguration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ollama Konfiguration',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // URL
        TextField(
          controller: _ollamaUrlController,
          decoration: InputDecoration(
            labelText: 'Ollama Server URL',
            hintText: 'http://localhost:11434',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Save URL Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saveOllamaUrl,
            icon: Icon(Icons.save),
            label: Text('URL speichern & testen'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Available Models
        if (_isLoadingModels) ...[
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('Lade verfügbare Modelle...'),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_availableModels.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonFormField<String>(
              value: _availableModels.contains(_ollamaModel) ? _ollamaModel : null,
              decoration: InputDecoration(
                labelText: 'Verfügbare Modelle',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _availableModels.map((model) {
                return DropdownMenuItem<String>(
                  value: model,
                  child: Text(model),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  _ollamaModelController.text = value;
                  _saveOllamaModel();
                }
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Model Name
        TextField(
          controller: _ollamaModelController,
          decoration: InputDecoration(
            labelText: 'Modell Name',
            hintText: 'llama3.2:3b',
            border: OutlineInputBorder(),
            helperText: _availableModels.isEmpty
                ? 'Erst URL speichern, dann werden Modelle angezeigt'
                : 'Oder eigenen Modellnamen eingeben',
            suffixIcon: IconButton(
              icon: Icon(Icons.save),
              onPressed: _saveOllamaModel,
              tooltip: 'Modell speichern',
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Template Selector
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<OllamaPromptTemplate>(
              value: _currentTemplate,
              decoration: InputDecoration(
                labelText: 'Prompt-Vorlage',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              isExpanded: true,
              items: OllamaPromptTemplate.values.map((template) {
                return DropdownMenuItem<OllamaPromptTemplate>(
                  value: template,
                  child: Text(
                    _settingsService.getTemplateDisplayName(template),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null && value != _currentTemplate) {
                  _updatePromptTemplate(value);
                }
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _settingsService.getTemplateDescription(_currentTemplate),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Prompt Text
        TextField(
          controller: _ollamaPromptController,
          decoration: InputDecoration(
            labelText: 'Prompt',
            border: OutlineInputBorder(),
            helperText: _currentTemplate == OllamaPromptTemplate.custom
                ? '{TEXT} als Platzhalter verwenden'
                : 'Nur im "Benutzerdefiniert" Modus editierbar',
            enabled: _currentTemplate == OllamaPromptTemplate.custom,
            suffixIcon: _currentTemplate == OllamaPromptTemplate.custom
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.restore),
                        onPressed: _resetPromptToDefault,
                        tooltip: 'Zurücksetzen',
                      ),
                      IconButton(
                        icon: Icon(Icons.save),
                        onPressed: _saveOllamaPrompt,
                        tooltip: 'Prompt speichern',
                      ),
                    ],
                  )
                : null,
          ),
          maxLines: 5,
          style: _currentTemplate != OllamaPromptTemplate.custom
              ? TextStyle(color: Colors.grey[600])
              : null,
        ),
        const SizedBox(height: 16),

        // Status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isOllamaHealthy
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isOllamaHealthy ? Colors.green : Colors.grey,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isOllamaHealthy ? Icons.check_circle : Icons.info,
                color: _isOllamaHealthy ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isCheckingHealth
                    ? 'Prüfe Verbindung...'
                    : _isOllamaHealthy
                      ? 'Ollama verbunden ✅'
                      : 'Noch nicht getestet',
                  style: TextStyle(
                    color: _isOllamaHealthy ? Colors.green : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Einstellungen'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSttSection(),
            const SizedBox(height: 16),
            _buildTextProcessingSection(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _settingsService.resetToDefaults();
                  _loadSettings();
                  _showSnackBar('Einstellungen zurückgesetzt');
                },
                icon: Icon(Icons.restore),
                label: Text('Zurücksetzen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ollamaUrlController.dispose();
    _ollamaModelController.dispose();
    _ollamaPromptController.dispose();
    super.dispose();
  }
}

/// Dialog widget for showing Whisper download progress
class _WhisperDownloadDialog extends StatefulWidget {
  final String modelName;
  final String modelDir;

  const _WhisperDownloadDialog({
    required this.modelName,
    required this.modelDir,
  });

  @override
  State<_WhisperDownloadDialog> createState() => _WhisperDownloadDialogState();
}

class _WhisperDownloadDialogState extends State<_WhisperDownloadDialog> {
  double _progress = 0.0;
  int _downloaded = 0;
  int _total = 0;
  String _status = 'Starte Download...';
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      await WhisperDownloadService.downloadModel(
        modelName: widget.modelName,
        destinationPath: widget.modelDir,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _downloaded = downloaded;
              _total = total;
              _status = 'Lade Whisper ${widget.modelName} Modell...';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isComplete = true;
          _status = 'Download abgeschlossen!';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = 'Download fehlgeschlagen';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isComplete || _error != null,
      child: AlertDialog(
        title: Row(
          children: [
            if (_isComplete)
              const Icon(Icons.check_circle, color: Colors.green)
            else if (_error != null)
              const Icon(Icons.error, color: Colors.red)
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isComplete ? 'Fertig!' : _error != null ? 'Fehler' : 'Download läuft',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            if (_error == null) ...[
              LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _isComplete ? Colors.green : Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_total > 0)
                    Text(
                      '${_formatBytes(_downloaded)} / ${_formatBytes(_total)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ] else ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Schließen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
