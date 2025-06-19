import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/ml/german_gec_service.dart';

class GECTextField extends StatefulWidget {
  final String? hintText;
  final Function(String)? onTextChanged;
  final Function(GECResult)? onCorrectionResult;
  final bool enableRealTimeCorrection;
  final Duration correctionDelay;
  
  const GECTextField({
    Key? key,
    this.hintText,
    this.onTextChanged,
    this.onCorrectionResult,
    this.enableRealTimeCorrection = true,
    this.correctionDelay = const Duration(milliseconds: 1000),
  }) : super(key: key);
  
  @override
  State<GECTextField> createState() => _GECTextFieldState();
}

class _GECTextFieldState extends State<GECTextField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GermanGECService _gecService = GermanGECService();
  
  Timer? _correctionTimer;
  GECResult? _lastResult;
  bool _isProcessing = false;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeGEC();
    _controller.addListener(_onTextChanged);
  }
  
  Future<void> _initializeGEC() async {
    try {
      await _gecService.initialize();
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Failed to initialize GEC: $e');
      _showError('Grammatikkorrektur nicht verfügbar');
    }
  }
  
  void _onTextChanged() {
    final text = _controller.text;
    widget.onTextChanged?.call(text);
    
    if (widget.enableRealTimeCorrection && 
        _isInitialized && 
        text.trim().isNotEmpty) {
      _scheduleCorrection();
    }
  }
  
  void _scheduleCorrection() {
    _correctionTimer?.cancel();
    _correctionTimer = Timer(widget.correctionDelay, () {
      _performCorrection();
    });
  }
  
  Future<void> _performCorrection() async {
    if (_isProcessing || !_isInitialized) return;
    
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final result = await _gecService.correctText(text);
      
      setState(() {
        _lastResult = result;
        _isProcessing = false;
      });
      
      widget.onCorrectionResult?.call(result);
      
      if (result.hasCorrections) {
        _showCorrectionSuggestion(result);
      }
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      print('Correction error: $e');
    }
  }
  
  void _showCorrectionSuggestion(GECResult result) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Korrekturvorschlag:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(result.correctedText),
            Text(
              'Vertrauen: ${(result.confidence * 100).toStringAsFixed(1)}% | ${result.inferenceTimeMs}ms',
              style: TextStyle(fontSize: 12, color: Colors.grey[300]),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Übernehmen',
          onPressed: () => _applySuggestion(result.correctedText),
        ),
        duration: Duration(seconds: 5),
        backgroundColor: Colors.blue[700],
      ),
    );
  }
  
  void _applySuggestion(String correctedText) {
    _controller.text = correctedText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: correctedText.length),
    );
  }
  
  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText ?? 'Text eingeben...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: _buildSuffixIcons(),
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
          maxLines: null,
          minLines: 3,
          textInputAction: TextInputAction.newline,
        ),
        if (_lastResult != null) _buildResultIndicator(),
      ],
    );
  }
  
  Widget _buildSuffixIcons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isProcessing)
          Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (!_isInitialized)
          Icon(Icons.warning, color: Colors.orange),
        if (_isInitialized && !_isProcessing)
          IconButton(
            icon: Icon(Icons.spellcheck),
            onPressed: _performCorrection,
            tooltip: 'Grammatik prüfen',
          ),
      ],
    );
  }
  
  Widget _buildResultIndicator() {
    final result = _lastResult!;
    
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.hasCorrections ? Colors.blue[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.hasCorrections ? Colors.blue : Colors.green,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.hasCorrections ? Icons.edit : Icons.check_circle,
            color: result.hasCorrections ? Colors.blue : Colors.green,
            size: 20,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.hasCorrections 
                    ? 'Korrekturen verfügbar'
                    : 'Text ist korrekt',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: result.hasCorrections ? Colors.blue[700] : Colors.green[700],
                  ),
                ),
                if (result.hasCorrections)
                  Text(
                    result.correctedText,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                Text(
                  'Vertrauen: ${(result.confidence * 100).toStringAsFixed(1)}% • ${result.inferenceTimeMs}ms',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          if (result.hasCorrections)
            TextButton(
              onPressed: () => _applySuggestion(result.correctedText),
              child: Text('Übernehmen'),
            ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _correctionTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _gecService.dispose();
    super.dispose();
  }
}