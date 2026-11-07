import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/state/app_controller.dart';
import '../../core/transfer/checksum.dart';
import '../../core/transfer/transfer_models.dart';
import '../../ui/glow.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(
      appControllerProvider.select((state) => state.history),
    );
    final controller = ref.read(appControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GradientHeadline('History'),
                  const SizedBox(height: 4),
                  Text(
                    history.isEmpty
                        ? 'Transfers you complete appear here'
                        : '${history.length} recent transfer${history.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (history.isNotEmpty)
              TextButton.icon(
                onPressed: () => _confirmClear(context, controller),
                icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                label: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (history.isEmpty)
          const _EmptyHistory()
        else
          for (final record in history) ...[
            _HistoryTile(record: record),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    AppController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This only deletes the local list of past transfers. Files that were '
          'already saved stay on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.clearHistory();
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final outgoing = record.direction == TransferDirection.sent;
    final accent = _accent(scheme, record.state);
    final when = DateFormat('MMM d · HH:mm').format(record.startedAt.toLocal());

    return GlowCard(
      glow: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      accent: accent,
      onTap: () => _showDetails(context, ref),
      child: Row(
        children: [
          GlowIcon(
            icon: outgoing
                ? Icons.north_east_rounded
                : Icons.south_west_rounded,
            color: accent,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${outgoing ? 'To' : 'From'} ${record.peerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(record),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: _label(record.state), color: accent),
              const SizedBox(height: 5),
              Text(
                when,
                style: TextStyle(
                  fontSize: 10.5,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(TransferRecord record) {
    final parts = <String>[];
    if (record.files.isNotEmpty) {
      parts.add(
        record.files.length == 1
            ? record.files.first.name
            : '${record.files.length} files',
      );
      parts.add(formatBytes(record.totalBytes));
    }
    if (record.textPreview != null && record.textPreview!.isNotEmpty) {
      parts.add(record.files.isEmpty ? 'Text' : 'with message');
    }
    return parts.isEmpty ? 'Session' : parts.join(' · ');
  }

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(appControllerProvider.notifier);
    final when = DateFormat.yMMMd().add_Hms().format(
      (record.finishedAt ?? record.startedAt).toLocal(),
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            4,
            22,
            22 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.direction == TransferDirection.sent ? 'Sent to' : 'Received from'} ${record.peerName}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '$when · ${_label(record.state)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 18),
                if (record.files.isNotEmpty) ...[
                  for (final file in record.files) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: scheme.onSurface.withValues(alpha: 0.04),
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file_rounded,
                            size: 17,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              file.relativePath ?? file.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatBytes(file.size),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
                if (record.textPreview != null &&
                    record.textPreview!.isNotEmpty) ...[
                  const Text(
                    'Message',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: scheme.onSurface.withValues(alpha: 0.04),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        record.textPreview!,
                        style: const TextStyle(fontSize: 12.5, height: 1.45),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (record.savedPath != null &&
                    record.savedPath!.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          record.savedPath!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy path',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: record.savedPath!),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Path copied')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await controller.deleteHistoryEntry(record.id);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('Remove from history'),
                    ),
                    const Spacer(),
                    GlowButton(
                      label: 'Close',
                      tone: GlowTone.ghost,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlowCard(
      glow: false,
      child: Column(
        children: [
          const SizedBox(height: 14),
          GlowIcon(
            icon: Icons.history_rounded,
            color: scheme.primary,
            size: 54,
          ),
          const SizedBox(height: 16),
          const Text(
            'No history yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Completed, declined and cancelled transfers are recorded locally.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

Color _accent(ColorScheme scheme, TransferState state) {
  switch (state) {
    case TransferState.completed:
      return const Color(0xFF57E39B);
    case TransferState.failed:
      return scheme.error;
    case TransferState.cancelled:
    case TransferState.declined:
      return const Color(0xFFFFB454);
    case TransferState.pending:
    case TransferState.active:
      return scheme.primary;
  }
}

String _label(TransferState state) {
  switch (state) {
    case TransferState.pending:
      return 'Waiting';
    case TransferState.active:
      return 'Live';
    case TransferState.completed:
      return 'Done';
    case TransferState.failed:
      return 'Failed';
    case TransferState.cancelled:
      return 'Cancelled';
    case TransferState.declined:
      return 'Declined';
  }
}
