import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/state/app_controller.dart';
import '../../core/discovery/qr_payload.dart';
import '../../core/security/fingerprint.dart';
import '../../ui/glow.dart';

Future<void> showQrScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const QrScreen()),
  );
}

class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen> {
  QrPayload? _payload;
  String? _error;
  bool _loading = true;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final payload = _payload;
      if (payload == null) return;
      final left = payload.remaining;
      if (left != _remaining) setState(() => _remaining = left);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload =
          await ref.read(appControllerProvider.notifier).createQrPayload();
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _remaining = payload.remaining;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('FlowDropException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final payload = _payload;
    final expired = payload != null && payload.remaining == Duration.zero;

    return Scaffold(
      body: NeonBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Your QR code',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _openScanner(context),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('Scan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GlowCard(
                    child: Column(
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 90),
                            child: CircularProgressIndicator(),
                          )
                        else if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: scheme.error,
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.error,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                GlowButton(
                                  label: 'Try again',
                                  icon: Icons.refresh_rounded,
                                  onPressed: _generate,
                                ),
                              ],
                            ),
                          )
                        else if (payload != null)
                          _QrBody(
                            payload: payload,
                            expired: expired,
                            remaining: _remaining,
                            onRefresh: _generate,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Scan this code from another FlowDrop device. '
                          'It expires after two minutes and can be used once.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        if (payload != null) ...[
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          _ConnectionFacts(payload: payload),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlowButton(
                    label: 'Scan a code instead',
                    icon: Icons.camera_alt_rounded,
                    tone: GlowTone.ghost,
                    expanded: true,
                    onPressed: () => _openScanner(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
    );
  }
}

class _QrBody extends StatelessWidget {
  const _QrBody({
    required this.payload,
    required this.expired,
    required this.remaining,
    required this.onRefresh,
  });

  final QrPayload payload;
  final bool expired;
  final Duration remaining;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return Column(
      children: [
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: expired ? 0.18 : 1,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 32,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: payload.encode(),
                  version: QrVersions.auto,
                  size: 236,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            if (expired)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlowIcon(
                    icon: Icons.timer_off_rounded,
                    color: scheme.error,
                    size: 46,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Code expired',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GlowButton(
                    label: 'New code',
                    icon: Icons.refresh_rounded,
                    onPressed: () => onRefresh(),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          payload.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        StatusPill(
          label: expired
              ? 'Expired'
              : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} left',
          color: expired ? scheme.error : scheme.primary,
          icon: expired ? Icons.timer_off_rounded : Icons.timer_rounded,
        ),
      ],
    );
  }
}

class _ConnectionFacts extends StatelessWidget {
  const _ConnectionFacts({required this.payload});

  final QrPayload payload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fact(
          context,
          Icons.lan_rounded,
          payload.addresses.join(', '),
          scheme,
        ),
        const SizedBox(height: 8),
        _fact(
          context,
          Icons.tag_rounded,
          'Port ${payload.port}',
          scheme,
        ),
        const SizedBox(height: 8),
        _fact(
          context,
          Icons.fingerprint_rounded,
          fingerprintPhrase(payload.fingerprint),
          scheme,
        ),
      ],
    );
  }

  Widget _fact(
    BuildContext context,
    IconData icon,
    String value,
    ColorScheme scheme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

bool get _scannerSupported {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _manual = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _lastRaw;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _connect(String raw) async {
    if (_busy) return;
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste a FlowDrop code or scan a QR code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final payload = QrPayload.parse(text);
      final device =
          await ref.read(appControllerProvider.notifier).connectWithQr(payload);
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        SnackBar(content: Text('Paired with ${device.name}')),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('FlowDropException: ', '');
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) setState(() => _error = 'Clipboard is empty.');
      return;
    }
    _manual.text = text;
    await _connect(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a code')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (_scannerSupported)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            onDetect: (capture) {
                              if (capture.barcodes.isEmpty) return;
                              final raw = capture.barcodes.first.rawValue;
                              if (raw == null || raw == _lastRaw) return;
                              _lastRaw = raw;
                              _manual.text = raw;
                              _connect(raw);
                            },
                          ),
                          IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.55),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          if (_busy)
                            Container(
                              color: Colors.black.withValues(alpha: 0.45),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  GlowCard(
                    glow: false,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        GlowIcon(
                          icon: Icons.qr_code_scanner_rounded,
                          size: 54,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Camera scanning is not available on this platform',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Show the code on the other device and paste the '
                          'FlowDrop link below, or use Connect by address.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                TextField(
                  controller: _manual,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'FlowDrop code',
                    hintText: 'flowdrop://connect?…',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GlowButton(
                        label: 'Connect',
                        icon: Icons.link_rounded,
                        expanded: true,
                        busy: _busy,
                        onPressed: () => _connect(_manual.text),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlowButton(
                      label: 'Paste',
                      icon: Icons.content_paste_rounded,
                      tone: GlowTone.ghost,
                      onPressed: _busy ? null : _paste,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
