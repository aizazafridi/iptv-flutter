import 'dart:convert';

/// Only recognized YouTube hosts/IDs or direct HTTP video links are playable.
String? youtubeTrailerId(Uri uri) {
  if (!const ['http', 'https'].contains(uri.scheme.toLowerCase())) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (const [
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  ].contains(host)) {
    if (uri.path == '/watch') {
      id = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        const [
          'embed',
          'shorts',
          'live',
          'v',
        ].contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    }
  }
  return id != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id) ? id : null;
}

bool isDirectTrailer(Uri uri) =>
    const ['https', 'http'].contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    RegExp(
      r'\.(mp4|m4v|mov|webm|m3u8|mpd|ts)$',
      caseSensitive: false,
    ).hasMatch(uri.path);

const trailerOrigin = 'https://com.iptv.iptv_flutter';
const trailerPageUrl = '$trailerOrigin/trailer';

String youtubeTrailerDocument(String id) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
    throw const FormatException('Invalid YouTube ID');
  }
  // Start loading the video frame alongside the API, rather than waiting for
  // the API download before it can create the frame.
  final embedUrl = Uri.https('www.youtube.com', '/embed/$id', {
    'enablejsapi': '1',
    'autoplay': '1',
    'controls': '1',
    'playsinline': '1',
    'fs': '0',
    'origin': trailerOrigin,
    'widget_referrer': '$trailerOrigin/',
  });
  final embedAttribute = const HtmlEscape().convert(embedUrl.toString());
  return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<link rel="preconnect" href="https://www.youtube.com">
<link rel="preconnect" href="https://i.ytimg.com">
<style>html,body,#player{margin:0;border:0;width:100%;height:100%;background:#000;overflow:hidden}</style></head><body>
<iframe id="player" src="$embedAttribute" allow="autoplay; encrypted-media" title="Movie trailer"></iframe><script>
var player,progressTimer;
function notify(type,value){if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('TrailerEvent',type,value);}
function reportProgress(){if(player&&player.getCurrentTime)notify('progress',[player.getCurrentTime(),player.getDuration()]);}
function updateState(state){clearInterval(progressTimer);notify('state',state);reportProgress();if(state===1)progressTimer=setInterval(reportProgress,1000);}
function onYouTubeIframeAPIReady(){player=new YT.Player('player',{
events:{onReady:function(){notify('ready',true);updateState(player.getPlayerState());player.playVideo();},onStateChange:function(e){updateState(e.data);},onError:function(e){clearInterval(progressTimer);notify('error',e.data);},onAutoplayBlocked:function(){clearInterval(progressTimer);notify('blocked',true);}}});}
function trailerToggle(){if(player&&player.getPlayerState){if(player.getPlayerState()===1)player.pauseVideo();else player.playVideo();}}
function trailerSeek(delta){if(player&&player.getCurrentTime)player.seekTo(Math.max(0,Math.min(player.getDuration(),player.getCurrentTime()+delta)),true);}
function trailerSeekTo(seconds){if(player&&player.seekTo)player.seekTo(Math.max(0,Math.min(player.getDuration(),seconds)),true);}
window.addEventListener('pagehide',function(){clearInterval(progressTimer);if(player&&player.destroy)player.destroy();});
</script><script async src="https://www.youtube.com/iframe_api"></script></body></html>''';
}

String trailerErrorMessage(int? code) => switch (code) {
  100 => 'This trailer is unavailable or private.',
  101 || 150 => 'This trailer does not allow playback inside apps.',
  153 => 'YouTube could not verify this embedded player.',
  2 => 'This trailer link is invalid.',
  5 => 'This device could not play the trailer format.',
  _ => 'The trailer could not be played. Check your connection and try again.',
};
