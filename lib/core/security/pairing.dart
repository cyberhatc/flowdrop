import 'dart:convert';
import 'dart:math';

import '../protocol/constants.dart';

enum PairingResult { ok, invalid, expired, used, rateLimited }

class PairingToken {
  PairingToken({
    required this.value,
    required this.createdAt,
    required this.expiresAt,
  });

  final String value;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool used = false;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
  int secondsLeftAt(DateTime now) {
    final remaining = expiresAt.difference(now).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }
}

/// Issues and redeems short-lived, single-use pairing tokens.
///
/// Tokens are 18 random bytes encoded as base64url (24 characters, QR safe).
/// Every redemption attempt counts against a per-IP rate limit, including
/// invalid tokens, so brute forcing a 144-bit token is pointless and flooding
/// is slowed down.
class PairingTokenManager {
  PairingTokenManager({
    this.ttl = FlowDropProtocol.pairingTokenTtl,
    int maxAttemptsPerMinute = FlowDropProtocol.pairingAttemptsPerMinute,
    Random? random,
    DateTime Function()? clock,
  }) : _maxAttempts = maxAttemptsPerMinute,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int _maxAttempts;
  final Random _random;
  final DateTime Function() _clock;

  final Map<String, PairingToken> _tokens = {};
  final Map<String, List<DateTime>> _attempts = {};

  PairingToken issue({Duration? ttl, DateTime? now}) {
    final at = now ?? _clock();
    _prune(at);
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    final token = PairingToken(
      value: base64Url.encode(bytes).replaceAll('=', ''),
      createdAt: at,
      expiresAt: at.add(ttl ?? this.ttl),
    );
    _tokens[token.value] = token;
    return token;
  }

  PairingResult redeem(
    String token, {
    String clientIp = 'unknown',
    DateTime? now,
  }) {
    final at = now ?? _clock();
    // Check the token *before* pruning so an expired token reports
    // PairingResult.expired instead of vanishing into PairingResult.invalid.
    final existing = _tokens[token];
    if (!_allowAttempt(clientIp, at)) {
      return PairingResult.rateLimited;
    }
    if (existing == null) return PairingResult.invalid;
    if (existing.used) return PairingResult.used;
    if (existing.isExpiredAt(at)) {
      _tokens.remove(token);
      return PairingResult.expired;
    }
    existing.used = true;
    // Keep the used token until the next prune so reuse reads as .used
    // rather than .invalid; _prune collects used tokens.
    return PairingResult.ok;
  }

  /// Verifies a token without consuming it. Used to render the QR countdown.
  PairingToken? peek(String token) => _tokens[token];

  /// Invalidates every outstanding token (e.g. on app lock or network change).
  void revokeAll() => _tokens.clear();

  void _prune(DateTime now) {
    _tokens.removeWhere((_, token) => token.used || token.isExpiredAt(now));
    for (final entry in _attempts.entries) {
      entry.value.removeWhere(
        (attempt) => now.difference(attempt) > const Duration(minutes: 1),
      );
    }
    _attempts.removeWhere((_, attempts) => attempts.isEmpty);
  }

  bool _allowAttempt(String ip, DateTime now) {
    final attempts = _attempts.putIfAbsent(ip, () => <DateTime>[]);
    attempts.removeWhere(
      (attempt) => now.difference(attempt) > const Duration(minutes: 1),
    );
    if (attempts.length >= _maxAttempts) return false;
    attempts.add(now);
    return true;
  }

  int attemptsFor(String ip) => _attempts[ip]?.length ?? 0;
}
