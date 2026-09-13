import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dart:io';

part 'app_database.g.dart';

@DataClassName('HostRow')
class Hosts extends Table {
  TextColumn get id => text()();
  TextColumn get alias => text()();
  TextColumn get hostname => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text()();
  IntColumn get connectionType => integer().withDefault(const Constant(0))();
  IntColumn get authType => integer().withDefault(const Constant(0))();
  IntColumn get localShellType => integer().withDefault(const Constant(0))();
  TextColumn get workingDirectory => text().nullable()();
  TextColumn get credentialRef => text().nullable()();
  TextColumn get jumpHostId => text().nullable()();
  TextColumn get kubernetesContext => text().nullable()();
  TextColumn get kubernetesNamespace => text().nullable()();
  TextColumn get kubernetesResource => text().nullable()();
  IntColumn get kubernetesSshPort =>
      integer().withDefault(const Constant(22))();
  TextColumn get kubernetesUsername => text().nullable()();
  IntColumn get kubernetesAuthType =>
      integer().withDefault(const Constant(0))();
  TextColumn get kubernetesCredentialRef => text().nullable()();
  IntColumn get remoteSessionPersistence =>
      integer().withDefault(const Constant(0))();
  BoolColumn get agentForwarding =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get x11Forwarding =>
      boolean().withDefault(const Constant(false))();
  TextColumn get startupScript => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HostKeyRow')
class HostKeys extends Table {
  TextColumn get id => text()();
  TextColumn get hostname => text()();
  IntColumn get port => integer()();
  TextColumn get keyType => text()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get pinnedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SnippetRow')
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get body => text()();
  IntColumn get scope => integer().withDefault(const Constant(0))();
  TextColumn get hostId => text().nullable()();
  IntColumn get defaultRunMode => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MemoRow')
class Memos extends Table {
  TextColumn get hostId => text()();
  TextColumn get body => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {hostId};
}

@DataClassName('SessionLogRow')
class SessionLogs extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get hostId => text()();
  TextColumn get hostAlias => text()();
  IntColumn get connectionType => integer()();
  TextColumn get endpoint => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get endReason => text().nullable()();
  TextColumn get logPath => text()();
  IntColumn get byteCount => integer().withDefault(const Constant(0))();
  IntColumn get lineCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Hosts, HostKeys, Snippets, Memos, SessionLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _createTableIfMissing(m, snippets);
      }
      if (from < 3) {
        await _addColumnIfMissing(m, hosts, hosts.connectionType);
        await _addColumnIfMissing(m, hosts, hosts.localShellType);
        await _addColumnIfMissing(m, hosts, hosts.workingDirectory);
      }
      if (from < 4) {
        await _addColumnIfMissing(m, hosts, hosts.jumpHostId);
      }
      if (from < 5) {
        await _addColumnIfMissing(m, hosts, hosts.startupScript);
      }
      if (from < 6) {
        await _createTableIfMissing(m, memos);
      }
      if (from < 8) {
        await _addColumnIfMissing(m, hosts, hosts.x11Forwarding);
      }
      if (from < 9) {
        await _createTableIfMissing(m, sessionLogs);
      }
      if (from < 10) {
        await _addColumnIfMissing(m, hosts, hosts.kubernetesContext);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesNamespace);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesResource);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesSshPort);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesUsername);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesAuthType);
        await _addColumnIfMissing(m, hosts, hosts.kubernetesCredentialRef);
      }
      if (from < 11) {
        await _addColumnIfMissing(m, hosts, hosts.remoteSessionPersistence);
      }
      if (from < 12) {
        await _addColumnIfMissing(m, hosts, hosts.agentForwarding);
      }
    },
  );

  /// `hosts`에 이미 있는 컬럼을 다시 추가하지 않는다.
  ///
  /// 구버전에서 만들어진 일부 DB는 테이블에 컬럼이 이미 있는데도
  /// `user_version`이 그보다 낮게 기록되어 있다. 그대로 `ALTER TABLE ... ADD
  /// COLUMN`을 실행하면 `duplicate column name`으로 실패하고, 마이그레이션
  /// 트랜잭션이 롤백되어 버전이 올라가지 못한 채 실행마다 같은 지점에서 계속
  /// 실패한다. 스키마를 바꾸지 않고 넘어가야 나머지 단계가 진행된다.
  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    final existing = await _columnNames(table.actualTableName);
    if (existing.contains(column.name)) return;
    await m.addColumn(table, column);
  }

  /// 같은 이유로 이미 있는 테이블을 다시 만들지 않는다.
  Future<void> _createTableIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
  ) async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(table.actualTableName)],
    ).get();
    if (rows.isNotEmpty) return;
    await m.createTable(table);
  }

  Future<Set<String>> _columnNames(String table) async {
    final rows = await customSelect("PRAGMA table_info('$table')").get();
    return {for (final row in rows) row.read<String>('name')};
  }

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'vibe_terminal.sqlite'));
      return NativeDatabase(file);
    });
  }

  /// 테스트용 인메모리 DB.
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());
}
