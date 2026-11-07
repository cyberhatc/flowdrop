import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../app/state/app_state.dart';
import '../../core/discovery/peer.dart';
import '../../core/security/fingerprint.dart';
import '../../ui/glow.dart';
import '../connect/manual_connect_dialog.dart';
import '../qr/qr_screen.dart';
import '../send/send_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final peers = state.peers;
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _Header(state: state),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final radar = _RadarCard(
                  peers: peers,
                  deviceName: state.deviceName,
                  localFingerprint: state.identity?.fingerprint ?? '',
                  trustedFingerprints: {
                    for (final device in state.trustedDevices)
                      normalizeFingerprint(device.fingerprint),
                  },
                  onPeerTap: (peer) => showSendSheet(context, peer.device),
                );
                final side = _QuickActions(
                  state: state,
                  hasPeers: peers.isNotEmpty,
                  onRefresh: controller.refreshNearby,
                );
                if (!wide) {
                  return Column(
                    children: [
                      radar,
                      const SizedBox(height: 18),
                      side,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: radar),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: side),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                const Text(
                  'Nearby devices',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                if (peers.isNotEmpty)
                  StatusPill(
                    label: '${peers.length}',
                    color: scheme.primary,
                    icon: Icons.radar_rounded,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: controller.refreshNearby,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (peers.isEmpty)
              _NoPeers(onShowQr: () => showQrScreen(context))
            else
              for (final peer in peers) ...[
                _PeerTile(
                  peer: peer,
                  trusted: _isTrusted(state, peer),
                  onTap: () => showSendSheet(context, peer.device),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 8),
            Text(
              'Discoveries happen on your local network only. Every connection '
              'uses TLS with a pinned certificate fingerprint.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isTrusted(AppState state, Peer peer) {
    return state.trustedDevices.any(
      (device) => fingerprintsEqual(device.fingerprint, peer.device.fingerprint),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GradientHeadline(
                    state.deviceName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.identity?.fingerprint.isNotEmpty == true
                        ? fingerprintPhrase(state.identity!.fingerprint)
                        : 'Preparing identity…',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.3,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            _FingerprintChip(fingerprint: state.shortFingerprint),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              label: state.serverRunning ? 'Ready to receive' : 'Server offline',
              color: state.serverRunning ? scheme.primary : scheme.error,
              icon: state.serverRunning
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
            ),
            StatusPill(
              label: state.settings.discoveryEnabled
                  ? (state.udpRunning ? 'Discoverable' : 'Discovery blocked')
                  : 'Invisible',
              color: !state.settings.discoveryEnabled
                  ? scheme.onSurface.withValues(alpha: 0.5)
                  : (state.udpRunning ? scheme.secondary : scheme.error),
              icon: state.settings.discoveryEnabled
                  ? Icons.wifi_tethering_rounded
                  : Icons.visibility_off_rounded,
            ),
            if (state.serverPort > 0)
              StatusPill(
                label: 'Port ${state.serverPort}',
                color: scheme.onSurface.withValues(alpha: 0.55),
                icon: Icons.tag_rounded,
              ),
          ],
        ),
      ],
    );
  }
}

