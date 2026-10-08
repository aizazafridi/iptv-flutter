enum ContentType { live, movies, series }

extension ContentTypeLabel on ContentType {
  String get label => switch (this) {
    ContentType.live => 'Live TV',
    ContentType.movies => 'Movies',
    ContentType.series => 'Series',
  };
}

class ProviderConfig {
  final String providerId, server, username, password;
  const ProviderConfig({
    required this.providerId,
    required this.server,
    required this.username,
    required this.password,
  });
  Map<String, String> toJson() => {
    'providerId': providerId,
    'server': server,
    'username': username,
    'password': password,
  };
  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    providerId: json['providerId'] as String? ?? 'starshare',
    server: json['server'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
  );
}

class Account {
  final String username, status;
  final DateTime? expiresAt;
  const Account(this.username, this.status, this.expiresAt);
}

class Category {
  final String id, name;
  final ContentType type;
  const Category(this.id, this.name, this.type);
}

class ContentItem {
  final String id, name;
  final ContentType type;
  final Uri? artwork;
  final String? extension;

  /// Null means cast metadata has not been fetched; empty means no cast supplied.
  final String? cast;
  const ContentItem({
    required this.id,
    required this.name,
    required this.type,
    this.artwork,
    this.extension,
    this.cast,
  });
}

class MediaDetails {
  final ContentItem item;
  final String synopsis, genre, cast, director, rating, releaseDate, duration;
  final Uri? artwork;
  const MediaDetails({
    required this.item,
    required this.synopsis,
    this.genre = '',
    this.cast = '',
    this.director = '',
    this.rating = '',
    this.releaseDate = '',
    this.duration = '',
    this.artwork,
  });
}

class Episode {
  final String id, title, extension;
  final int season, number;
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    required this.extension,
  });
}

class SeriesDetails {
  final MediaDetails details;
  final List<Episode> episodes;
  const SeriesDetails(this.details, this.episodes);
}

class PlaybackSource {
  final Uri uri;
  final String title;
  final bool isLive;
  final Map<String, String> headers;
  const PlaybackSource({
    required this.uri,
    required this.title,
    this.isLive = false,
    this.headers = const {},
  });
}

// Only safe, user-facing messages cross into presentation. Raw network errors
// may contain authenticated URLs and must never be displayed or logged.
class ProviderException implements Exception {
  final String message;
  const ProviderException(this.message);
  @override
  String toString() => message;
}
