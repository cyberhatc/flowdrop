import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/state/app_controller.dart';
import '../../../core/protocol/constants.dart';
import '../../../ui/glow.dart';

Future<void> showManualConnectDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ManualConnectDialog(),
  );
}

class _ManualConnectDialog extends ConsumerStatefulWidget {
  const _ManualConnectDialog();

  @override
  ConsumerState<_ManualConnectDialog> createState() =>
      _ManualConnectDialogState();
}

class _ManualConnectDialogState extends ConsumerState<_ManualConnectDialog> {
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '${FlowDropProtocol.defaultPort}');
  final _fingerprint = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _fingerprint.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a port between 1 and 65535.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final device = await ref
          .read(appControllerProvider.notifier)
          .connectManually(
            host: _ip.text,
            port: port,
            fingerprint: _fingerprint.text,
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('FlowDropException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Connect by address'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use this when discovery is blocked. The short fingerprint is '
                'shown on the other device.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ip,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'IP address',
                  hintText: '192.168.1.24',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Port'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fingerprint,
                decoration: const InputDecoration(
                  labelText: 'Certificate fingerprint',
                  hintText: 'a1b2 c3d4 e5f6 7890',
                  helperText: 'At least 16 hex characters',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        GlowButton(
          label: 'Connect',
          icon: Icons.link_rounded,
          busy: _busy,
          onPressed: _connect,
        ),
      ],
    );
  }
}
