/// Esperas crecientes entre reintentos; la última se repite indefinidamente.
class RetryBackoff {
  static const _delays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  int _attempt = 0;

  Duration next() {
    final delay = _delays[_attempt];
    if (_attempt < _delays.length - 1) _attempt++;
    return delay;
  }

  void reset() => _attempt = 0;
}
