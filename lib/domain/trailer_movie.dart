class TrailerCastMember {
  final String name, character, profilePath;
  const TrailerCastMember({
    required this.name,
    this.character = '',
    this.profilePath = '',
  });
  factory TrailerCastMember.fromJson(Map row) => TrailerCastMember(
    name: row['name'] as String? ?? '',
    character: row['character'] as String? ?? '',
    profilePath: row['profile_path'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'character': character,
    'profile_path': profilePath,
  };
}

class TrailerVideo {
  final String key, name, type;
  final bool official;
  final DateTime? published;
  const TrailerVideo({
    required this.key,
    required this.name,
    required this.type,
    required this.official,
    this.published,
  });
  Uri get uri => Uri.https('www.youtube.com', '/watch', {'v': key});
  String get label =>
      '${official ? 'Official ' : ''}${type.isEmpty ? 'Preview' : type}';
  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'type': type,
    'official': official,
    'published_at': published?.toIso8601String(),
    'site': 'YouTube',
  };
  static TrailerVideo? select(List<dynamic> raw) {
    final videos = <TrailerVideo>[];
    for (final row in raw.whereType<Map>()) {
      final key = row['key'];
      if (row['site'] != 'YouTube' ||
          key is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(key) ||
          !const ['Trailer', 'Teaser', 'Clip'].contains(row['type'])) {
        continue;
      }
      videos.add(
        TrailerVideo(
          key: key,
          name: row['name'] as String? ?? '',
          type: row['type'] as String,
          official: row['official'] == true,
          published: DateTime.tryParse(row['published_at'] as String? ?? ''),
        ),
      );
    }
    int rank(TrailerVideo v) => v.type == 'Trailer'
        ? (v.official ? 0 : 1)
        : v.type == 'Teaser'
        ? (v.official ? 2 : 3)
        : 4;
    videos.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0
          ? r
          : (b.published ?? DateTime(1970)).compareTo(
              a.published ?? DateTime(1970),
            );
    });
    return videos.firstOrNull;
  }
}

class TrailerMovie {
  final int id;
  final String title,
      originalTitle,
      originalLanguage,
      overview,
      releaseDate,
      posterPath,
      backdropPath,
      certification;
  final List<String> genres;
  final List<TrailerCastMember> cast;
  final double rating;
  final int runtime;
  final TrailerVideo? video;
  const TrailerMovie({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.originalLanguage = '',
    this.overview = '',
    this.releaseDate = '',
    this.posterPath = '',
    this.backdropPath = '',
    this.certification = '',
    this.genres = const [],
    this.cast = const [],
    this.rating = 0,
    this.runtime = 0,
    this.video,
  });
  DateTime? get release => DateTime.tryParse(releaseDate);
  String get dateLabel => release == null
      ? 'Release date TBA'
      : '${release!.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][release!.month - 1]} ${release!.year}';
  static Uri? image(String path, String size) =>
      path.startsWith('/') && !path.contains('..') && !path.contains('://')
      ? Uri.https('image.tmdb.org', '/t/p/$size$path')
      : null;
  Uri? get poster => image(posterPath, 'w342');
  Uri? get card => image(backdropPath, 'w300') ?? poster;
  Uri? get backdrop => image(backdropPath, 'w780');
  Uri? get preview => video == null
      ? null
      : Uri.https('i.ytimg.com', '/vi/${video!.key}/hqdefault.jpg');
  factory TrailerMovie.fromJson(
    Map<String, dynamic> row, {
    String region = 'US',
  }) {
    String cert = '';
    final dates = row['release_dates'];
    if (dates is Map) {
      for (final country
          in (dates['results'] as List? ?? []).whereType<Map>()) {
        if (country['iso_3166_1'] != region) continue;
        for (final date
            in (country['release_dates'] as List? ?? []).whereType<Map>()) {
          if ((date['certification'] as String? ?? '').isNotEmpty) {
            cert = date['certification'];
            break;
          }
        }
      }
    }
    final videos = row['videos'];
    return TrailerMovie(
      id: (row['id'] as num).toInt(),
      title: row['title'] as String? ?? 'Untitled',
      originalTitle: row['original_title'] as String? ?? '',
      originalLanguage: row['original_language'] as String? ?? '',
      overview: row['overview'] as String? ?? '',
      releaseDate: row['release_date'] as String? ?? '',
      posterPath: row['poster_path'] as String? ?? '',
      backdropPath: row['backdrop_path'] as String? ?? '',
      certification: row['certification'] as String? ?? cert,
      rating: (row['vote_average'] as num?)?.toDouble() ?? 0,
      runtime: (row['runtime'] as num?)?.toInt() ?? 0,
      genres: (row['genres'] as List? ?? [])
          .map((g) => g is Map ? g['name'] as String? ?? '' : g.toString())
          .where((g) => g.isNotEmpty)
          .toList(),
      cast: ((row['credits'] as Map?)?['cast'] as List? ?? [])
          .whereType<Map>()
          .map(TrailerCastMember.fromJson)
          .where((p) => p.name.isNotEmpty)
          .take(20)
          .toList(),
      video: TrailerVideo.select(
        videos is Map ? videos['results'] as List? ?? [] : [],
      ),
    );
  }
  TrailerMovie withVideo(TrailerVideo? v) => TrailerMovie(
    id: id,
    title: title,
    originalTitle: originalTitle,
    originalLanguage: originalLanguage,
    overview: overview,
    releaseDate: releaseDate,
    posterPath: posterPath,
    backdropPath: backdropPath,
    genres: genres,
    cast: cast,
    rating: rating,
    runtime: runtime,
    certification: certification,
    video: v,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'original_title': originalTitle,
    'original_language': originalLanguage,
    'overview': overview,
    'release_date': releaseDate,
    'poster_path': posterPath,
    'backdrop_path': backdropPath,
    'genres': genres,
    'credits': {'cast': cast.map((p) => p.toJson()).toList()},
    'vote_average': rating,
    'runtime': runtime,
    'certification': certification,
    'videos': {
      'results': video == null ? [] : [video!.toJson()],
    },
  };
}

class TrailerPage {
  final List<TrailerMovie> movies;
  final int page, totalPages;
  final bool stale;
  const TrailerPage(
    this.movies,
    this.page,
    this.totalPages, {
    this.stale = false,
  });
}
