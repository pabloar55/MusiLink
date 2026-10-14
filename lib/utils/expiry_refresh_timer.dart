import 'dart:async';

/// Avisa una sola vez en el instante de caducidad futuro más próximo. Solo
/// reprograma el temporizador cuando ese instante cambia, de modo que se puede
/// invocar en cada reconstrucción sin reiniciarlo.
class ExpiryRefreshTimer {
  ExpiryRefreshTimer(this._onExpired);

  final void Function() _onExpired;
  Timer? _timer;
  DateTime? _scheduledExpiry;

  /// Programa el aviso para la primera de [expirations] posterior a [now].
  /// Las caducidades nulas o ya pasadas se ignoran.
  void schedule(Iterable<DateTime?> expirations, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final pending =
        expirations.nonNulls.where((expiry) => expiry.isAfter(current)).toList()
          ..sort();
    final nextExpiry = pending.firstOrNull;
    if (nextExpiry == _scheduledExpiry) return;

    _timer?.cancel();
    _scheduledExpiry = nextExpiry;
    if (nextExpiry == null) return;

    _timer = Timer(nextExpiry.difference(current), () {
      _scheduledExpiry = null;
      _onExpired();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _scheduledExpiry = null;
  }
}
