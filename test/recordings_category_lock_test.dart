import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test(
    'recordings protection is shared by media types and isolated by profile',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final locks = CategoryLocks('recordings-user');
      await locks.load();
      await locks.setPassword('123456');
      final movies = CategoryLocks.recordingsCategory(ContentType.movies);
      final series = CategoryLocks.recordingsCategory(ContentType.series);
      final live = CategoryLocks.recordingsCategory(ContentType.live);
      await locks.configureCategory(movies, true);
      await locks.setHidden(live, true);
      final restored = CategoryLocks('recordings-user');
      await restored.load();
      expect(restored.isLocked(movies), isTrue);
      expect(restored.isLocked(series), isTrue);
      expect(restored.hidden(live), isTrue);
      expect(restored.unlock(movies, '000000'), isFalse);
      expect(restored.unlock(movies, '123456'), isTrue);
      expect(restored.isLocked(live), isFalse);
      expect(restored.hidden(movies), isTrue);
      await restored.setHidden(series, false);
      expect(restored.hidden(live), isFalse);
      final other = CategoryLocks('other-recordings-user');
      await other.load();
      expect(other.configured(movies), isFalse);
      expect(other.hidden(live), isFalse);
    },
  );
}
