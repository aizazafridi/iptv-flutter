import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';
import 'player_screen.dart';
import 'smooth_page_route.dart';
import 'trailer_source.dart';

Future<void> openInAppTrailer(
  BuildContext context,
  Uri uri, {
  required String title,
  bool allowExternalFallback = false,
}) async {
  // Repeated OK presses must not stack embedded players above this route.
  if (ModalRoute.of(context)?.isCurrent != true) return;
  final focus = FocusManager.instance.primaryFocus;
  final id = youtubeTrailerId(uri);
  if (id == null && !isDirectTrailer(uri)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This trailer link cannot be played inside Streamora.'),
      ),
    );
    return;
  }
  await Navigator.of(context).push(
    id != null
        ? PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => YoutubeTrailerScreen(
              videoId: id,
              title: title,
              allowExternalFallback: allowExternalFallback,
            ),
          )
        : SmoothPageRoute<void>(
            builder: (_) => PlayerScreen(
              source: PlaybackSource(uri: uri, title: '$title ? Trailer'),
              initialFullscreen: true,
            ),
          ),
  );
  if (context.mounted && focus?.context != null) focus!.requestFocus();
}

class TrailerBridge extends ChangeNotifier {
  bool ready = false, playing = false, buffering = false;
  double position = 0, duration = 0;
  int state = -1;
  String? error;
  Future<dynamic> Function(String)? evaluate;
  void receive(List<dynamic> args) {
    if (args.length < 2) return;
    switch (args[0]) {
      case 'ready':
        ready = true;
        error = null;
      case 'state':
        if (state == args[1]) return;
        state = args[1] is int ? args[1] as int : -1;
        playing = args[1] == 1;
        buffering = args[1] == 3;
      case 'progress':
        final times = args[1];
        if (times is! List ||
            times.length != 2 ||
            times.any((v) => v is! num || !v.toDouble().isFinite)) {
          return;
        }
        position = (times[0] as num).toDouble().clamp(0, double.infinity);
        duration = (times[1] as num).toDouble().clamp(0, double.infinity);
        // No Flutter progress UI is displayed over the native video surface.
        return;
      case 'blocked':
        playing = false;
      case 'error':
        playing = false;
        buffering = false;
        error = trailerErrorMessage(
          args[1] is num ? (args[1] as num).toInt() : null,
        );
        ready = false;
      default:
        return;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (ready) await evaluate?.call('window.trailerToggle();');
  }

  Future<void> seekTo(double seconds) async {
    if (ready && duration > 0) {
      await evaluate?.call(
        'window.trailerSeekTo(${seconds.clamp(0, duration)});',
      );
    }
  }

  Future<void> seek(int seconds) async {
    if (ready) {
      await evaluate?.call('window.trailerSeek(${seconds.clamp(-10, 10)});');
    }
  }
}

typedef TrailerEmbedBuilder = Widget Function(BuildContext, TrailerBridge);

class YoutubeTrailerScreen extends StatefulWidget {
  final String videoId, title;
  final bool allowExternalFallback;
  final TrailerEmbedBuilder? embedBuilder;
  const YoutubeTrailerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.embedBuilder,
    this.allowExternalFallback = false,
  });
  @override
  State<YoutubeTrailerScreen> createState() => _YoutubeTrailerScreenState();
}

