/// Status enumeration for call lifecycle.
///
/// The backend `calls.state` column uses a `call_state` enum with these
/// values: created, ringing, accepted, connected, declined, cancelled,
/// missed, busy, ended, failed, expired.
///
/// [wireValue] and [fromWireValue] map between DB states and this richer
/// client-side enum. Client-only statuses like [connecting] and
/// [reconnecting] are never persisted to the backend.
library;

/// All possible call states.
enum CallStatus {
  /// No active call. Initial state.
  idle,

  /// Outgoing call is ringing on the callee's device.
  /// Maps from DB states `created` and `ringing` when this user is the caller.
  ringingOutgoing,

  /// Incoming call is ringing on this device.
  /// Maps from DB state `ringing` when this user is the callee.
  ringingIncoming,

  /// Call has been accepted, connecting to the LiveKit room.
  /// Local-only status — not persisted.
  connecting,

  /// Call is active: connected to the LiveKit room.
  /// Maps from DB states `accepted` and `connected`.
  accepted,

  /// Connection temporarily lost, attempting reconnect.
  /// Local-only status — not persisted.
  reconnecting,

  /// Call ended normally.
  /// Maps from DB state `ended`.
  completed,

  /// Callee did not answer within the timeout.
  /// Maps from DB states `missed` and `expired`.
  missed,

  /// Callee explicitly declined the call.
  /// Maps from DB state `declined`.
  declined,

  /// Caller cancelled before the callee answered.
  /// Maps from DB state `cancelled`.
  cancelled,

  /// Callee was already in another call.
  /// Maps from DB state `busy`.
  busy,

  /// Call failed due to a technical error.
  /// Maps from DB state `failed`.
  failed;

  /// The value stored in the `calls.state` column.
  ///
  /// Local-only statuses map to their closest persisted equivalent.
  String get wireValue => switch (this) {
    CallStatus.idle => 'created',
    CallStatus.ringingOutgoing => 'ringing',
    CallStatus.ringingIncoming => 'ringing',
    CallStatus.connecting => 'accepted',
    CallStatus.accepted => 'connected',
    CallStatus.reconnecting => 'connected',
    CallStatus.completed => 'ended',
    CallStatus.missed => 'missed',
    CallStatus.declined => 'declined',
    CallStatus.cancelled => 'cancelled',
    CallStatus.busy => 'busy',
    CallStatus.failed => 'failed',
  };

  /// Whether this status is terminal (call is over).
  bool get isTerminal =>
      this == CallStatus.completed ||
      this == CallStatus.missed ||
      this == CallStatus.declined ||
      this == CallStatus.cancelled ||
      this == CallStatus.busy ||
      this == CallStatus.failed;

  /// Whether this status indicates the call was never connected.
  bool get wasNeverConnected =>
      this == CallStatus.missed ||
      this == CallStatus.declined ||
      this == CallStatus.cancelled ||
      this == CallStatus.busy;

  /// Parse from the wire value stored in the database `calls.state` column.
  ///
  /// Because the wire value `ringing` (and `created`) is shared by both
  /// outgoing and incoming, the caller must disambiguate using direction.
  /// Use [fromWireValueDirectional] when the caller/callee role is known.
  static CallStatus fromWireValue(String value) {
    return switch (value) {
      'created' => CallStatus.ringingOutgoing,
      'ringing' => CallStatus.ringingOutgoing,
      'accepted' => CallStatus.accepted,
      'connected' => CallStatus.accepted,
      'ended' => CallStatus.completed,
      'missed' => CallStatus.missed,
      'expired' => CallStatus.missed,
      'declined' => CallStatus.declined,
      'cancelled' => CallStatus.cancelled,
      'busy' => CallStatus.busy,
      'failed' => CallStatus.failed,
      _ => CallStatus.failed, // Defensive: unknown states map to failed.
    };
  }

  /// Parse from the wire value, disambiguating ringing/created by direction.
  static CallStatus fromWireValueDirectional(
    String value, {
    required bool isCaller,
  }) {
    if (value == 'ringing' || value == 'created') {
      return isCaller ? CallStatus.ringingOutgoing : CallStatus.ringingIncoming;
    }
    return fromWireValue(value);
  }
}
