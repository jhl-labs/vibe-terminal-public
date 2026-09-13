import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../models/host.dart';
import '../models/session_log.dart';

const _maxPlainTextReadBytes = 1024 * 1024;
const _truncatedLogNotice = '[앞부분 생략됨: 마지막 1 MB만 표시합니다]';
const _maxPlainTextLines = 5000;
const _truncatedLineNotice = '[앞부분 생략됨: 마지막 5000줄만 표시합니다]';

/// 본문 검색을 시작하는 최소 검색어 길이. 한 글자 검색은 거의 모든 로그와
/// 일치해 파일 전부를 읽게 되므로 메타데이터만 비교한다.
const sessionLogContentSearchMinLength = 2;

/// 로그 파일을 표시용 평문으로 읽은 결과.
///
/// 파일이 표시 상한(마지막 1 MB / 5000줄)을 넘으면 [truncated]가 참이고,
/// [text]에는 상한 안쪽만 담긴다. [lineCount]는 안내 문구를 뺀 본문 줄 수다.
class SessionLogText {
  const SessionLogText({
    required this.text,
    required this.truncated,
    required this.lineCount,
  });

  static const empty = SessionLogText(text: '', truncated: false, lineCount: 0);

  final String text;
  final bool truncated;
  final int lineCount;
}

/// 세션 로그 보관 정책.
///
/// 세션 로그에는 터미널 출력 원문이 그대로 남는다. 사용자가 화면에서 본 것은
/// 무엇이든(설정 파일, 토큰, 조회한 DB 내용) 평문으로 들어간다는 뜻이라,
/// 무한정 쌓이게 두면 안 된다.
///
/// 두 상한의 성격이 다르다는 점이 중요하다.
/// - [maxTotalBytes]는 **용량**이 실제로 문제가 됐을 때만 동작한다. 지워질
///   때는 이미 로그가 아주 많다는 뜻이므로 사용자가 놀랄 일이 없다. 기본으로
///   켜 둔다.
/// - [maxAge]는 아직 쓸모 있을 수 있는 기록을 시간만 보고 지운다. 자동으로
///   켜면 업그레이드 직후 몇 달치 기록이 예고 없이 사라진다. 그래서 기본값은
///   null(끔)이고, 보관 기간을 강제해야 하는 환경에서만 명시적으로 켠다.
class SessionLogRetention {
  const SessionLogRetention({
    this.maxAge,
    this.maxTotalBytes = 200 * 1024 * 1024,
  });

  /// 설정하면 이 기간보다 오래된 종료 로그를 지운다. null이면 나이로는 지우지
  /// 않는다.
  final Duration? maxAge;

  /// 전체 로그 용량 상한. 넘으면 오래된 것부터 지운다.
  final int maxTotalBytes;

  /// 아무것도 지우지 않는 정책. 테스트에서 정리 동작을 배제할 때 쓴다.
  static const keepEverything = SessionLogRetention(maxTotalBytes: 1 << 62);
}

