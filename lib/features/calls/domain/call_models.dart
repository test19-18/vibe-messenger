/// Domain models for 1:1 audio/video calls.
///
/// All models are immutable and use defensive parsing, matching the conventions
/// of the rest of the codebase. No codegen is used.
library;

import 'call_status.dart';

export 'call_status.dart';

/// Type of call: audio-only or audio+video.
enum CallType { audio, video }

/// Represents an active or recently-ended call session.
///
/// The [status] field drives the UI state machine. Transitions are validated
/// through [CallSessionTransition] to prevent illegal jumps.
class CallSession {
  const CallSession({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.roomName,
    this.serverUrl,
    this.token,
    this.acceptedAt,
    this.endedAt,
    this.endReason,
    this.durationSeconds,
  });

  /// UUID from the `calls` table.
  final String id;

  /// Conversation this call belongs to.
  final String conversationId;

  /// User ID of the caller (initiator).
  final String callerId;

  /// User ID of the callee (receiver).
  final String calleeId;

  final CallType type;

  final CallStatus status;

  /// When the call row was created (ringing started).
  final DateTime createdAt;

  /// LiveKit room name returned by the Edge Function.
  final String? roomName;

  /// LiveKit server WebSocket URL.
  final String? serverUrl;

  /// Server-issued JWT token for the LiveKit room.
  /// This is short-lived and must never be persisted or logged.
  final String? token;

  /// When the callee accepted (call became active).
  final DateTime? acceptedAt;

  /// When the call ended.
  final DateTime? endedAt;

  /// Why the call ended — mirrors the `end_reason` column.
  final String? endReason;

  /// Server-authoritative duration once the call has ended.
  final int? durationSeconds;

  /// Whether the current user is the caller.
  bool isCallerFor(String userId) => callerId == userId;

  /// Whether the current user is the callee.
  bool isCalleeFor(String userId) => calleeId == userId;

  /// The other participant's user ID (relative to [userId]).
  String otherParticipantId(String userId) =>
      callerId == userId ? calleeId : callerId;

  /// Whether the call is in a state where a LiveKit room connection
  /// should be established (token + URL must be present).
  ///
  /// Both [CallStatus.accepted] and [CallStatus.connecting] are valid
  /// connection states — connecting is a transient local state that
  /// occurs immediately after acceptance.
  bool get canConnectRoom =>
      (status == CallStatus.accepted || status == CallStatus.connecting) &&
      roomName != null &&
      serverUrl != null &&
      token != null;

  /// Whether the call is actively in progress.
  bool get isActive =>
      status == CallStatus.accepted || status == CallStatus.connecting;

  /// Whether the call is ringing (outgoing or incoming).
  bool get isRinging =>
      status == CallStatus.ringingOutgoing ||
      status == CallStatus.ringingIncoming;

  /// Elapsed seconds since acceptance, for live duration display.
  /// Returns null if the call hasn't been accepted yet.
  int? get liveDurationSeconds {
    final start = acceptedAt;
    if (start == null) {
      return null;
    }
    final end = endedAt ?? DateTime.now();
    return end.difference(start).inSeconds;
  }

