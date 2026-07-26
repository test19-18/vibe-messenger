import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/call_models.dart';
import '../providers/call_providers.dart';

/// Call history screen, reachable from the conversation and settings.
class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key, this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(callHistoryProvider);
    final userId = ref.watch(currentUserProvider)?.id ?? '';

    return Scaffold(
      backgroundColor: context.tokens.groupedBackground,
      appBar: AppBar(
        backgroundColor: context.tokens.groupedBackground,
        title: Text(context.tr(ru: 'История звонков', en: 'Call history')),
      ),
      body: AsyncStateView<List<CallRecord>>(
        value: historyState,
        emptyTitle: context.tr(ru: 'Нет звонков', en: 'No calls yet'),
        emptyMessage: context.tr(
          ru: 'Здесь появится история ваших звонков.',
          en: 'Your call history will appear here.',
        ),
        isEmpty: (records) => records.isEmpty,
        onRetry: () => ref.invalidate(callHistoryProvider),
        dataBuilder: (context, records) {
          final filtered = conversationId != null
              ? records
                    .where((r) => r.conversationId == conversationId)
                    .toList()
              : records;
          if (filtered.isEmpty) {
            return EmptyState(
              title: context.tr(ru: 'Нет звонков', en: 'No calls yet'),
              message: context.tr(
                ru: 'Здесь появится история ваших звонков.',
                en: 'Your call history will appear here.',
              ),
              icon: Icons.phone_rounded,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final record = filtered[index];
              return _CallHistoryTile(record: record, userId: userId);
            },
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({required this.record, required this.userId});

  final CallRecord record;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final isOutgoing = record.isOutgoingFor(userId);
    final isMissed = record.status == CallStatus.missed;
    final isVideo = record.type == CallType.video;

    final directionIcon = isOutgoing
        ? Icons.call_made_rounded
        : Icons.call_received_rounded;
    final directionColor = isMissed
        ? context.tokens.danger
        : isOutgoing
        ? context.tokens.accent
        : context.tokens.success;

    final typeIcon = isVideo ? Icons.videocam_rounded : Icons.phone_rounded;

    final timeStr = DateFormat('dd.MM.yyyy HH:mm').format(record.createdAt);
    final durationStr = record.displayDurationSeconds > 0
        ? _formatDuration(record.displayDurationSeconds)
        : record.historyLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: SectionCard(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            leading: AppAvatar(
              label: record.peerDisplayName ?? 'Пользователь Вайба',
              seed: record.otherParticipantIdForHistory(userId),
              radius: 24,
            ),
            title: Row(
              children: [
                Icon(directionIcon, color: directionColor, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    record.peerDisplayName ?? 'Пользователь Вайба',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isMissed ? context.tokens.danger : null,
                    ),
                  ),
                ),
                Icon(typeIcon, color: context.tokens.textSecondary, size: 18),
              ],
            ),
            subtitle: Text(
              '$timeStr · $durationStr',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
