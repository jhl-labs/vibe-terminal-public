import '../data/db/app_database.dart';
import '../security/secure_store.dart';
import 'sections/core_sync_sections.dart';
import 'sync_section.dart';

/// 이 앱이 동기화하는 섹션. 여기 없는 섹션은 원격에 그대로 보존된다.
List<SyncSection> buildSyncSections(AppDatabase db, SecureStore secureStore) =>
    [
      SshKeysSyncSection(db, secureStore),
      IdentitiesSyncSection(db, secureStore),
      HostsSyncSection(db, secureStore),
      SnippetsSyncSection(db, secureStore),
      MemosSyncSection(db, secureStore),
      HostKeysSyncSection(db, secureStore),
    ];
