import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../core/transfer/checksum.dart';
import '../../core/transfer/transfer_models.dart';
import '../../ui/glow.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final active = state.activeSessions;
    final finished = state.finishedSessions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GradientHeadline('Transfers'),
                  const SizedBox(height: 4),
                  Text(
                    active.isEmpty
                        ? 'Nothing in flight right now'
                        : '${active.length} active transfer${active.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: state.serverRunning ? 'Server live' : 'Server offline',
              color: state.serverRunning
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              icon: state.serverRunning
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
            ),
          ],
        ),
        if (state.clipboardText != null) ...[
          const SizedBox(height: 18),
          _ClipboardCard(
            text: state.clipboardText!,
            from: state.clipboardFrom ?? 'a paired device',
            onDismiss: controller.clearClipboard,
          ),
        ],
        const SizedBox(height: 22),
        if (active.isEmpty && finished.isEmpty)
          const _EmptyTransfers()
        else ...[
          for (final session in active) ...[
            _SessionCard(
              session: session,
              canCancel: session.direction == TransferDirection.sent,
              onCancel: () => controller.cancelSession(session.sessionId),
            ),
            const SizedBox(height: 12),
          ],
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Recently finished',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 10),
            for (final session in finished) ...[
              _SessionCard(
                session: session,
                onDismiss: () => controller.dismissSession(session.sessionId),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    this.onCancel,
    this.onDismiss,
    this.canCancel = false,
  });

  final SessionProgress session;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outgoing = session.direction == TransferDirection.sent;
    final running = session.state == TransferState.active ||
        session.state == TransferState.pending;
    final accent = _stateColor(scheme, session.state);

    return GlowCard(
      accent: accent,
      glow: running,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlowIcon(
                icon: outgoing
                    ? Icons.north_east_rounded
                    : Icons.south_west_rounded,
                color: accent,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outgoing
                          ? 'To ${session.peerName}'
                          : 'From ${session.peerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _summary(session),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: _stateLabel(session.state), color: accent),
              if (canCancel && running)
                IconButton(
                  tooltip: 'Cancel transfer',
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                ),
            ],
          ),
          if (session.files.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: running ? session.fraction : _finalFraction(session),
                minHeight: 6,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${formatBytes(session.transferredBytes)} / ${formatBytes(session.totalBytes)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                if (running && session.bytesPerSecond > 0)
                  Text(
                    formatSpeed(session.bytesPerSecond),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.primary,
                    ),
                  )
                else
                  Text(
                    '${(session.fraction * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ],
          if (session.text != null && session.text!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: scheme.onSurface.withValues(alpha: 0.04),
              ),
              child: Text(
                session.text!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _finalFraction(SessionProgress session) {
    switch (session.state) {
      case TransferState.completed:
        return 1;
      default:
        return session.fraction;
    }
  }

  String _summary(SessionProgress session) {
    final files = session.files.length;
    final parts = <String>[];
    if (files > 0) {
      parts.add(files == 1 ? session.files.first.name : '$files files');
    }
    if (files > 0) parts.add(formatBytes(session.totalBytes));
    if (session.text != null && session.text!.isNotEmpty) {
      parts.add(files == 0 ? 'Text message' : 'with message');
    }
    return parts.isEmpty ? 'Session' : parts.join(' · ');
  }
}

class _ClipboardCard extends StatelessWidget {
  const _ClipboardCard({
    required this.text,
    required this.from,
    required this.onDismiss,
  });

  final String text;
  final String from;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlowCard(
      accent: scheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlowIcon(
                icon: Icons.content_paste_rounded,
                color: scheme.secondary,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Clipboard from $from',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copy'),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: const Icon(Icons.clear_rounded, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlowCard(
      glow: false,
      child: Column(
        children: [
          const SizedBox(height: 12),
          GlowIcon(
            icon: Icons.swap_vert_rounded,
            color: scheme.primary,
            size: 54,
          ),
          const SizedBox(height: 16),
          const Text(
            'No transfers yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a device on the radar and send files or text.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

Color _stateColor(ColorScheme scheme, TransferState state) {
  switch (state) {
    case TransferState.completed:
      return const Color(0xFF57E39B);
    case TransferState.failed:
      return scheme.error;
    case TransferState.cancelled:
      return const Color(0xFFFFB454);
    case TransferState.declined:
      return const Color(0xFF9AA7C2);
    case TransferState.pending:
    case TransferState.active:
      return scheme.primary;
  }
}

String _stateLabel(TransferState state) {
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
