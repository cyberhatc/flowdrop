/// Wire-level constants for FlowDrop Protocol v1.
///
/// Keep this file free of Flutter imports: it is shared by the app, the tests
/// and the benchmark tool.
library;

class FlowDropProtocol {
  FlowDropProtocol._();

  /// Bump only for breaking wire changes. Older peers must be rejected
  /// explicitly rather than silently misinterpreted.
  static const int version = 1;

  static const int defaultPort = 53317;
  static const int discoveryPort = 53318;

  static const String serviceType = '_flowdrop._tcp';
  static const String serviceDomain = 'local';

  /// One-time QR / pairing tokens are valid for two minutes.
  static const Duration pairingTokenTtl = Duration(seconds: 120);

  /// Pairing attempts per IP per minute.
  static const int pairingAttemptsPerMinute = 5;

  /// Text and clipboard payloads are capped at 1 MiB.
  static const int maxTextBytes = 1 << 20;

  /// Sanity cap for a single offered file (1 TiB). The real limit is the
  /// receiver's free disk space.
  static const int maxFileSize = 1 << 40;

  /// A single offer may not contain more entries than this.
  static const int maxFilesPerOffer = 10000;

  /// 1 MiB is a good compromise between syscall overhead and latency.
  static const int chunkSize = 1 << 20;

  /// Streams per session. A single large file uses one stream.
  static const int maxParallelUploads = 3;

  /// Peers disappear from the radar after this much silence.
  static const Duration peerTimeout = Duration(seconds: 6);

  /// How often the UDP beacon announces this device.
  static const Duration beaconInterval = Duration(milliseconds: 1500);

  static const String scheme = 'flowdrop';
  static const String connectHost = 'connect';
}
