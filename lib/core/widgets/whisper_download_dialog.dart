import 'package:flutter/material.dart';

/// Dialog that shows Whisper model download progress
class WhisperDownloadDialog extends StatefulWidget {
  final String modelName;
  final Future<void> Function(Function(double, int, int) onProgress) downloadFuture;
  
  const WhisperDownloadDialog({
    super.key,
    required this.modelName,
    required this.downloadFuture,
  });

  @override
  State<WhisperDownloadDialog> createState() => _WhisperDownloadDialogState();
}

class _WhisperDownloadDialogState extends State<WhisperDownloadDialog> {
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
      await widget.downloadFuture((progress, downloaded, total) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _downloaded = downloaded;
            _total = total;
            _status = 'Lade Whisper ${widget.modelName} Modell...';
          });
        }
      });
      
      if (mounted) {
        setState(() {
          _isComplete = true;
          _status = 'Download abgeschlossen!';
        });
        
        // Auto-close after 1 second
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
