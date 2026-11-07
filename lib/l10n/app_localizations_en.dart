// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FlowDrop';

  @override
  String get appTagline => 'Fast, secure LAN file and text transfer';

  @override
  String get nearby => 'Nearby';

  @override
  String get transfers => 'Transfers';

  @override
  String get history => 'History';

  @override
  String get settings => 'Settings';

  @override
  String get showQr => 'Show my QR code';
}
