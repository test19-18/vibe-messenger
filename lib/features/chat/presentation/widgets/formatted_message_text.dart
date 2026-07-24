import 'package:flutter/material.dart';

import '../../domain/text_formatting.dart';

class FormattedMessageText extends StatelessWidget {
  const FormattedMessageText({
    required this.text,
    required this.style,
    super.key,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: parseSimpleFormatting(text).map((segment) {
          final segmentStyle = switch (segment.format) {
            TextFormat.bold => style.copyWith(fontWeight: FontWeight.w700),
            TextFormat.italic => style.copyWith(fontStyle: FontStyle.italic),
            TextFormat.code => style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.black.withValues(alpha: 0.18),
            ),
            TextFormat.plain => style,
          };
          return TextSpan(text: segment.text, style: segmentStyle);
        }).toList(),
      ),
    );
  }
}
