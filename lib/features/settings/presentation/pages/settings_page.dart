import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/hybrid_grammar_provider.dart';
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
  late AIGrammarService _aiGrammarService;
  
  GrammarCorrectionMode _currentMode = GrammarCorrectionMode.hybrid;
  SttEngine _currentSttEngine = SttEngine.whisper;
  WhisperModelSize _currentWhisperModel = WhisperModelSize.base;
  String _serverUrl = '';
  String _ollamaUrl = '';
  String _ollamaModel = '';
  String _ollamaPrompt = '';
  bool _isServerHealthy = false;
  bool _isOllamaHealthy = false;
  bool _isCheckingHealth = false;
  bool _isLoadingModels = false;
  List<String> _availableModels = [];
  
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _ollamaModelController = TextEditingController();
  final TextEditingController _ollamaPromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsService = getIt<SettingsService>();
    _aiGrammarService = getIt<AIGrammarService>();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _currentMode = _settingsService.grammarCorrectionMode;
      _currentSttEngine = _settingsService.sttEngine;
      _currentWhisperModel = _settingsService.whisperModelSize;
      _serverUrl = _settingsService.serverUrl;
      _ollamaUrl = _settingsService.ollamaUrl;
      _ollamaModel = _settingsService.ollamaModel;
      _ollamaPrompt = _settingsService.ollamaPrompt;
      _serverUrlController.text = _serverUrl;
      _ollamaUrlController.text = _ollamaUrl;
      _ollamaModelController.text = _ollamaModel;
      _ollamaPromptController.text = _ollamaPrompt;
    });
    _checkServerHealth();
    if (_shouldShowOllamaSettings()) {
      _loadAvailableModels();
    }
  }

  Future<void> _checkServerHealth() async {
    if (_currentMode == GrammarCorrectionMode.offlineOnly) return;
    
    setState(() {
      _isCheckingHealth = true;
    });

    try {
      final provider = _aiGrammarService.currentProvider;
      if (provider is HybridGrammarProvider) {
        final status = await provider.getProviderStatus();
        setState(() {
          _isServerHealthy = status['fastapi'] ?? false;
          _isOllamaHealthy = status['ollama'] ?? false;
        });
      }
    } catch (e) {
      setState(() {
        _isServerHealthy = false;
        _isOllamaHealthy = false;
      });
    } finally {
      setState(() {
        _isCheckingHealth = false;
      });
    }
  }

  Future<void> _updateSttEngine(SttEngine newEngine) async {
    await _settingsService.setSttEngine(newEngine);
    setState(() {
      _currentSttEngine = newEngine;
    });
    
    // Show dialog to restart app
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
                // Close the app
                Navigator.of(context).pop(); // Close settings
              },
              child: const Text('OK - App schließen'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _updateMode(GrammarCorrectionMode newMode) async {
    await _settingsService.setGrammarCorrectionMode(newMode);
    setState(() {
      _currentMode = newMode;
    });
    
    // Update the hybrid provider
    final provider = _aiGrammarService.currentProvider;
    if (provider is HybridGrammarProvider) {
      _checkServerHealth();
    }
    
    _showSnackBar('Grammar correction mode updated to ${newMode.name}');
  }

  Future<void> _updateServerUrl() async {
    final newUrl = _serverUrlController.text.trim();
    if (newUrl.isEmpty) {
      _showSnackBar('Server URL cannot be empty', isError: true);
      return;
    }

    await _settingsService.setServerUrl(newUrl);
    setState(() {
      _serverUrl = newUrl;
    });

    // Update the hybrid provider with new URL
    final provider = _aiGrammarService.currentProvider;
    if (provider is HybridGrammarProvider) {
      provider.updateServerUrl(newUrl);
      _checkServerHealth();
    }

    _showSnackBar('FastAPI Server URL updated successfully');
  }

  Future<void> _updateOllamaConfig() async {
    final newUrl = _ollamaUrlController.text.trim();
    final newModel = _ollamaModelController.text.trim();
    final newPrompt = _ollamaPromptController.text.trim();
    
    if (newUrl.isEmpty) {
      _showSnackBar('Ollama URL cannot be empty', isError: true);
      return;
    }
    
    if (newModel.isEmpty) {
      _showSnackBar('Ollama model cannot be empty', isError: true);
      return;
    }

    if (newPrompt.isEmpty) {
      _showSnackBar('Ollama prompt cannot be empty', isError: true);
      return;
    }

    if (!newPrompt.contains('{TEXT}')) {
      _showSnackBar('Prompt must contain {TEXT} placeholder', isError: true);
      return;
    }

    await _settingsService.setOllamaUrl(newUrl);
    await _settingsService.setOllamaModel(newModel);
    await _settingsService.setOllamaPrompt(newPrompt);
    
    setState(() {
      _ollamaUrl = newUrl;
      _ollamaModel = newModel;
      _ollamaPrompt = newPrompt;
    });

    // Update the hybrid provider with new Ollama config
    final provider = _aiGrammarService.currentProvider;
    if (provider is HybridGrammarProvider) {
      provider.updateOllamaConfig(newUrl, newModel, newPrompt: newPrompt);
      _checkServerHealth();
    }

    _showSnackBar('Ollama configuration updated successfully');
  }

  void _resetPromptToDefault() {
    const defaultPrompt = 'Schreib den folgenden Text mit korrekter deutscher Grammatik und Rechtschreibung neu. Verändere dabei nicht die Bedeutung. Gib nur den korrigierten Text zurück, ohne zusätzliche Erklärungen:\n\n{TEXT}';
    
    setState(() {
      _ollamaPromptController.text = defaultPrompt;
    });
    
    _showSnackBar('Prompt reset to default');
  }

  Future<void> _testOllamaConnection() async {
    debugPrint('=== Manual Ollama Connection Test ===');
    debugPrint('User initiated Ollama connection test');
    
    final url = _ollamaUrlController.text.trim();
    final model = _ollamaModelController.text.trim();
    
    if (url.isEmpty) {
      _showSnackBar('Please enter Ollama URL first', isError: true);
      return;
    }

    if (model.isEmpty) {
      _showSnackBar('Please enter Ollama model name first', isError: true);
      return;
    }

    setState(() {
      _isCheckingHealth = true;
    });

    try {
      final prompt = _ollamaPromptController.text.trim();
      debugPrint('Creating test Ollama provider with URL: $url, Model: $model, Prompt: ${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}...');
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: url,
        modelName: model,
        customPrompt: prompt.isNotEmpty ? prompt : _settingsService.ollamaPrompt,
      );

      debugPrint('Testing Ollama health check...');
      final isHealthy = await testProvider.isServerHealthy();
      debugPrint('Ollama health check result: $isHealthy');

      setState(() {
        _isOllamaHealthy = isHealthy;
        _isCheckingHealth = false;
      });

      if (isHealthy) {
        _showSnackBar('✅ Ollama connection successful! Model "$model" is available.');
        
        // Try a test correction
        debugPrint('Testing actual text correction...');
        try {
          final result = await testProvider.correctText('Das ist ein test satz.');
          debugPrint('Test correction result: ${result.correctedText}');
          _showSnackBar('✅ Test correction successful: "${result.correctedText}"');
        } catch (correctionError) {
          debugPrint('Test correction failed: $correctionError');
          _showSnackBar('⚠️ Connection OK but correction failed: $correctionError', isError: true);
        }
      } else {
        _showSnackBar('❌ Cannot connect to Ollama server or model not found', isError: true);
      }
    } catch (e) {
      debugPrint('Ollama test failed with error: $e');
      setState(() {
        _isOllamaHealthy = false;
        _isCheckingHealth = false;
      });
      _showSnackBar('❌ Ollama test failed: $e', isError: true);
    }
  }

  void _showOllamaDebugInfo() {
    final url = _ollamaUrlController.text.trim();
    final model = _ollamaModelController.text.trim();
    
    debugPrint('=== Ollama Debug Information ===');
    debugPrint('Current URL: $url');
    debugPrint('Current Model: $model');
    debugPrint('Platform: ${Platform.operatingSystem}');
    debugPrint('Checking URL format...');
    
    String debugInfo = 'Ollama Debug Information:\n\n';
    debugInfo += 'URL: ${url.isNotEmpty ? url : 'Not configured'}\n';
    debugInfo += 'Model: ${model.isNotEmpty ? model : 'Not configured'}\n';
    debugInfo += 'Platform: ${Platform.operatingSystem}\n';
    debugInfo += 'Status: ${_isOllamaHealthy ? 'Healthy' : 'Not accessible'}\n\n';
    
    if (url.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        debugInfo += 'URL Analysis:\n';
        debugInfo += '- Protocol: ${uri.scheme}\n';
        debugInfo += '- Host: ${uri.host}\n';
        debugInfo += '- Port: ${uri.port}\n';
        debugInfo += '- Path: ${uri.path}\n';
        debugInfo += '- Valid: ${uri.host.isNotEmpty}\n\n';
      } catch (e) {
        debugInfo += 'URL Analysis: Invalid format - $e\n\n';
      }
    }
    
    debugInfo += 'Troubleshooting Tips:\n';
    debugInfo += '• Ensure Ollama is running: "ollama serve"\n';
    debugInfo += '• Check available models: "ollama list"\n';
    debugInfo += '• Test URL in browser: $url/api/tags\n';
    debugInfo += '• For mobile testing, use actual IP address\n';
    debugInfo += '• Default URL: http://localhost:11434\n';
    debugInfo += '• Common models: llama3.2:3b, llama3.1:8b\n';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ollama Debug Information'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              Navigator.of(context).pop();
              _showSnackBar('Debug info copied to clipboard');
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
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

  Widget _buildSttEngineSelector() {
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
                  'Speech-to-Text Engine',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            RadioListTile<SttEngine>(
              title: const Text('Whisper (Offline) - EMPFOHLEN ✅'),
              subtitle: const Text('Lokales Whisper-Modell. Funktioniert offline. ⚠️ App-Neustart nach Wechsel erforderlich!'),
              value: SttEngine.whisper,
              groupValue: _currentSttEngine,
              onChanged: (value) {
                if (value != null) {
                  _updateSttEngine(value);
                }
              },
            ),
            // Show model selection if Whisper is selected
            if (_currentSttEngine == SttEngine.whisper) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
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
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _downloadWhisperModel(),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Laden', style: TextStyle(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                minimumSize: const Size(0, 32),
                              ),
                            ),
                          ],
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
                    }).toList(),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            RadioListTile<SttEngine>(
              title: const Text('Google Speech-to-Text (Online)'),
              subtitle: const Text('Google Cloud STT. Benötigt Internet, schnelle Echtzeit-Transkription.'),
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

  Future<void> _updateWhisperModel(WhisperModelSize newModel) async {
    await _settingsService.setWhisperModelSize(newModel);
    setState(() {
      _currentWhisperModel = newModel;
    });
    
    _showSnackBar('Modell auf ${_getModelInfo(newModel)['title']} geändert. Nutze "Modell laden" um es herunterzuladen.');
  }

  Future<void> _downloadWhisperModel() async {
    // Get model name from current selection
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
    
    // Get model directory
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = '${appDir.path}/whisper_models';
    
    // Create directory if it doesn't exist
    final dir = Directory(modelDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // Check if model already exists
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
    
    // Start download
    _startDownload(modelName, modelDir, modelInfo);
  }

  Future<void> _startDownload(String modelName, String modelDir, Map<String, String> modelInfo) async {
    if (!mounted) return;
    
    // Show download dialog
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

  Widget _buildModeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grammar Correction Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            ...GrammarCorrectionMode.values.map((mode) {
              return RadioListTile<GrammarCorrectionMode>(
                title: Text(_getModeTitle(mode)),
                subtitle: Text(_getModeDescription(mode)),
                value: mode,
                groupValue: _currentMode,
                onChanged: (value) {
                  if (value != null) {
                    _updateMode(value);
                  }
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FastAPI Server Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'FastAPI Server URL',
                hintText: 'http://localhost:8000',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.save),
                  onPressed: _updateServerUrl,
                ),
              ),
              onSubmitted: (_) => _updateServerUrl(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  _isServerHealthy ? Icons.check_circle : Icons.error,
                  color: _isServerHealthy ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isCheckingHealth 
                        ? 'Checking FastAPI server status...'
                        : _isServerHealthy 
                            ? 'FastAPI server is healthy and ready'
                            : 'FastAPI server is not reachable',
                    style: TextStyle(
                      color: _isServerHealthy ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOllamaSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ollama Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ollamaUrlController,
              decoration: InputDecoration(
                labelText: 'Ollama Server URL',
                hintText: 'http://localhost:11434',
                border: OutlineInputBorder(),
                helperText: 'Full URL including protocol (http/https) and port',
                suffixIcon: IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _loadAvailableModels,
                  tooltip: 'Refresh available models',
                ),
              ),
              onChanged: (value) {
                // Auto-load models when URL changes
                if (value.trim().isNotEmpty) {
                  Future.delayed(Duration(milliseconds: 500), () {
                    if (value == _ollamaUrlController.text) {
                      _loadAvailableModels();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            if (_isLoadingModels) ...[
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Loading available models...'),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_availableModels.isNotEmpty) ...[
              Text(
                'Available Models',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonFormField<String>(
                  value: _availableModels.contains(_ollamaModel) ? _ollamaModel : null,
                  decoration: InputDecoration(
                    labelText: 'Select Model',
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
                      _updateOllamaConfig();
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _ollamaModelController,
              decoration: InputDecoration(
                labelText: 'Ollama Model Name',
                hintText: 'llama3.2:3b',
                border: OutlineInputBorder(),
                helperText: _availableModels.isNotEmpty 
                    ? 'Or type a custom model name'
                    : 'Exact model name as shown in "ollama list"',
                suffixIcon: IconButton(
                  icon: Icon(Icons.save),
                  onPressed: _updateOllamaConfig,
                ),
              ),
              onSubmitted: (_) => _updateOllamaConfig(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ollamaPromptController,
              decoration: InputDecoration(
                labelText: 'Custom Prompt',
                hintText: 'Schreib den folgenden Text mit korrekter deutscher Grammatik...',
                border: OutlineInputBorder(),
                helperText: 'Use {TEXT} as placeholder for the input text',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.restore),
                      onPressed: _resetPromptToDefault,
                      tooltip: 'Reset to default prompt',
                    ),
                    IconButton(
                      icon: Icon(Icons.save),
                      onPressed: _updateOllamaConfig,
                      tooltip: 'Save prompt',
                    ),
                  ],
                ),
              ),
              maxLines: 3,
              onSubmitted: (_) => _updateOllamaConfig(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prompt Guidelines:',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Must contain {TEXT} placeholder\n'
                    '• Be specific about output format\n'
                    '• Request only corrected text without explanations\n'
                    '• Works best with German grammar correction',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testOllamaConnection,
                    icon: Icon(Icons.network_check),
                    label: Text('Test Ollama'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showOllamaDebugInfo,
                  icon: Icon(Icons.info),
                  label: Text('Debug Info'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isOllamaHealthy ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isOllamaHealthy ? Colors.green : Colors.red,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isOllamaHealthy ? Icons.check_circle : Icons.error,
                        color: _isOllamaHealthy ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isCheckingHealth 
                              ? 'Checking Ollama status...'
                              : _isOllamaHealthy 
                                  ? 'Ollama is healthy and model is available'
                                  : 'Ollama is not reachable or model not found',
                          style: TextStyle(
                            color: _isOllamaHealthy ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_isCheckingHealth) ...[
                    const SizedBox(height: 8),
                    Text(
                      'URL: ${_ollamaUrlController.text.isNotEmpty ? _ollamaUrlController.text : 'Not configured'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Model: ${_ollamaModelController.text.isNotEmpty ? _ollamaModelController.text : 'Not configured'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_availableModels.isNotEmpty)
                      Text(
                        'Available: ${_availableModels.length} models',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCheckButton() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Check all server health status',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!_isCheckingHealth)
              ElevatedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text('Check Health'),
                onPressed: _checkServerHealth,
              ),
            if (_isCheckingHealth)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowFastApiSettings() {
    return _currentMode == GrammarCorrectionMode.onlineOnly ||
           _currentMode == GrammarCorrectionMode.hybrid;
  }

  bool _shouldShowOllamaSettings() {
    return _currentMode == GrammarCorrectionMode.ollamaOnly ||
           _currentMode == GrammarCorrectionMode.hybridOllama;
  }

  String _getModeTitle(GrammarCorrectionMode mode) {
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'FastAPI Only';
      case GrammarCorrectionMode.offlineOnly:
        return 'Offline Only';
      case GrammarCorrectionMode.ollamaOnly:
        return 'Ollama Only';
      case GrammarCorrectionMode.hybrid:
        return 'Hybrid FastAPI (Recommended)';
      case GrammarCorrectionMode.hybridOllama:
        return 'Hybrid Ollama';
    }
  }

  String _getModeDescription(GrammarCorrectionMode mode) {
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'Always use FastAPI server-based correction. Requires internet connection.';
      case GrammarCorrectionMode.offlineOnly:
        return 'Always use local correction. Works without internet.';
      case GrammarCorrectionMode.ollamaOnly:
        return 'Always use Ollama AI model. Requires local Ollama installation.';
      case GrammarCorrectionMode.hybrid:
        return 'Try FastAPI server first, fallback to local if server unavailable.';
      case GrammarCorrectionMode.hybridOllama:
        return 'Try Ollama first, fallback to local if Ollama unavailable.';
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
        modelName: 'dummy', // We just need the URL for fetching models
      );
      
      final models = await testProvider.getAvailableModels();
      setState(() {
        _availableModels = models;
        _isLoadingModels = false;
      });
      
      debugPrint('Loaded ${models.length} available models: $models');
    } catch (e) {
      debugPrint('Failed to load models: $e');
      setState(() {
        _availableModels = [];
        _isLoadingModels = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Grammar Correction Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSttEngineSelector(),
            const SizedBox(height: 16),
            _buildModeSelector(),
            const SizedBox(height: 16),
            if (_shouldShowFastApiSettings())
              _buildServerSettings(),
            if (_shouldShowFastApiSettings())
              const SizedBox(height: 16),
            if (_shouldShowOllamaSettings())
              _buildOllamaSettings(),
            if (_shouldShowOllamaSettings())
              const SizedBox(height: 16),
            if (_currentMode != GrammarCorrectionMode.offlineOnly)
              _buildHealthCheckButton(),
            if (_currentMode != GrammarCorrectionMode.offlineOnly)
              const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _settingsService.resetToDefaults();
                  _loadSettings();
                  _showSnackBar('Settings reset to defaults');
                },
                icon: Icon(Icons.restore),
                label: Text('Reset to Defaults'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
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
    _serverUrlController.dispose();
    _ollamaUrlController.dispose();
    _ollamaModelController.dispose();
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
    return WillPopScope(
      onWillPop: () async => _isComplete || _error != null,
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