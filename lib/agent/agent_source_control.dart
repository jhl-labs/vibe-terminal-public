enum AgentFileChangeKind {
  added,
  modified,
  deleted,
  renamed,
  untracked,
  conflicted,
}

class AgentFileChange {
  const AgentFileChange({
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
    required this.kind,
    this.originalPath,
  });

  final String path;
  final String? originalPath;
  final String indexStatus;
  final String worktreeStatus;
  final AgentFileChangeKind kind;

  bool get isStaged => indexStatus != ' ' && indexStatus != '?';
  bool get isConflicted => kind == AgentFileChangeKind.conflicted;

  Iterable<String> get gitPaths sync* {
    yield path;
    if (originalPath case final original?) yield original;
  }
}

class AgentSourceControlSnapshot {
  const AgentSourceControlSnapshot({
    required this.branchName,
    required this.headSha,
    required this.files,
  });

  final String branchName;
  final String headSha;
  final List<AgentFileChange> files;

  bool get isClean => files.isEmpty;
}

class AgentFileDiff {
  const AgentFileDiff({
    required this.path,
    required this.content,
    required this.truncated,
  });

  final String path;
  final String content;
  final bool truncated;
}

class AgentCommitResult {
  const AgentCommitResult({required this.shortSha, required this.subject});

  final String shortSha;
  final String subject;
}

/// `git status --porcelain=v1 -z`의 기계 판독 형식을 UI 모델로 변환한다.
/// NUL 구분자를 사용하므로 공백, 탭, 줄바꿈이 포함된 경로도 손실하지 않는다.
List<AgentFileChange> parseAgentGitStatus(String output) {
  if (output.isEmpty) return const [];
  final records = output.split('\u0000');
  final changes = <AgentFileChange>[];
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record.length < 4) continue;
    final indexStatus = record[0];
    final worktreeStatus = record[1];
    if (indexStatus == '!' && worktreeStatus == '!') continue;
    final path = record.substring(3);
    String? originalPath;
    if (_isRenameOrCopy(indexStatus, worktreeStatus) &&
        index + 1 < records.length &&
        records[index + 1].isNotEmpty) {
      originalPath = records[++index];
    }
    changes.add(
      AgentFileChange(
        path: path,
        originalPath: originalPath,
        indexStatus: indexStatus,
        worktreeStatus: worktreeStatus,
        kind: _changeKind(indexStatus, worktreeStatus),
      ),
    );
  }
  changes.sort((left, right) => left.path.compareTo(right.path));
  return List.unmodifiable(changes);
}

bool _isRenameOrCopy(String indexStatus, String worktreeStatus) =>
    indexStatus == 'R' ||
    indexStatus == 'C' ||
    worktreeStatus == 'R' ||
    worktreeStatus == 'C';

AgentFileChangeKind _changeKind(String indexStatus, String worktreeStatus) {
  final status = '$indexStatus$worktreeStatus';
  if (status.contains('U') || status == 'AA' || status == 'DD') {
    return AgentFileChangeKind.conflicted;
  }
  if (indexStatus == '?' && worktreeStatus == '?') {
    return AgentFileChangeKind.untracked;
  }
  if (_isRenameOrCopy(indexStatus, worktreeStatus)) {
    return AgentFileChangeKind.renamed;
  }
  if (status.contains('D')) return AgentFileChangeKind.deleted;
  if (status.contains('A')) return AgentFileChangeKind.added;
  return AgentFileChangeKind.modified;
}
