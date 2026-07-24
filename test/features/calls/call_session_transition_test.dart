import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/calls/domain/call_models.dart';

void main() {
  group('CallSessionTransition', () {
    test('idle → ringingOutgoing is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.idle,
          to: CallStatus.ringingOutgoing,
        ),
        isTrue,
      );
    });

    test('idle → ringingIncoming is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.idle,
          to: CallStatus.ringingIncoming,
        ),
        isTrue,
      );
    });

    test('ringingOutgoing → connecting is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingOutgoing,
          to: CallStatus.connecting,
        ),
        isTrue,
      );
    });

    test('ringingOutgoing → cancelled is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingOutgoing,
          to: CallStatus.cancelled,
        ),
        isTrue,
      );
    });

    test('ringingOutgoing → busy is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingOutgoing,
          to: CallStatus.busy,
        ),
        isTrue,
      );
    });

    test(
      'ringingOutgoing → accepted is NOT legal (must go through connecting)',
      () {
        expect(
          CallSessionTransition.canTransition(
            from: CallStatus.ringingOutgoing,
            to: CallStatus.accepted,
          ),
          isFalse,
        );
      },
    );

    test('ringingIncoming → accepted is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingIncoming,
          to: CallStatus.accepted,
        ),
        isTrue,
      );
    });

    test('ringingIncoming → declined is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingIncoming,
          to: CallStatus.declined,
        ),
        isTrue,
      );
    });

    test('ringingIncoming → missed is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.ringingIncoming,
          to: CallStatus.missed,
        ),
        isTrue,
      );
    });

    test('connecting → accepted is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.connecting,
          to: CallStatus.accepted,
        ),
        isTrue,
      );
    });

    test('connecting → failed is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.connecting,
          to: CallStatus.failed,
        ),
        isTrue,
      );
    });

    test('accepted → completed is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.accepted,
          to: CallStatus.completed,
        ),
        isTrue,
      );
    });

    test('accepted → reconnecting is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.accepted,
          to: CallStatus.reconnecting,
        ),
        isTrue,
      );
    });

    test('reconnecting → accepted is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.reconnecting,
          to: CallStatus.accepted,
        ),
        isTrue,
      );
    });

    test('reconnecting → failed is legal', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.reconnecting,
          to: CallStatus.failed,
        ),
        isTrue,
      );
    });

    test('completed → any is NOT legal (terminal state)', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.completed,
          to: CallStatus.accepted,
        ),
        isFalse,
      );
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.completed,
          to: CallStatus.reconnecting,
        ),
        isFalse,
      );
    });

    test('missed → any is NOT legal (terminal state)', () {
      expect(
        CallSessionTransition.canTransition(
          from: CallStatus.missed,
          to: CallStatus.accepted,
        ),
        isFalse,
      );
    });

    test(
      'apply returns new session with updated status on legal transition',
      () {
        final session = CallSession(
          id: 'call-1',
          conversationId: 'conv-1',
          callerId: 'user-a',
          calleeId: 'user-b',
          type: CallType.video,
          status: CallStatus.ringingIncoming,
          createdAt: DateTime.now(),
        );

        final accepted = CallSessionTransition.apply(
          session: session,
          to: CallStatus.accepted,
          acceptedAt: DateTime.now(),
        );
        expect(accepted.status, CallStatus.accepted);
        expect(accepted.acceptedAt, isNotNull);
      },
    );

    test('apply throws StateError on illegal transition', () {
      final session = CallSession(
        id: 'call-1',
        conversationId: 'conv-1',
        callerId: 'user-a',
        calleeId: 'user-b',
        type: CallType.video,
        status: CallStatus.completed,
        createdAt: DateTime.now(),
      );

      expect(
        () => CallSessionTransition.apply(
          session: session,
          to: CallStatus.accepted,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('terminal states have no outgoing transitions', () {
      for (final terminal in [
        CallStatus.completed,
        CallStatus.missed,
        CallStatus.declined,
        CallStatus.cancelled,
        CallStatus.busy,
        CallStatus.failed,
      ]) {
        expect(
          CallSessionTransition.transition(
            from: terminal,
            to: CallStatus.accepted,
          ),
          isNull,
        );
        expect(
          CallSessionTransition.transition(from: terminal, to: CallStatus.idle),
          isNull,
        );
      }
    });
  });
}
