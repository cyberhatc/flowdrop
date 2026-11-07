import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

import '../protocol/constants.dart';
import '../protocol/device.dart';

/// Best-effort mDNS/DNS-SD discovery.
///
/// FlowDrop advertises with the UDP beacon; mDNS is used to find other clients
/// (and compatible third-party implementations) when the network allows it.
/// Missing avahi/Bonjour or a blocked multicast group must never be fatal.
class MdnsDiscoveryService {
  MdnsDiscoveryService({
    required this.onDevice,
    this.scanInterval = const Duration(seconds: 4),
    this.onError,
  });

  final void Function(DeviceInfo device) onDevice;
  final Duration scanInterval;
  final void Function(Object error)? onError;

  MDnsClient? _client;
  Timer? _timer;
  bool _started = false;
  bool _scanning = false;

  static const String _service = '${FlowDropProtocol.serviceType}.'
      '${FlowDropProtocol.serviceDomain}';

  bool get isRunning => _started;

  Future<void> start() async {
    if (_started) return;
    try {
      final client = MDnsClient();
      await client.start();
      _client = client;
      _started = true;
      _timer = Timer.periodic(scanInterval, (_) => unawaited(_scan()));
      unawaited(_scan());
    } on Object catch (error) {
      onError?.call(error);
      await stop();
    }
  }

  Future<void> _scan() async {
    final client = _client;
    if (client == null || _scanning || !_started) return;
    _scanning = true;
    try {
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_service),
            timeout: const Duration(seconds: 2),
          )
          .toList()
          .timeout(const Duration(seconds: 3), onTimeout: () => const []);
      for (final pointer in pointers) {
        final service = await _first(
          client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(pointer.domainName),
            timeout: const Duration(seconds: 2),
          ),
        );
        if (service == null) continue;
        final txt = await _first(
          client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(pointer.domainName),
            timeout: const Duration(seconds: 2),
          ),
        );
        if (txt == null) continue;
        final fields = _parseTxt(txt.text);
        final id = fields['id'];
        final fingerprint = fields['fp'];
        final version = int.tryParse(fields['v'] ?? '');
        if (id == null || id.isEmpty) continue;
        if (fingerprint == null || fingerprint.length < 32) continue;
        if (version == null || version != FlowDropProtocol.version) continue;

        final addresses = <String>[];
        final addressRecords = await client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(service.target),
              timeout: const Duration(seconds: 2),
            )
            .toList()
            .timeout(const Duration(seconds: 3), onTimeout: () => const []);
        for (final record in addressRecords) {
          addresses.add(record.address.address);
        }
        if (addresses.isEmpty) continue;

        onDevice(
          DeviceInfo(
            id: id,
            name: fields['name'] ?? 'FlowDrop device',
            platform: fields['platform'] ?? 'unknown',
            publicKey: fields['pk'] ?? '',
            fingerprint: fingerprint,
            addresses: addresses,
            port: service.port,
            protocolVersion: version,
          ),
        );
      }
    } on TimeoutException {
      // Normal on quiet networks.
    } on Object catch (error) {
      onError?.call(error);
    } finally {
      _scanning = false;
    }
  }

  Map<String, String> _parseTxt(String text) {
    final fields = <String, String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final index = line.indexOf('=');
      if (index <= 0) continue;
      fields[line.substring(0, index)] = line.substring(index + 1);
    }
    return fields;
  }

  Future<T?> _first<T>(Stream<T> stream) async {
    try {
      return await stream.first.timeout(const Duration(seconds: 2));
    } on Object {
      return null;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _client?.stop();
    _client = null;
  }
}
