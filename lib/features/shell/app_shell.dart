import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../app/state/app_state.dart';
import '../../features/history/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/incoming/incoming_dialogs.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/share/share_bridge.dart';
import '../../features/share/share_sheet.dart';
import '../../features/transfers/transfers_screen.dart';
import '../../ui/glow.dart';

/// Navigation shell: splash while starting, fatal-error screen if startup
/// fails, otherwise radar home + transfers + history + settings.
///
/// Side-effects (incoming offer dialogs, text dialogs, notice snackbars) are
/// driven from here so they work no matter which tab is visible.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;
  bool _starting = false;
  bool _dragging = false;
  ShareBridge? _shareBridge;
  final Set<String> _showedOffers = {};
  final Set<_TextKey> _showedTexts = {};

  static const _pages = [
    HomeScreen(),
    TransfersScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  static const _labels = ['Nearby', 'Transfers', 'History', 'Settings'];
  static const _icons = [
    Icons.radar_rounded,
    Icons.swap_vert_rounded,
    Icons.history_rounded,
    Icons.settings_rounded,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      await ref.read(appControllerProvider.notifier).init();
      // Share sheet bridge (Android SEND intent + iOS with extension).
      _shareBridge =
          ShareBridge(ref.read(appControllerProvider.notifier));
      unawaited(_shareBridge?.attach());
    } finally {
      if (mounted) _starting = false;
    }
  }

  void _handleDrop(DropDoneDetails details) {
    setState(() => _dragging = false);
    final controller = ref.read(appControllerProvider.notifier);
    final items = details.files
        .where((file) => file.path.isNotEmpty)
        .map(
          (file) => ShareItem(
            filePath: file.path,
            name: file.name,
            mime: file.mimeType ?? 'application/octet-stream',
          ),
        )
        .toList();
    if (items.isEmpty) return;
    unawaited(controller.ingestShare(items));
  }

  @override
  void dispose() {
    _shareBridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<String?>(appControllerProvider.select((s) => s.notice),
        (previous, next) {
      if (next == null || next == previous) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(content: Text(next)));
      controller.clearNotice();
    });

    // Incoming offers: show dialog for each new pending offer.
    ref.listen<List<IncomingOffer>>(
        appControllerProvider.select((s) => s.pendingOffers), (previous, next) {
      for (final offer in next) {
        if (_showedOffers.add(offer.sessionId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showIncomingOfferDialog(context, offer).whenComplete(() {
              _showedOffers.remove(offer.sessionId);
            });
          });
        }
      }
    });

    // Incoming text (from /v1/text for third-party senders).
    ref.listen<List<IncomingText>>(
        appControllerProvider.select((s) => s.incomingTexts), (previous, next) {
      for (final entry in next) {
        final key = _TextKey(entry.senderName, entry.receivedAt);
        if (_showedTexts.add(key)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showIncomingTextDialog(context, entry).whenComplete(() {
              _showedTexts.remove(key);
            });
          });
        }
      }
    });

    // Shares that arrived through the OS share sheet.
    ref.listen<List<ShareItem>>(
        appControllerProvider.select((s) => s.pendingShare), (previous, next) {
      if (next.isEmpty || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showShareSheet(context, next);
      });
    });

    if (state.fatalError != null && !state.ready) {
      return _FatalError(
        message: state.fatalError!,
        onRetry: () {
          controller.clearFatalError();
          controller.clearNotice();
          _starting = false;
          _start();
        },
      );
    }
    if (!state.ready) {
      return _Splash(message: state.loadingMessage);
    }
    if (!state.settings.onboardingDone) {
      return const OnboardingScreen();
    }

    final active = state.activeSessions.length;
    final pending = state.pendingOffers.length;

    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = IndexedStack(index: _tab, children: _pages);

    return Scaffold(
      extendBody: true,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) => _handleDrop(details),
        child: Stack(
          children: [
            NeonBackground(
              child: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _tab,
                          onDestinationSelected: (i) =>
                              setState(() => _tab = i),
                          labelType: NavigationRailLabelType
                              .none, // custom labels below
                          destinations: [
                            for (var i = 0; i < _labels.length; i++)
                              NavigationRailDestination(
                                icon: Badge(
                                  isLabelVisible: i == 1 && active > 0 ||
                                      i == 0 && pending > 0,
                                  label: Text(
                                    i == 0 && pending > 0
                                        ? '$pending'
                                        : '$active',
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                  child: Icon(_icons[i]),
                                ),
                                label: Text(_labels[i]),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
            ),
            if (_dragging)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: GlowCard(
                    accent: scheme.primary,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlowIcon(
                          icon: Icons.cloud_upload_rounded,
                          size: 56,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Drop files to send',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'FlowDrop will pick a device to forward them to',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (var i = 0; i < _labels.length; i++)
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible:
                          i == 1 && active > 0 || i == 0 && pending > 0,
                      label: Text(
                        i == 0 && pending > 0 ? '$pending' : '$active',
                        style: const TextStyle(fontSize: 9),
                      ),
                      child: Icon(_icons[i]),
                    ),
                    label: _labels[i],
                  ),
              ],
            ),
      floatingActionButton: state.serverRunning
          ? FloatingActionButton.small(
              heroTag: 'status',
              tooltip: state.serverPort > 0
                  ? 'Listening on port ${state.serverPort}'
                  : 'Server running',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FlowDrop is listening',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(
                        state.serverPort > 0
                            ? 'HTTPS server on port ${state.serverPort} · pinned client certificate required.'
                            : 'HTTPS server running with a pinned client certificate.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlowButton(
                        label: 'Done',
                        tone: GlowTone.ghost,
                        expanded: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Icon(Icons.lock_rounded),
            )
          : null,
    );
  }
}

class _TextKey {
  _TextKey(this.sender, this.at);
  final String sender;
  final DateTime at;
  @override
  bool operator ==(Object other) =>
      other is _TextKey && other.sender == sender && other.at == at;
  @override
  int get hashCode => Object.hash(sender, at);
}

/// Splash while the secure server, discovery and storage boot.
class _Splash extends StatelessWidget {
  const _Splash({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: NeonBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulseDot(color: Color(0xFF4DE1FF), size: 14),
              const SizedBox(height: 22),
              const GradientHeadline(
                'FlowDrop',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FatalError extends StatelessWidget {
  const _FatalError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: NeonBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: GlowCard(
                accent: scheme.error,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GlowIcon(
                          icon: Icons.error_outline_rounded,
                          color: scheme.error,
                          size: 44,
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'FlowDrop couldn\'t start',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GlowButton(
                      label: 'Try again',
                      icon: Icons.restart_alt_rounded,
                      expanded: true,
                      onPressed: onRetry,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Make sure another FlowDrop instance isn\'t running. '
                        'The server needs one free port.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