  /// Creates a copy with updated fields.
  CallSession copyWith({
    CallStatus? status,
    String? roomName,
    String? serverUrl,
    String? token,
    DateTime? acceptedAt,
    DateTime? endedAt,
    String? endReason,
    int? durationSeconds,
  }) {
    return CallSession(
      id: id,
      conversationId: conversationId,
      callerId: callerId,
      calleeId: calleeId,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      roomName: roomName ?? this.roomName,
      serverUrl: serverUrl ?? this.serverUrl,
      token: token ?? this.token,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  factory CallSession.fromMap(Map<String, dynamic> map) {
    final typeStr = _requiredString(map['media_kind']);
    if (typeStr != 'audio' && typeStr != 'video') {
      throw const FormatException('Некорректный тип звонка.');
    }
    final stateStr = _requiredString(map['state']);
    final status = CallStatus.fromWireValue(stateStr);

    return CallSession(
      id: _requiredString(map['id']),
      // conversation_id is nullable in the DB — direct calls may carry it,
      // calls initiated without a conversation context will be empty.
      conversationId: _string(map['conversation_id']) ?? '',
      callerId: _requiredString(map['caller_id']),
      calleeId: _requiredString(map['callee_id']),
      type: typeStr == 'audio' ? CallType.audio : CallType.video,
      status: status,
      createdAt:
          _date(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal(),
      roomName: _string(map['room_name']),
      // server_url and token are NEVER stored in the DB — they come from
      // issue-livekit-token and are injected by the repository/provider.
      serverUrl: _string(map['server_url']),
      token: _string(map['token']),
      acceptedAt: _date(map['accepted_at']),
      endedAt: _date(map['ended_at']),
      endReason: _string(map['end_reason']),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'conversation_id': conversationId,
    'caller_id': callerId,
    'callee_id': calleeId,
    'media_kind': type == CallType.audio ? 'audio' : 'video',
    'state': status.wireValue,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (roomName != null) 'room_name': roomName,
    if (acceptedAt != null)
      'accepted_at': acceptedAt!.toUtc().toIso8601String(),
    if (endedAt != null) 'ended_at': endedAt!.toUtc().toIso8601String(),
    if (endReason != null) 'end_reason': endReason,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };
}

/// A completed call record for history display.
class CallRecord {
  const CallRecord({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.endReason,
    this.durationSeconds,
    this.peerDisplayName,
    this.peerAvatarUrl,
  });

  final String id;
  final String conversationId;
  final String callerId;
  final String calleeId;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final String? endReason;
  final int? durationSeconds;
  final String? peerDisplayName;
  final String? peerAvatarUrl;

  /// Whether the current user initiated this call.
  bool isOutgoingFor(String userId) => callerId == userId;

  /// Duration for display: server value if ended, else elapsed.
  int get displayDurationSeconds {
    if (durationSeconds != null) {
      return durationSeconds!;
    }
    final start = acceptedAt;
    final end = endedAt;
    if (start == null || end == null) {
      return 0;
    }
    return end.difference(start).inSeconds;
  }

  /// Short status label for history UI.
  String get historyLabel {
    return switch (status) {
      CallStatus.completed => 'Завершён',
      CallStatus.missed => 'Пропущен',
      CallStatus.declined => 'Отклонён',
      CallStatus.cancelled => 'Отменён',
      CallStatus.busy => 'Занято',
      _ => 'Завершён',
    };
  }

  /// The other participant's user ID relative to [userId].
  String otherParticipantIdForHistory(String userId) =>
      callerId == userId ? calleeId : callerId;

  factory CallRecord.fromMap(Map<String, dynamic> map) {
    final typeStr = _requiredString(map['media_kind']);
    if (typeStr != 'audio' && typeStr != 'video') {
      throw const FormatException('Некорректный тип звонка.');
    }
    final stateStr = _requiredString(map['state']);
    final status = CallStatus.fromWireValue(stateStr);

    return CallRecord(
      id: _requiredString(map['id']),
      conversationId: _string(map['conversation_id']) ?? '',
      callerId: _requiredString(map['caller_id']),
      calleeId: _requiredString(map['callee_id']),
      type: typeStr == 'audio' ? CallType.audio : CallType.video,
      status: status,
      createdAt:
          _date(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal(),
      acceptedAt: _date(map['accepted_at']),
      endedAt: _date(map['ended_at']),
      endReason: _string(map['end_reason']),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt(),
      peerDisplayName: _string(map['peer_display_name']),
      peerAvatarUrl: _string(map['peer_avatar_url']),
    );
  }
}

/// Validates and applies state transitions for [CallSession].
///
/// This is a pure class with no side effects, making it testable.
class CallSessionTransition {
  CallSessionTransition._();

  /// Returns the new status if the transition is legal, otherwise null.
  static CallStatus? transition({
    required CallStatus from,
    required CallStatus to,
  }) {
    return _transitionTable[from]?[to];
  }

  /// Returns true if [from] → [to] is a legal transition.
  static bool canTransition({
    required CallStatus from,
    required CallStatus to,
  }) {
    return transition(from: from, to: to) != null;
  }

  /// Applies the transition and returns a new [CallSession], or throws
  /// if the transition is illegal.
  static CallSession apply({
    required CallSession session,
    required CallStatus to,
    DateTime? acceptedAt,
    DateTime? endedAt,
    String? endReason,
    int? durationSeconds,
  }) {
    if (!canTransition(from: session.status, to: to)) {
      throw StateError(
        'Недопустимый переход звонка: ${session.status.wireValue} → ${to.wireValue}',
      );
    }
    return session.copyWith(
      status: to,
      acceptedAt: acceptedAt,
      endedAt: endedAt,
      endReason: endReason,
      durationSeconds: durationSeconds,
    );
  }

  /// Legal transitions. Each [CallStatus] maps to a set of statuses it
  /// can transition to (value is the target status, used for lookup).
  static final Map<CallStatus, Map<CallStatus, CallStatus>> _transitionTable = {
    CallStatus.idle: {
      CallStatus.ringingOutgoing: CallStatus.ringingOutgoing,
      CallStatus.ringingIncoming: CallStatus.ringingIncoming,
      CallStatus.connecting: CallStatus.connecting,
    },
    CallStatus.ringingOutgoing: {
      CallStatus.connecting: CallStatus.connecting,
      CallStatus.cancelled: CallStatus.cancelled,
      CallStatus.busy: CallStatus.busy,
      CallStatus.failed: CallStatus.failed,
      CallStatus.ringingIncoming: CallStatus.ringingIncoming,
    },
    CallStatus.ringingIncoming: {
      CallStatus.accepted: CallStatus.accepted,
      CallStatus.declined: CallStatus.declined,
      CallStatus.missed: CallStatus.missed,
      CallStatus.failed: CallStatus.failed,
    },
    CallStatus.connecting: {
      CallStatus.accepted: CallStatus.accepted,
      CallStatus.failed: CallStatus.failed,
      CallStatus.cancelled: CallStatus.cancelled,
    },
    CallStatus.accepted: {
      CallStatus.completed: CallStatus.completed,
      CallStatus.failed: CallStatus.failed,
      CallStatus.reconnecting: CallStatus.reconnecting,
    },
    CallStatus.reconnecting: {
      CallStatus.accepted: CallStatus.accepted,
      CallStatus.failed: CallStatus.failed,
      CallStatus.completed: CallStatus.completed,
    },
    CallStatus.completed: <CallStatus, CallStatus>{},
    CallStatus.missed: <CallStatus, CallStatus>{},
    CallStatus.declined: <CallStatus, CallStatus>{},
    CallStatus.cancelled: <CallStatus, CallStatus>{},
    CallStatus.busy: <CallStatus, CallStatus>{},
    CallStatus.failed: <CallStatus, CallStatus>{},
  };
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final string = _string(value);
  if (string == null || string.isEmpty) {
    throw const FormatException('Некорректные данные звонка.');
  }
  return string;
}

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
