import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../app/theme.dart';
import '../../core/security/fingerprint.dart';
import '../../core/security/trust_store.dart';
import '../../core/storage/settings.dart';
import '../../ui/glow.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final settings = state.settings;
    final scheme = Theme.of(context).colorScheme;
    final fingerprint = state.identity?.fingerprint ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      children: [
        const GradientHeadline('Settings'),
        const SizedBox(height: 4),
        Text(
          'FlowDrop stays local: no account, no cloud, no telemetry.',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsSection(
          title: 'This device',
          children: [
            _NameEditor(
              initialName: settings.deviceName,
              onSave: (name) async {
                if (name.trim().isEmpty) return;
                await controller.applySettings(
                  settings.copyWith(deviceName: name.trim()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: 'Appearance',
          children: [
            const _RowLabel('Theme'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in AppThemeMode.values)
                  ChoiceChip(
                    label: Text(_themeLabel(mode)),
                    selected: settings.themeMode == mode,
                    onSelected: (_) => controller.applySettings(
                      settings.copyWith(themeMode: mode),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _RowLabel('Accent'),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final accent in AccentColor.values) ...[
                  _AccentSwatch(
                    accent: accent,
                    selected: settings.accent == accent,
                    onTap: () => controller.applySettings(
                      settings.copyWith(accent: accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: 'Discovery',
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Find nearby devices'),
              subtitle: const Text(
                'UDP beacon and mDNS. Turn this off to stay invisible.',
              ),
              value: settings.discoveryEnabled,
              onChanged: (value) => controller.applySettings(
                settings.copyWith(discoveryEnabled: value),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also advertise over mDNS'),
              subtitle: const Text(
                'Bonjour/avahi compatible. UDP alone normally works.',
              ),
              value: settings.useMdns,
              onChanged: settings.discoveryEnabled
                  ? (value) => controller.applySettings(
                        settings.copyWith(useMdns: value),
                      )
                  : null,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                StatusPill(
                  label: state.udpRunning ? 'UDP live' : 'UDP blocked',
                  color: state.udpRunning ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: state.mdnsRunning ? 'mDNS live' : 'mDNS off',
                  color: state.mdnsRunning
                      ? scheme.secondary
                      : scheme.onSurface.withValues(alpha: 0.5),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: 'Receiving',
          children: [
            Row(
              children: [
                GlowIcon(
                  icon: Icons.folder_rounded,
                  color: scheme.primary,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.receiveDirectory.trim().isEmpty
                            ? 'Downloads/FlowDrop'
                            : settings.receiveDirectory,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        settings.receiveDirectory.trim().isEmpty
                            ? 'Default folder'
                            : 'Custom folder',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final path = await getDirectoryPath(
                      confirmButtonText: 'Use folder',
                    );
                    if (path == null) return;
                    await controller.setReceiveDirectory(path);
                    messenger.showSnackBar(
                      SnackBar(content: Text('Saving to $path')),
                    );
                  },
                  child: const Text('Change'),
                ),
                if (settings.receiveDirectory.trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Use default folder',
                    onPressed: () => controller.setReceiveDirectory(''),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-accept paired devices'),
              subtitle: const Text(
                'Paired devices can send without a prompt. Unknown devices '
                'always need confirmation.',
              ),
              value: settings.autoAcceptTrusted,
              onChanged: (value) => controller.applySettings(
                settings.copyWith(autoAcceptTrusted: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: 'Security',
          children: [
            _RowLabel('Certificate fingerprint'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.primary.withValues(alpha: 0.06),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: SelectableText(
                fingerprint.isEmpty
                    ? 'Generating…'
                    : formatFingerprint(fingerprint),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.6,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fingerprintPhrase(fingerprint),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: fingerprint.isEmpty
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: fingerprint),
                          );
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Fingerprint copied'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RowLabel(
              state.trustedDevices.isEmpty
                  ? 'Trusted devices'
                  : 'Trusted devices (${state.trustedDevices.length})',
            ),
            const SizedBox(height: 8),
            if (state.trustedDevices.isEmpty)
              Text(
                'Pair by QR code or accept an incoming transfer to add a '
                'device. Pinned fingerprints make later transfers verifiable.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              )
            else
              for (final device in state.trustedDevices)
                _TrustedDeviceRow(
                  device: device,
                  onForget: () => controller.forgetDevice(device.fingerprint),
                ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: 'Data',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, color: scheme.primary),
              title: const Text('Transfer history'),
              subtitle: Text(
                state.history.isEmpty
                    ? 'No entries'
                    : '${state.history.length} entries, stored on this device',
              ),
              trailing: TextButton(
                onPressed:
                    state.history.isEmpty ? null : controller.clearHistory,
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Only transfer metadata is stored. File contents never leave '
              'this device except to the receiving peer.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            'FlowDrop · Protocol v1 · ${state.serverPort > 0 ? 'port ${state.serverPort}' : 'server idle'}',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ],
    );
  }

  static String _themeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.system:
        return 'System';
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
        GlowCard(
          glow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

class _NameEditor extends StatefulWidget {
  const _NameEditor({required this.initialName, required this.onSave});

  final String initialName;
  final Future<void> Function(String name) onSave;

  @override
  State<_NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<_NameEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  bool _dirty = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device name updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.done,
      onChanged: (value) {
        final dirty = value.trim() != widget.initialName;
        if (dirty != _dirty) setState(() => _dirty = dirty);
      },
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: 'Device name',
        hintText: 'Visible to nearby devices',
        suffixIcon: _dirty
            ? IconButton(
                tooltip: 'Save name',
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
              )
            : null,
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AccentColor accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = FlowDropTheme.accent(accent);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: selected ? 0.30 : 0.14),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: selected ? 2.2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 18, color: color)
            : null,
      ),
    );
  }
}

class _TrustedDeviceRow extends StatelessWidget {
  const _TrustedDeviceRow({required this.device, required this.onForget});

  final TrustedDevice device;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GlowIcon(
            icon: Icons.verified_user_rounded,
            color: scheme.primary,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.platform} · ${fingerprintPhrase(device.fingerprint)}',
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
          IconButton(
            tooltip: 'Forget device',
            onPressed: () => _confirmForget(context),
            icon: const Icon(Icons.link_off_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${device.name}?'),
        content: const Text(
          'The pinned fingerprint is removed. This device will need to be '
          'confirmed again before it can send files without a prompt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) onForget();
  }
}
