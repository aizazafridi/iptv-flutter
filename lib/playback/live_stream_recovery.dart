import 'dart:async';
import 'dart:math' as math;

/// Reopens failed live streams with bounded backoff until media advances again.
class LiveStreamRecovery {
  final Future<void> Function() reconnect;
  final void Function(bool) onRecovering;
  late final Timer _watchdog;
  Timer? _retry;
  Future<void>? _operation;
  bool _closed = false, _paused = false, _recovering = false;
  int _quietTicks = 0, _attempts = 0, _generation = 0;
  Duration? _position;
  LiveStreamRecovery({required this.reconnect, required this.onRecovering}) {
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_closed || _paused || _retry != null || _operation != null) return;
      if (++_quietTicks >= 6) failed();
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
    _position = position;
    _generation++;
    _quietTicks = 0;
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
    _status(false);
  }

  void setPaused(bool value) {
    _paused = value;
    _quietTicks = 0;
    if (value) {
      _retry?.cancel();
      _retry = null;
      _status(false);
    }
  }

  void failed() {
    if (_closed || _paused || _retry != null || _operation != null) return;
    final generation = _generation;
    final seconds = math.min(30, 2 * (1 << math.min(_attempts, 4)));
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      if (_closed || _paused || generation != _generation) return;
      _status(true);
      _operation = _reopen().whenComplete(() {
        _operation = null;
        // Command completion does not confirm playback; wait for media progress.
        if (!_closed && !_paused && generation == _generation) failed();
      });
    });
  }

  Future<void> _reopen() async {
    _attempts++;
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
    await _operation;
  }
}
