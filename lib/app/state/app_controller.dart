import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/clipboard/clipboard_sync.dart';
import '../../core/discovery/discovery_service.dart';
import '../../core/discovery/network_interfaces.dart';
import '../../core/discovery/peer.dart';
import '../../core/protocol/paths.dart';
import '../../core/discovery/qr_payload.dart';
import '../../core/protocol/constants.dart';
import '../../core/protocol/device.dart';
import '../../core/protocol/offers.dart';
import '../../core/security/fingerprint.dart';
import '../../core/security/identity.dart';
import '../../core/security/pairing.dart';
import '../../core/security/trust_store.dart';
import '../../core/storage/history_store.dart';
import '../../core/storage/settings.dart';
import '../../core/transfer/transfer_models.dart';
import '../../core/transport/client.dart';
import '../../core/transport/server.dart';
import '../storage/json_trust_store.dart';
import '../storage/prefs_settings_store.dart';
import '../storage/secure_identity_store.dart';
import 'app_state.dart';

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

/// Owns every long-lived resource: identity, HTTPS server, discovery, the
/// trust store, history and active clients. The UI only calls methods here.
class AppController extends Notifier<AppState> {
  SettingsStore _settingsStore = InMemorySettingsStore();
  SecureIdentityStore? _identityStore;
  TrustStore? _trustStore;
  HistoryStore? _history;

  DeviceIdentity? _identity;
  FlowDropServer? _server;
  DiscoveryService? _discovery;
  final PairingTokenManager _tokenManager = PairingTokenManager();

  String _downloadDirectory = '';
  List<String> _addresses = const [];
  final Map<String, Completer<bool>> _pendingOffers = {};
  final Map<String, FlowDropClient> _outgoingClients = {};
  final Map<String, OfferRequest> _incomingOffers = {};
  final Set<String> _cancelledSessions = {};

  StreamSubscription<List<Peer>>? _peerSubscription;
  Timer? _addressTimer;
  Timer? _presenceTimer;
  final Set<String> _probing = {};
  final Map<String, DateTime> _nextProbe = {};
  final Map<String, ({int bytes, DateTime at})> _speedSamples = {};

  // Clipboard sync (opt-in). The watcher polls the OS clipboard; the guard
  // remembers remote payloads so received values are never re-pushed.
  final ClipboardSyncGuard _clipboardGuard = ClipboardSyncGuard();
  Timer? _clipboardTimer;
  bool _clipboardSyncing = false;

  bool _initialising = false;
  bool _disposed = false;

