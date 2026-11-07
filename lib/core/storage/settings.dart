/// User settings and the persistence boundary for them.
///
/// This file is pure Dart on purpose: `lib/core/` must not depend on Flutter so
/// the protocol and storage logic can be tested headlessly. The Flutter-backed
/// implementation lives in `lib/app/storage/`.
library;

enum AppThemeMode { dark, light, system }

enum AccentColor { cyan, violet, magenta, lime }

/// Who can discover and send to this device (spec §6).
enum VisibilityMode {
  /// Unpaired devices show up and can ask; you confirm each transfer.
  everyone,

  /// Only already-paired devices can talk. Offers from strangers are
  /// declined automatically, without a prompt.
  trustedOnly,

  /// No discovery beacons at all — invisible on the LAN. QR code and manual
  /// address entry still work.
  hidden,
}

class AppSettings {
  const AppSettings({
    this.deviceName = '',
    this.themeMode = AppThemeMode.dark,
    this.accent = AccentColor.cyan,
    this.autoAcceptTrusted = false,
    this.useMdns = true,
    this.discoveryEnabled = true,
    this.clipboardSync = false,
    this.receiveDirectory = '',
    this.onboardingDone = false,
    this.visibility = VisibilityMode.everyone,
  });

  /// Empty means "use the platform default downloads folder".
  final String deviceName;
  final AppThemeMode themeMode;
  final AccentColor accent;

  /// When true, a device you paired with may send files without a prompt.
  final bool autoAcceptTrusted;

  final bool useMdns;
  final bool discoveryEnabled;
  final bool clipboardSync;

  /// Empty means "use the platform downloads folder".
  final String receiveDirectory;

  /// Set once the user finishes the 3-slide onboarding.
  final bool onboardingDone;

  /// Who may discover/ask this device. Default: everyone.
  final VisibilityMode visibility;

  AppSettings copyWith({
    String? deviceName,
    AppThemeMode? themeMode,
    AccentColor? accent,
    bool? autoAcceptTrusted,
    bool? useMdns,
    bool? discoveryEnabled,
    bool? clipboardSync,
    String? receiveDirectory,
    bool? onboardingDone,
    VisibilityMode? visibility,
  }) {
    return AppSettings(
      deviceName: deviceName ?? this.deviceName,
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      autoAcceptTrusted: autoAcceptTrusted ?? this.autoAcceptTrusted,
      useMdns: useMdns ?? this.useMdns,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
      clipboardSync: clipboardSync ?? this.clipboardSync,
      receiveDirectory: receiveDirectory ?? this.receiveDirectory,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      visibility: visibility ?? this.visibility,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'themeMode': themeMode.name,
    'accent': accent.name,
    'autoAcceptTrusted': autoAcceptTrusted,
    'useMdns': useMdns,
    'discoveryEnabled': discoveryEnabled,
    'clipboardSync': clipboardSync,
    'receiveDirectory': receiveDirectory,
    'onboardingDone': onboardingDone,
    'visibility': visibility.name,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      deviceName: json['deviceName'] as String? ?? '',
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => AppThemeMode.dark,
      ),
      accent: AccentColor.values.firstWhere(
        (color) => color.name == json['accent'],
        orElse: () => AccentColor.cyan,
      ),
      autoAcceptTrusted: json['autoAcceptTrusted'] == true,
      useMdns: json['useMdns'] != false,
      discoveryEnabled: json['discoveryEnabled'] != false,
      clipboardSync: json['clipboardSync'] == true,
      receiveDirectory: json['receiveDirectory'] as String? ?? '',
      onboardingDone: json['onboardingDone'] == true,
      visibility: VisibilityMode.values.firstWhere(
        (value) => value.name == json['visibility'],
        orElse: () => VisibilityMode.everyone,
      ),
    );
  }

  @override
  String toString() =>
      'AppSettings(name=$deviceName, theme=${themeMode.name}, accent=${accent.name})';
}

abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// Test double that also works before platform storage is available.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([AppSettings? initial]) : _settings = initial;

  AppSettings? _settings;

  @override
  Future<AppSettings> load() async => _settings ?? const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}
