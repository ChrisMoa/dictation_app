import 'package:flutter/material.dart';
import 'package:dictation_app/core/services/settings_service.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';
import 'package:dictation_app/core/services/hybrid_grammar_provider.dart';
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
  bool _isServerHealthy = false;
  bool _isCheckingHealth = false;
  
  final TextEditingController _serverUrlController = TextEditingController();

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
      _serverUrlController.text = _serverUrl;
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
          _isServerHealthy = status['online_available'] ?? false;
        });
      }
    } catch (e) {
      setState(() {
        _isServerHealthy = false;
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

    _showSnackBar('Server URL updated successfully');
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
              'Server Configuration',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
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
                        ? 'Checking server status...'
                        : _isServerHealthy 
                            ? 'Server is healthy and ready'
                            : 'Server is not reachable',
                    style: TextStyle(
                      color: _isServerHealthy ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                if (!_isCheckingHealth)
                  IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: _checkServerHealth,
                    tooltip: 'Check server health',
                  ),
                if (_isCheckingHealth)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getModeTitle(GrammarCorrectionMode mode) {
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'Online Only';
      case GrammarCorrectionMode.offlineOnly:
        return 'Offline Only';
      case GrammarCorrectionMode.hybrid:
        return 'Hybrid (Recommended)';
    }
  }

  String _getModeDescription(GrammarCorrectionMode mode) {
    switch (mode) {
      case GrammarCorrectionMode.onlineOnly:
        return 'Always use server-based correction. Requires internet connection.';
      case GrammarCorrectionMode.offlineOnly:
        return 'Always use local correction. Works without internet.';
      case GrammarCorrectionMode.hybrid:
        return 'Try server first, fallback to local if server unavailable.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Grammar Correction Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildModeSelector(),
            const SizedBox(height: 16),
            if (_currentMode != GrammarCorrectionMode.offlineOnly)
              _buildServerSettings(),
            const Spacer(),
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
    super.dispose();
  }
} 