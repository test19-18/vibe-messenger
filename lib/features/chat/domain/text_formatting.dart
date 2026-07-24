enum TextFormat { plain, bold, italic, code }

class FormattedSegment {
  const FormattedSegment(this.text, this.format);

  final String text;
  final TextFormat format;
}

List<FormattedSegment> parseSimpleFormatting(String source) {
  final pattern = RegExp(r'(\*\*[^*\n]+\*\*|_[^_\n]+_|`[^`\n]+`)');
  final segments = <FormattedSegment>[];
  var cursor = 0;
  for (final match in pattern.allMatches(source)) {
    if (match.start > cursor) {
      segments.add(
        FormattedSegment(
          source.substring(cursor, match.start),
          TextFormat.plain,
        ),
      );
    }
    final token = match.group(0)!;
    if (token.startsWith('**')) {
      segments.add(
        FormattedSegment(token.substring(2, token.length - 2), TextFormat.bold),
      );
    } else if (token.startsWith('_')) {
      segments.add(
        FormattedSegment(
          token.substring(1, token.length - 1),
          TextFormat.italic,
        ),
      );
    } else {
      segments.add(
        FormattedSegment(token.substring(1, token.length - 1), TextFormat.code),
      );
    }
    cursor = match.end;
  }
  if (cursor < source.length) {
    segments.add(FormattedSegment(source.substring(cursor), TextFormat.plain));
  }
  return segments.isEmpty
      ? <FormattedSegment>[FormattedSegment(source, TextFormat.plain)]
      : List.unmodifiable(segments);
}
