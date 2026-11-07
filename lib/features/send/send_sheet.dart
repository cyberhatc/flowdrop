import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_controller.dart';
import '../../../app/state/app_state.dart';
import '../../../core/protocol/constants.dart';
import '../../../core/protocol/device.dart';
import '../../../core/transfer/checksum.dart';
import '../../../core/transfer/folder_scan.dart';
import '../../../ui/glow.dart';

Future<void> showSendSheet(BuildContext context, DeviceInfo peer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SendSheet(peer: peer),
  );
}

class _SendSheet extends ConsumerStatefulWidget {
  const _SendSheet({required this.peer});

  final DeviceInfo peer;

  @override
  ConsumerState<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<_SendSheet> {
  final List<SendFile> _files = [];
  final _text = TextEditingController();
  String? _error;
  bool _picking = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await openFiles(confirmButtonText: 'Select');
      for (final file in picked) {
        final size = await file.length();
        _files.add(
          SendFile(
            path: file.path,
            name: file.name,
            size: size,
            mime: file.mimeType ?? 'application/octet-stream',
          ),
        );
      }
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not open files: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFolder() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await getDirectoryPath(confirmButtonText: 'Select folder');
      if (picked != null && picked.isNotEmpty) {
        final result = await scanFolder(picked);
        if (result.entries.isEmpty) {
          if (mounted) {
            setState(() => _error =
                'That folder is empty or nothing inside can be sent.');
          }
        } else {
          for (final entry in result.entries) {
            _files.add(
              SendFile(
                path: entry.fullPath,
                name: entry.relativePath,
                size: entry.size,
                relativePath: entry.relativePath,
              ),
            );
          }
          if (mounted) {
            setState(() {
              final notes = <String>[
                'Added ${result.entries.length} file${result.entries.length == 1 ? '' : 's'} from ${picked.split('\\').last}',
                if (result.skipped > 0) '${result.skipped} skipped',
                if (result.truncated)
                  'only the first ${FlowDropProtocol.maxFilesPerOffer} files',
              ];
              _error = notes.join(' · ');
            });
          }
        }
      }
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Could not open folder: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _remove(SendFile file) {
    setState(() => _files.remove(file));
  }

  void _send() {
    if (_files.isEmpty && _text.text.trim().isEmpty) {
      setState(() => _error = 'Pick a file or type a message first.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final controller = ref.read(appControllerProvider.notifier);
    final files = List<SendFile>.from(_files);
    final text = _text.text;
    navigator.pop();
    unawaited(
      controller
          .sendToPeer(peer: widget.peer, files: files, text: text)
          .then((error) {
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Sent to ${widget.peer.name}')),
          );
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlowIcon(
                  icon: _platformIcon(widget.peer.platform),
                  size: 46,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send to ${widget.peer.name}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.peer.addresses.isEmpty
                            ? 'No address'
                            : '${widget.peer.addresses.first}:${widget.peer.port}',
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
            const SizedBox(height: 20),
            Row(
              children: [
                GlowButton(
                  label: _picking ? 'Choosing…' : 'Choose files',
                  icon: Icons.attach_file_rounded,
                  onPressed: _picking ? null : _pickFiles,
                ),
                const SizedBox(width: 12),
                GlowButton(
                  label: 'Folder',
                  icon: Icons.folder_open_rounded,
                  tone: GlowTone.ghost,
                  onPressed: _picking ? null : _pickFolder,
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: _files.isEmpty
                      ? 'No files selected'
                      : '${_files.length} file${_files.length == 1 ? '' : 's'}',
                  color: _files.isEmpty ? scheme.onSurface : scheme.primary,
                  icon: Icons.folder_rounded,
                ),
              ],
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final file = _files[index];
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
                            Icons.insert_drive_file_rounded,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatBytes(file.size),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _remove(file),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Or send text / a link',
                hintText: 'https://…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            GlowButton(
              label: 'Send now',
              icon: Icons.send_rounded,
              expanded: true,
              onPressed: _send,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Encrypted with a pinned certificate · unknown devices must accept',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.desktop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.computer_rounded;
      case 'android':
        return Icons.smartphone_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }
}
