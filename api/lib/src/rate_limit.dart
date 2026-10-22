/// Fixed-window counter: at most [limit] hits per key per [window].
///
/// Memory is bounded by [maxKeys]. Once that many keys are tracked in the
/// current window, new keys are refused until it rolls over.
class RateLimiter {
  RateLimiter({
    required this.limit,
    required this.window,
    required this._clock,
    this.maxKeys = 100000,
  });

  final int limit;
  final Duration window;
  final int maxKeys;
  final DateTime Function() _clock;

  final _hits = <String, int>{};
  DateTime? _windowEnd;

  /// Records a hit for [key] and returns whether it is within the limit.
  bool allow(String key) {
    final now = _clock();
    if (_windowEnd == null || !now.isBefore(_windowEnd!)) {
      _hits.clear();
      _windowEnd = now.add(window);
    }
    final hits = _hits[key];
    if (hits == null && _hits.length >= maxKeys) return false;
    if ((hits ?? 0) >= limit) return false;
    _hits[key] = (hits ?? 0) + 1;
    return true;
  }
}
