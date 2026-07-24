import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';
import '../domain/call_models.dart';
import '../providers/call_providers.dart';

/// Full-screen active call screen.
///
/// Shows the call state (ringing, connecting, active, reconnecting),
/// local/remote video, and call controls (mute, camera, speaker, end).
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  bool _speakerOn = false;

  @override
  void initState() {
    super.initState();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = ref.read(activeCallProvider).valueOrNull;
      if (session != null && session.acceptedAt != null && mounted) {
        setState(() {
          _elapsedSeconds = session.liveDurationSeconds ?? 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(activeCallProvider);
    final session = callState.valueOrNull;

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final userId = ref.watch(currentUserProvider)?.id ?? '';
    final isCaller = session.isCallerFor(userId);
    final peerProfile = ref.watch(myProfileProvider).valueOrNull;
    final peerName = isCaller
        ? _getCalleeName(session, peerProfile)
        : _getCallerName(session, peerProfile);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: session.type == CallType.video
            ? _VideoCallBody(
                session: session,
                peerName: peerName,
                elapsedSeconds: _elapsedSeconds,
                speakerOn: _speakerOn,
                onToggleMute: _toggleMute,
                onToggleCamera: _toggleCamera,
                onSwitchCamera: _switchCamera,
                onToggleSpeaker: _toggleSpeaker,
                onEndCall: _endCall,
              )
            : _AudioCallBody(
                session: session,
                peerName: peerName,
                elapsedSeconds: _elapsedSeconds,
                speakerOn: _speakerOn,
                onToggleMute: _toggleMute,
                onToggleSpeaker: _toggleSpeaker,
                onEndCall: _endCall,
              ),
      ),
    );
  }

  String _getCalleeName(CallSession session, UserProfile? profile) {
    // In a real implementation, we'd fetch the callee's profile.
    // For now, use a generic name.
    return context.tr(ru: 'Собеседник', en: 'Caller');
  }

  String _getCallerName(CallSession session, UserProfile? profile) {
    return context.tr(ru: 'Собеседник', en: 'Caller');
  }

  Future<void> _toggleMute() async {
    await ref.read(activeCallProvider.notifier).toggleMute();
    setState(() {});
  }

  Future<void> _toggleCamera() async {
    await ref.read(activeCallProvider.notifier).toggleCamera();
    setState(() {});
  }

  Future<void> _switchCamera() async {
    await ref.read(activeCallProvider.notifier).switchCamera();
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await ref.read(activeCallProvider.notifier).setSpeakerOn(_speakerOn);
  }

  Future<void> _endCall() async {
    await ref.read(activeCallProvider.notifier).endCall();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }
}

// ---------------------------------------------------------------------------
// Audio call body
// ---------------------------------------------------------------------------

