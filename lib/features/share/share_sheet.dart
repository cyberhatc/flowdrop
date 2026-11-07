import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../app/state/app_state.dart';
import '../../core/transfer/checksum.dart';
import '../../ui/glow.dart';

/// Sheet shown when files/text arrive through the OS share sheet (Android
/// SEND intent). Pick a device to forward the shared content immediately —
/// no separate pick step in the file picker.
Future<void> showShareSheet(BuildContext context, List<ShareItem> items) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ShareSheet(items: items),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.items});

  final List<ShareItem> items;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  String? _selectedPeerId;
  bool _busy = false;

  Future<void> _send() async {
    final state = ref.read(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final peer = state.peers
        .where((entry) => entry.device.id == _selectedPeerId)
        .map((entry) => entry.device)
        .firstOrNull;
    if (peer == null) return;

    final files = widget.items
        .where((item) => item.isFile)
        .map(
          (item) => SendFile(
            path: item.filePath!,
            name: item.displayName,
            size: item.size,
            mime: item.mime,
          ),
        )
        .toList();
    final text = widget.items
        .where((item) => !item.isFile)
        .map((item) => item.text)
        .whereType<String>()
        .join('\n');

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await controller.sendToPeer(
      peer: peer,
      files: files,
      text: text.isEmpty ? null : text,
    );
    controller.clearPendingShare();
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Shared to ${peer.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final peers = state.peers;

    _selectedPeerId ??= peers.isNotEmpty ? peers.first.device.id : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlowIcon(icon: Icons.send_rounded, size: 46),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send shared items',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'From another app',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: scheme.primary.withValues(alpha: 0.06),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.isFile
                              ? Icons.insert_drive_file_rounded
                              : Icons.text_fields_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.isFile)
                          Text(
                            formatBytes(item.size),
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
            const SizedBox(height: 18),
            const Text(
              'Send to',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (peers.isEmpty)
              Text(
                'No devices nearby yet. Open FlowDrop on the other device, '
                'then try again — or use the QR code in FlowDrop.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final peer in peers) ...[
                      ChoiceChip(
                        avatar: Icon(
                          Icons.devices_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        label: Text(peer.device.name),
                        selected: peer.device.id == _selectedPeerId,
                        onSelected: (_) =>
                            setState(() => _selectedPeerId = peer.device.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            GlowButton(
              label: _busy ? 'Sending…' : 'Send now',
              icon: Icons.send_rounded,
              expanded: true,
              busy: _busy,
              onPressed:
                  (_selectedPeerId != null && !_busy) ? () => _send() : null,
            ),
          ],
        ),
      ),
    );
  }
}
