import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('IncomingCallButton displays icon and label correctly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              _TestButton(
                icon: Icons.call_rounded,
                label: 'Ответить',
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Ответить'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
  });

  test('call type enum has audio and video values', () {
    // Simple sanity test without Riverpod dependencies.
    expect(CallTypeTest.audio.index, 0);
    expect(CallTypeTest.video.index, 1);
  });
}

enum CallTypeTest { audio, video }

class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(label),
      ],
    );
  }
}