class _AudioCallBody extends ConsumerWidget {
  const _AudioCallBody({
    required this.session,
    required this.peerName,
    required this.elapsedSeconds,
    required this.speakerOn,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  final CallSession session;
  final String peerName;
  final int elapsedSeconds;
  final bool speakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomService = ref.watch(callRoomServiceProvider);
    final statusLabel = _statusLabel(context, session);
    final isMuted = !roomService.isMicrophoneEnabled;

    return Column(
      children: [
        const Spacer(),
        AppAvatar(
          label: peerName,
          seed: session.otherParticipantId(
            ref.read(currentUserProvider)?.id ?? '',
          ),
          radius: 64,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(peerName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(statusLabel, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        _CallControls(
          isVideo: false,
          isMuted: isMuted,
          isCameraOn: false,
          speakerOn: speakerOn,
          isReconnecting: session.status == CallStatus.reconnecting,
          onToggleMute: onToggleMute,
          onToggleCamera: () {},
          onSwitchCamera: () {},
          onToggleSpeaker: onToggleSpeaker,
          onEndCall: onEndCall,
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Video call body
// ---------------------------------------------------------------------------

class _VideoCallBody extends ConsumerStatefulWidget {
  const _VideoCallBody({
    required this.session,
    required this.peerName,
    required this.elapsedSeconds,
    required this.speakerOn,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  final CallSession session;
  final String peerName;
  final int elapsedSeconds;
  final bool speakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  @override
  ConsumerState<_VideoCallBody> createState() => _VideoCallBodyState();
}

class _VideoCallBodyState extends ConsumerState<_VideoCallBody> {
  @override
  Widget build(BuildContext context) {
    final roomService = ref.watch(callRoomServiceProvider);
    final remoteIdentity = roomService.firstRemoteIdentity;
    final remoteTrack = remoteIdentity != null
        ? roomService.remoteVideoTrack(remoteIdentity)
        : null;
    final localTrack = roomService.localVideoTrack;
    final isMuted = !roomService.isMicrophoneEnabled;
    final isCameraOn = roomService.isCameraEnabled;
    final statusLabel = _statusLabel(context, widget.session);

    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Text(
                widget.peerName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              if (widget.session.status == CallStatus.accepted)
                Text(
                  _formatDuration(widget.elapsedSeconds),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        // Video area
        Expanded(
          child: Stack(
            children: [
              // Remote video (full screen)
              if (remoteTrack != null && !remoteTrack.muted)
                Positioned.fill(
                  child: VideoTrackRenderer(
                    remoteTrack,
                    fit: VideoViewFit.contain,
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: AppColors.surface,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppAvatar(
                            label: widget.peerName,
                            seed: widget.session.otherParticipantId(
                              ref.read(currentUserProvider)?.id ?? '',
                            ),
                            radius: 48,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            widget.session.status == CallStatus.reconnecting
                                ? context.tr(
                                    ru: 'Переподключение…',
                                    en: 'Reconnecting…',
                                  )
                                : statusLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Local video (picture-in-picture)
              if (isCameraOn && localTrack != null)
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: SizedBox(
                      width: 120,
                      height: 160,
                      child: VideoTrackRenderer(
                        localTrack,
                        fit: VideoViewFit.cover,
                        mirrorMode: VideoViewMirrorMode.mirror,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Controls
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _CallControls(
            isVideo: true,
            isMuted: isMuted,
            isCameraOn: isCameraOn,
            speakerOn: widget.speakerOn,
            isReconnecting: widget.session.status == CallStatus.reconnecting,
            onToggleMute: () {
              widget.onToggleMute();
              setState(() {});
            },
            onToggleCamera: () {
              widget.onToggleCamera();
              setState(() {});
            },
            onSwitchCamera: widget.onSwitchCamera,
            onToggleSpeaker: widget.onToggleSpeaker,
            onEndCall: widget.onEndCall,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Call controls
// ---------------------------------------------------------------------------

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.isVideo,
    required this.isMuted,
    required this.isCameraOn,
    required this.speakerOn,
    required this.isReconnecting,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
    required this.onEndCall,
  });

  final bool isVideo;
  final bool isMuted;
  final bool isCameraOn;
  final bool speakerOn;
  final bool isReconnecting;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: isMuted ? 'Вкл' : 'Выкл',
          active: !isMuted,
          onPressed: onToggleMute,
        ),
        if (isVideo)
          _ControlButton(
            icon: isCameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: isCameraOn ? 'Камера' : 'Нет',
            active: isCameraOn,
            onPressed: onToggleCamera,
          ),
        if (isVideo)
          _ControlButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Сменить',
            active: true,
            onPressed: onSwitchCamera,
          ),
        _ControlButton(
          icon: speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: speakerOn ? 'Спикер' : 'Динамик',
          active: speakerOn,
          onPressed: onToggleSpeaker,
        ),
        _EndCallButton(onPressed: onEndCall),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: active
                ? AppColors.electricBlue.withValues(alpha: 0.2)
                : AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: AppColors.electricBlue, width: 1.5)
                : null,
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: AppColors.textPrimary, size: 24),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _EndCallButton extends StatelessWidget {
  const _EndCallButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.tr(ru: 'Завершить', en: 'End'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _statusLabel(BuildContext context, CallSession session) {
  return switch (session.status) {
    CallStatus.ringingOutgoing => context.tr(ru: 'Вызов…', en: 'Calling…'),
    CallStatus.ringingIncoming => context.tr(
      ru: 'Входящий звонок',
      en: 'Incoming call',
    ),
    CallStatus.connecting => context.tr(ru: 'Подключение…', en: 'Connecting…'),
    CallStatus.accepted => _formatDuration(session.liveDurationSeconds ?? 0),
    CallStatus.reconnecting => context.tr(
      ru: 'Переподключение…',
      en: 'Reconnecting…',
    ),
    CallStatus.completed => context.tr(ru: 'Завершён', en: 'Ended'),
    CallStatus.missed => context.tr(ru: 'Пропущен', en: 'Missed'),
    CallStatus.declined => context.tr(ru: 'Отклонён', en: 'Declined'),
    CallStatus.cancelled => context.tr(ru: 'Отменён', en: 'Cancelled'),
    CallStatus.busy => context.tr(ru: 'Занято', en: 'Busy'),
    CallStatus.failed => context.tr(ru: 'Ошибка', en: 'Failed'),
    CallStatus.idle => '',
  };
}

String _formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
