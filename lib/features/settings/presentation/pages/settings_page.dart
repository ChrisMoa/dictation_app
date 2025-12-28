import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';
import 'package:dictation_app/core/theme/components/components.dart';
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

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late SettingsService _settingsService;
  late TabController _tabController;

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
    _tabController = TabController(length: 2, vsync: this);
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
    setState(() => _isCheckingHealth = true);

    try {
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: _ollamaUrl,
        modelName: _ollamaModel,
        customPrompt: _ollamaPromptController.text,
      );

      final isHealthy = await testProvider.isServerHealthy();
      setState(() => _isOllamaHealthy = isHealthy);
    } catch (e) {
      setState(() => _isOllamaHealthy = false);
    } finally {
      setState(() => _isCheckingHealth = false);
    }
  }

  Future<void> _loadAvailableModels() async {
    final url = _ollamaUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoadingModels = true);

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
    setState(() => _textProcessingMode = newMode);

    if (newMode == TextProcessingMode.ollamaEnabled) {
      _checkOllamaHealth();
      _loadAvailableModels();
    }

    _showSnackBar(newMode == TextProcessingMode.disabled 
      ? 'Textverarbeitung deaktiviert' 
      : 'Ollama aktiviert');
  }

  Future<void> _updateSttEngine(SttEngine newEngine) async {
    await _settingsService.setSttEngine(newEngine);
    setState(() => _currentSttEngine = newEngine);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RestartDialog(
          engineName: newEngine == SttEngine.whisper 
            ? 'Whisper (Offline)' 
            : 'Google STT (Online)',
        ),
      );
    }
  }

  Future<void> _updateWhisperModel(WhisperModelSize newModel) async {
    await _settingsService.setWhisperModelSize(newModel);
    setState(() => _currentWhisperModel = newModel);
    _showSnackBar('Modell geändert - bitte herunterladen');
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
  }

  Future<void> _saveOllamaUrl() async {
    final newUrl = _ollamaUrlController.text.trim();
    if (newUrl.isEmpty) {
      _showSnackBar('URL darf nicht leer sein', isError: true);
      return;
    }

    await _settingsService.setOllamaUrl(newUrl);
    setState(() => _ollamaUrl = newUrl);
    _showSnackBar('URL gespeichert');
    await _testOllamaConnection();
  }

  Future<void> _saveOllamaModel() async {
    final newModel = _ollamaModelController.text.trim();
    if (newModel.isEmpty) {
      _showSnackBar('Modell darf nicht leer sein', isError: true);
      return;
    }

    await _settingsService.setOllamaModel(newModel);
    setState(() => _ollamaModel = newModel);
    _showSnackBar('Modell gespeichert');
  }

  Future<void> _saveOllamaPrompt() async {
    final newPrompt = _ollamaPromptController.text.trim();
    if (newPrompt.isEmpty || !newPrompt.contains('{TEXT}')) {
      _showSnackBar('Prompt muss {TEXT} Platzhalter enthalten', isError: true);
      return;
    }

    await _settingsService.setOllamaPrompt(newPrompt);
    _showSnackBar('Prompt gespeichert');
  }

  Future<void> _testOllamaConnection() async {
    final url = _ollamaUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isCheckingHealth = true);

    try {
      final testProvider = OllamaGrammarProvider(
        ollamaUrl: url,
        modelName: 'dummy',
      );

      final models = await testProvider.getAvailableModels();
      setState(() {
        _isOllamaHealthy = models.isNotEmpty;
        _isCheckingHealth = false;
        _availableModels = models;
      });

      _showSnackBar(
        models.isNotEmpty 
          ? '${models.length} Modelle gefunden' 
          : 'Keine Modelle gefunden',
        isError: models.isEmpty,
      );
    } catch (e) {
      setState(() {
        _isOllamaHealthy = false;
        _isCheckingHealth = false;
        _availableModels = [];
      });
      _showSnackBar('Verbindung fehlgeschlagen', isError: true);
    }
  }

  Future<void> _downloadWhisperModel() async {
    final modelInfo = _getModelInfo(_currentWhisperModel);
    String modelName;

    switch (_currentWhisperModel) {
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

    if (modelExists && mounted) {
      final size = await WhisperDownloadService.getModelSize(modelName, modelDir);
      final shouldRedownload = await showDialog<bool>(
        context: context,
        builder: (context) => _ModelExistsDialog(
          modelTitle: modelInfo['title']!,
          sizeInMb: (size! / 1024 / 1024).toStringAsFixed(1),
        ),
      );

      if (shouldRedownload != true) return;
    }

    if (mounted) {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _WhisperDownloadDialog(
          modelName: modelName,
          modelDir: modelDir,
        ),
      );

      if (result == true) {
        _showSnackBar('${modelInfo['title']} heruntergeladen');
      }
    }
  }

  Map<String, String> _getModelInfo(WhisperModelSize size) {
    switch (size) {
      case WhisperModelSize.tiny:
        return {'title': 'Tiny', 'size': '~75 MB', 'desc': 'Schnell, niedrige Qualität'};
      case WhisperModelSize.base:
        return {'title': 'Base', 'size': '~150 MB', 'desc': 'Gute Balance (Empfohlen)'};
      case WhisperModelSize.small:
        return {'title': 'Small', 'size': '~500 MB', 'desc': 'Beste Qualität'};
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ollamaUrlController.dispose();
    _ollamaModelController.dispose();
    _ollamaPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Spracherkennung'),
            Tab(text: 'Textverarbeitung'),
          ],
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: isDark 
            ? AppColors.textSecondaryDark 
            : AppColors.textSecondaryLight,
          indicatorColor: theme.colorScheme.primary,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSttTab(),
          _buildTextProcessingTab(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: AppButton(
            label: 'Alle Einstellungen zurücksetzen',
            icon: Icons.restore_rounded,
            style: AppButtonStyle.secondary,
            expanded: true,
            onPressed: () async {
              await _settingsService.resetToDefaults();
              _loadSettings();
              _showSnackBar('Einstellungen zurückgesetzt');
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSttTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Engine selection
          AppSectionCard(
            title: 'STT Engine',
            subtitle: 'Wähle die Spracherkennungs-Engine',
            icon: Icons.mic_rounded,
            child: Column(
              children: [
                _EngineOption(
                  title: 'Whisper (Offline)',
                  subtitle: 'Lokales Modell, funktioniert ohne Internet',
                  icon: Icons.offline_bolt_rounded,
                  isSelected: _currentSttEngine == SttEngine.whisper,
                  recommended: true,
                  onTap: () => _updateSttEngine(SttEngine.whisper),
                ),
                const SizedBox(height: AppSpacing.sm),
                _EngineOption(
                  title: 'Google STT (Online)',
                  subtitle: 'Google Cloud, benötigt Internet',
                  icon: Icons.cloud_rounded,
                  isSelected: _currentSttEngine == SttEngine.googleStt,
                  onTap: () => _updateSttEngine(SttEngine.googleStt),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: AppSpacing.md),
          
          // Whisper settings (if selected)
          if (_currentSttEngine == SttEngine.whisper)
            AppSectionCard(
              title: 'Whisper Modell',
              subtitle: 'Wähle die Modellgröße',
              icon: Icons.tune_rounded,
              actions: [
                AppButton(
                  label: 'Laden',
                  icon: Icons.download_rounded,
                  onPressed: _downloadWhisperModel,
                ),
              ],
              child: Column(
                children: WhisperModelSize.values.map((size) {
                  final info = _getModelInfo(size);
                  return _ModelOption(
                    title: info['title']!,
                    subtitle: '${info['size']} - ${info['desc']}',
                    isSelected: _currentWhisperModel == size,
                    isRecommended: size == WhisperModelSize.base,
                    onTap: () => _updateWhisperModel(size),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextProcessingTab() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enable/Disable
          AppSectionCard(
            title: 'Ollama Textverarbeitung',
            subtitle: 'KI-gestützte Textkorrektur',
            icon: Icons.auto_fix_high_rounded,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _textProcessingMode == TextProcessingMode.ollamaEnabled
                      ? 'Aktiviert'
                      : 'Deaktiviert',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    _textProcessingMode == TextProcessingMode.ollamaEnabled
                      ? 'Text wird nach der Erkennung verarbeitet'
                      : 'Nur Spracherkennung ohne Nachbearbeitung',
                  ),
                  value: _textProcessingMode == TextProcessingMode.ollamaEnabled,
                  onChanged: (value) => _updateTextProcessingMode(
                    value ? TextProcessingMode.ollamaEnabled : TextProcessingMode.disabled,
                  ),
                ),
              ],
            ),
          ),
          
          // Ollama config (if enabled)
          if (_textProcessingMode == TextProcessingMode.ollamaEnabled) ...[
            const SizedBox(height: AppSpacing.md),
            
            // Connection status
            AppStatusBanner(
              type: _isOllamaHealthy ? AppStatusType.success : AppStatusType.neutral,
              message: _isCheckingHealth 
                ? 'Verbindung wird geprüft...'
                : _isOllamaHealthy 
                  ? 'Ollama verbunden'
                  : 'Nicht verbunden',
              isLoading: _isCheckingHealth,
              onAction: _testOllamaConnection,
              actionLabel: 'Testen',
            ),
            
            const SizedBox(height: AppSpacing.md),
            
            // Server config
            AppSectionCard(
              title: 'Server Konfiguration',
              icon: Icons.dns_rounded,
              child: Column(
                children: [
                  TextField(
                    controller: _ollamaUrlController,
                    decoration: InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://localhost:11434',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_rounded),
                        onPressed: _saveOllamaUrl,
                        tooltip: 'Speichern',
                      ),
                    ),
                    onSubmitted: (_) => _saveOllamaUrl(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  
                  // Model dropdown
                  if (_availableModels.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _availableModels.contains(_ollamaModel) ? _ollamaModel : null,
                      decoration: const InputDecoration(
                        labelText: 'Verfügbare Modelle',
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
                    const SizedBox(height: AppSpacing.sm),
                  ] else if (_isLoadingModels) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text('Lade Modelle...'),
                        ],
                      ),
                    ),
                  ],
                  
                  TextField(
                    controller: _ollamaModelController,
                    decoration: InputDecoration(
                      labelText: 'Modell Name',
                      hintText: 'llama3.2:3b',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save_rounded),
                        onPressed: _saveOllamaModel,
                        tooltip: 'Speichern',
                      ),
                    ),
                    onSubmitted: (_) => _saveOllamaModel(),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: AppSpacing.md),
            
            // Prompt template
            AppSectionCard(
              title: 'Prompt Vorlage',
              icon: Icons.edit_note_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<OllamaPromptTemplate>(
                    value: _currentTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Vorlage wählen',
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
                      if (value != null) _updatePromptTemplate(value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _settingsService.getTemplateDescription(_currentTemplate),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _ollamaPromptController,
                    decoration: InputDecoration(
                      labelText: 'Prompt',
                      helperText: '{TEXT} als Platzhalter verwenden',
                      enabled: _currentTemplate == OllamaPromptTemplate.custom,
                      suffixIcon: _currentTemplate == OllamaPromptTemplate.custom
                        ? IconButton(
                            icon: const Icon(Icons.save_rounded),
                            onPressed: _saveOllamaPrompt,
                            tooltip: 'Speichern',
                          )
                        : null,
                    ),
                    maxLines: 4,
                    onSubmitted: (_) => _saveOllamaPrompt(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Helper Widgets

class _EngineOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool recommended;
  final VoidCallback onTap;

  const _EngineOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    this.recommended = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isSelected 
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isSelected 
                ? theme.colorScheme.primary 
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected 
                  ? theme.colorScheme.primary 
                  : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isSelected ? theme.colorScheme.primary : null,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Empfohlen',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isRecommended;
  final VoidCallback onTap;

  const _ModelOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    this.isRecommended = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RadioListTile<bool>(
      value: true,
      groupValue: isSelected,
      onChanged: (_) => onTap(),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Text(title),
          if (isRecommended) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Empfohlen',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
    );
  }
}

class _RestartDialog extends StatelessWidget {
  final String engineName;

  const _RestartDialog({required this.engineName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.restart_alt_rounded, size: 48, color: AppColors.warning),
      title: const Text('Neustart erforderlich'),
      content: Text(
        'Die Engine wurde auf $engineName umgestellt.\n\n'
        'Bitte starte die App neu, damit die Änderung wirksam wird.',
      ),
      actions: [
        AppButton(
          label: 'OK',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _ModelExistsDialog extends StatelessWidget {
  final String modelTitle;
  final String sizeInMb;

  const _ModelExistsDialog({
    required this.modelTitle,
    required this.sizeInMb,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.check_circle_rounded, size: 48, color: AppColors.success),
      title: const Text('Modell vorhanden'),
      content: Text(
        'Das $modelTitle Modell ist bereits heruntergeladen.\n'
        'Größe: $sizeInMb MB\n\n'
        'Erneut herunterladen?',
      ),
      actions: [
        AppButton(
          label: 'Abbrechen',
          style: AppButtonStyle.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Erneut laden',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

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
              _status = 'Lade ${widget.modelName} Modell...';
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
        if (mounted) Navigator.of(context).pop(true);
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
    final theme = Theme.of(context);

    return PopScope(
      canPop: _isComplete || _error != null,
      child: AlertDialog(
        icon: Icon(
          _isComplete 
            ? Icons.check_circle_rounded 
            : _error != null 
              ? Icons.error_rounded 
              : Icons.downloading_rounded,
          size: 48,
          color: _isComplete 
            ? AppColors.success 
            : _error != null 
              ? AppColors.error 
              : theme.colorScheme.primary,
        ),
        title: Text(
          _isComplete 
            ? 'Fertig!' 
            : _error != null 
              ? 'Fehler' 
              : 'Download läuft',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            if (_error == null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    style: theme.textTheme.labelLarge,
                  ),
                  if (_total > 0)
                    Text(
                      '${_formatBytes(_downloaded)} / ${_formatBytes(_total)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ] else ...[
              Text(
                _error!,
                style: TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Schließen',
                style: AppButtonStyle.secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
