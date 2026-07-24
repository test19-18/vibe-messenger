import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chat/domain/text_formatting.dart';

void main() {
  test('parses bold, italic and code without code generation', () {
    final segments = parseSimpleFormatting('Обычный **жирный** _курсив_ `код`');

    expect(segments.map((segment) => segment.format), [
      TextFormat.plain,
      TextFormat.bold,
      TextFormat.plain,
      TextFormat.italic,
      TextFormat.plain,
      TextFormat.code,
    ]);
    expect(
      segments.map((segment) => segment.text).join(),
      'Обычный жирный курсив код',
    );
  });
}
