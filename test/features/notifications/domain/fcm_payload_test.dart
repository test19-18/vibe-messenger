import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/notifications/domain/fcm_payload.dart';

void main() {
  group('FcmPayload.fromData', () {
    test('returns null for empty map', () {
      expect(FcmPayload.fromData({}), isNull);
    });

    test('returns null for unknown type', () {
      expect(FcmPayload.fromData({'type': 'something_else'}), isNull);
    });

    test('returns null for missing type', () {
      expect(FcmPayload.fromData({'call_id': 'abc'}), isNull);
    });
  });

  group('MessagePayload', () {
    test('parses a complete message payload', () {
      final payload = FcmPayload.fromData({
        'type': 'message',
        'conversation_id': 'conv-123',
        'message_id': 'msg-456',
        'sender_id': 'user-789',
        'sender_name': 'Alice',
        'body_preview': 'Hello!',
        'is_group': 'false',
      });

      expect(payload, isA<MessagePayload>());
      final msg = payload as MessagePayload;
      expect(msg.type, FcmPayloadType.message);
      expect(msg.conversationId, 'conv-123');
      expect(msg.messageId, 'msg-456');
      expect(msg.senderId, 'user-789');
      expect(msg.senderName, 'Alice');
      expect(msg.bodyPreview, 'Hello!');
      expect(msg.isGroup, isFalse);
    });

    test('parses a group message payload', () {
      final payload = FcmPayload.fromData({
        'type': 'message',
        'conversation_id': 'conv-grp',
        'is_group': 'true',
      });

      expect(payload, isA<MessagePayload>());
      final msg = payload as MessagePayload;
      expect(msg.conversationId, 'conv-grp');
      expect(msg.isGroup, isTrue);
      // Optional fields default to empty.
      expect(msg.messageId, isEmpty);
      expect(msg.senderId, isEmpty);
      expect(msg.senderName, isEmpty);
      expect(msg.bodyPreview, isEmpty);
    });

    test('returns null when conversation_id is missing', () {
      expect(
        FcmPayload.fromData({'type': 'message', 'message_id': 'msg'}),
        isNull,
      );
    });

    test('fieldMap documents the expected server contract', () {
      expect(MessagePayload.fieldMap['type'], 'message');
      expect(MessagePayload.fieldMap['conversation_id'], contains('required'));
    });
  });

  group('IncomingCallPayload', () {
    test('parses a complete incoming_call payload', () {
      final payload = FcmPayload.fromData({
        'type': 'incoming_call',
        'call_id': 'call-abc',
        'room_name': 'room-xyz',
        'caller_id': 'caller-123',
        'caller_name': 'Bob',
        'media_kind': 'video',
        'conversation_id': 'conv-456',
      });

      expect(payload, isA<IncomingCallPayload>());
      final call = payload as IncomingCallPayload;
      expect(call.type, FcmPayloadType.incomingCall);
      expect(call.callId, 'call-abc');
      expect(call.roomName, 'room-xyz');
      expect(call.callerId, 'caller-123');
      expect(call.callerName, 'Bob');
      expect(call.mediaKind, 'video');
      expect(call.isVideo, isTrue);
      expect(call.conversationId, 'conv-456');
    });

    test('parses an audio call payload with minimal fields', () {
      final payload = FcmPayload.fromData({
        'type': 'incoming_call',
        'call_id': 'call-min',
        'room_name': 'room-min',
      });

      expect(payload, isA<IncomingCallPayload>());
      final call = payload as IncomingCallPayload;
      expect(call.callId, 'call-min');
      expect(call.roomName, 'room-min');
      expect(call.callerId, isEmpty);
      expect(call.callerName, isEmpty);
      expect(call.mediaKind, isEmpty);
      expect(call.isVideo, isFalse);
      expect(call.conversationId, isEmpty);
    });

    test('returns null when call_id is missing', () {
      expect(
        FcmPayload.fromData({'type': 'incoming_call', 'room_name': 'room-1'}),
        isNull,
      );
    });

    test('returns null when room_name is missing', () {
      expect(
        FcmPayload.fromData({'type': 'incoming_call', 'call_id': 'call-1'}),
        isNull,
      );
    });

    test('fieldMap documents the expected server contract', () {
      expect(IncomingCallPayload.fieldMap['type'], 'incoming_call');
      expect(IncomingCallPayload.fieldMap['call_id'], contains('required'));
      expect(IncomingCallPayload.fieldMap['room_name'], contains('required'));
    });
  });

  group('CallCancelledPayload', () {
    test('parses a call_cancelled payload', () {
      final payload = FcmPayload.fromData({
        'type': 'call_cancelled',
        'call_id': 'call-abc',
      });

      expect(payload, isA<CallCancelledPayload>());
      final cancelled = payload as CallCancelledPayload;
      expect(cancelled.type, FcmPayloadType.callCancelled);
      expect(cancelled.callId, 'call-abc');
    });

    test('returns null when call_id is missing', () {
      expect(FcmPayload.fromData({'type': 'call_cancelled'}), isNull);
    });

    test('fieldMap documents the expected server contract', () {
      expect(CallCancelledPayload.fieldMap['type'], 'call_cancelled');
      expect(CallCancelledPayload.fieldMap['call_id'], contains('required'));
    });
  });

  group('Defensive coercion', () {
    test('handles non-string values gracefully', () {
      final payload = FcmPayload.fromData({
        'type': 'message',
        'conversation_id': 12345, // non-string
        'is_group': true, // bool, not string
      });

      expect(payload, isA<MessagePayload>());
      final msg = payload as MessagePayload;
      expect(msg.conversationId, '12345');
      expect(msg.isGroup, isTrue);
    });

    test('handles null values gracefully', () {
      final payload = FcmPayload.fromData({
        'type': 'incoming_call',
        'call_id': 'call-1',
        'room_name': null,
      });

      expect(payload, isNull);
    });
  });
}