class SessionLogRepository {
  SessionLogRepository(
    this._db, {
    this.logDirectory,
    this.retention = const SessionLogRetention(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final Directory? logDirectory;
  final SessionLogRetention retention;
  final DateTime Function() _now;
  Future<void>? _recoverPreviousRunFuture;

  Future<SessionLogWriter> start({
    required String sessionId,
    required Host host,
  }) async {
    await _recoverPreviousRun();
    final startedAt = _now();
    final id = '${startedAt.microsecondsSinceEpoch}-$sessionId';
    final dir = await _ensureLogDirectory();
    final file = File(p.join(dir.path, '$id.log'));
    await file.create(recursive: true);

    await _db
        .into(_db.sessionLogs)
        .insert(
          SessionLogsCompanion.insert(
            id: id,
            sessionId: sessionId,
            hostId: host.id,
            hostAlias: host.alias,
            connectionType: host.connectionType.index,
            endpoint: host.endpointLabel,
            startedAt: startedAt,
            logPath: file.path,
          ),
        );

    return SessionLogWriter._(repository: this, id: id, file: file);
  }

  Future<List<SessionLog>> getAll() async {
    await _recoverPreviousRun();
    final rows =
        await (_db.select(_db.sessionLogs)..orderBy([
              (t) => OrderingTerm(
                expression: t.startedAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();
    return rows.map(_toModel).toList();
  }

  Future<SessionLog?> getById(String id) async {
    await _recoverPreviousRun();
    final row = await (_db.select(
      _db.sessionLogs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<List<SessionLog>> search(String query) async {
    final logs = await getAll();
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return logs;
    final scanContent = needle.length >= sessionLogContentSearchMinLength;

    final matches = <SessionLog>[];
    for (final log in logs) {
      if (_metadataMatches(log, needle)) {
        matches.add(log);
        continue;
      }
      if (!scanContent) continue;
      final text = await readPlainText(log);
      if (text.toLowerCase().contains(needle)) {
        matches.add(log);
      }
    }
    return matches;
  }

  /// 표시 상한을 적용한 평문과 잘림 여부를 함께 돌려준다.
  Future<SessionLogText> readPlainTextDetailed(SessionLog log) async {
    final file = File(log.logPath);
    if (!await file.exists()) return SessionLogText.empty;
    final length = await file.length();
    final truncated = length > _maxPlainTextReadBytes;
    final bytes = truncated
        ? await _readTailBytes(file, length)
        : await file.readAsBytes();
    final raw = utf8.decode(bytes, allowMalformed: true);
    final text = _normalizeTerminalText(_stripAnsi(raw));
    return _applyDisplayLimits(text, truncatedBytes: truncated);
  }

  Future<String> readPlainText(SessionLog log) async {
    return (await readPlainTextDetailed(log)).text;
  }

  /// 마지막 [maxLines]줄만 돌려준다. 앞부분이 잘려 나갔으면 [SessionLogText.truncated]가
  /// 참이다.
  Future<SessionLogText> readPlainTextTail(
    SessionLog log, {
    int maxLines = 500,
  }) async {
    final detailed = await readPlainTextDetailed(log);
    final tailed = _tailLines(detailed.text, maxLines: maxLines);
    final dropped = tailed.length != detailed.text.length;
    return SessionLogText(
      text: tailed,
      truncated: detailed.truncated || dropped,
      lineCount: dropped ? _countLines(tailed) : detailed.lineCount,
    );
  }

  Future<String> readPlainTextTailById(String id, {int maxLines = 500}) async {
    final log = await getById(id);
    if (log == null) return '';
    return (await readPlainTextTail(log, maxLines: maxLines)).text;
  }

  /// 파일을 먼저 지우고 나서 DB 행을 지운다.
  ///
  /// 순서가 반대면 파일 삭제가 실패했을 때(다른 프로세스가 열어 둔 경우 등)
  /// 목록에서는 사라졌는데 평문 파일만 디스크에 남는 고아가 생긴다.
  Future<void> delete(SessionLog log) async {
    if (log.active) {
      throw const ActiveSessionLogDeleteException();
    }
    final file = File(log.logPath);
    if (await file.exists()) {
      await file.delete();
    }
    await (_db.delete(_db.sessionLogs)..where((t) => t.id.equals(log.id))).go();
  }

  /// 기록 중이 아닌 로그를 모두 지우고 지운 개수를 돌려준다.
  ///
  /// 개별 삭제가 실패한 로그는 그대로 두어 다음에 다시 시도할 수 있게 한다.
  Future<int> deleteInactive() async {
    final logs = await getAll();
    var removed = 0;
    for (final log in logs) {
      if (log.active) continue;
      try {
        await delete(log);
        removed += 1;
      } on FileSystemException {
        // 파일이 잠겨 있으면 목록에 남겨 두고 나중에 다시 지운다.
      }
    }
    return removed;
  }

  Future<void> _complete(
    String id, {
    required String reason,
    required int byteCount,
    required int lineCount,
  }) async {
    await (_db.update(_db.sessionLogs)..where((t) => t.id.equals(id))).write(
      SessionLogsCompanion(
        endedAt: Value(_now()),
        endReason: Value(reason),
        byteCount: Value(byteCount),
        lineCount: Value(lineCount),
      ),
    );
  }

  Future<void> _updateCounts(
    String id, {
    required int byteCount,
    required int lineCount,
  }) async {
    await (_db.update(_db.sessionLogs)..where((t) => t.id.equals(id))).write(
      SessionLogsCompanion(
        byteCount: Value(byteCount),
        lineCount: Value(lineCount),
      ),
    );
  }

  Future<void> _recoverPreviousRun() {
    final existing = _recoverPreviousRunFuture;
    if (existing != null) return existing;
    _recoverPreviousRunFuture = _recoverThenPrune();
    return _recoverPreviousRunFuture!;
  }

  Future<void> _recoverThenPrune() async {
    await (_db.update(_db.sessionLogs)..where((t) => t.endedAt.isNull())).write(
      SessionLogsCompanion(
        endedAt: Value(_now()),
        endReason: const Value('abandoned'),
      ),
    );
    await pruneExpired();
  }

  /// 보관 정책을 넘긴 로그를 지운다. 실행 중인 로그는 건드리지 않는다.
  ///
  /// 실행당 한 번, [_recoverPreviousRun] 뒤에 자동으로 불린다. 정리 실패가
  /// 로그 기능 전체를 막으면 안 되므로 개별 삭제 오류는 넘긴다.
  Future<int> pruneExpired() async {
    final rows =
        await (_db.select(_db.sessionLogs)
              ..where((t) => t.endedAt.isNotNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.startedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    final maxAge = retention.maxAge;
    final cutoff = maxAge == null ? null : _now().subtract(maxAge);
    final doomed = <SessionLogRow>[];
    var keptBytes = 0;

    for (final row in rows) {
      // 최신순으로 훑으면서, 너무 오래됐거나 용량 상한을 넘긴 시점부터 버린다.
      if (cutoff != null && row.startedAt.isBefore(cutoff)) {
        doomed.add(row);
        continue;
      }
      final size = await _fileSize(row.logPath);
      if (keptBytes + size > retention.maxTotalBytes) {
        doomed.add(row);
        continue;
      }
      keptBytes += size;
    }

    var removed = 0;
    for (final row in doomed) {
      try {
        final file = File(row.logPath);
        if (await file.exists()) await file.delete();
        await (_db.delete(
          _db.sessionLogs,
        )..where((t) => t.id.equals(row.id))).go();
        removed += 1;
      } catch (_) {
        // 파일이 잠겨 있거나 이미 없어도 다음 실행에서 다시 시도된다.
      }
    }
    return removed;
  }

  Future<int> _fileSize(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Directory> _ensureLogDirectory() async {
    final configured = logDirectory;
    if (configured != null) {
      await configured.create(recursive: true);
      return configured;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'session_logs'));
    await dir.create(recursive: true);
    return dir;
  }

  bool _metadataMatches(SessionLog log, String needle) {
    return log.hostAlias.toLowerCase().contains(needle) ||
        log.endpoint.toLowerCase().contains(needle) ||
        log.sessionId.toLowerCase().contains(needle) ||
        log.connectionLabel.toLowerCase().contains(needle) ||
        log.endLabel.toLowerCase().contains(needle);
  }

  SessionLog _toModel(SessionLogRow row) {
    final connectionType =
        row.connectionType >= 0 &&
            row.connectionType < HostConnectionType.values.length
        ? HostConnectionType.values[row.connectionType]
        : HostConnectionType.ssh;
    return SessionLog(
      id: row.id,
      sessionId: row.sessionId,
      hostId: row.hostId,
      hostAlias: row.hostAlias,
      connectionType: connectionType,
      endpoint: row.endpoint,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      endReason: row.endReason,
      logPath: row.logPath,
      byteCount: row.byteCount,
      lineCount: row.lineCount,
    );
  }
}

Future<List<int>> _readTailBytes(File file, int length) async {
  final start = length - _maxPlainTextReadBytes;
  final readStart = start > 0 ? start - 1 : 0;
  final readLength = length - readStart;
  final handle = await file.open();
  try {
    await handle.setPosition(readStart);
    final bytes = await handle.read(readLength);
    if (start <= 0 || bytes.isEmpty) return bytes;

    final previous = bytes.first;
    var tail = bytes.sublist(1);
    if (previous == 0x0A || previous == 0x0D) return tail;

    final nextLine = tail.indexOf(0x0A);
    if (nextLine >= 0 && nextLine + 1 < tail.length) {
      tail = tail.sublist(nextLine + 1);
    }
    return tail;
  } finally {
    await handle.close();
  }
}

class SessionLogWriter {
  SessionLogWriter._({
    required this._repository,
    required this._id,
    required this._file,
  });

  final SessionLogRepository _repository;
  final String _id;
  final File _file;

  bool _closed = false;
  int _byteCount = 0;
  int _lineCount = 0;
  Timer? _flushTimer;
  Timer? _inputFlushTimer;
  Future<void>? _finishFuture;
  Future<void> _pendingWrite = Future.value();
  final _inputBuffer = StringBuffer();
  String _currentOutputLine = '';
  bool _redactingInput = false;
  bool _redactedInputHasContent = false;

  String get id => _id;

  void write(List<int> data) {
    _rememberOutput(data);
    _append(data);
  }

  void writeInput(List<int> data) {
    if (_closed || data.isEmpty) return;
    final text = utf8.decode(data, allowMalformed: true);
    if (_isTerminalControlResponse(text)) return;
    if (_redactingInput || _looksSensitivePrompt(_currentOutputLine)) {
      _redactingInput = true;
      _redactedInputHasContent =
          _redactedInputHasContent || _hasLoggableInput(text);
      if (_shouldFlushInput(text)) {
        _flushInputBuffer();
      } else {
        _scheduleInputFlush();
      }
      return;
    }
    _inputBuffer.write(text);
    if (_shouldFlushInput(text)) {
      _flushInputBuffer();
    } else {
      _scheduleInputFlush();
    }
  }

  void _append(List<int> data) {
    if (_closed) return;
    final chunk = List<int>.from(data, growable: false);
    _pendingWrite = _pendingWrite.then(
      (_) => _file.writeAsBytes(chunk, mode: FileMode.append),
    );
    _byteCount += data.length;
    for (final byte in data) {
      if (byte == 0x0A) _lineCount++;
    }
    _scheduleFlush();
  }

  /// 예약된 디스크 쓰기가 모두 끝날 때까지 기다린다.
  ///
  /// [write]/[writeInput]은 쓰기를 큐에 넣기만 하므로, 곧바로 파일을 읽으면
  /// 아직 반영 전일 수 있다. 테스트가 고정 시간 대기 대신 이 메서드를 쓰면
  /// 부하에 따라 결과가 달라지지 않는다.
  Future<void> flushPendingWrites() async {
    _flushInputBuffer();
    await _pendingWrite;
  }

  Future<void> finish(String reason) {
    final existing = _finishFuture;
    if (existing != null) return existing;
    _finishFuture = _finish(reason);
    return _finishFuture!;
  }

  Future<void> _finish(String reason) async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _inputFlushTimer?.cancel();
    _inputFlushTimer = null;
    _flushInputBuffer();
    _closed = true;
    await _pendingWrite;
    await _repository._complete(
      _id,
      reason: reason,
      byteCount: _byteCount,
      lineCount: _lineCount,
    );
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      if (_closed) return;
      unawaited(
        _repository._updateCounts(
          _id,
          byteCount: _byteCount,
          lineCount: _lineCount,
        ),
      );
    });
  }

  void _rememberOutput(List<int> data) {
    if (data.isEmpty) return;
    final text = _stripAnsi(
      utf8.decode(data, allowMalformed: true),
    ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (text.isEmpty) return;
    final newline = text.lastIndexOf('\n');
    if (newline >= 0) {
      _currentOutputLine = text.substring(newline + 1);
    } else {
      _currentOutputLine += text;
    }
    const maxPromptChars = 500;
    if (_currentOutputLine.length > maxPromptChars) {
      _currentOutputLine = _currentOutputLine.substring(
        _currentOutputLine.length - maxPromptChars,
      );
    }
  }

  void _scheduleInputFlush() {
    _inputFlushTimer?.cancel();
    _inputFlushTimer = Timer(const Duration(milliseconds: 1200), () {
      _inputFlushTimer = null;
      _flushInputBuffer();
    });
  }

  void _flushInputBuffer() {
    _inputFlushTimer?.cancel();
    _inputFlushTimer = null;
    if (_redactingInput) {
      final shouldAppend = _redactedInputHasContent;
      _redactingInput = false;
      _redactedInputHasContent = false;
      _inputBuffer.clear();
      if (!shouldAppend) return;
      _append(utf8.encode('[input] <redacted>\n'));
      return;
    }
    final line = _formatInputLogLine(_inputBuffer.toString());
    _inputBuffer.clear();
    if (line == null) return;
    _append(utf8.encode(line));
  }
}

final _terminalControlResponsePattern = RegExp(r'^\x1B\[[0-9;?]*[A-Za-z]$');

bool _isTerminalControlResponse(String value) {
  if (value.isEmpty) return true;
  return _terminalControlResponsePattern.hasMatch(value);
}

bool _shouldFlushInput(String value) {
  return value.contains('\r') ||
      value.contains('\n') ||
      value.contains('\x03') ||
      value.contains('\x04');
}

bool _hasLoggableInput(String value) {
  if (value.contains('\x03') || value.contains('\x04')) return true;
  return value.runes.any((rune) => rune >= 0x20 && rune != 0x7F);
}

bool _looksSensitivePrompt(String value) {
  final lower = value.toLowerCase();
  return lower.contains('password') ||
      lower.contains('passphrase') ||
      value.contains('비밀번호') ||
      value.contains('암호');
}

String? _formatInputLogLine(String value) {
  final normalized = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trimRight();
  if (normalized.isEmpty) return null;
  final escaped = normalized
      .replaceAll('\x03', '<Ctrl-C>')
      .replaceAll('\x04', '<Ctrl-D>')
      .replaceAll('\x1b', '<Esc>');
  return '[input] $escaped\n';
}

final _ansiPattern = RegExp(
  r'\x1B(?:\][^\x07]*(?:\x07|\x1B\\)|\[[0-?]*[ -/]*[@-~]|[@-Z\\-_])',
);

String _stripAnsi(String value) => value.replaceAll(_ansiPattern, '');

String _normalizeTerminalText(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
}

String _tailLines(String value, {required int maxLines}) {
  final safeMax = maxLines <= 0 ? 1 : maxLines;
  final lines = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  if (lines.length <= safeMax) return value;
  return lines.sublist(lines.length - safeMax).join('\n').trimRight();
}

SessionLogText _applyDisplayLimits(
  String text, {
  required bool truncatedBytes,
}) {
  final notices = <String>[if (truncatedBytes) _truncatedLogNotice];

  var body = text;
  var lines = text.split('\n');
  if (lines.length > _maxPlainTextLines) {
    notices.add(_truncatedLineNotice);
    lines = lines.sublist(lines.length - _maxPlainTextLines);
    body = lines.join('\n');
  }
  final lineCount = body.isEmpty ? 0 : lines.length;

  if (notices.isEmpty) {
    return SessionLogText(text: body, truncated: false, lineCount: lineCount);
  }
  final joined = body.isEmpty
      ? notices.join('\n')
      : '${notices.join('\n')}\n$body';
  return SessionLogText(text: joined, truncated: true, lineCount: lineCount);
}

int _countLines(String value) => value.isEmpty ? 0 : value.split('\n').length;

class ActiveSessionLogDeleteException implements Exception {
  const ActiveSessionLogDeleteException();
}
