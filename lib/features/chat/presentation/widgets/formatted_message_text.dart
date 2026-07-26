import 'package:flutter/material.dart';

import '../../domain/text_formatting.dart';

class FormattedMessageText extends StatelessWidget {
  const FormattedMessageText({
    required this.text,
    required this.style,
    super.key,
    this.trailingGap = 0,
  });

  final String text;
  final TextStyle style;

  /// Blank space reserved at the end of the last line.
  ///
  /// The bubble overlays its timestamp there, which is what lets short messages
  /// keep the time on the same line instead of pushing it onto its own row.
  final double trailingGap;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          ...parseSimpleFormatting(text).map((segment) {
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
          }),
          if (trailingGap > 0)
            WidgetSpan(
              alignment: PlaceholderAlignment.bottom,
              child: SizedBox(width: trailingGap, height: 1),
            ),
        ],
      ),
    );
  }
}
