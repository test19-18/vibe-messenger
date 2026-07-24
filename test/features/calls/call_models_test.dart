import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/calls/domain/call_models.dart';

void main() {
  group('CallStatus', () {
    test('wireValue maps correctly to backend call_state column values', () {
      // Local-only statuses map to their closest persisted equivalent.
      expect(CallStatus.idle.wireValue, 'created');
      expect(CallStatus.ringingOutgoing.wireValue, 'ringing');
      expect(CallStatus.ringingIncoming.wireValue, 'ringing');
      expect(CallStatus.connecting.wireValue, 'accepted');
      expect(CallStatus.accepted.wireValue, 'connected');
      expect(CallStatus.reconnecting.wireValue, 'connected');
      expect(CallStatus.completed.wireValue, 'ended');
      expect(CallStatus.missed.wireValue, 'missed');
      expect(CallStatus.declined.wireValue, 'declined');
      expect(CallStatus.cancelled.wireValue, 'cancelled');
      expect(CallStatus.busy.wireValue, 'busy');
      expect(CallStatus.failed.wireValue, 'failed');
    });

    test('fromWireValue parses known DB state strings', () {
      expect(CallStatus.fromWireValue('created'), CallStatus.ringingOutgoing);
      expect(CallStatus.fromWireValue('ringing'), CallStatus.ringingOutgoing);
      expect(CallStatus.fromWireValue('accepted'), CallStatus.accepted);
      expect(CallStatus.fromWireValue('connected'), CallStatus.accepted);
      expect(CallStatus.fromWireValue('ended'), CallStatus.completed);
      expect(CallStatus.fromWireValue('missed'), CallStatus.missed);
      expect(CallStatus.fromWireValue('expired'), CallStatus.missed);
      expect(CallStatus.fromWireValue('declined'), CallStatus.declined);
      expect(CallStatus.fromWireValue('cancelled'), CallStatus.cancelled);
      expect(CallStatus.fromWireValue('busy'), CallStatus.busy);
      expect(CallStatus.fromWireValue('failed'), CallStatus.failed);
    });

    test('fromWireValue maps unknown state to failed (defensive)', () {
      expect(CallStatus.fromWireValue('unknown'), CallStatus.failed);
    });

    test(
      'fromWireValueDirectional disambiguates ringing/created by direction',
      () {
        expect(
          CallStatus.fromWireValueDirectional('ringing', isCaller: true),
          CallStatus.ringingOutgoing,
        );
        expect(
          CallStatus.fromWireValueDirectional('ringing', isCaller: false),
          CallStatus.ringingIncoming,
        );
        expect(
          CallStatus.fromWireValueDirectional('created', isCaller: true),
          CallStatus.ringingOutgoing,
        );
        expect(
          CallStatus.fromWireValueDirectional('created', isCaller: false),
          CallStatus.ringingIncoming,
        );
      },
    );

    test('isTerminal is true for ended states', () {
      expect(CallStatus.completed.isTerminal, isTrue);
      expect(CallStatus.missed.isTerminal, isTrue);
      expect(CallStatus.declined.isTerminal, isTrue);
      expect(CallStatus.cancelled.isTerminal, isTrue);
      expect(CallStatus.busy.isTerminal, isTrue);
      expect(CallStatus.failed.isTerminal, isTrue);
    });

    test('isTerminal is false for active and pending states', () {
      expect(CallStatus.idle.isTerminal, isFalse);
      expect(CallStatus.ringingOutgoing.isTerminal, isFalse);
      expect(CallStatus.ringingIncoming.isTerminal, isFalse);
      expect(CallStatus.accepted.isTerminal, isFalse);
      expect(CallStatus.connecting.isTerminal, isFalse);
      expect(CallStatus.reconnecting.isTerminal, isFalse);
    });

    test('wasNeverConnected is true for states before connection', () {
      expect(CallStatus.missed.wasNeverConnected, isTrue);
      expect(CallStatus.declined.wasNeverConnected, isTrue);
      expect(CallStatus.cancelled.wasNeverConnected, isTrue);
      expect(CallStatus.busy.wasNeverConnected, isTrue);
      expect(CallStatus.completed.wasNeverConnected, isFalse);
      expect(CallStatus.accepted.wasNeverConnected, isFalse);
    });
  });

  group('CallSession', () {
    final baseSession = CallSession(
      id: 'call-1',
      conversationId: 'conv-1',
      callerId: 'user-a',
      calleeId: 'user-b',
      type: CallType.video,
      status: CallStatus.idle,
      createdAt: DateTime.parse('2026-07-24T10:00:00Z'),
    );

    test('isCallerFor and isCalleeFor identify participant roles', () {
      expect(baseSession.isCallerFor('user-a'), isTrue);
      expect(baseSession.isCallerFor('user-b'), isFalse);
      expect(baseSession.isCalleeFor('user-b'), isTrue);
      expect(baseSession.isCalleeFor('user-a'), isFalse);
    });

    test('otherParticipantId returns the peer ID', () {
      expect(baseSession.otherParticipantId('user-a'), 'user-b');
      expect(baseSession.otherParticipantId('user-b'), 'user-a');
    });

    test('canConnectRoom requires accepted status + all connection params', () {
      expect(baseSession.canConnectRoom, isFalse);

      final withToken = baseSession.copyWith(
        status: CallStatus.accepted,
        roomName: 'room-1',
        serverUrl: 'wss://livekit.example.com',
        token: 'jwt-token',
      );
      expect(withToken.canConnectRoom, isTrue);

      // Without connection params, canConnectRoom should be false.
      final noConnection = baseSession.copyWith(
        status: CallStatus.accepted,
        roomName: 'room-1',
        serverUrl: 'wss://livekit.example.com',
        // token intentionally omitted
      );
      expect(noConnection.canConnectRoom, isFalse);
    });

    test('isActive is true for accepted and connecting states', () {
      expect(
        baseSession.copyWith(status: CallStatus.accepted).isActive,
        isTrue,
      );
      expect(
        baseSession.copyWith(status: CallStatus.connecting).isActive,
        isTrue,
      );
      expect(
        baseSession.copyWith(status: CallStatus.ringingOutgoing).isActive,
        isFalse,
      );
    });

    test('isRinging is true for ringing states', () {
      expect(
        baseSession.copyWith(status: CallStatus.ringingOutgoing).isRinging,
        isTrue,
      );
      expect(
        baseSession.copyWith(status: CallStatus.ringingIncoming).isRinging,
        isTrue,
      );
      expect(
        baseSession.copyWith(status: CallStatus.accepted).isRinging,
        isFalse,
      );
    });

    test('liveDurationSeconds returns null before acceptance', () {
      expect(baseSession.liveDurationSeconds, isNull);
    });

    test('liveDurationSeconds returns elapsed after acceptance', () {
      final accepted = baseSession.copyWith(
        status: CallStatus.accepted,
        acceptedAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      expect(accepted.liveDurationSeconds, isNotNull);
      expect(accepted.liveDurationSeconds! >= 29, isTrue);
    });

    test('fromMap parses a valid call map with DB column names', () {
      final session = CallSession.fromMap({
        'id': 'call-2',
        'conversation_id': 'conv-2',
        'caller_id': 'user-a',
        'callee_id': 'user-b',
        'media_kind': 'audio',
        'state': 'ringing',
        'created_at': '2026-07-24T10:00:00Z',
        'room_name': 'room-2',
        'server_url': 'wss://livekit.example.com',
        'token': 'jwt-abc',
      });
      expect(session.id, 'call-2');
      expect(session.type, CallType.audio);
      expect(session.status, CallStatus.ringingOutgoing);
      expect(session.roomName, 'room-2');
    });

    test('fromMap handles nullable conversation_id', () {
      final session = CallSession.fromMap({
        'id': 'call-9',
        'conversation_id': null,
        'caller_id': 'user-a',
        'callee_id': 'user-b',
        'media_kind': 'video',
        'state': 'connected',
        'created_at': '2026-07-24T10:00:00Z',
      });
      expect(session.conversationId, '');
      expect(session.type, CallType.video);
      expect(session.status, CallStatus.accepted);
    });

    test('fromMap throws on invalid media_kind', () {
      expect(
        () => CallSession.fromMap({
          'id': 'call-3',
          'conversation_id': 'conv-3',
          'caller_id': 'user-a',
          'callee_id': 'user-b',
          'media_kind': 'screen',
          'state': 'ringing',
          'created_at': '2026-07-24T10:00:00Z',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('toMap produces correct wire format without token', () {
      final session = baseSession.copyWith(
        status: CallStatus.accepted,
        roomName: 'room-1',
        serverUrl: 'wss://livekit.example.com',
        token: 'jwt-xyz',
        acceptedAt: DateTime.parse('2026-07-24T10:00:05Z'),
      );
      final map = session.toMap();
      expect(map['media_kind'], 'video');
      expect(map['state'], 'connected');
      expect(map['room_name'], 'room-1');
      // Token is intentionally excluded from toMap for security —
      // it must never be persisted or logged.
      expect(map.containsKey('token'), isFalse);
    });
  });

  group('CallRecord', () {
    test('isOutgoingFor identifies caller', () {
      final record = CallRecord(
        id: 'call-1',
        conversationId: 'conv-1',
        callerId: 'user-a',
        calleeId: 'user-b',
        type: CallType.audio,
        status: CallStatus.completed,
        createdAt: DateTime.now(),
        acceptedAt: DateTime.now().subtract(const Duration(seconds: 60)),
        endedAt: DateTime.now(),
        durationSeconds: 60,
      );
      expect(record.isOutgoingFor('user-a'), isTrue);
      expect(record.isOutgoingFor('user-b'), isFalse);
    });

    test('displayDurationSeconds uses server value when available', () {
      final record = CallRecord(
        id: 'call-1',
        conversationId: 'conv-1',
        callerId: 'user-a',
        calleeId: 'user-b',
        type: CallType.audio,
        status: CallStatus.completed,
        createdAt: DateTime.now(),
        durationSeconds: 120,
      );
      expect(record.displayDurationSeconds, 120);
    });

    test(
      'displayDurationSeconds computes from timestamps if no server value',
      () {
        final start = DateTime.now().subtract(const Duration(seconds: 45));
        final end = DateTime.now();
        final record = CallRecord(
          id: 'call-1',
          conversationId: 'conv-1',
          callerId: 'user-a',
          calleeId: 'user-b',
          type: CallType.audio,
          status: CallStatus.completed,
          createdAt: DateTime.now(),
          acceptedAt: start,
          endedAt: end,
        );
        expect(record.displayDurationSeconds, greaterThanOrEqualTo(44));
      },
    );

    test('displayDurationSeconds returns 0 for never-connected calls', () {
      final record = CallRecord(
        id: 'call-1',
        conversationId: 'conv-1',
        callerId: 'user-a',
        calleeId: 'user-b',
        type: CallType.audio,
        status: CallStatus.missed,
        createdAt: DateTime.now(),
      );
      expect(record.displayDurationSeconds, 0);
    });

    test('historyLabel maps status to display text', () {
      expect(
        CallRecord(
          id: 'c',
          conversationId: 'cv',
          callerId: 'a',
          calleeId: 'b',
          type: CallType.audio,
          status: CallStatus.completed,
          createdAt: DateTime.now(),
        ).historyLabel,
        'Завершён',
      );
      expect(
        CallRecord(
          id: 'c',
          conversationId: 'cv',
          callerId: 'a',
          calleeId: 'b',
          type: CallType.audio,
          status: CallStatus.missed,
          createdAt: DateTime.now(),
        ).historyLabel,
        'Пропущен',
      );
      expect(
        CallRecord(
          id: 'c',
          conversationId: 'cv',
          callerId: 'a',
          calleeId: 'b',
          type: CallType.audio,
          status: CallStatus.declined,
          createdAt: DateTime.now(),
        ).historyLabel,
        'Отклонён',
      );
    });
  });
}