class _FingerprintChip extends StatelessWidget {
  const _FingerprintChip({required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (fingerprint.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: 'Copy your identity fingerprint',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: fingerprint));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Fingerprint copied')),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: scheme.primary.withValues(alpha: 0.08),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                fingerprint,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarCard extends StatelessWidget {
  const _RadarCard({
    required this.peers,
    required this.deviceName,
    required this.localFingerprint,
    required this.trustedFingerprints,
    required this.onPeerTap,
  });

  final List<Peer> peers;
  final String deviceName;
  final String localFingerprint;
  final Set<String> trustedFingerprints;
  final ValueChanged<Peer> onPeerTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = peers.take(8).toList(growable: false);

    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 348,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final center = size.center(Offset.zero);
            final orbit = math.min(size.width, size.height) * 0.33;
            final nodes = <Widget>[];
            for (var i = 0; i < visible.length; i++) {
              final angle = -math.pi / 2 + i * (2 * math.pi / visible.length);
              final position = Offset(
                center.dx + math.cos(angle) * orbit,
                center.dy + math.sin(angle) * orbit,
              );
              nodes.add(
                Positioned(
                  left: position.dx - 42,
                  top: position.dy - 40,
                  width: 84,
                  child: _PeerBubble(
                    peer: visible[i],
                    trusted: trustedFingerprints.contains(
                      normalizeFingerprint(visible[i].device.fingerprint),
                    ),
                    onTap: () => onPeerTap(visible[i]),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Center(
                    child: RadarSweep(
                      color: scheme.primary,
                      size: math.min(size.width, size.height) * 0.92,
                    ),
                  ),
                ),
                Positioned(
                  left: center.dx - 46,
                  top: center.dy - 40,
                  width: 92,
                  child: _LocalNode(
                    name: deviceName,
                    fingerprint: localFingerprint,
                  ),
                ),
                ...nodes,
                if (visible.isEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Text(
                      'Looking for nearby devices…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocalNode extends StatelessWidget {
  const _LocalNode({required this.name, required this.fingerprint});

  final String name;
  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary.withValues(alpha: 0.14),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.3),
                blurRadius: 26,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(
            Icons.devices_rounded,
            color: scheme.primary,
            size: 34,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        Text(
          'This device',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

class _PeerBubble extends StatelessWidget {
  const _PeerBubble({
    required this.peer,
    required this.trusted,
    required this.onTap,
  });

  final Peer peer;
  final bool trusted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = trusted ? scheme.primary : scheme.secondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.14),
              border: Border.all(color: tint.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.25),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Icon(
              _platformIcon(peer.device.platform),
              color: tint,
              size: 24,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            peer.device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
          if (trusted)
            Icon(Icons.verified_rounded, size: 11, color: tint),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.state,
    required this.hasPeers,
    required this.onRefresh,
  });

  final AppState state;
  final bool hasPeers;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connect',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            hasPeers
                ? 'Tap a device to send files or text. No setup needed.'
                : 'Show a QR code or enter the other device address.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
          GlowButton(
            label: 'Show my QR code',
            icon: Icons.qr_code_2_rounded,
            expanded: true,
            onPressed: () => showQrScreen(context),
          ),
          const SizedBox(height: 10),
          GlowButton(
            label: 'Connect by address',
            icon: Icons.link_rounded,
            tone: GlowTone.ghost,
            expanded: true,
            onPressed: () => showManualConnectDialog(context),
          ),
          const SizedBox(height: 10),
          GlowButton(
            label: 'Refresh radar',
            icon: Icons.refresh_rounded,
            tone: GlowTone.ghost,
            expanded: true,
            onPressed: () => onRefresh(),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.lan_rounded,
            label: state.addresses.isEmpty
                ? 'No IPv4 address detected'
                : state.addresses.join(', '),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.tag_rounded,
            label: state.serverPort > 0
                ? 'Listening on port ${state.serverPort}'
                : 'Server not listening',
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.security_rounded,
            label: state.settings.autoAcceptTrusted
                ? 'Paired devices send without a prompt'
                : 'Every transfer needs confirmation',
          ),
          if (state.settings.discoveryEnabled && !state.udpRunning) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.error.withValues(alpha: 0.07),
                border: Border.all(color: scheme.error.withValues(alpha: 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Discovery looks blocked. Allow FlowDrop through the '
                      'firewall, or use the QR code.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
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
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: scheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
      ],
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peer,
    required this.trusted,
    required this.onTap,
  });

  final Peer peer;
  final bool trusted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = peer.device;
    return GlowCard(
      glow: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: onTap,
      child: Row(
        children: [
          GlowIcon(
            icon: _platformIcon(device.platform),
            color: trusted ? scheme.primary : scheme.secondary,
            size: 44,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (trusted) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${device.addresses.isEmpty ? 'No address' : device.addresses.first}'
                  ' · ${_sourceLabel(peer.source)} · ${_platformLabel(device.platform)}',
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
          StatusPill(
            label: trusted ? 'Paired' : 'New',
            color: trusted
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.55),
            icon: trusted ? Icons.verified_rounded : Icons.fiber_new_rounded,
          ),
          const SizedBox(width: 8),
          Icon(Icons.send_rounded, size: 18, color: scheme.primary),
        ],
      ),
    );
  }
}

class _NoPeers extends StatelessWidget {
  const _NoPeers({required this.onShowQr});

  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlowCard(
      glow: false,
      child: Column(
        children: [
          const SizedBox(height: 8),
          GlowIcon(icon: Icons.radar_rounded, color: scheme.primary, size: 52),
          const SizedBox(height: 14),
          const Text(
            'No devices nearby yet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Make sure the other device is on the same Wi-Fi or hotspot and has '
            'FlowDrop open. Discovery can take a few seconds.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          GlowButton(
            label: 'Show my QR code',
            icon: Icons.qr_code_2_rounded,
            tone: GlowTone.ghost,
            onPressed: onShowQr,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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

String _platformLabel(String platform) {
  switch (platform.toLowerCase()) {
    case 'windows':
      return 'Windows';
    case 'macos':
      return 'macOS';
    case 'linux':
      return 'Linux';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iOS';
    default:
      return platform;
  }
}

String _sourceLabel(PeerSource source) {
  switch (source) {
    case PeerSource.udp:
      return 'Nearby';
    case PeerSource.mdns:
      return 'mDNS';
    case PeerSource.qr:
      return 'Paired';
    case PeerSource.manual:
      return 'Manual';
  }
}