class _YoutubeTrailerScreenState extends State<YoutubeTrailerScreen>
    with WidgetsBindingObserver {
  final bridge = TrailerBridge();
  final playFocus = FocusNode(debugLabel: 'trailer play pause');
  final backFocus = FocusNode(debugLabel: 'trailer back');
  final reloadFocus = FocusNode(debugLabel: 'trailer reload');
  bool confirmingExit = false, allowExit = false;
  WebViewEnvironment? environment;
  InAppWebViewController? web;
  Timer? timeout;
  Widget? nativeEmbed;
  bool initialized = false, focusedReady = false, externalAvailable = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(remoteBack);
    bridge.addListener(changed);
    if (widget.allowExternalFallback) {
      unawaited(() async {
        try {
          final available = await canLaunchUrl(
            Uri.https('www.youtube.com', '/watch', {'v': widget.videoId}),
          );
          if (mounted) setState(() => externalAvailable = available);
        } catch (_) {}
      }());
    }
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(initialize());
  }

  void changed() {
    if (!mounted) return;
    if (bridge.error != null || bridge.playing || bridge.state == 2) {
      timeout?.cancel();
    } else if (bridge.buffering && timeout?.isActive != true) {
      startTimeout();
    }
    setState(() {});
    if (bridge.ready && !focusedReady) {
      focusedReady = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            bridge.ready &&
            !confirmingExit &&
            ModalRoute.of(context)?.isCurrent == true) {
          playFocus.requestFocus();
        }
      });
    }
  }

  Future<void> initialize() async {
    try {
      if (widget.embedBuilder == null &&
          defaultTargetPlatform == TargetPlatform.android) {
        if (await InAppWebViewController.getCurrentWebViewPackage() == null) {
          throw StateError('Android WebView unavailable');
        }
      }

      if (widget.embedBuilder == null &&
          defaultTargetPlatform == TargetPlatform.windows) {
        if (await WebViewEnvironment.getAvailableVersion() == null) {
          throw StateError('WebView runtime unavailable');
        }
        final data = await getApplicationSupportDirectory();
        final created = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: '${data.path}/trailer-webview',
            additionalBrowserArguments:
                '--autoplay-policy=no-user-gesture-required',
          ),
        );
        if (!mounted) {
          await created.dispose();
          return;
        }
        environment = created;
      }
      if (!mounted) return;
      setState(() => initialized = true);
      startTimeout();
    } catch (_) {
      if (mounted) {
        setState(() {
          bridge.error = defaultTargetPlatform == TargetPlatform.windows
              ? 'The embedded trailer player is unavailable. Check that Microsoft Edge WebView2 is installed.'
              : 'The embedded trailer player is unavailable on this device.';
        });
      }
    }
  }

  void startTimeout() {
    timeout?.cancel();
    timeout = Timer(const Duration(seconds: 25), () {
      if (mounted &&
          (!bridge.ready || bridge.buffering || bridge.state == -1) &&
          bridge.error == null) {
        fail(
          'The trailer took too long to load. Check your connection and try again.',
        );
      }
    });
  }

  void fail(String message) {
    if (!mounted) return;
    timeout?.cancel();
    unawaited(
      web
          ?.evaluateJavascript(
            source: 'if(window.player&&player.pauseVideo)player.pauseVideo();',
          )
          .catchError((Object _) => null),
    );
    setState(() {
      bridge.error = message;
      bridge.playing = false;
      bridge.buffering = false;
    });
  }

  // Navigation must never wait on a stalled native WebView/JavaScript bridge.
  void playbackCommand(String command) {
    unawaited(() async {
      try {
        await bridge.evaluate
            ?.call(command)
            .timeout(const Duration(seconds: 1));
      } catch (_) {}
    }());
  }

  Future<void> requestExit() async {
    if (confirmingExit || !mounted) return;
    confirmingExit = true;
    final previousFocus = FocusManager.instance.primaryFocus;
    final resume = bridge.playing;
    if (resume) {
      playbackCommand(
        'if(window.player&&player.pauseVideo)player.pauseVideo();',
      );
    }
    if (!mounted) return;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit trailer?'),
        content: const Text('Stop watching this trailer and return?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep watching'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit trailer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    confirmingExit = false;
    if (exit == true) {
      playbackCommand('if(window.player&&player.stopVideo)player.stopVideo();');
      setState(() => allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } else {
      if (resume) {
        playbackCommand(
          'if(window.player&&player.playVideo)player.playVideo();',
        );
      }
      if (mounted) {
        (previousFocus?.context != null ? previousFocus! : playFocus)
            .requestFocus();
      }
    }
  }

  KeyEventResult remoteBack(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) unawaited(requestExit());
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (bridge.ready &&
        bridge.error == null &&
        !backFocus.hasFocus &&
        !reloadFocus.hasFocus &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select)) {
      if (event is KeyDownEvent) unawaited(bridge.toggle());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) unawaited(bridge.toggle());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && bridge.ready && bridge.playing) {
      unawaited(
        web?.evaluateJavascript(
          source: 'if(window.player&&player.pauseVideo)player.pauseVideo();',
        ),
      );
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    FocusManager.instance.removeEarlyKeyEventHandler(remoteBack);
    WidgetsBinding.instance.removeObserver(this);
    bridge.removeListener(changed);
    bridge.evaluate = null;
    bridge.dispose();
    playFocus.dispose();
    backFocus.dispose();
    reloadFocus.dispose();
    // The platform view releases its player when unmounted. Do not dispose a
    // shared environment before its platform view has finished detaching.
    final old = environment;
    if (old != null) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 300), old.dispose),
      );
    }
    super.dispose();
  }

  void retry() {
    if (!initialized) {
      unawaited(initialize());
      return;
    }
    setState(() {
      revision++;
      nativeEmbed = null;
      focusedReady = false;
      bridge.ready = false;
      bridge.playing = false;
      bridge.buffering = false;
      bridge.state = -1;
      bridge.position = 0;
      bridge.duration = 0;
      web = null;
      bridge.error = null;
      bridge.evaluate = null;
    });
    startTimeout();
  }

  Widget embed() {
    final generation = revision;
    final android = defaultTargetPlatform == TargetPlatform.android;
    bool current() => mounted && generation == revision;
    return InAppWebView(
      key: ValueKey('trailer-embed-$revision'),
      webViewEnvironment: environment,
      initialData: android
          ? InAppWebViewInitialData(
              data: youtubeTrailerDocument(widget.videoId),
              baseUrl: WebUri(trailerPageUrl),
              historyUrl: WebUri(trailerPageUrl),
            )
          : null,
      initialUrlRequest: android
          ? null
          : URLRequest(
              url: WebUri(trailerPageUrl),
              headers: {'Referer': '$trailerOrigin/'},
            ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useHybridComposition: true,
        // This plugin maps false to LAYER_TYPE_NONE, not SOFTWARE. Inherit
        // the accelerated Activity instead of forcing a cached hardware layer
        // around the WebView's separately composited video surface.
        hardwareAcceleration: false,
        useOnRenderProcessGone: true,
        useShouldInterceptRequest: !android,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        geolocationEnabled: false,
      ),
      shouldInterceptRequest: (controller, request) async {
        if (request.url.toString() != trailerPageUrl) return null;
        return WebResourceResponse(
          contentType: 'text/html',
          contentEncoding: 'utf-8',
          data: Uint8List.fromList(
            utf8.encode(youtubeTrailerDocument(widget.videoId)),
          ),
          statusCode: 200,
          reasonPhrase: 'OK',
          headers: {
            'Referrer-Policy': 'strict-origin-when-cross-origin',
            'Cache-Control': 'no-store',
          },
        );
      },
      onWebViewCreated: (controller) {
        if (!current()) return;
        web = controller;
        bridge.evaluate = (script) =>
            controller.evaluateJavascript(source: script);
        controller.addJavaScriptHandler(
          handlerName: 'TrailerEvent',
          callback: (args) {
            if (current()) bridge.receive(args);
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (_, action) async {
        final uri = Uri.tryParse(action.request.url.toString());
        final host = uri?.host.toLowerCase() ?? '';
        final allowed =
            uri?.toString() == 'about:blank' ||
            (uri?.scheme == 'https' &&
                (host == 'com.iptv.iptv_flutter' ||
                    host == 'youtube.com' ||
                    host.endsWith('.youtube.com') ||
                    host == 'youtube-nocookie.com' ||
                    host.endsWith('.youtube-nocookie.com')));
        return allowed
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (_, _) async => false,
      onPermissionRequest: (_, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onRenderProcessGone: (_, _) {
        if (current()) {
          fail(
            'The video renderer stopped. Choose Try again to reload the trailer.',
          );
        }
      },
      onReceivedError: (_, request, _) {
        if (current() && request.isForMainFrame == true) {
          fail(trailerErrorMessage(null));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowExit,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(requestExit());
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                TextButton.icon(
                  focusNode: backFocus,
                  onPressed: requestExit,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  label: const Text('Back'),
                ),
                const Spacer(),
                TextButton.icon(
                  focusNode: reloadFocus,
                  onPressed: retry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('Reload video'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                SizedBox(
                  key: const ValueKey('trailer-video-viewport'),
                  width: double.infinity,
                  child: Focus(
                    focusNode: playFocus,
                    autofocus: true,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        backFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: initialized
                        ? (widget.embedBuilder?.call(context, bridge) ??
                              (nativeEmbed ??= embed()))
                        : const SizedBox.shrink(),
                  ),
                ),
                if (!bridge.ready || bridge.error != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              bridge.error ?? 'Loading trailer?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: bridge.error == null
                                    ? Colors.white60
                                    : Colors.orangeAccent,
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              children: [
                                if (bridge.error != null)
                                  TextButton(
                                    onPressed: retry,
                                    child: const Text('Try again'),
                                  ),
                                if (bridge.error != null &&
                                    widget.allowExternalFallback &&
                                    externalAvailable)
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        final launched = await launchUrl(
                                          Uri.https(
                                            'www.youtube.com',
                                            '/watch',
                                            {'v': widget.videoId},
                                          ),
                                          mode: LaunchMode.externalApplication,
                                        );
                                        if (!launched) {
                                          throw const FormatException(
                                            'Unavailable launcher',
                                          );
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'No compatible YouTube application or browser is available.',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Open in YouTube'),
                                  ),
                                TextButton(
                                  onPressed: requestExit,
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
