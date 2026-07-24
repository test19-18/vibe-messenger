import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/call_models.dart';

/// Repository for the calls feature.
///
/// All call lifecycle operations go through Supabase Edge Functions that
/// match the backend contract:
///
/// - `create-call` — creates a `calls` row (state `created`), returns
///   `{callId, roomName, state, conversationId}`. The caller then issues a
///   LiveKit token separately via `issue-livekit-token`.
/// - `issue-livekit-token` — issues a short-lived LiveKit JWT for a
///   participant joining the room. Returns `{token, url}`. The token is
///   NEVER stored in the `calls` table nor logged.
/// - `call-action` — transitions call state. Body: `{callId, action}` where
///   action ∈ {ringing, accept, connect, decline, cancel, end, missed, fail}.
///   Returns `{callId, state, durationSeconds}`.
/// - `send-call-push` — sends a VoIP push notification to the callee.
///
/// The Flutter client calls `create-call` then `issue-livekit-token` when
/// the caller/callee joins the LiveKit room. State transitions go through
/// `call-action`. DB states (`state`, `media_kind`) are mapped to UI
/// [CallStatus] / [CallType] defensively.
///
/// **Security:** LiveKit tokens come ONLY from `issue-livekit-token`. They
/// are never stored in the database, never logged, and never included in
/// `toMap()` output.
class CallRepository {
  const CallRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  /// Initiates an outgoing call.
  ///
  /// Calls the `create-call` Edge Function, which creates a `calls` row
  /// (state `created`) and returns `{callId, roomName, state, conversationId}`.
  /// The caller then transitions to `ringing` via `call-action`, and issues
  /// a LiveKit token via `issue-livekit-token` so the caller can join the
  /// room immediately (publishing local media).
  ///
  /// [conversationId] — the direct conversation this call belongs to.
  ///   May be null for calls initiated outside a conversation context.
  Future<CallSession> startCall({
    required String callerId,
    required String calleeId,
    required CallType type,
    String? conversationId,
  }) async {
    // 1. Create the call record.
    final createResponse = await _requiredClient.functions.invoke(
      'create-call',
      body: {
        'calleeId': calleeId,
        'mediaKind': type == CallType.audio ? 'audio' : 'video',
        if (conversationId != null) 'conversationId': conversationId,
      },
    );

    final createData = _ensureMap(createResponse.data);
    final callId = _requiredStringField(createData, 'callId');
    final roomName = _requiredStringField(createData, 'roomName');
    // state is "created" at this point.
    final returnedConversationId = _string(createData['conversationId']);

    // 2. Transition to ringing (caller signals the callee is being alerted).
    try {
      await _requiredClient.functions.invoke(
        'call-action',
        body: {'callId': callId, 'action': 'ringing'},
      );
    } catch (_) {
      // Best-effort: the call is created; ringing transition is not critical
      // for the caller's local session. The callee will still see the call
      // row via realtime.
    }

    // 3. Issue a LiveKit token for the caller.
    final tokenResponse = await _requiredClient.functions.invoke(
      'issue-livekit-token',
      body: {'callId': callId, 'roomName': roomName},
    );
    final tokenData = _ensureMap(tokenResponse.data);
    final token = _requiredStringField(tokenData, 'token');
    final url = _requiredStringField(tokenData, 'url');

    return CallSession(
      id: callId,
      conversationId: returnedConversationId ?? conversationId ?? '',
      callerId: callerId,
      calleeId: calleeId,
      type: type,
      // Outgoing call is ringing on the callee's side.
      status: CallStatus.ringingOutgoing,
      createdAt: DateTime.now(),
      roomName: roomName,
      token: token,
      serverUrl: url,
    );
  }

  /// Accepts an incoming call.
  ///
  /// Transitions the call to `accepted` via `call-action`, then issues a
  /// LiveKit token for the callee so they can join the room.
  Future<CallSession> acceptCall({required CallSession session}) async {
    // 1. Accept the call (callee transitions ringing → accepted).
    await _requiredClient.functions.invoke(
      'call-action',
      body: {'callId': session.id, 'action': 'accept'},
    );

    // 2. Issue a LiveKit token for the callee.
    final tokenResponse = await _requiredClient.functions.invoke(
      'issue-livekit-token',
      body: {'callId': session.id, 'roomName': session.roomName!},
    );
    final tokenData = _ensureMap(tokenResponse.data);
    final token = _requiredStringField(tokenData, 'token');
    final url = _requiredStringField(tokenData, 'url');

    return session.copyWith(
      status: CallStatus.connecting,
      token: token,
      serverUrl: url,
      acceptedAt: DateTime.now(),
    );
  }

  /// Declines an incoming call (callee side).
  Future<void> declineCall({required String callId}) async {
    await _requiredClient.functions.invoke(
      'call-action',
      body: {'callId': callId, 'action': 'decline'},
    );
  }

