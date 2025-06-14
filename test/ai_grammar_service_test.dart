import 'package:flutter_test/flutter_test.dart';
import 'package:dictation_app/core/services/ai_grammar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AIGrammarService Tests', () {
    late AIGrammarService grammarService;
    late SpacyProvider spacyProvider;

    setUp(() {
      grammarService = AIGrammarService();
      spacyProvider = SpacyProvider();
    });

    tearDown(() {
      spacyProvider.dispose();
    });

    group('Basic Functionality Tests', () {
      test('should initialize service', () {
        expect(grammarService, isNotNull);
        expect(grammarService.currentProviderName, equals('SpaCy Mobile'));
      });

      test('should handle empty text', () async {
        const input = '';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, equals(''));
        expect(result.confidence, equals(1.0));
        expect(result.hasCorrections, isFalse);
        expect(result.errors, isEmpty);
      });

      test('should handle single word', () async {
        const input = 'hallo';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, startsWith('H')); // Should capitalize
        expect(result.confidence, greaterThan(0.0));
        expect(result.errors.length, lessThanOrEqualTo(1)); // Might have capitalization error
      });
    });

    group('Sentence Processing Tests', () {
      test('should process multiple sentences', () async {
        const input = 'heute ist ein schöner tag. morgen wird es regnen.';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, startsWith('H')); // First sentence capitalized
        expect(result.correctedText, contains('. M')); // Second sentence capitalized
        expect(result.confidence, greaterThan(0.0));
      });

      test('should handle sentence boundaries', () async {
        const input = 'Das ist der erste Satz! Und hier ist der zweite.';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, contains('! '));
        expect(result.correctedText, contains('. '));
        expect(result.confidence, greaterThan(0.0));
      });
    });

    group('German Grammar Tests', () {
      test('should correct verb conjugation', () async {
        const input = 'ich gehen zum Laden';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, contains('gehe')); // Should correct verb form
        expect(result.errors, isNotEmpty);
        expect(result.errors.first.category, equals('Grammar'));
      });

      test('should handle noun capitalization', () async {
        const input = 'der hund läuft im park';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, contains('Hund'));
        expect(result.correctedText, contains('Park'));
        expect(result.errors, isNotEmpty);
      });

      test('should correct common German phrases', () async {
        const input = 'wird es regnen heute';
        
        final result = await grammarService.correctGermanText(input);

        expect(result.errors, isNotEmpty);
        expect(result.errors.first.replacements, isNotEmpty);
        expect(result.confidence, greaterThan(0.0));
      });
    });

    group('Error Handling Tests', () {
      test('should handle invalid input gracefully', () async {
        const input = '!@#\$%^&*()';  // Escaped $ character
        
        final result = await grammarService.correctGermanText(input);

        expect(result.correctedText, isNotEmpty);
        expect(result.confidence, greaterThan(0.0));
      });
    });

    group('Performance Tests', () {
      test('should process text within reasonable time', () async {
        final input = 'Dies ist ein Test Satz mit mehreren Wörtern. Hier ist ein zweiter Satz. Und noch ein dritter.';

        final stopwatch = Stopwatch()..start();
        final result = await grammarService.correctGermanText(input);
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(2000));
        expect(result.correctedText, isNotEmpty);
        expect(result.confidence, greaterThan(0.0));
      });
    });

    group('Resource Management Tests', () {
      test('should properly dispose resources', () async {
        final provider = SpacyProvider();
        await provider.correctText('Test');
        
        expect(() => provider.dispose(), returnsNormally);
      });
    });
  });
}

/// Helper extension for counting occurrences
extension StringExtension on String {
  Iterable<Match> allMatches(String pattern) {
    return RegExp(pattern).allMatches(this);
  }
} 