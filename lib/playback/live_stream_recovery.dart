import 'dart:async';
import 'dart:math' as math;

/// Reopens failed live streams with bounded backoff until media advances again.
class LiveStreamRecovery {
  final Future<void> Function() reconnect;
  final void Function(bool) onRecovering;
  late final Timer _watchdog;
  Timer? _retry, _settling;
  Duration _healthyProgress = Duration.zero;
  Future<void>? _operation;
  bool _closed = false, _paused = false, _recovering = false;
  int _quietTicks = 0, _attempts = 0, _generation = 0;
  Duration? _position;
  LiveStreamRecovery({required this.reconnect, required this.onRecovering}) {
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_closed ||
          _paused ||
          _retry != null ||
          _operation != null ||
          _settling != null) {
        return;
      }
      if (++_quietTicks >= 15) failed();
    });
  }
  void _status(bool value) {
    if (_closed || _recovering == value) return;
    _recovering = value;
    onRecovering(value);
  }

  void progress(Duration position) {
    if (_closed ||
        _paused ||
        position <= Duration.zero ||
        position == _position) {
      return;
    }
    final delta = _position == null ? Duration.zero : position - _position!;
    _healthyProgress =
        delta > Duration.zero && delta <= const Duration(seconds: 3)
        ? _healthyProgress + delta
        : Duration.zero;
    _position = position;
    _generation++;
    _quietTicks = 0;
    if (_healthyProgress >= const Duration(seconds: 10)) _attempts = 0;
    _retry?.cancel();
    _retry = null;
    _settling?.cancel();
    _settling = null;
    _status(false);
  }

  void setPaused(bool value) {
    _paused = value;
    _quietTicks = 0;
    if (value) {
      _retry?.cancel();
      _retry = null;
      _settling?.cancel();
      _settling = null;
      _status(false);
    }
  }

  void failed() {
    if (_closed ||
        _paused ||
        _retry != null ||
        _operation != null ||
        _settling != null) {
      return;
    }
    final generation = _generation;
    final seconds = math.min(30, 2 * (1 << math.min(_attempts, 4)));
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      if (_closed || _paused || generation != _generation) return;
      _status(true);
      _operation = _reopen().whenComplete(() {
        _operation = null;
        // Opening returns before the decoder has filled its network buffer.
        // Give this connection a real startup window before trying again.
        if (!_closed && !_paused && generation == _generation) {
          _settling = Timer(const Duration(seconds: 30), () {
            _settling = null;
            if (!_closed && !_paused && generation == _generation) failed();
          });
        }
      });
    });
  }

  Future<void> _reopen() async {
    _attempts++;
    _healthyProgress = Duration.zero;
    _quietTicks = 0;
    try {
      await reconnect();
    } catch (_) {
      /* Keep retrying without exposing stream URLs. */
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    _watchdog.cancel();
    _settling?.cancel();
    await _operation;
  }
}