  /// Cancels an outgoing call (caller hangs up before acceptance).
  Future<void> cancelCall({required String callId}) async {
    await _requiredClient.functions.invoke(
      'call-action',
      body: {'callId': callId, 'action': 'cancel'},
    );
  }

  /// Ends an active call (either party).
  Future<void> endCall({required String callId}) async {
    await _requiredClient.functions.invoke(
      'call-action',
      body: {'callId': callId, 'action': 'end'},
    );
  }

  /// Signals that the local participant connected to the LiveKit room.
  /// Transitions the call to `connected` (accepted → connected).
  Future<void> signalConnected({required String callId}) async {
    await _requiredClient.functions.invoke(
      'call-action',
      body: {'callId': callId, 'action': 'connect'},
    );
  }

  /// Fetches a single call by ID from the database.
  Future<CallSession> getCall(String callId) async {
    final rows = await _requiredClient
        .from('calls')
        .select(
          'id,conversation_id,caller_id,callee_id,state,media_kind,'
          'room_name,created_at,accepted_at,connected_at,ended_at,'
          'end_reason,duration_seconds',
        )
        .eq('id', callId)
        .limit(1);
    if (rows.isEmpty) {
      throw const FormatException('Звонок не найден.');
    }
    return CallSession.fromMap(rows.first);
  }

  /// Lists call history for a user, joined with peer profile data.
  ///
  /// Returns the most recent calls first, limited to [limit] rows.
  Future<List<CallRecord>> listCallHistory({
    required String userId,
    int limit = 50,
  }) async {
    final rows = await _requiredClient
        .from('calls')
        .select(
          'id,conversation_id,caller_id,callee_id,state,media_kind,'
          'created_at,accepted_at,connected_at,ended_at,'
          'end_reason,duration_seconds',
        )
        .or('caller_id.eq.$userId,callee_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(limit);

    // Fetch peer display names separately — the calls table doesn't
    // have a direct FK to profiles, so we batch-resolve unique peer IDs.
    final peerIds = <String>{};
    for (final row in rows) {
      final callerId = _string(row['caller_id']);
      final calleeId = _string(row['callee_id']);
      if (callerId != null && callerId != userId) {
        peerIds.add(callerId);
      }
      if (calleeId != null && calleeId != userId) {
        peerIds.add(calleeId);
      }
    }

    final peerNames = <String, String>{};
    final peerAvatars = <String, String>{};
    if (peerIds.isNotEmpty) {
      final profileRows = await _requiredClient
          .from('profiles')
          .select('id,display_name,avatar_path')
          .inFilter('id', peerIds.toList());
      for (final row in profileRows) {
        final id = _string(row['id']);
        if (id != null) {
          peerNames[id] = _string(row['display_name']) ?? 'Пользователь Вайба';
          // avatar_path would need a signed URL; left as null for now.
          // A future iteration can batch-resolve signed URLs.
        }
      }
    }

    return rows.map((row) {
      final callerId = _string(row['caller_id']) ?? '';
      final calleeId = _string(row['callee_id']) ?? '';
      final peerId = callerId == userId ? calleeId : callerId;
      final mapWithPeer = <String, dynamic>{
        ...row,
        'peer_display_name': peerNames[peerId],
        'peer_avatar_url': peerAvatars[peerId],
      };
      return CallRecord.fromMap(mapWithPeer);
    }).toList();
  }

  /// Subscribes to realtime changes on a specific call row.
  ///
  /// Used to detect when the callee accepts/declines or when the
  /// server marks a call as missed/busy/expired.
  Stream<CallSession> watchCall(String callId) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((rows) {
          if (rows.isEmpty) {
            throw const FormatException('Звонок не найден.');
          }
          return CallSession.fromMap(rows.first);
        });
  }

  /// Subscribes to incoming calls for a specific user.
  ///
  /// Filters the `calls` table for rows where this user is the callee
  /// and state is `ringing` or `created`. This is how the app detects
  /// incoming calls in the foreground. Background push delivery requires
  /// Firebase, which is not yet configured — see FEATURE_STATUS.md.
  Stream<List<CallSession>> watchIncomingCalls(String userId) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('callee_id', userId)
        .map(
          (rows) => rows
              .where(
                (row) => row['state'] == 'ringing' || row['state'] == 'created',
              )
              .map(
                (row) => CallSession.fromMap(
                  row,
                ).copyWith(status: CallStatus.ringingIncoming),
              )
              .toList(),
        );
  }
}

Map<String, dynamic> _ensureMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  throw const FormatException('Некорректный ответ сервера.');
}

String? _string(Object? value) => value is String ? value : null;

String _requiredStringField(Map<String, dynamic> map, String field) {
  final value = _string(map[field]);
  if (value == null || value.isEmpty) {
    throw FormatException('Сервер не вернул обязательное поле: $field');
  }
  return value;
}
