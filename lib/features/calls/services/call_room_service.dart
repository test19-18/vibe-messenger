import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

import '../domain/call_models.dart';

/// Manages the LiveKit room lifecycle for an active call.
///
/// This service wraps the LiveKit Flutter client SDK and exposes
/// a simplified API for the call state machine. It ensures:
///
/// - A Room is only connected after a server-issued token is available.
/// - Local audio/video tracks are published on connect.
/// - Mute, camera on/off, camera switch, and speaker operations
///   delegate to `LocalParticipant` convenience methods.
/// - The room is properly disposed on call end.
///
/// The service does NOT hold any API secrets. The LiveKit token is
/// short-lived and issued by the Edge Function per call.
class CallRoomService {
  CallRoomService();

  Room? _room;
  Timer? _statePollTimer;
  final _connectionStateController =
      StreamController<CallConnectionState>.broadcast();

  /// Stream of connection state changes for UI updates.
  Stream<CallConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Current room, or null if not connected.
  Room? get room => _room;

  /// Whether a room is currently connected.
  bool get isConnected =>
      _room != null && _room!.connectionState == ConnectionState.connected;

  /// Connects to a LiveKit room using server-issued credentials.
  ///
  /// The [session] must have [CallSession.canConnectRoom] == true,
  /// meaning it has a valid token, server URL, and room name.
  ///
  /// [enableVideo] controls whether the camera track is published
  /// immediately (video call) or not (audio-only call).
  Future<void> connect({
    required CallSession session,
    required String userId,
    required String displayName,
    bool enableVideo = true,
  }) async {
    if (!session.canConnectRoom) {
      throw StateError(
        'Невозможно подключиться к комнате: нет токена или адреса.',
      );
    }

    // Ensure WebRTC is initialized on mobile platforms.
    await LiveKitClient.initialize();

    _room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );

    _connectionStateController.add(CallConnectionState.connecting);

    await _room!.connect(session.serverUrl!, session.token!);

    // Publish local tracks.
    final localParticipant = _room!.localParticipant;
    if (localParticipant != null) {
      await localParticipant.setMicrophoneEnabled(true);
      if (enableVideo) {
        try {
          await localParticipant.setCameraEnabled(true);
        } catch (_) {
          // Camera may fail on simulator or if permission is denied.
          // Audio call can continue without video.
        }
      }
    }

    // Poll connection state for reconnect/disconnect detection.
    _startStatePolling();

    _connectionStateController.add(CallConnectionState.connected);
  }

  /// Toggles the local microphone mute state.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return;
    }
    await participant.setMicrophoneEnabled(enabled);
  }

  /// Toggles the local camera on/off.
  Future<void> setCameraEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return;
    }
    await participant.setCameraEnabled(enabled);
  }

  /// Switches between front and back camera.
  Future<void> switchCamera() async {
    final room = _room;
    if (room == null) {
      return;
    }
    // Enumerate available cameras and switch to a different one.
    final cameras = await Hardware.instance.videoInputs();
    if (cameras.length < 2) {
      return;
    }
    final currentDeviceId = room.selectedVideoInputDeviceId;
    final nextCamera = cameras
        .where((c) => c.deviceId != currentDeviceId)
        .firstOrNull;
    if (nextCamera != null) {
      await room.setVideoInputDevice(nextCamera);
    }
  }

  /// Sets the speaker output preference.
  Future<void> setSpeakerOn(bool speakerOn) async {
    await Hardware.instance.setSpeakerphoneOn(speakerOn);
  }

  /// Gets whether the microphone is currently enabled.
  bool get isMicrophoneEnabled {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return false;
    }
    return participant.isMicrophoneEnabled();
  }

  /// Gets whether the camera is currently enabled.
  bool get isCameraEnabled {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return false;
    }
    return participant.isCameraEnabled();
  }

  /// Gets the local participant's camera video track for rendering.
  VideoTrack? get localVideoTrack {
    final participant = _room?.localParticipant;
    if (participant == null) {
      return null;
    }
    return participant.videoTrackPublications
        .where((pub) => pub.source == TrackSource.camera)
        .firstOrNull
        ?.track;
  }

  /// Gets the remote participant's camera video track for rendering.
  VideoTrack? remoteVideoTrack(String remoteIdentity) {
    final room = _room;
    if (room == null) {
      return null;
    }
    final remote = room.remoteParticipants.values
        .where((p) => p.identity == remoteIdentity)
        .firstOrNull;
    if (remote == null) {
      return null;
    }
    return remote.videoTrackPublications
        .where((pub) => pub.source == TrackSource.camera)
        .firstOrNull
        ?.track;
  }

  /// Gets the remote participant identity (first non-local participant).
  String? get firstRemoteIdentity {
    final room = _room;
    if (room == null) {
      return null;
    }
    return room.remoteParticipants.values.firstOrNull?.identity;
  }

  /// Disconnects from the room and cleans up resources.
  Future<void> disconnect() async {
    _statePollTimer?.cancel();
    _statePollTimer = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        // Best effort — room may already be disconnected.
      }
      await room.dispose();
    }
    _connectionStateController.add(CallConnectionState.disconnected);
  }

  /// Disposes the service entirely.
  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController.close();
  }

  void _startStatePolling() {
    _statePollTimer?.cancel();
    CallConnectionState? lastState;
    _statePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final room = _room;
      if (room == null) {
        return;
      }
      final connState = room.connectionState;
      final newState = switch (connState) {
        ConnectionState.connected => CallConnectionState.connected,
        ConnectionState.connecting => CallConnectionState.connecting,
        ConnectionState.reconnecting => CallConnectionState.reconnecting,
        ConnectionState.disconnected => CallConnectionState.disconnected,
      };
      if (newState != lastState) {
        lastState = newState;
        _connectionStateController.add(newState);
      }
    });
  }
}

/// Connection state for the LiveKit room, exposed to the UI.
enum CallConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}