  @override
  AppState build() {
    ref.onDispose(_dispose);
    return const AppState();
  }

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialising || state.ready) return;
    _initialising = true;
    try {
      _settingsStore = PrefsSettingsStore();
      _identityStore = SecureIdentityStore();

      final support = await getApplicationSupportDirectory();
      final downloads =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();

      var settings = await _settingsStore.load();
      final hostname = _hostname();
      if (settings.deviceName.trim().isEmpty) {
        settings = settings.copyWith(deviceName: hostname);
        await _settingsStore.save(settings);
      }
      _set(state.copyWith(settings: settings));

      _set(state.copyWith(loadingMessage: 'Creating your secure identity…'));
      final stored = await _identityStore!.load();
      final identity =
          stored ??
          await DeviceIdentity.generate(
            name: settings.deviceName,
            platform: Platform.operatingSystem,
          );
      final named = identity.copyWith(name: settings.deviceName);
      _identity = named;
      await _identityStore!.save(named);

      _trustStore = JsonTrustStore(
        File(p.join(support.path, 'trusted_devices.json')),
      );
      try {
        _history = HistoryStore.open(p.join(support.path, 'history.db'));
      } on Object {
        _history = HistoryStore.inMemory();
      }

      _downloadDirectory = settings.receiveDirectory.trim().isNotEmpty
          ? settings.receiveDirectory
          : p.join(downloads.path, 'FlowDrop');
      await Directory(_downloadDirectory).create(recursive: true);
      await _refreshAddressesInternal();

      _set(state.copyWith(loadingMessage: 'Starting the secure server…'));
      await _startServer();

      final trusted = await _trustStore!.all();
      _set(
        state.copyWith(
          ready: true,
          loadingMessage: 'Live',
          identity: named,
          trustedDevices: trusted,
          history: _history?.recent() ?? const [],
        ),
      );

      await _startDiscovery();
      _seedPairedPeers(trusted);
      _presenceTimer = Timer.periodic(
        FlowDropProtocol.pairedProbeInterval,
        (_) => unawaited(_probePairedPeers()),
      );
      _addressTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(refreshAddresses()),
      );
      syncClipboardWatcher();
    } on Object catch (error) {
      _set(
        state.copyWith(
          fatalError: 'FlowDrop could not start: $error',
          loadingMessage: 'Startup failed',
        ),
      );
    } finally {
      _initialising = false;
    }
  }

  String _hostname() {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty) return name;
    } on Object {
      // Some sandboxes block the hostname lookup.
    }
    return 'FlowDrop device';
  }

  Future<void> _startServer() async {
    final identity = _identity;
    if (identity == null) throw StateError('Identity is not ready');
    final server = FlowDropServer(
      identity: identity,
      downloadDirectory: _downloadDirectory,
      onOffer: _approveOffer,
      trustStore: _trustStore!,
      tokenManager: _tokenManager,
      deviceInfoBuilder: (port) => identity.toDeviceInfo(
        addresses: _effectiveAddresses,
        port: port,
        name: state.settings.deviceName,
      ),
      onText: _handleIncomingText,
      onClipboard: _handleClipboard,
      onEvent: _handleServerEvent,
    );
    server.autoDeclineUntrusted =
        state.settings.visibility == VisibilityMode.trustedOnly;
    await server.start();
    _server = server;
    _set(
      state.copyWith(
        serverRunning: true,
        serverPort: server.port,
        localDevice: _currentLocalDevice,
        addresses: _addresses,
      ),
    );
  }

  Future<void> _startDiscovery() async {
    await _peerSubscription?.cancel();
    _peerSubscription = null;
    await _discovery?.dispose();

    final hidden = state.settings.visibility == VisibilityMode.hidden;
    // In hidden / discovery-off mode we keep a passive registry alive instead
    // of dropping discovery entirely: paired devices still appear and can be
    // reconnected by address even when this device is invisible.
    final passive = !state.settings.discoveryEnabled || hidden;

    final discovery = DiscoveryService(
      deviceInfo: () => _currentLocalDevice ?? _fallbackDevice,
      broadcast: !passive,
      useMdns: !passive && state.settings.useMdns,
      isPaired: (deviceId) =>
          state.trustedDevices.any((device) => device.deviceId == deviceId),
      onError: (_) {
        // Discovery is best effort. A firewall hint is shown in the UI.
      },
    );
    _discovery = discovery;
    try {
      await discovery.start();
    } on Object {
      // QR and manual connect still work.
    }
    _seedPairedPeers(state.trustedDevices);
    _peerSubscription = discovery.peers.listen((peers) {
      _set(state.copyWith(peers: peers));
    });
    _set(
      state.copyWith(
        peers: discovery.nearby,
        udpRunning: discovery.udpRunning,
        mdnsRunning: discovery.mdnsRunning,
      ),
    );
  }

  DeviceInfo get _fallbackDevice => DeviceInfo(
    id: _identity?.id ?? '',
    name: state.settings.deviceName,
    platform: Platform.operatingSystem,
    publicKey: _identity?.publicKey ?? '',
    fingerprint: _identity?.fingerprint ?? '',
    addresses: _effectiveAddresses,
    port: _server?.port ?? FlowDropProtocol.defaultPort,
  );

  DeviceInfo? get _currentLocalDevice {
    final identity = _identity;
    if (identity == null) return null;
    return identity.toDeviceInfo(
      addresses: _effectiveAddresses,
      port: _server?.port ?? FlowDropProtocol.defaultPort,
      name: state.settings.deviceName,
    );
  }

  List<String> get _effectiveAddresses =>
      _addresses.isEmpty ? const ['127.0.0.1'] : _addresses;

  Future<void> _refreshAddressesInternal() async {
    try {
      _addresses = await localIPv4Addresses();
    } on Object {
      _addresses = const [];
    }
  }

  Future<void> refreshAddresses() async {
    await _refreshAddressesInternal();
    _set(
      state.copyWith(addresses: _addresses, localDevice: _currentLocalDevice),
    );
  }

  Future<void> refreshNearby() async {
    await refreshAddresses();
    await _discovery?.refresh();
    _set(state.copyWith(peers: _discovery?.nearby ?? state.peers));
  }

  // ---------------------------------------------------------------------------
  // Paired-device presence (stay reachable after restarts / Wi-Fi changes)
  // ---------------------------------------------------------------------------

  /// Puts every paired device on the radar, even if it is not beaconing right
  /// now. This is what stops a paired phone from vanishing after an app
  /// restart and makes "send to my laptop" a one-tap action later.
  void _seedPairedPeers(List<TrustedDevice> devices) {
    final discovery = _discovery;
    if (discovery == null) return;
    for (final device in devices) {
      discovery.seedPaired(device.toDeviceInfo(), lastSeen: device.lastSeen);
    }
    _set(state.copyWith(peers: discovery.nearby));
  }

  /// Probes paired devices that are not currently visible and refreshes their
  /// endpoint in the trust store. Runs on a timer and from the UI button.
  Future<void> reconnectPaired() async {
    _nextProbe.clear();
    await _probePairedPeers(wait: true);
    final online = state.trustedDevices
        .where((device) => _peerFor(device)?.isLive == true)
        .length;
    _banner(
      state.trustedDevices.isEmpty
          ? 'Pair a device first — tap Show my QR code'
          : online == 0
          ? 'No paired device answered. Check Wi-Fi or open FlowDrop there.'
          : '$online paired device${online == 1 ? '' : 's'} reachable',
    );
  }

  Future<void> _probePairedPeers({bool wait = false}) async {
    if (_identity == null || _disposed) return;
    final devices = state.trustedDevices;
    final pending = <Future<void>>[];
    for (final device in devices) {
      final peer = _peerFor(device);
      if (peer != null && peer.isLive) continue;
      final next = _nextProbe[device.deviceId];
      if (next != null && next.isAfter(DateTime.now())) continue;
      final probe = _probePairedDevice(device);
      if (wait) {
        pending.add(probe);
      } else {
        unawaited(probe);
      }
    }
    if (wait) await Future.wait(pending);
  }

  Peer? _peerFor(TrustedDevice device) {
    for (final peer in state.peers) {
      if (peer.device.id == device.deviceId ||
          fingerprintsEqual(peer.device.fingerprint, device.fingerprint)) {
        return peer;
      }
    }
    return null;
  }

  Future<void> _probePairedDevice(TrustedDevice device) async {
    if (_probing.contains(device.deviceId)) return;
    final identity = _identity;
    final local = _currentLocalDevice;
    if (identity == null || local == null) return;
    _probing.add(device.deviceId);
    try {
      for (final endpoint in _endpointsForDevice(device)) {
        final client = FlowDropClient(
          host: endpoint.host,
          port: endpoint.port,
          identity: identity,
          localDevice: local,
          expectedFingerprint: device.fingerprint,
          connectionTimeout: const Duration(seconds: 4),
        );
        try {
          final info = await client.info();
          if (info.id != device.deviceId) continue;
          await _rememberPaired(info);
          _nextProbe.remove(device.deviceId);
          return;
        } on Object {
          // Try the next remembered address / port.
        } finally {
          client.close();
        }
      }
      _nextProbe[device.deviceId] = DateTime.now().add(
        FlowDropProtocol.pairedRetryDelay,
      );
    } finally {
      _probing.remove(device.deviceId);
    }
  }

  /// Persists the endpoint a paired device just answered on, so the next cold
  /// start can reconnect without discovery.
  Future<void> _rememberPaired(DeviceInfo info) async {
    final index = state.trustedDevices.indexWhere(
      (device) =>
          device.deviceId == info.id ||
          fingerprintsEqual(device.fingerprint, info.fingerprint),
    );
    if (index < 0) return;
    final current = state.trustedDevices[index];
    final merged = current.mergeDevice(info);
    final changed =
        merged.port != current.port ||
        merged.addresses.join(',') != current.addresses.join(',') ||
        merged.name != current.name;
    final staleWrite =
        current.lastSeen == null ||
        DateTime.now().difference(current.lastSeen!) >
            const Duration(seconds: 60);
    if (changed || staleWrite) {
      await _trustStore?.trust(merged);
      final next = [...state.trustedDevices];
      next[index] = merged;
      _set(state.copyWith(trustedDevices: next));
    }
    _discovery?.markPairedOnline(info);
    _set(state.copyWith(peers: _discovery?.nearby ?? state.peers));
    if (merged.port != current.port) {
      // The remote app may have restarted on a different port; beacons will
      // catch up, and the probe path already uses the fresh endpoint.
      _banner('${info.name} is reachable on port ${merged.port}');
    }
  }

  /// Every endpoint worth trying for a device: live addresses first, then
  /// remembered ones, and the default port as a last resort.
  List<({String host, int port})> _endpointsForDevice(TrustedDevice device) {
    return _endpoints(device.addresses, device.port);
  }

  List<({String host, int port})> _endpoints(
    Iterable<String> addresses,
    int port,
  ) {
    final hosts = addresses
        .map((address) => address.trim())
        .where((address) => address.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final ports = <int>{
      if (port > 0) port,
      FlowDropProtocol.defaultPort,
    }.toList(growable: false);
    return [
      for (final host in hosts.take(6))
        for (final candidate in ports) (host: host, port: candidate),
    ];
  }

  List<({String host, int port})> _endpointsForPeer(DeviceInfo peer) {
    final trusted = state.trustedDevices
        .where(
          (device) =>
              device.deviceId == peer.id ||
              fingerprintsEqual(device.fingerprint, peer.fingerprint),
        )
        .firstOrNull;
    return _endpoints(
      [...peer.addresses, ...?trusted?.addresses],
      peer.port > 0
          ? peer.port
          : (trusted?.port ?? FlowDropProtocol.defaultPort),
    );
  }

  // ---------------------------------------------------------------------------
  // Incoming
  // ---------------------------------------------------------------------------

  Future<bool> _approveOffer(
    OfferRequest offer,
    String remoteIp,
    bool trusted,
  ) async {
    if (trusted) {
      // A paired device just proved it is reachable; keep its endpoint fresh
      // so the next cold start reconnects without discovery.
      unawaited(_rememberPaired(offer.sender));
    }
    if (trusted && state.settings.autoAcceptTrusted) {
      await _beginIncoming(offer, remoteIp, trusted);
      return true;
    }

    final completer = Completer<bool>();
    _pendingOffers[offer.sessionId] = completer;
    _set(
      state.copyWith(
        incoming: [
          ...state.incoming,
          IncomingOffer(
            offer: offer,
            remoteIp: remoteIp,
            trusted: trusted,
            completer: completer,
          ),
        ],
      ),
    );
    _banner(
      offer.files.isEmpty
          ? '${offer.sender.name} sent text'
          : '${offer.sender.name} wants to send ${offer.files.length} file${offer.files.length == 1 ? '' : 's'}',
    );

    final accepted = await completer.future;
    _pendingOffers.remove(offer.sessionId);
    _set(
      state.copyWith(
        incoming: state.incoming
            .where((entry) => entry.sessionId != offer.sessionId)
            .toList(growable: false),
      ),
    );
    if (accepted) {
      await _beginIncoming(offer, remoteIp, trusted);
    } else {
      await _saveRecord(
        _recordFrom(
          offer,
          TransferDirection.received,
          DateTime.now(),
          TransferState.declined,
          finishedAt: DateTime.now(),
        ),
      );
    }
    return accepted;
  }

  /// Registers an accepted incoming session exactly once. The server calls the
  /// approval callback before it creates its own session, so this is the only
  /// place incoming progress can be attached to a UI session.
  Future<void> _beginIncoming(
    OfferRequest offer,
    String remoteIp,
    bool trusted,
  ) async {
    _incomingOffers[offer.sessionId] = offer;
    final textOnly = offer.files.isEmpty;
    final progress = SessionProgress(
      sessionId: offer.sessionId,
      peerName: offer.sender.name,
      files: offer.files
          .map(
            (file) => FileProgress(
              fileId: file.id,
              name: file.name,
              totalBytes: file.size,
            ),
          )
          .toList(growable: false),
      state: textOnly ? TransferState.completed : TransferState.active,
      text: offer.text,
      direction: TransferDirection.received,
    );
    _upsertSession(progress);
    await _saveRecord(
      _recordFrom(
        offer,
        TransferDirection.received,
        DateTime.now(),
        textOnly ? TransferState.completed : TransferState.active,
        finishedAt: textOnly ? DateTime.now() : null,
      ),
    );
  }

  void acceptIncoming(String sessionId) {
    final completer = _pendingOffers.remove(sessionId);
    if (completer != null && !completer.isCompleted) completer.complete(true);
  }

  void declineIncoming(String sessionId) {
    final completer = _pendingOffers.remove(sessionId);
    if (completer != null && !completer.isCompleted) completer.complete(false);
  }

  Future<void> _handleIncomingText(
    TextPayload payload,
    String remoteIp,
    bool trusted,
  ) async {
    _set(
      state.copyWith(
        incomingTexts: [
          IncomingText(
            payload: payload,
            remoteIp: remoteIp,
            trusted: trusted,
            receivedAt: DateTime.now(),
          ),
          ...state.incomingTexts,
        ].take(50).toList(growable: false),
      ),
    );
    _banner('Text received from ${payload.sender.name}');
  }

  void _handleClipboard(String fromFingerprint, String data) {
    final deviceId = state.trustedDevices
        .where(
          (device) => fingerprintsEqual(device.fingerprint, fromFingerprint),
        )
        .map((device) => device.deviceId)
        .firstOrNull;
    final trusted = state.trustedDevices
        .where(
          (device) => fingerprintsEqual(device.fingerprint, fromFingerprint),
        )
        .map((device) => device.name)
        .firstOrNull;
    // Register the payload with the guard first so the local watcher never
    // re-pushes a value that came from a peer (loop prevention).
    _clipboardGuard.rememberRemote(
      ClipboardEvent(
        data: data,
        originDeviceId: deviceId ?? fromFingerprint,
        createdAt: DateTime.now(),
        originFingerprint: fromFingerprint,
      ),
    );
    _set(
      state.copyWith(
        clipboardText: data,
        clipboardFrom: trusted ?? 'a paired device',
        clipboardHistory: [
          ClipboardEntry(
            data: data,
            fromName: trusted ?? 'a paired device',
            at: DateTime.now(),
          ),
          ...state.clipboardHistory,
        ].take(20).toList(growable: false),
      ),
    );
    _banner('Clipboard received from ${trusted ?? 'a paired device'}');
  }

  void dismissIncomingText(IncomingText text) {
    _set(
      state.copyWith(
        incomingTexts: state.incomingTexts
            .where((entry) => !identical(entry, text))
            .toList(growable: false),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Outgoing
  // ---------------------------------------------------------------------------

  /// Ingests items that arrived through the OS share sheet. Each text item
  /// becomes a text entry; each file path becomes a [SendFile] (missing or
  /// unreadable files are skipped with a banner so one bad file never blocks
  /// the rest).
  Future<void> ingestShare(List<ShareItem> items) async {
    final files = <SendFile>[];
    final texts = <String>[];
    for (final item in items) {
      if (item.isFile) {
        final path = item.filePath!;
        try {
          final file = File(path);
          final size = await file.length();
          final name = item.name ?? p.basename(path);
          files.add(
            SendFile(path: path, name: name, size: size, mime: item.mime),
          );
        } on Object {
          _banner('Skipped unreadable shared file: ${item.displayName}');
        }
      } else if (item.text != null && (item.text ?? '').trim().isNotEmpty) {
        texts.add(item.text!.trim());
      }
    }
    if (files.isEmpty && texts.isEmpty) return;
    _set(
      state.copyWith(
        pendingShare: [
          ...files.map(
            (f) => ShareItem(
              filePath: f.path,
              name: f.name,
              size: f.size,
              mime: f.mime,
            ),
          ),
          ...texts.map((t) => ShareItem(text: t)),
        ],
      ),
    );
    _banner(
      files.isEmpty
          ? 'Shared text ready — pick a device'
          : 'Shared ${files.length} item${files.length == 1 ? '' : 's'} — pick a device',
    );
  }

  void clearPendingShare() {
    if (state.pendingShare.isNotEmpty) {
      _set(state.copyWith(clearPendingShare: true));
    }
  }

  Future<String?> sendToPeer({
    required DeviceInfo peer,
    required List<SendFile> files,
    String? text,
  }) async {
    final identity = _identity;
    if (identity == null) return 'FlowDrop is still starting.';
    final endpoints = _endpointsForPeer(peer);
    if (endpoints.isEmpty) {
      return 'No network address for ${peer.name}. Tap reconnect to try again.';
    }
    final trimmed = text?.trim();
    if (files.isEmpty && (trimmed == null || trimmed.isEmpty)) {
      return 'Pick at least one file or type a message.';
    }

    final local = _currentLocalDevice;
    if (local == null) return 'FlowDrop is still starting.';

    final sessionId = FlowDropClient.newSessionId();
    final startedAt = DateTime.now();
    final offered = files
        .map(
          (file) => OfferedFile(
            id: const Uuid().v4(),
            name: file.name,
            size: file.size,
            mime: file.mime,
            relativePath: file.relativePath,
          ),
        )
        .toList(growable: false);
    final byId = {
      for (var i = 0; i < offered.length; i++) offered[i].id: files[i],
    };
    final offer = OfferRequest(
      sessionId: sessionId,
      sender: local,
      files: offered,
      text: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );

    _upsertSession(
      SessionProgress(
        sessionId: sessionId,
        peerName: peer.name,
        files: offered
            .map(
              (file) => FileProgress(
                fileId: file.id,
                name: file.name,
                totalBytes: file.size,
              ),
            )
            .toList(growable: false),
        text: offer.text,
        direction: TransferDirection.sent,
      ),
    );
    await _saveRecord(
      _recordFrom(
        offer,
        TransferDirection.sent,
        startedAt,
        TransferState.active,
      ),
    );

    FlowDropClient? client;
    Object? lastError;
    try {
      // The same device can answer on several addresses (Wi-Fi roam, hotspot,
      // stale DHCP lease). Try them all instead of failing on the first one.
      for (final endpoint in endpoints) {
        final candidate = FlowDropClient(
          host: endpoint.host,
          port: endpoint.port,
          identity: identity,
          localDevice: local,
          expectedFingerprint: peer.fingerprint,
        );
        try {
          final info = await candidate.info();
          if (info.id != peer.id) {
            throw FlowDropException(
              'device_changed',
              '${peer.name} presented a different identity. Reconnect to continue.',
            );
          }
          client = candidate;
          unawaited(_rememberPaired(info));
          break;
        } on FlowDropException catch (error) {
          candidate.close();
          lastError = error;
          if (error.code == 'device_changed') rethrow;
        } on Object catch (error) {
          candidate.close();
          lastError = error;
        }
      }
      if (client == null) {
        _markSession(sessionId, TransferState.failed);
        await _updateRecordState(sessionId, TransferState.failed);
        _nextProbe.remove(peer.id);
        return 'Could not reach ${peer.name}. It may have moved to another '
            'network — tap Reconnect paired devices and try again.';
      }
      _outgoingClients[sessionId] = client;

      final response = await client.offer(offer);
      if (!response.accepted) {
        _markSession(sessionId, TransferState.declined);
        await _updateRecordState(sessionId, TransferState.declined);
        return '${peer.name} declined the transfer.';
      }
      if (files.isNotEmpty) {
        await _uploadAll(
          client: client,
          sessionId: sessionId,
          offered: offered,
          filesById: byId,
          uploadUrls: response.uploadUrls,
        );
      }
      if (_cancelledSessions.contains(sessionId)) {
        return 'Transfer cancelled.';
      }
      _markSession(sessionId, TransferState.completed);
      await _updateRecordState(sessionId, TransferState.completed);
      return null;
    } on FlowDropException catch (error) {
      if (_cancelledSessions.contains(sessionId)) {
        return 'Transfer cancelled.';
      }
      _markSession(sessionId, TransferState.failed);
      await _updateRecordState(sessionId, TransferState.failed);
      return error.message;
    } on Object catch (error) {
      if (_cancelledSessions.contains(sessionId)) {
        return 'Transfer cancelled.';
      }
      _markSession(sessionId, TransferState.failed);
      await _updateRecordState(sessionId, TransferState.failed);
      return 'Transfer failed: $error${lastError == null ? '' : ' ($lastError)'}';
    } finally {
      _outgoingClients.remove(sessionId);
      client?.close();
    }
  }

  Future<void> _uploadAll({
    required FlowDropClient client,
    required String sessionId,
    required List<OfferedFile> offered,
    required Map<String, SendFile> filesById,
    required Map<String, String> uploadUrls,
  }) async {
    final queue = [...offered];
    final workers = math.min(
      FlowDropProtocol.maxParallelUploads,
      math.max(1, queue.length),
    );

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (_cancelledSessions.contains(sessionId)) return;
        final offeredFile = queue.removeAt(0);
        final local = filesById[offeredFile.id];
        if (local == null) continue;
        final path =
            uploadUrls[offeredFile.id] ??
            '/v1/upload/$sessionId/${offeredFile.id}';
        await _uploadOne(
          client: client,
          sessionId: sessionId,
          offeredFile: offeredFile,
          localPath: local.path,
          uploadPath: path,
        );
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Future<void> _uploadOne({
    required FlowDropClient client,
    required String sessionId,
    required OfferedFile offeredFile,
    required String localPath,
    required String uploadPath,
  }) async {
    void progress(int sent, int total) =>
        _updateFileProgress(sessionId, offeredFile.id, sent, total);

    try {
      await client.uploadFile(
        file: offeredFile,
        localPath: localPath,
        uploadPath: uploadPath,
        onProgress: progress,
      );
    } on FlowDropException catch (error) {
      if (error.code != 'network_error' && error.code != 'resume_failed') {
        rethrow;
      }
      if (_cancelledSessions.contains(sessionId)) return;
      // One resume attempt: ask the receiver how many bytes it kept and
      // continue from there.
      final status = await client.status(sessionId);
      final remote = status.files.firstWhere(
        (file) => file.id == offeredFile.id,
        orElse: () => FileStatus(
          id: offeredFile.id,
          received: 0,
          size: offeredFile.size,
          state: 'pending',
        ),
      );
      if (remote.received <= 0 || remote.received >= offeredFile.size) rethrow;
      await client.uploadFile(
        file: offeredFile,
        localPath: localPath,
        uploadPath: uploadPath,
        startOffset: remote.received,
        onProgress: progress,
      );
    }
  }

  Future<String?> sendClipboardTo(DeviceInfo peer, String text) async {
    final identity = _identity;
    final local = _currentLocalDevice;
    final endpoints = _endpointsForPeer(peer);
    if (identity == null || local == null || endpoints.isEmpty) {
      return 'FlowDrop is not ready.';
    }
    Object? lastError;
    for (final endpoint in endpoints) {
      final client = FlowDropClient(
        host: endpoint.host,
        port: endpoint.port,
        identity: identity,
        localDevice: local,
        expectedFingerprint: peer.fingerprint,
        connectionTimeout: const Duration(seconds: 5),
      );
      try {
        final info = await client.info();
        await client.sendClipboard(text);
        unawaited(_rememberPaired(info));
        return null;
      } on FlowDropException catch (error) {
        lastError = error;
      } on Object catch (error) {
        lastError = error;
      } finally {
        client.close();
      }
    }
    return 'Clipboard failed: $lastError';
  }

  Future<void> cancelSession(String sessionId) async {
    _cancelledSessions.add(sessionId);
    final client = _outgoingClients[sessionId];
    if (client != null) {
      try {
        await client.cancel(sessionId);
      } on Object {
        // The peer may already be gone.
      }
    }
    _markSession(sessionId, TransferState.cancelled);
    await _updateRecordState(sessionId, TransferState.cancelled);
    _banner('Transfer cancelled');
  }

  void dismissSession(String sessionId) {
    _speedSamples.removeWhere((key, _) => key.startsWith('$sessionId/'));
    _set(
      state.copyWith(
        sessions: state.sessions
            .where((session) => session.sessionId != sessionId)
            .toList(growable: false),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Server events
  // ---------------------------------------------------------------------------

  void _handleServerEvent(ServerEvent event) {
    switch (event.type) {
      case 'progress':
        _handleProgress(event);
      case 'completed':
        {
          final sessionId = event.data['sessionId'];
          if (sessionId is String) {
            final rawPaths = event.data['savedPaths'];
            final savedPaths = rawPaths is List<dynamic>
                ? rawPaths.whereType<String>().toList(growable: false)
                : const <String>[];
            _markSessionWithSavedPaths(sessionId, savedPaths);
            unawaited(
              _updateRecordState(
                sessionId,
                TransferState.completed,
                savedPath: savedPaths.isEmpty ? null : savedPaths.first,
              ),
            );
          }
        }
      case 'cancelled':
        {
          final sessionId = event.data['sessionId'];
          if (sessionId is String) {
            _markSession(sessionId, TransferState.cancelled);
            unawaited(_updateRecordState(sessionId, TransferState.cancelled));
          }
        }
      case 'clipboard':
        {
          final data = event.data['data'];
          final from = event.data['from'];
          if (data is String && from is String) {
            _handleClipboard(from, data);
          }
        }
      default:
        break;
    }
  }

  void _handleProgress(ServerEvent event) {
    final sessionId = event.data['sessionId'];
    final fileId = event.data['fileId'];
    final received = _asInt(event.data['received']);
    if (sessionId is! String || fileId is! String || received == null) return;
    final session = _findSession(sessionId);
    if (session == null) return;
    final speed = _speedFor('$sessionId/$fileId', received);
    final files = session.files
        .map(
          (file) => file.fileId == fileId
              ? file.copyWith(
                  transferredBytes: received,
                  bytesPerSecond: speed,
                  state: TransferState.active,
                )
              : file,
        )
        .toList(growable: false);
    _upsertSession(session.copyWith(files: files, state: TransferState.active));
  }

  /// Smooths a byte counter into bytes/second without storing per-file state
  /// beyond the last sample.
  double? _speedFor(String key, int bytes) {
    final now = DateTime.now();
    final last = _speedSamples[key];
    if (last == null) {
      _speedSamples[key] = (bytes: bytes, at: now);
      return null;
    }
    final elapsed = now.difference(last.at).inMilliseconds;
    if (elapsed < 300) return null;
    final delta = bytes - last.bytes;
    if (delta < 0) {
      _speedSamples[key] = (bytes: bytes, at: now);
      return null;
    }
    _speedSamples[key] = (bytes: bytes, at: now);
    return delta * 1000 / elapsed;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pairing and connection
  // ---------------------------------------------------------------------------

  Future<QrPayload> createQrPayload() async {
    final identity = _identity;
    if (identity == null || _server == null) {
      throw FlowDropException('not_ready', 'FlowDrop is still starting.');
    }
    await refreshAddresses();
    final token = _tokenManager.issue();
    final payload = QrPayload.fromDevice(
      device: identity.toDeviceInfo(
        addresses: _effectiveAddresses,
        port: _server!.port,
        name: state.settings.deviceName,
      ),
      token: token,
    );
    _set(state.copyWith(qrPayload: payload));
    return payload;
  }

  Future<DeviceInfo> connectManually({
    required String host,
    required int port,
    required String fingerprint,
  }) async {
    final identity = _identity;
    final local = _currentLocalDevice;
    final normalized = normalizeFingerprint(fingerprint);
    if (identity == null || local == null) {
      throw FlowDropException('not_ready', 'FlowDrop is still starting.');
    }
    if (host.trim().isEmpty) {
      throw FlowDropException(
        'bad_input',
        'Enter the other device IP address.',
      );
    }
    if (normalized.length < 16) {
      throw FlowDropException(
        'bad_input',
        'Enter at least 16 characters of the certificate fingerprint.',
      );
    }
    final client = FlowDropClient(
      host: host.trim(),
      port: port,
      identity: identity,
      localDevice: local,
      expectedFingerprint: normalized,
    );
    try {
      final info = await client.info();
      _discovery?.addManual(info);
      unawaited(_rememberPaired(info));
      _set(state.copyWith(peers: _discovery?.nearby ?? state.peers));
      return info;
    } finally {
      client.close();
    }
  }

  Future<DeviceInfo> connectWithQr(QrPayload payload) async {
    final identity = _identity;
    final local = _currentLocalDevice;
    if (identity == null || local == null) {
      throw FlowDropException('not_ready', 'FlowDrop is still starting.');
    }

    DeviceInfo? remote;
    Object? lastError;
    for (final address in payload.addresses) {
      final probe = FlowDropClient(
        host: address,
        port: payload.port,
        identity: identity,
        localDevice: local,
        expectedFingerprint: payload.fingerprint,
      );
      try {
        final info = await probe.info();
        if (info.id != payload.deviceId) {
          throw FlowDropException(
            'device_changed',
            'This code belongs to a different device.',
          );
        }
        remote = info;
        break;
      } on Object catch (error) {
        lastError = error;
      } finally {
        probe.close();
      }
    }
    if (remote == null) {
      throw FlowDropException(
        'unreachable',
        'Could not reach ${payload.name}. $lastError',
      );
    }

    final client = FlowDropClient(
      host: remote.addresses.isNotEmpty
          ? remote.addresses.first
          : payload.addresses.first,
      port: remote.port,
      identity: identity,
      localDevice: local,
      expectedFingerprint: remote.fingerprint,
    );
    try {
      final response = await client.pair(payload: payload);
      if (!response.ok) {
        throw FlowDropException(
          response.error ?? 'pair_failed',
          'The other device rejected the pairing code.',
        );
      }
    } finally {
      client.close();
    }

    final trustedDevice = TrustedDevice.fromDevice(remote);
    await _trustStore!.trust(trustedDevice);
    final trusted = await _trustStore!.all();
    _discovery?.addFromQr(remote);
    _set(
      state.copyWith(
        peers: _discovery?.nearby ?? state.peers,
        trustedDevices: trusted,
      ),
    );
    _banner('Paired with ${remote.name}');
    unawaited(_rememberPaired(remote));
    return remote;
  }

  Future<void> forgetDevice(String fingerprint) async {
    final match = state.trustedDevices
        .where((device) => fingerprintsEqual(device.fingerprint, fingerprint))
        .firstOrNull;
    await _trustStore?.forget(fingerprint);
    if (match != null) {
      _discovery?.removePaired(match.deviceId);
      _nextProbe.remove(match.deviceId);
    }
    final trusted = await _trustStore?.all() ?? const [];
    _set(
      state.copyWith(
        trustedDevices: trusted,
        peers: _discovery?.nearby ?? state.peers,
      ),
    );
    _banner('Device removed');
  }

  /// Starts/stops the clipboard watcher based on the current setting.
  void syncClipboardWatcher() {
    if (state.settings.clipboardSync) {
      _startClipboardSync();
    } else {
      _stopClipboardSync();
    }
  }

  // ---------------------------------------------------------------------------
  // Settings and housekeeping
  // ---------------------------------------------------------------------------

  Future<void> applySettings(AppSettings next) async {
    final previous = state.settings;
    await _settingsStore.save(next);
    _set(state.copyWith(settings: next));

    if (next.deviceName.trim().isNotEmpty &&
        next.deviceName != previous.deviceName) {
      final identity = _identity;
      if (identity != null) {
        final renamed = identity.copyWith(name: next.deviceName.trim());
        _identity = renamed;
        await _identityStore?.save(renamed);
        _set(
          state.copyWith(identity: renamed, localDevice: _currentLocalDevice),
        );
      }
    }

    if (next.discoveryEnabled != previous.discoveryEnabled ||
        next.useMdns != previous.useMdns ||
        next.visibility != previous.visibility) {
      if (next.visibility == VisibilityMode.hidden) {
        _banner('Invisible: discovery is off. QR and manual still work.');
      }
      await _startDiscovery();
    }

    if (next.visibility != previous.visibility) {
      final server = _server;
      if (server != null) {
        server.autoDeclineUntrusted =
            next.visibility == VisibilityMode.trustedOnly;
      }
      _banner(switch (next.visibility) {
        VisibilityMode.everyone => 'Visible to everyone on the LAN',
        VisibilityMode.trustedOnly => 'Only paired devices can talk to you',
        VisibilityMode.hidden => 'Hidden: no beacons, QR/manual still work',
      });
    }

    if (next.clipboardSync != previous.clipboardSync) {
      if (next.clipboardSync) {
        _startClipboardSync();
      } else {
        _stopClipboardSync();
      }
    }
  }

  /// Pushes the current OS clipboard to every currently-discovered peer that
  /// can be reached. Used by the manual quick action and by sync ticks.
  Future<void> pushClipboardNow() async {
    final data = await _readClipboardText();
    if (data == null || data.trim().isEmpty) return;
    _recordOutgoingClipboard(data);
    final peers = state.peers
        .where((peer) => peer.device.addresses.isNotEmpty)
        .toList();
    if (peers.isEmpty) {
      _banner('No nearby devices to sync to');
      return;
    }
    var sent = 0;
    for (final peer in peers) {
      final error = await sendClipboardTo(peer.device, data);
      if (error == null) sent++;
    }
    _banner(
      sent > 0
          ? 'Clipboard sent to $sent device${sent == 1 ? '' : 's'}'
          : 'Clipboard sync failed — devices unreachable',
    );
  }

  /// Manual quick action: sends the current OS clipboard straight to [peer]
  /// without requiring the sync toggle.
  Future<String?> sendCurrentClipboardTo(DeviceInfo peer) async {
    final data = await _readClipboardText();
    if (data == null || data.trim().isEmpty) {
      return 'Clipboard is empty';
    }
    return sendClipboardTo(peer, data);
  }

  void _recordOutgoingClipboard(String data) {
    _set(
      state.copyWith(
        clipboardHistory: [
          ClipboardEntry(
            data: data,
            fromName: 'This device',
            at: DateTime.now(),
            outgoing: true,
          ),
          ...state.clipboardHistory,
        ].take(20).toList(growable: false),
      ),
    );
  }

  void _startClipboardSync() {
    _stopClipboardSync();
    _clipboardTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_clipboardTick()),
    );
    // Run one tick immediately so toggling on starts syncing right away.
    unawaited(_clipboardTick());
    _banner('Clipboard sync on');
  }

  void _stopClipboardSync() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    _clipboardGuard.reset();
  }

  Future<void> _clipboardTick() async {
    if (_clipboardSyncing || _disposed) return;
    if (!state.settings.clipboardSync) return;
    _clipboardSyncing = true;
    try {
      final data = await _readClipboardText();
      if (data == null) return;
      if (!_clipboardGuard.shouldPush(data)) return;
      _clipboardGuard.markPushed(data);
      _recordOutgoingClipboard(data);
      final peers = state.peers
          .where((peer) => peer.device.addresses.isNotEmpty)
          .toList();
      for (final peer in peers) {
        await sendClipboardTo(peer.device, data);
      }
    } finally {
      _clipboardSyncing = false;
    }
  }

  Future<String?> _readClipboardText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } on Object {
      return null;
    }
  }

  /// Stops or starts the receive server (quick offline mode, spec §6).
  Future<void> setServerEnabled(bool enabled) async {
    final server = _server;
    if (server == null) return;
    if (enabled) {
      await server.start();
      _set(
        state.copyWith(
          serverRunning: true,
          serverPort: server.port,
          localDevice: _currentLocalDevice,
        ),
      );
      _banner('Server is listening again');
    } else {
      await server.stop();
      _set(state.copyWith(serverRunning: false));
      _banner('Server stopped — you are offline in FlowDrop');
    }
  }

  /// Marks the 3-slide onboarding as seen so it never shows again.
  Future<void> completeOnboarding() async {
    final next = state.settings.copyWith(onboardingDone: true);
    await _settingsStore.save(next);
    _set(state.copyWith(settings: next));
  }

  Future<void> setReceiveDirectory(String path) async {
    final trimmed = path.trim();
    final next = state.settings.copyWith(receiveDirectory: trimmed);
    await _settingsStore.save(next);
    _set(state.copyWith(settings: next));
    try {
      if (trimmed.isNotEmpty) {
        await Directory(trimmed).create(recursive: true);
        _downloadDirectory = trimmed;
        _server?.downloadDirectory = trimmed;
      } else {
        final downloads =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        final resolved = p.join(downloads.path, 'FlowDrop');
        await Directory(resolved).create(recursive: true);
        _downloadDirectory = resolved;
        _server?.downloadDirectory = resolved;
      }
      _banner(
        trimmed.isEmpty
            ? 'Using the default Downloads folder'
            : 'Saving incoming files to $trimmed',
      );
    } on Object catch (error) {
      _banner('Could not use that folder: $error');
    }
  }

  Future<void> clearHistory() async {
    _history?.clear();
    _set(state.copyWith(history: const []));
  }

  Future<void> deleteHistoryEntry(String id) async {
    _history?.delete(id);
    _set(
      state.copyWith(
        history: state.history
            .where((entry) => entry.id != id)
            .toList(growable: false),
      ),
    );
  }

  void clearNotice() {
    if (state.notice != null) {
      _set(state.copyWith(clearNotice: true));
    }
  }

  void clearFatalError() {
    if (state.fatalError != null) {
      _set(state.copyWith(clearFatalError: true, loadingMessage: 'Retrying…'));
    }
  }

  /// Saves a text payload as a `.txt` file in the receive directory using a
  /// sanitized filename derived from the sender name.
  Future<String?> saveTextAsFile(String text, String senderName) async {
    try {
      final slug = sanitizeFileName(senderName)
          .replaceAll(RegExp(r'\s+'), '-')
          .toLowerCase();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final name = sanitizeFileName('${slug}_${stamp.substring(11)}.txt');
      final file = File(p.join(_downloadDirectory, name));
      await file.writeAsString(text, flush: true);
      _banner('Saved to ${file.path}');
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  void clearClipboard() {
    if (state.clipboardText != null) {
      _set(state.copyWith(clearClipboard: true));
    }
  }

  void clearClipboardHistory() {
    _set(state.copyWith(clipboardHistory: const []));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  TransferRecord _recordFrom(
    OfferRequest offer,
    TransferDirection direction,
    DateTime startedAt,
    TransferState transferState, {
    DateTime? finishedAt,
  }) {
    return TransferRecord(
      id: offer.sessionId,
      peerName: offer.sender.name,
      peerDeviceId: offer.sender.id,
      direction: direction,
      files: offer.files,
      totalBytes: offer.totalSize,
      startedAt: startedAt,
      finishedAt: finishedAt,
      state: transferState,
      textPreview: offer.text,
    );
  }

  Future<void> _saveRecord(TransferRecord record) async {
    try {
      _history?.upsert(record);
    } on Object {
      // History is a convenience; never fail a transfer over it.
    }
    final list = [...state.history];
    final index = list.indexWhere((entry) => entry.id == record.id);
    if (index >= 0) {
      list[index] = record;
    } else {
      list.insert(0, record);
    }
    _set(state.copyWith(history: list.take(200).toList(growable: false)));
  }

  Future<void> _updateRecordState(
    String sessionId,
    TransferState next, {
    String? savedPath,
  }) async {
    final index = state.history.indexWhere((entry) => entry.id == sessionId);
    if (index < 0) return;
    final current = state.history[index];
    final finished =
        next == TransferState.completed ||
        next == TransferState.failed ||
        next == TransferState.cancelled ||
        next == TransferState.declined;
    await _saveRecord(
      current.copyWith(
        state: next,
        finishedAt: finished ? DateTime.now() : null,
        savedPath: savedPath,
      ),
    );
  }

  SessionProgress? _findSession(String sessionId) {
    for (final session in state.sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  void _upsertSession(SessionProgress session) {
    final list = [...state.sessions];
    final index = list.indexWhere(
      (entry) => entry.sessionId == session.sessionId,
    );
    if (index >= 0) {
      list[index] = session;
    } else {
      list.insert(0, session);
    }
    _set(state.copyWith(sessions: list.take(100).toList(growable: false)));
  }

  void _markSession(String sessionId, TransferState next) {
    final session = _findSession(sessionId);
    if (session == null) return;
    final files = session.files
        .map(
          (file) => file.copyWith(
            state: next,
            transferredBytes: next == TransferState.completed
                ? file.totalBytes
                : null,
          ),
        )
        .toList(growable: false);
    _upsertSession(session.copyWith(files: files, state: next));
  }

  void _markSessionWithSavedPaths(String sessionId, List<String> savedPaths) {
    final session = _findSession(sessionId);
    if (session == null) return;
    final files = session.files
        .map(
          (file) => file.copyWith(
            state: TransferState.completed,
            transferredBytes: file.totalBytes,
          ),
        )
        .toList(growable: false);
    _upsertSession(
      session.copyWith(
        files: files,
        state: TransferState.completed,
        savedPaths: savedPaths,
      ),
    );
  }

  void _updateFileProgress(
    String sessionId,
    String fileId,
    int transferred,
    int total,
  ) {
    final session = _findSession(sessionId);
    if (session == null) return;
    final speed = _speedFor('$sessionId/$fileId', transferred);
    final files = session.files
        .map(
          (file) => file.fileId == fileId
              ? file.copyWith(
                  transferredBytes: transferred,
                  bytesPerSecond: speed,
                  state: TransferState.active,
                )
              : file,
        )
        .toList(growable: false);
    _upsertSession(session.copyWith(files: files, state: TransferState.active));
  }

  void _banner(String message) {
    _set(state.copyWith(notice: message));
  }

  void _set(AppState next) {
    if (_disposed) return;
    state = next;
  }

  Future<void> _dispose() async {
    _disposed = true;
    _addressTimer?.cancel();
    _presenceTimer?.cancel();
    _speedSamples.clear();
    _stopClipboardSync();
    await _peerSubscription?.cancel();
    for (final completer in _pendingOffers.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    for (final client in _outgoingClients.values) {
      client.close();
    }
    await _discovery?.dispose();
    await _server?.stop();
    _history?.close();
  }
}
