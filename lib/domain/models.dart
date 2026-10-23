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
  final String? profileId;
  const ProviderConfig({
    required this.providerId,
    required this.server,
    required this.username,
    required this.password,
    this.profileId,
  });
  Map<String, String> toJson() => {
    'providerId': providerId,
    'server': server,
    'username': username,
    'password': password,
    'profileId': ?profileId,
  };
  factory ProviderConfig.fromJson(Map<String, dynamic> json) => ProviderConfig(
    providerId: json['providerId'] as String? ?? 'starshare',
    server: json['server'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    profileId: json['profileId'] as String?,
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
  final String? categoryId;

  /// Provider added timestamp; series may fall back to last modification.
  final DateTime? addedAt;
  const ContentItem({
    required this.id,
    required this.name,
    required this.type,
    this.artwork,
    this.extension,
    this.categoryId,
    this.addedAt,
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
  final Uri? artwork;
  final int season, number;
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    required this.extension,
    this.artwork,
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

/// Absolute instants: compare with the system clock and display in local time.
class EpgProgramme {
  final String title, description;
  final DateTime start, end;

  /// Provider wall-clock time used by its archive endpoint.
  final String? archiveStart;
  const EpgProgramme({
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    this.archiveStart,
  });
  bool isCurrent(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}

class SubtitleOption {
  final String id, label;
  const SubtitleOption(this.id, this.label);
}

const profileAvatarCount = 8;

class AccountProfile {
  final String id, name;
  final int avatar;
  final ProviderConfig config;
  const AccountProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.config,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'avatarSet': 'photos-v1',
    'config': config.toJson(),
  };
  factory AccountProfile.fromJson(Map<String, dynamic> json) => AccountProfile(
    id: json['id'],
    name: json['name'],
    // Preserve previously selected supplied photos (old indices 30–37).
    // Retired illustrations fall back to the first supplied portrait.
    avatar: json['avatarSet'] == 'photos-v1'
        ? (json['avatar'] as int).clamp(0, profileAvatarCount - 1)
        : ((json['avatar'] as int) >= 30 && (json['avatar'] as int) <= 37
              ? (json['avatar'] as int) - 30
              : 0),
    config: ProviderConfig.fromJson(json['config'] as Map<String, dynamic>),
  );
}
