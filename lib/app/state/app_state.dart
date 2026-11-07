import 'dart:async';

import '../../core/discovery/peer.dart';
import '../../core/discovery/qr_payload.dart';
import '../../core/protocol/device.dart';
import '../../core/protocol/offers.dart';
import '../../core/security/identity.dart';
import '../../core/security/trust_store.dart';
import '../../core/storage/settings.dart';
import '../../core/transfer/transfer_models.dart';

/// A file selected by the user, ready to be offered.
class SendFile {
  const SendFile({
    required this.path,
    required this.name,
    required this.size,
    this.mime = 'application/octet-stream',
  });

  final String path;
  final String name;
  final int size;
  final String mime;
}

/// An offer waiting for the user's Accept/Decline decision.
class IncomingOffer {
  IncomingOffer({
    required this.offer,
    required this.remoteIp,
    required this.trusted,
    required this.completer,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  final OfferRequest offer;
  final String remoteIp;
  final bool trusted;
  final Completer<bool> completer;
  final DateTime receivedAt;

  String get sessionId => offer.sessionId;
  bool get hasFiles => offer.files.isNotEmpty;
  bool get hasText => (offer.text ?? '').isNotEmpty;
}

/// Text received through `POST /v1/text` (used by third-party clients).
class IncomingText {
  IncomingText({
    required this.payload,
    required this.remoteIp,
    required this.trusted,
    required this.receivedAt,
  });

  final TextPayload payload;
  final String remoteIp;
  final bool trusted;
  final DateTime receivedAt;

  String get text => payload.text;
  String get senderName => payload.sender.name;
}

/// One clipboard payload observed, either locally or from a peer.
class ClipboardEntry {
  const ClipboardEntry({
    required this.data,
    required this.fromName,
    required this.at,
    this.outgoing = false,
  });

  final String data;
  final String fromName;
  final DateTime at;
  final bool outgoing;
}

/// A file or text that arrived through the OS share sheet (Phase 7).
class ShareItem {
  const ShareItem({this.filePath, this.name, this.text, this.size = 0, this.mime = 'application/octet-stream'});

  /// Local file path when the item is a file.
  final String? filePath;
  final String? name;

  /// Text/URL payload when the item is text-like.
  final String? text;
  final int size;
  final String mime;

  bool get isFile => filePath != null && filePath!.isNotEmpty;
  String get displayName => name ?? (text ?? 'Shared item');
}

class AppState {
  const AppState({
    this.ready = false,
    this.loadingMessage = 'Warming up the radio…',
    this.fatalError,
    this.settings = const AppSettings(),
    this.identity,
    this.localDevice,
    this.addresses = const [],
    this.serverRunning = false,
    this.serverPort = 0,
    this.udpRunning = false,
    this.mdnsRunning = false,
    this.peers = const [],
    this.incoming = const [],
    this.incomingTexts = const [],
    this.sessions = const [],
    this.history = const [],
    this.trustedDevices = const [],
    this.notice,
    this.qrPayload,
    this.clipboardText,
    this.clipboardFrom,
    this.clipboardHistory = const [],
    this.pendingShare = const [],
  });

  final bool ready;
  final String loadingMessage;
  final String? fatalError;
  final AppSettings settings;
  final DeviceIdentity? identity;
  final DeviceInfo? localDevice;
  final List<String> addresses;
  final bool serverRunning;
  final int serverPort;
  final bool udpRunning;
  final bool mdnsRunning;

  /// Devices seen through UDP, mDNS, QR or manual connect.
  final List<Peer> peers;

  /// Offers waiting for the user.
  final List<IncomingOffer> incoming;

  final List<IncomingText> incomingTexts;

  /// Active and recently finished sessions (incoming and outgoing).
  final List<SessionProgress> sessions;
  final List<TransferRecord> history;
  final List<TrustedDevice> trustedDevices;

  /// One-shot message shown as a snackbar by the shell.
  final String? notice;

  /// The QR currently displayed by the QR screen.
  final QrPayload? qrPayload;

  /// Last clipboard payload received from a paired device.
  final String? clipboardText;
  final String? clipboardFrom;

  /// Last 20 clipboard payloads (incoming and outgoing), newest first.
  final List<ClipboardEntry> clipboardHistory;

  /// Files/text that arrived through the OS share sheet and are waiting for
  /// the user to pick a target device.
  final List<ShareItem> pendingShare;

  String get deviceName =>
      settings.deviceName.isNotEmpty ? settings.deviceName : 'This device';

  String get shortFingerprint {
    final fingerprint = identity?.fingerprint ?? '';
    if (fingerprint.length <= 12) return fingerprint;
    return fingerprint.substring(0, 12);
  }

  List<IncomingOffer> get pendingOffers =>
      incoming.where((offer) => !offer.completer.isCompleted).toList();

  List<SessionProgress> get activeSessions => sessions
      .where(
        (session) =>
            session.state == TransferState.active ||
            session.state == TransferState.pending,
      )
      .toList(growable: false);

  List<SessionProgress> get finishedSessions => sessions
      .where(
        (session) =>
            session.state != TransferState.active &&
            session.state != TransferState.pending,
      )
      .toList(growable: false);

  AppState copyWith({
    bool? ready,
    String? loadingMessage,
    String? fatalError,
    bool clearFatalError = false,
    AppSettings? settings,
    DeviceIdentity? identity,
    DeviceInfo? localDevice,
    List<String>? addresses,
    bool? serverRunning,
    int? serverPort,
    bool? udpRunning,
    bool? mdnsRunning,
    List<Peer>? peers,
    List<IncomingOffer>? incoming,
    List<IncomingText>? incomingTexts,
    List<SessionProgress>? sessions,
    List<TransferRecord>? history,
    List<TrustedDevice>? trustedDevices,
    String? notice,
    bool clearNotice = false,
    QrPayload? qrPayload,
    bool clearQr = false,
    String? clipboardText,
    String? clipboardFrom,
    bool clearClipboard = false,
    List<ClipboardEntry>? clipboardHistory,
    List<ShareItem>? pendingShare,
    bool clearPendingShare = false,
  }) {
    return AppState(
      ready: ready ?? this.ready,
      loadingMessage: loadingMessage ?? this.loadingMessage,
      fatalError: clearFatalError ? null : (fatalError ?? this.fatalError),
      settings: settings ?? this.settings,
      identity: identity ?? this.identity,
      localDevice: localDevice ?? this.localDevice,
      addresses: addresses ?? this.addresses,
      serverRunning: serverRunning ?? this.serverRunning,
      serverPort: serverPort ?? this.serverPort,
      udpRunning: udpRunning ?? this.udpRunning,
      mdnsRunning: mdnsRunning ?? this.mdnsRunning,
      peers: peers ?? this.peers,
      incoming: incoming ?? this.incoming,
      incomingTexts: incomingTexts ?? this.incomingTexts,
      sessions: sessions ?? this.sessions,
      history: history ?? this.history,
      trustedDevices: trustedDevices ?? this.trustedDevices,
      notice: clearNotice ? null : (notice ?? this.notice),
      qrPayload: clearQr ? null : (qrPayload ?? this.qrPayload),
      clipboardText:
          clearClipboard ? null : (clipboardText ?? this.clipboardText),
      clipboardFrom:
          clearClipboard ? null : (clipboardFrom ?? this.clipboardFrom),
      clipboardHistory: clipboardHistory ?? this.clipboardHistory,
      pendingShare: clearPendingShare
          ? const []
          : (pendingShare ?? this.pendingShare),
    );
  }
}
