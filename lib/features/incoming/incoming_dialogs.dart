import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../app/state/app_state.dart';
import '../../core/security/fingerprint.dart';
import '../../core/transfer/checksum.dart';
import '../../ui/glow.dart';
import '../shell/platform_actions.dart';

/// Accept/decline prompt shown for every offer from an untrusted device.
///
/// Nothing is written to disk until the user accepts: the sender only uploaded
/// metadata at this point.
Future<void> showIncomingOfferDialog(
  BuildContext context,
  IncomingOffer offer,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => IncomingOfferDialog(offer: offer),
  );
}

class IncomingOfferDialog extends ConsumerWidget {
  const IncomingOfferDialog({super.key, required this.offer});

  final IncomingOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sender = offer.offer.sender;
    final files = offer.offer.files;
    final text = offer.offer.text;
    final controller = ref.read(appControllerProvider.notifier);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      title: Row(
        children: [
          GlowIcon(
            icon: offer.hasFiles
                ? Icons.call_received_rounded
                : Icons.chat_bubble_outline_rounded,
            color: scheme.primary,
            size: 42,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  offer.trusted
                      ? 'Trusted device · ${offer.remoteIp}'
                      : 'New device · ${offer.remoteIp}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: offer.trusted
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (files.isNotEmpty) ...[
                Text(
                  files.length == 1
                      ? 'Wants to send 1 file'
                      : 'Wants to send ${files.length} files',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: scheme.primary.withValues(alpha: 0.06),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.14),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              formatBytes(file.size),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Total ${formatBytes(offer.offer.totalSize)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
              if (text != null && text.isNotEmpty) ...[
                if (files.isNotEmpty) const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        files.isEmpty ? 'Message' : 'Attached message',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Text copied')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.onSurface.withValues(alpha: 0.04),
                    border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.10),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Verify this phrase on the other device:',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                fingerprintPhrase(sender.fingerprint),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.primary,
                ),
              ),
              if (!offer.trusted) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.error.withValues(alpha: 0.08),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only accept if you know who is sending. FlowDrop '
                          'will save incoming files to your Downloads folder.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      actions: [
        TextButton(
          onPressed: () {
            controller.declineIncoming(offer.sessionId);
            Navigator.of(context).pop();
          },
          child: const Text('Decline'),
        ),
        GlowButton(
          label: offer.hasFiles ? 'Accept files' : 'Accept',
          icon: Icons.check_rounded,
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            controller.acceptIncoming(offer.sessionId);
            Navigator.of(context).pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  offer.hasFiles
                      ? 'Receiving from ${sender.name}'
                      : 'Message accepted',
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

Future<void> showIncomingTextDialog(BuildContext context, IncomingText entry) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => IncomingTextDialog(entry: entry),
  );
}

class IncomingTextDialog extends ConsumerWidget {
  const IncomingTextDialog({super.key, required this.entry});

  final IncomingText entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appControllerProvider.notifier);
    return AlertDialog(
      title: Row(
        children: [
          GlowIcon(icon: Icons.chat_bubble_outline_rounded, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Text from ${entry.senderName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: SelectableText(
            entry.text,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
      ),
      actions: [
        if (isLink(entry.text))
          TextButton.icon(
            onPressed: () => openLink(entry.text),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open'),
          ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: entry.text));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Text copied')));
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: () async {
            final saved = await controller.saveTextAsFile(
              entry.text,
              entry.senderName,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(saved ?? 'Saved as .txt')));
            }
          },
          icon: const Icon(Icons.save_rounded, size: 16),
          label: const Text('Save .txt'),
        ),
        GlowButton(
          label: 'Done',
          onPressed: () {
            ref.read(appControllerProvider.notifier).dismissIncomingText(entry);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
