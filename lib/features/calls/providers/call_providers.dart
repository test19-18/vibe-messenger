import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../data/call_repository.dart';
import '../domain/call_models.dart';
import '../services/call_room_service.dart';
import '../services/telecom_api.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(ref.watch(supabaseClientProvider));
});

final callRoomServiceProvider = Provider<CallRoomService>((ref) {
  final service = CallRoomService();
  ref.onDispose(service.dispose);
  return service;
});

final telecomApiProvider = Provider<TelecomApi>((ref) {
  return const MethodChannelTelecomApi();
});

// ---------------------------------------------------------------------------
// Call history
// ---------------------------------------------------------------------------

final callHistoryProvider = FutureProvider.autoDispose<List<CallRecord>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw const BackendUnavailableException('Сессия не найдена.');
  }
  return ref.watch(callRepositoryProvider).listCallHistory(userId: user.id);
});

// ---------------------------------------------------------------------------
// Incoming call watcher
// ---------------------------------------------------------------------------

/// Watches for incoming calls (callee-side) in real time.
///
/// This only works while the app is in the foreground. Background
/// push delivery requires Firebase, which is not yet configured.
final incomingCallsProvider = StreamProvider.autoDispose<List<CallSession>>((
  ref,
) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream.error(
      const BackendUnavailableException('Сессия не найдена.'),
    );
  }
  return ref.watch(callRepositoryProvider).watchIncomingCalls(user.id);
});

/// The most recent incoming call (if any), for showing the incoming call UI.
final latestIncomingCallProvider = Provider.autoDispose<CallSession?>((ref) {
  final calls = ref.watch(incomingCallsProvider).valueOrNull ?? const [];
  if (calls.isEmpty) {
    return null;
  }
  // Return the most recent ringing call.
  return calls.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
});

// ---------------------------------------------------------------------------
// Active call controller
// ---------------------------------------------------------------------------

/// The central call state controller.
///
/// Manages the full lifecycle of a single active call:
/// - Starting an outgoing call (startCall → ringing → accept/decline/cancel)
/// - Accepting an incoming call (accept → connecting → active)
/// - LiveKit room connection after token issuance
/// - Mute, camera, speaker, camera switch operations
/// - Ending the call and cleanup
///
/// Only one call can be active at a time.
final activeCallProvider =
    StateNotifierProvider<ActiveCallController, AsyncValue<CallSession?>>((
      ref,
    ) {
      return ActiveCallController(
        repository: ref.watch(callRepositoryProvider),
        roomService: ref.watch(callRoomServiceProvider),
        telecomApi: ref.watch(telecomApiProvider),
        userId: ref.watch(currentUserProvider)?.id,
        displayName:
            ref.watch(myProfileProvider).valueOrNull?.visibleName ??
            'Пользователь Вайба',
        onCallEnded: () => ref.invalidate(callHistoryProvider),
      );
    });

/// Controller for outgoing call initiation.
///
/// Used from the conversation screen / profile to start a call.
/// Delegates to [ActiveCallController].
final callInitiationProvider =
    StateNotifierProvider.autoDispose<
      CallInitiationController,
      AsyncValue<void>
    >((ref) {
      return CallInitiationController(
        activeCallController: ref.watch(activeCallProvider.notifier),
      );
    });

/// Controller for accepting/declining incoming calls.
final incomingCallActionProvider =
    StateNotifierProvider.autoDispose<
      IncomingCallActionController,
      AsyncValue<void>
    >((ref) {
      return IncomingCallActionController(
        activeCallController: ref.watch(activeCallProvider.notifier),
      );
    });

// ---------------------------------------------------------------------------
// Permission helper
// ---------------------------------------------------------------------------

/// Requests camera and microphone permissions.
///
/// Returns true if all requested permissions are granted.
Future<bool> requestCallPermissions({required bool isVideo}) async {
  final permissions = <Permission>[Permission.microphone];
  if (isVideo) {
    permissions.add(Permission.camera);
  }

  final results = await permissions.request();
  return results.values.every((status) => status.isGranted);
}

// ---------------------------------------------------------------------------
// Controllers
// ---------------------------------------------------------------------------

/// Manages the active call state machine.
class ActiveCallController extends StateNotifier<AsyncValue<CallSession?>> {
  ActiveCallController({
    required this._repository,
    required this._roomService,
    required this._telecomApi,
    required this._userId,
    required this._displayName,
    required this._onCallEnded,
  }) : super(const AsyncData(null));

