/// FCM data-payload domain models.
///
/// The server sends FCM **data** messages (not notification messages) so that
/// the client retains full control over UI presentation and call lifecycle.
/// Three payload types are supported:
///
/// * `message` — a new chat message arrived.
/// * `incoming_call` — a 1:1 call is ringing on this device.
/// * `call_cancelled` — the caller cancelled before the callee answered.
///
/// All parsing is defensive: missing or malformed fields produce `null` from
/// [FcmPayload.fromData] rather than throwing. The caller can then ignore the
/// corrupt payload.
library;

/// The type of FCM data payload, identified by the `type` field.
enum FcmPayloadType { message, incomingCall, callCancelled, unknown }

/// Base class for parsed FCM data payloads.
sealed class FcmPayload {
  const FcmPayload(this.type);

  final FcmPayloadType type;

  /// Parses a raw FCM `data` map (all values are strings) into a typed
  /// payload, or returns `null` if the map is empty or unrecognised.
  ///
  /// FCM data payloads are always `Map<String, String>` on the wire, but the
  /// plugin may deliver them as `Map<String, dynamic>`. We coerce defensively.
  static FcmPayload? fromData(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return null;
    }
    final type = _string(data['type']);
    switch (type) {
      case 'message':
        return MessagePayload.fromData(data);
      case 'incoming_call':
        return IncomingCallPayload.fromData(data);
      case 'call_cancelled':
        return CallCancelledPayload.fromData(data);
      default:
        return null;
    }
  }
}

/// A new chat message notification.
class MessagePayload extends FcmPayload {
  const MessagePayload({
    required this.conversationId,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.bodyPreview,
    required this.isGroup,
  }) : super(FcmPayloadType.message);

  final String conversationId;
  final String messageId;
  final String senderId;
  final String senderName;
  final String bodyPreview;
  final bool isGroup;

  static FcmPayload? fromData(Map<String, dynamic> data) {
    final conversationId = _string(data['conversation_id']);
    if (conversationId.isEmpty) {
      return null;
    }
    return MessagePayload(
      conversationId: conversationId,
      messageId: _string(data['message_id']),
      senderId: _string(data['sender_id']),
      senderName: _string(data['sender_name']),
      bodyPreview: _string(data['body_preview']),
      isGroup: _bool(data['is_group']),
    );
  }

  /// Map of fields as expected from the server. Used by tests to verify the
  /// contract between the server payload and the client parser.
  static const Map<String, String> fieldMap = {
    'type': 'message',
    'conversation_id': 'String (required)',
    'message_id': 'String (optional)',
    'sender_id': 'String (optional)',
    'sender_name': 'String (optional)',
    'body_preview': 'String (optional)',
    'is_group': 'String "true"/"false" (optional)',
  };
}

/// An incoming call (ringing) notification.
class IncomingCallPayload extends FcmPayload {
  const IncomingCallPayload({
    required this.callId,
    required this.roomName,
    required this.callerId,
    required this.callerName,
    required this.mediaKind,
    required this.conversationId,
  }) : super(FcmPayloadType.incomingCall);

  /// UUID of the `calls` row.
  final String callId;

  /// LiveKit room name to join after accepting.
  final String roomName;

  /// User ID of the caller.
  final String callerId;

  /// Display name of the caller.
  final String callerName;

  /// `audio` or `video`.
  final String mediaKind;

  /// Optional conversation context.
  final String conversationId;

  bool get isVideo => mediaKind == 'video';

  static FcmPayload? fromData(Map<String, dynamic> data) {
    final callId = _string(data['call_id']);
    final roomName = _string(data['room_name']);
    if (callId.isEmpty || roomName.isEmpty) {
      return null;
    }
    return IncomingCallPayload(
      callId: callId,
      roomName: roomName,
      callerId: _string(data['caller_id']),
      callerName: _string(data['caller_name']),
      mediaKind: _string(data['media_kind']),
      conversationId: _string(data['conversation_id']),
    );
  }

  /// Map of fields as expected from the server.
  static const Map<String, String> fieldMap = {
    'type': 'incoming_call',
    'call_id': 'String (required)',
    'room_name': 'String (required)',
    'caller_id': 'String (optional)',
    'caller_name': 'String (optional)',
    'media_kind': 'String "audio"/"video" (optional)',
    'conversation_id': 'String (optional)',
  };
}

/// A call cancelled notification — the caller hung up before the callee
/// answered. The client should dismiss any incoming-call UI.
class CallCancelledPayload extends FcmPayload {
  const CallCancelledPayload({required this.callId})
    : super(FcmPayloadType.callCancelled);

  /// UUID of the `calls` row whose ringing was cancelled.
  final String callId;

  static FcmPayload? fromData(Map<String, dynamic> data) {
    final callId = _string(data['call_id']);
    if (callId.isEmpty) {
      return null;
    }
    return CallCancelledPayload(callId: callId);
  }

  /// Map of fields as expected from the server.
  static const Map<String, String> fieldMap = {
    'type': 'call_cancelled',
    'call_id': 'String (required)',
  };
}

// -- Defensive coercion helpers (pure, testable) --

String _string(Object? value) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return '';
  }
  return value.toString();
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  return _string(value).toLowerCase() == 'true';
}
