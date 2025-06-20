import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/hybrid_grammar_provider.dart';
import 'package:dictation_app/core/services/ollama_grammar_provider.dart';
import 'package:dictation_app/core/dependency_injection.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late SettingsService _settingsService;
  late AIGrammarService _aiGrammarService;
  
  GrammarCorrectionMode _currentMode = GrammarCorrectionMode.hybrid;
  String _serverUrl = '';
  String _ollamaUrl = '';
  String _ollamaModel = '';
  bool _isServerHealthy = false;
  bool _isOllamaHealthy = false;
  bool _isCheckingHealth = false;
  
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _ollamaUrlController = TextEditingController();
  final TextEditingController _ollamaModelController = TextEditingController();

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
      _serverUrl = _settingsService.serverUrl;
      _ollamaUrl = _settingsService.ollamaUrl;
      _ollamaModel = _settingsService.ollamaModel;
      _serverUrlController.text = _serverUrl;
      _ollamaUrlController.text = _ollamaUrl;
      _ollamaModelController.text = _ollamaModel;
    });
    _checkServerHealth();
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
    
    if (newUrl.isEmpty) {
      _showSnackBar('Ollama URL cannot be empty', isError: true);
      return;
    }
    
    if (newModel.isEmpty) {
      _showSnackBar('Ollama model cannot be empty', isError: true);
      return;
    }

    await _settingsService.setOllamaUrl(newUrl);
    await _settingsService.setOllamaModel(newModel);
    
    setState(() {
      _ollamaUrl = newUrl;
      _ollamaModel = newModel;
    });

    // Update the hybrid provider with new Ollama config
    final provider = _aiGrammarService.currentProvider;
    if (provider is HybridGrammarProvider) {
      provider.updateOllamaConfig(newUrl, newModel);
      _checkServerHealth();
    }

    _showSnackBar('Ollama configuration updated successfully');
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
      debugPrint('Creating test Ollama provider with URL: $url, Model: $model');
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: url,
        modelName: model,
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
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ollamaModelController,
              decoration: InputDecoration(
                labelText: 'Ollama Model Name',
                hintText: 'llama3.2:3b',
                border: OutlineInputBorder(),
                helperText: 'Exact model name as shown in "ollama list"',
                suffixIcon: IconButton(
                  icon: Icon(Icons.save),
                  onPressed: _updateOllamaConfig,
                ),
              ),
              onSubmitted: (_) => _updateOllamaConfig(),
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
                color: _isOllamaHealthy ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
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