  final CallRepository _repository;
  final CallRoomService _roomService;
  // ignore: unused_field
  final TelecomApi _telecomApi;
  final String? _userId;
  final String _displayName;
  final void Function() _onCallEnded;

  StreamSubscription<CallSession>? _callWatchSub;
  StreamSubscription<CallConnectionState>? _connStateSub;
  Timer? _ringingTimeout;
  Timer? _missedCheckTimer;

  /// Starts an outgoing call.
  ///
  /// [conversationId] — the conversation to call within (optional for direct
  ///   calls without a conversation context).
  /// [calleeId] — the user ID of the person being called.
  /// [type] — audio or video.
  Future<void> startOutgoingCall({
    String? conversationId,
    required String calleeId,
    required CallType type,
  }) async {
    if (_userId == null) {
      state = const AsyncError(
        BackendUnavailableException('Сессия не найдена.'),
        StackTrace.empty,
      );
      return;
    }

    state = const AsyncLoading();
    try {
      final session = await _repository.startCall(
        callerId: _userId,
        calleeId: calleeId,
        type: type,
        conversationId: conversationId,
      );
      state = AsyncData(session);

      // Watch for callee response (accept/decline/busy/missed/expired).
      _startCallWatch(session.id);

      // Start ringing timeout (30s → auto-cancel/missed).
      _startRingingTimeout(session.id);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Accepts an incoming call.
  ///
  /// [session] — the ringing incoming call session.
  Future<void> acceptIncomingCall(CallSession session) async {
    state = const AsyncLoading();
    try {
      final accepted = await _repository.acceptCall(session: session);
      state = AsyncData(accepted);

      // Connect to the LiveKit room.
      await _connectToRoom(accepted);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Declines an incoming call.
  Future<void> declineIncomingCall(CallSession session) async {
    try {
      await _repository.declineCall(callId: session.id);
      _cleanup();
      state = const AsyncData(null);
      _onCallEnded();
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Cancels an outgoing call (caller hangs up before acceptance).
  Future<void> cancelOutgoingCall() async {
    final session = state.valueOrNull;
    if (session == null) {
      return;
    }
    try {
      if (session.status == CallStatus.accepted ||
          session.status == CallStatus.connecting) {
        // Call was already connected — end it normally.
        await _repository.endCall(callId: session.id);
      } else {
        await _repository.cancelCall(callId: session.id);
      }
      _cleanup();
      state = const AsyncData(null);
      _onCallEnded();
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// Ends the active call.
  Future<void> endCall() async {
    final session = state.valueOrNull;
    if (session == null) {
      return;
    }
    try {
      await _roomService.disconnect();
      if (!session.status.isTerminal) {
        await _repository.endCall(callId: session.id);
      }
      _cleanup();
      state = const AsyncData(null);
      _onCallEnded();
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  // -- Local media controls (delegated to CallRoomService) --

  Future<void> toggleMute() async {
    final enabled = !_roomService.isMicrophoneEnabled;
    await _roomService.setMicrophoneEnabled(enabled);
  }

  Future<void> toggleCamera() async {
    final enabled = !_roomService.isCameraEnabled;
    await _roomService.setCameraEnabled(enabled);
  }

  Future<void> switchCamera() async {
    await _roomService.switchCamera();
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    await _roomService.setSpeakerOn(speakerOn);
  }

  /// Forces a state refresh (e.g. after room event changes local track state).
  void refreshState() {
    final session = state.valueOrNull;
    if (session != null) {
      // Trigger a rebuild by re-emitting the same session.
      state = AsyncData(session);
    }
  }

  // -- Internal helpers --

  Future<void> _connectToRoom(CallSession session) async {
    _connStateSub = _roomService.connectionStateStream.listen((connState) {
      final current = state.valueOrNull;
      if (current == null) {
        return;
      }
      switch (connState) {
        case CallConnectionState.connecting:
          if (current.status == CallStatus.accepted) {
            state = AsyncData(current.copyWith(status: CallStatus.connecting));
          }
        case CallConnectionState.connected:
          state = AsyncData(
            current.copyWith(
              status: CallStatus.accepted,
              acceptedAt: current.acceptedAt ?? DateTime.now(),
            ),
          );
        case CallConnectionState.reconnecting:
          state = AsyncData(current.copyWith(status: CallStatus.reconnecting));
        case CallConnectionState.failed:
          state = AsyncData(
            current.copyWith(
              status: CallStatus.failed,
              endReason: 'connection_failed',
            ),
          );
          _cleanup();
          _onCallEnded();
        case CallConnectionState.disconnected:
          // Will be handled by endCall or timeout.
          break;
      }
    });

    await _roomService.connect(
      session: session,
      userId: _userId ?? '',
      displayName: _displayName,
      enableVideo: session.type == CallType.video,
    );
  }

  void _startCallWatch(String callId) {
    _callWatchSub = _repository
        .watchCall(callId)
        .listen(
          (updated) async {
            final current = state.valueOrNull;
            if (current == null || current.id != updated.id) {
              return;
            }

            // Disambiguate ringing/created status by direction.
            // The DB states `created` and `ringing` both map to ringingOutgoing
            // in fromMap, so we re-derive the directional status here.
            final isCaller = current.isCallerFor(_userId ?? '');
            final directionalStatus =
                updated.status == CallStatus.ringingOutgoing
                ? (isCaller
                      ? CallStatus.ringingOutgoing
                      : CallStatus.ringingIncoming)
                : updated.status;

            final newSession = updated.copyWith(
              status: directionalStatus,
              token: current.token ?? updated.token,
              serverUrl: current.serverUrl ?? updated.serverUrl,
              roomName: current.roomName ?? updated.roomName,
            );

            // If the callee accepted, connect to the room.
            if (directionalStatus == CallStatus.accepted &&
                current.status != CallStatus.accepted &&
                current.status != CallStatus.connecting) {
              state = AsyncData(newSession);
              await _connectToRoom(
                newSession.copyWith(
                  status: CallStatus.connecting,
                  acceptedAt: DateTime.now(),
                ),
              );
              return;
            }

            // If the call reached a terminal state, clean up.
            if (directionalStatus.isTerminal) {
              await _roomService.disconnect();
              _cleanup();
              state = const AsyncData(null);
              _onCallEnded();
              return;
            }

            state = AsyncData(newSession);
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncError(error, stackTrace);
          },
        );
  }

  void _startRingingTimeout(String callId) {
    _ringingTimeout?.cancel();
    _ringingTimeout = Timer(const Duration(seconds: 30), () async {
      final current = state.valueOrNull;
      if (current == null || current.id != callId) {
        return;
      }
      if (current.status == CallStatus.ringingOutgoing) {
        // Caller-side timeout → cancel.
        try {
          await _repository.cancelCall(callId: callId);
        } catch (_) {
          // Best effort.
        }
        _cleanup();
        state = const AsyncData(null);
        _onCallEnded();
      }
    });
  }

  void _cleanup() {
    _callWatchSub?.cancel();
    _callWatchSub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
    _missedCheckTimer?.cancel();
    _missedCheckTimer = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

/// Controller for initiating outgoing calls.
class CallInitiationController extends StateNotifier<AsyncValue<void>> {
  CallInitiationController({required this._activeCallController})
    : super(const AsyncData(null));

  final ActiveCallController _activeCallController;

  Future<bool> startCall({
    String? conversationId,
    required String calleeId,
    required CallType type,
  }) async {
    state = const AsyncLoading();

    // Request permissions first.
    final granted = await requestCallPermissions(
      isVideo: type == CallType.video,
    );
    if (!granted) {
      state = const AsyncData(null);
      return false;
    }

    await _activeCallController.startOutgoingCall(
      conversationId: conversationId,
      calleeId: calleeId,
      type: type,
    );
    state = const AsyncData(null);
    return true;
  }
}

/// Controller for accepting/declining incoming calls.
class IncomingCallActionController extends StateNotifier<AsyncValue<void>> {
  IncomingCallActionController({required this._activeCallController})
    : super(const AsyncData(null));

  final ActiveCallController _activeCallController;

  Future<bool> accept(CallSession session) async {
    state = const AsyncLoading();

    final granted = await requestCallPermissions(
      isVideo: session.type == CallType.video,
    );
    if (!granted) {
      state = const AsyncData(null);
      return false;
    }

    await _activeCallController.acceptIncomingCall(session);
    state = const AsyncData(null);
    return true;
  }

  Future<void> decline(CallSession session) async {
    state = const AsyncLoading();
    await _activeCallController.declineIncomingCall(session);
    state = const AsyncData(null);
  }
}
