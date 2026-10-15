import 'dart:async';
import 'dart:convert';
import 'dart:io' hide ContentType;
import 'dart:io' as io;
import '../domain/models.dart';

class SubtitleResult {
  final int fileId;
  final String label;
  final double score;
  const SubtitleResult(this.fileId, this.label, {this.score = 0});
}

/// Subtitle discovery is independent of the IPTV provider and playback library.
class SubtitleService {
  final String apiKey;
  final Uri endpoint;
  SubtitleService(this.apiKey, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://api.opensubtitles.com/api/v1/');
  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = endpoint.resolve(path).replace(queryParameters: query);
      final request = await client
          .openUrl(body == null ? 'GET' : 'POST', uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set('Api-Key', apiKey);
      request.headers.set('User-Agent', 'Streamlane v0.1.0');
      request.headers.set('Accept', 'application/json');
      if (body != null) {
        request.headers.contentType = io.ContentType.json;
        final payload = utf8.encode(jsonEncode(body));
        // Send a fixed-size JSON body; the download service rejects chunked POSTs.
        request.contentLength = payload.length;
        request.add(payload);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ProviderException(switch (response.statusCode) {
          401 || 403 => 'OpenSubtitles rejected the API key or account access.',
          406 || 429 =>
            'OpenSubtitles download quota or request limit reached. Try again later.',
          503 =>
            'OpenSubtitles is temporarily unable to serve this download (HTTP 503). Try another subtitle or retry later.',
          400 || 404 || 422 =>
            'OpenSubtitles could not provide this subtitle (HTTP ${response.statusCode}). Choose another result.',
          _ =>
            'OpenSubtitles $path failed (HTTP ${response.statusCode}). Please retry.',
        });
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const ProviderException(
            'Subtitle search response is too large.',
          );
        }
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on ProviderException {
      rethrow;
    } catch (_) {
      throw const ProviderException(
        'Could not contact the subtitle service. Please retry.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<List<SubtitleResult>> search(String title, String language) async {
    final match = RegExp(r'^(.*?)\s*· S(\d+) E(\d+)').firstMatch(title);
    final result = await _request(
      'subtitles',
      query: {
        if (match != null) 'episode_number': match.group(3)!,
        'languages': language,
        'query': match?.group(1)?.trim() ?? title,
        if (match != null) 'season_number': match.group(2)!,
      },
    );
    final rows = result['data'] as List? ?? [];
    final target = (match?.group(1)?.trim() ?? title).toLowerCase();
    Set<String> words(String value) => value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toSet();
    final targetWords = words(target);
    final year = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(title)?.group(1);
    final found = <SubtitleResult>[];
    final seen = <int>{};
    for (final row in rows) {
      final attributes = row['attributes'];
      final feature = attributes['feature_details'] as Map? ?? {};
      if (match != null) {
        if (feature['season_number'] != null &&
            feature['season_number'].toString() != match.group(2)) {
          continue;
        }
        if (feature['episode_number'] != null &&
            feature['episode_number'].toString() != match.group(3)) {
          continue;
        }
      }
      final release = (attributes['release'] ?? '').toString();
      final candidate =
          (feature['parent_title'] ??
                  feature['movie_name'] ??
                  feature['title'] ??
                  release)
              .toString();
      final candidateWords = words(candidate);
      final overlap = targetWords.intersection(candidateWords).length;
      final similarity = targetWords.isEmpty
          ? 0.0
          : overlap / targetWords.length;
      var score = similarity * 100;
      if (candidate.toLowerCase() == target) score += 100;
      if (year != null && feature['year']?.toString() == year) score += 30;
      if (attributes['from_trusted'] == true) score += 10;
      if (attributes['ai_translated'] == true ||
          attributes['machine_translated'] == true) {
        score -= 10;
      }
      final downloads =
          num.tryParse(attributes['download_count']?.toString() ?? '') ?? 0;
      score += downloads.clamp(0, 10000) / 10000;
      for (final file in attributes['files'] as List? ?? []) {
        final id = file['file_id'];
        if (id is! int || !seen.add(id)) continue;
        found.add(
          SubtitleResult(
            id,
            '${release.isEmpty ? file['file_name'] ?? candidate : release} · ${attributes['language'] ?? language}',
            score: score,
          ),
        );
      }
    }
    found.sort((a, b) => b.score.compareTo(a.score));
    return found;
  }

  Future<Uri> download(SubtitleResult result) async {
    final data = await _request(
      'download',
      body: {'file_id': result.fileId, 'sub_format': 'srt'},
    );
    final link = Uri.tryParse(data['link']?.toString() ?? '');
    if (link == null || link.scheme != 'https' || link.host.isEmpty) {
      throw const ProviderException(
        'Subtitle service returned an invalid download link.',
      );
    }
    return link;
  }
}
