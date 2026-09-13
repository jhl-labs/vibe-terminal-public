import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models/host.dart';
import 'agent_delivery.dart';
import 'agent_worktree.dart';

class AgentDeliveryProcessResult {
  const AgentDeliveryProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef RemoteAgentDeliveryExecutor =
    Future<AgentDeliveryProcessResult> Function({
      required Host host,
      required String? preferredSessionId,
      required String executable,
      required List<String> arguments,
      required String? workingDirectory,
      required Duration timeout,
    });

class AgentDeliveryRuntimeException implements Exception {
  const AgentDeliveryRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Agent worktree의 전달 가능 상태와 명시적으로 승인된 Git/GitHub 동작만 담당한다.
/// 세션과 UI를 알지 않으며, 원격 명령 실행은 주입된 executor에 위임한다.
class AgentDeliveryRuntime {
  const AgentDeliveryRuntime(this._remoteExecutor);

  final RemoteAgentDeliveryExecutor _remoteExecutor;

  Future<AgentDeliveryPreview> preview({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final worktreeStatus = await _git(
      entry: entry,
      host: host,
      arguments: const ['status', '--porcelain=v1', '--untracked-files=normal'],
      directory: entry.worktreePath,
    );
    _requireSuccess(worktreeStatus, 'Agent 작업 트리 상태를 읽지 못했습니다.');
    final worktreeDirty = worktreeStatus.stdout.trim().isNotEmpty;

    final currentBranch = await _git(
      entry: entry,
      host: host,
      arguments: const ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      directory: entry.worktreePath,
    );
    _requireSuccess(currentBranch, 'Agent 브랜치를 확인하지 못했습니다.');
    if (currentBranch.stdout.trim() != entry.branchName) {
      throw AgentDeliveryRuntimeException(
        'worktree의 현재 브랜치(${currentBranch.stdout.trim()})가 기록된 브랜치'
        '(${entry.branchName})와 다릅니다.',
      );
    }

    final headSha = await _revParse(entry, host, entry.branchName);
    final baseSha = await _revParse(entry, host, entry.baseRef);
    final counts = await _git(
      entry: entry,
      host: host,
      arguments: [
        'rev-list',
        '--left-right',
        '--count',
        '${entry.baseRef}...${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(counts, '기준 브랜치와 Agent 브랜치의 차이를 읽지 못했습니다.');
    final countParts = counts.stdout.trim().split(RegExp(r'\s+'));
    final behind = countParts.isEmpty ? 0 : int.tryParse(countParts.first) ?? 0;
    final ahead = countParts.length < 2 ? 0 : int.tryParse(countParts[1]) ?? 0;
    final conflictPaths = ahead > 0 && behind > 0
        ? await _predictedConflictPaths(entry: entry, host: host)
        : const <String>[];

    final names = await _git(
      entry: entry,
      host: host,
      arguments: [
        'diff',
        '--name-only',
        '-z',
        '${entry.baseRef}...${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(names, '전달할 파일 목록을 읽지 못했습니다.');
    final changedFiles = names.stdout
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .length;

    final numstat = await _git(
      entry: entry,
      host: host,
      arguments: [
        'diff',
        '--numstat',
        '${entry.baseRef}...${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(numstat, '변경 통계를 읽지 못했습니다.');
    var additions = 0;
    var deletions = 0;
    for (final line in const LineSplitter().convert(numstat.stdout)) {
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      additions += int.tryParse(parts[0]) ?? 0;
      deletions += int.tryParse(parts[1]) ?? 0;
    }

    final log = await _git(
      entry: entry,
      host: host,
      arguments: [
        'log',
        '--reverse',
        '--format=%H%x00%h%x00%s%x00%an%x00%aI%x1e',
        '${entry.baseRef}..${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(log, '전달할 commit 목록을 읽지 못했습니다.');
    final commits = _parseCommits(log.stdout);

    final rootBranch = await _git(
      entry: entry,
      host: host,
      arguments: const ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      directory: entry.repositoryRoot,
    );
    final baseCheckedOut =
        rootBranch.exitCode == 0 && rootBranch.stdout.trim() == entry.baseRef;
    final rootStatus = await _git(
      entry: entry,
      host: host,
      arguments: const ['status', '--porcelain=v1', '--untracked-files=normal'],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(rootStatus, '기준 작업 트리 상태를 읽지 못했습니다.');
    final baseDirty = rootStatus.stdout.trim().isNotEmpty;
    final mergeReadiness = worktreeDirty
        ? AgentDeliveryMergeReadiness.worktreeDirty
        : ahead == 0
        ? AgentDeliveryMergeReadiness.alreadyMerged
        : !baseCheckedOut
        ? AgentDeliveryMergeReadiness.baseNotCheckedOut
        : baseDirty
        ? AgentDeliveryMergeReadiness.baseDirty
        : behind > 0
        ? AgentDeliveryMergeReadiness.diverged
        : AgentDeliveryMergeReadiness.ready;

    final remote = await _remoteDetails(entry, host);
    final existingPullRequestUrl = remote.slug == null || !remote.branchExists
        ? null
        : await _existingPullRequest(
            entry: entry,
            host: host,
            repository: remote.slug!,
          );
    return AgentDeliveryPreview(
      branchName: entry.branchName,
      baseRef: entry.baseRef,
      headSha: _shortSha(headSha),
      baseSha: _shortSha(baseSha),
      aheadCount: ahead,
      behindCount: behind,
      changedFiles: changedFiles,
      additions: additions,
      deletions: deletions,
      commits: List.unmodifiable(commits),
      mergeReadiness: mergeReadiness,
      remoteName: remote.name,
      remoteUrl: remote.url,
      remoteBranchExists: remote.branchExists,
      compareUrl: remote.compareUrl(entry.baseRef, entry.branchName),
      existingPullRequestUrl: existingPullRequestUrl,
      conflictPaths: List.unmodifiable(conflictPaths),
    );
  }

  /// 현재 worktree를 변경하지 않고 기준 ref와 Agent 브랜치의 가상 병합 결과를
  /// 계산한다. exit code 1은 merge-tree에서 충돌을 발견했다는 정상 결과다.
  Future<List<String>> predictedConflictPaths({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final counts = await _git(
      entry: entry,
      host: host,
      arguments: [
        'rev-list',
        '--left-right',
        '--count',
        '${entry.baseRef}...${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(counts, '충돌 예측을 위한 브랜치 차이를 읽지 못했습니다.');
    final parts = counts.stdout.trim().split(RegExp(r'\s+'));
    final behind = parts.isEmpty ? 0 : int.tryParse(parts.first) ?? 0;
    final ahead = parts.length < 2 ? 0 : int.tryParse(parts[1]) ?? 0;
    if (ahead == 0 || behind == 0) return const [];
    return _predictedConflictPaths(entry: entry, host: host);
  }

  Future<List<String>> _predictedConflictPaths({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final result = await _git(
      entry: entry,
      host: host,
      arguments: [
        'merge-tree',
        '--write-tree',
        '--name-only',
        '-z',
        '--no-messages',
        entry.baseRef,
        entry.branchName,
      ],
      directory: entry.repositoryRoot,
    );
    if (result.exitCode != 0 && result.exitCode != 1) {
      _requireSuccess(result, 'Git 충돌을 예측하지 못했습니다.');
    }
    if (result.exitCode == 0) return const [];
    final records = result.stdout
        .split('\u0000')
        .where((value) => value.isNotEmpty)
        .toList();
    if (records.isNotEmpty &&
        RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(records.first.trim())) {
      records.removeAt(0);
    }
    return records.toSet().toList()..sort();
  }

  Future<AgentDeliveryResult> mergeFastForward({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final current = await preview(entry: entry, host: host);
    if (!current.canMerge) {
      throw AgentDeliveryRuntimeException(
        _mergeBlockedMessage(current.mergeReadiness),
      );
    }
    final merged = await _git(
      entry: entry,
      host: host,
      arguments: ['merge', '--ff-only', entry.branchName],
      directory: entry.repositoryRoot,
      timeout: const Duration(minutes: 2),
    );
    _requireSuccess(merged, 'fast-forward 병합에 실패했습니다. 저장소 상태를 다시 확인해 주세요.');
    final sha = await _revParse(entry, host, entry.baseRef);
    return AgentDeliveryResult(
      summary: '${entry.baseRef}에 병합했습니다.',
      detail: '${entry.branchName} → ${entry.baseRef} · ${_shortSha(sha)}',
    );
  }

  Future<AgentDeliveryResult> pushBranch({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final current = await preview(entry: entry, host: host);
    if (!current.canPush || current.remoteName == null) {
      throw const AgentDeliveryRuntimeException(
        'push할 remote 또는 commit이 없습니다.',
      );
    }
    if (current.mergeReadiness == AgentDeliveryMergeReadiness.worktreeDirty) {
      throw const AgentDeliveryRuntimeException('커밋하지 않은 변경을 먼저 처리해 주세요.');
    }
    final pushed = await _git(
      entry: entry,
      host: host,
      arguments: [
        'push',
        '--set-upstream',
        current.remoteName!,
        'refs/heads/${entry.branchName}:refs/heads/${entry.branchName}',
      ],
      directory: entry.worktreePath,
      timeout: const Duration(minutes: 5),
    );
    _requireSuccess(pushed, '브랜치를 push하지 못했습니다. force push는 자동으로 수행하지 않습니다.');
    return AgentDeliveryResult(
      summary: '${entry.branchName} 브랜치를 push했습니다.',
      detail: '${current.remoteName}/${entry.branchName} · ${current.headSha}',
      url: current.compareUrl,
    );
  }

  Future<AgentDeliveryResult> createPullRequest({
    required AgentWorktreeRecord entry,
    required Host host,
    required AgentPullRequestDraft draft,
  }) async {
    final title = draft.title.trim();
    final body = draft.body.trim();
    if (title.isEmpty || title.length > 256 || title.contains('\u0000')) {
      throw const AgentDeliveryRuntimeException('PR 제목은 1~256자로 입력해 주세요.');
    }
    if (body.length > 65536 || body.contains('\u0000')) {
      throw const AgentDeliveryRuntimeException('PR 본문은 65,536자 이하여야 합니다.');
    }
    final current = await preview(entry: entry, host: host);
    if (current.existingPullRequestUrl != null) {
      return AgentDeliveryResult(
        summary: '이미 열린 Pull Request가 있습니다.',
        detail: '${entry.branchName} → ${entry.baseRef}',
        url: current.existingPullRequestUrl,
      );
    }
    final repository = parseAgentGitHubRepository(current.remoteUrl);
    if (!current.canCreatePullRequest || repository == null) {
      throw const AgentDeliveryRuntimeException(
        '먼저 GitHub remote에 Agent 브랜치를 push해 주세요.',
      );
    }
    final created = await _run(
      entry: entry,
      host: host,
      executable: 'gh',
      arguments: [
        'pr',
        'create',
        '--repo',
        repository,
        '--base',
        entry.baseRef,
        '--head',
        entry.branchName,
        '--title',
        title,
        '--body',
        body,
      ],
      directory: entry.worktreePath,
      timeout: const Duration(minutes: 2),
    );
    _requireSuccess(
      created,
      'Pull Request를 만들지 못했습니다. gh 로그인과 저장소 권한을 확인해 주세요.',
    );
    final url = _lastUri(created.stdout) ?? current.compareUrl;
    return AgentDeliveryResult(
      summary: 'Pull Request를 만들었습니다.',
      detail: '${entry.branchName} → ${entry.baseRef}',
      url: url,
    );
  }

  Future<String> _revParse(
    AgentWorktreeRecord entry,
    Host host,
    String ref,
  ) async {
    final result = await _git(
      entry: entry,
      host: host,
      arguments: ['rev-parse', ref],
      directory: entry.repositoryRoot,
    );
    _requireSuccess(result, '$ref commit을 확인하지 못했습니다.');
    return result.stdout.trim();
  }

  Future<({String? name, String? url, bool branchExists, String? slug})>
  _remoteDetails(AgentWorktreeRecord entry, Host host) async {
    final remotes = await _git(
      entry: entry,
      host: host,
      arguments: const ['remote'],
      directory: entry.repositoryRoot,
    );
    if (remotes.exitCode != 0) {
      return (name: null, url: null, branchExists: false, slug: null);
    }
    final names = const LineSplitter()
        .convert(remotes.stdout)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return (name: null, url: null, branchExists: false, slug: null);
    }
    final name = names.contains('origin') ? 'origin' : names.first;
    final urlResult = await _git(
      entry: entry,
      host: host,
      arguments: ['remote', 'get-url', name],
      directory: entry.repositoryRoot,
    );
    final url = urlResult.exitCode == 0 ? urlResult.stdout.trim() : null;
    final branch = await _git(
      entry: entry,
      host: host,
      arguments: [
        'show-ref',
        '--verify',
        '--quiet',
        'refs/remotes/$name/${entry.branchName}',
      ],
      directory: entry.repositoryRoot,
    );
    return (
      name: name,
      url: url?.isEmpty == true ? null : url,
      branchExists: branch.exitCode == 0,
      slug: parseAgentGitHubRepository(url),
    );
  }

  Future<Uri?> _existingPullRequest({
    required AgentWorktreeRecord entry,
    required Host host,
    required String repository,
  }) async {
    try {
      final result = await _run(
        entry: entry,
        host: host,
        executable: 'gh',
        arguments: [
          'pr',
          'view',
          entry.branchName,
          '--repo',
          repository,
          '--json',
          'url',
          '--jq',
          '.url',
        ],
        directory: entry.worktreePath,
        timeout: const Duration(seconds: 20),
      );
      return result.exitCode == 0 ? _lastUri(result.stdout) : null;
    } catch (_) {
      return null;
    }
  }

  Future<AgentDeliveryProcessResult> _git({
    required AgentWorktreeRecord entry,
    required Host host,
    required List<String> arguments,
    required String directory,
    Duration timeout = const Duration(seconds: 45),
  }) => _run(
    entry: entry,
    host: host,
    executable: 'git',
    arguments: arguments,
    directory: directory,
    timeout: timeout,
  );

  Future<AgentDeliveryProcessResult> _run({
    required AgentWorktreeRecord entry,
    required Host host,
    required String executable,
    required List<String> arguments,
    required String? directory,
    required Duration timeout,
  }) async {
    if (!host.isLocalShell) {
      return _remoteExecutor(
        host: host,
        preferredSessionId: entry.sessionId,
        executable: executable,
        arguments: arguments,
        workingDirectory: directory,
        timeout: timeout,
      );
    }
    ProcessResult result;
    if (Platform.isWindows && host.localShellType == LocalShellType.wsl) {
      final command = [
        executable,
        for (final argument in arguments) _quotePosix(argument),
      ].join(' ');
      result = await Process.run('wsl.exe', [
        '--',
        'sh',
        '-lc',
        'cd ${_quotePosix(directory!)} && $command',
      ], runInShell: false).timeout(timeout);
    } else {
      result = await Process.run(
        executable,
        arguments,
        workingDirectory: directory,
        runInShell: false,
      ).timeout(timeout);
    }
    return AgentDeliveryProcessResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  void _requireSuccess(AgentDeliveryProcessResult result, String fallback) {
    if (result.exitCode == 0) return;
    final detail = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    throw AgentDeliveryRuntimeException(
      detail.isEmpty ? fallback : '$fallback $detail',
    );
  }
}

List<AgentDeliveryCommit> _parseCommits(String output) {
  final commits = <AgentDeliveryCommit>[];
  for (final record in output.split('\u001e')) {
    final fields = record.trim().split('\u0000');
    if (fields.length < 5 || fields[0].isEmpty) continue;
    commits.add(
      AgentDeliveryCommit(
        sha: fields[0],
        shortSha: fields[1],
        subject: fields[2],
        author: fields[3],
        authoredAt: DateTime.tryParse(fields[4]),
      ),
    );
  }
  return commits;
}

String _shortSha(String sha) => sha.length <= 10 ? sha : sha.substring(0, 10);

String _mergeBlockedMessage(AgentDeliveryMergeReadiness readiness) =>
    switch (readiness) {
      AgentDeliveryMergeReadiness.ready => '',
      AgentDeliveryMergeReadiness.alreadyMerged => '기준 브랜치에 이미 병합되어 있습니다.',
      AgentDeliveryMergeReadiness.worktreeDirty => '커밋하지 않은 변경을 먼저 처리해 주세요.',
      AgentDeliveryMergeReadiness.baseNotCheckedOut =>
        '저장소 루트에서 기준 브랜치를 checkout해 주세요.',
      AgentDeliveryMergeReadiness.baseDirty => '기준 작업 트리의 변경을 먼저 처리해 주세요.',
      AgentDeliveryMergeReadiness.diverged =>
        '기준 브랜치와 갈라졌습니다. Agent 브랜치에서 기준 브랜치를 먼저 반영해 주세요.',
    };

String? parseAgentGitHubRepository(String? remoteUrl) {
  final value = remoteUrl?.trim();
  if (value == null || value.isEmpty) return null;
  String? host;
  String? path;
  final scp = RegExp(r'^[^@]+@([^:]+):(.+)$').firstMatch(value);
  if (scp != null) {
    host = scp.group(1);
    path = scp.group(2);
  } else {
    final uri = Uri.tryParse(value);
    host = uri?.host;
    path = uri?.path.replaceFirst(RegExp(r'^/'), '');
  }
  if (host == null || path == null || !host.toLowerCase().contains('github')) {
    return null;
  }
  final cleanPath = path.replaceFirst(RegExp(r'\.git$'), '');
  final parts = cleanPath.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return null;
  final ownerRepo = '${parts[parts.length - 2]}/${parts.last}';
  return host.toLowerCase() == 'github.com' ? ownerRepo : '$host/$ownerRepo';
}

Uri? buildAgentGitHubCompareUrl(
  String? remoteUrl,
  String baseRef,
  String branchName,
) {
  final slug = parseAgentGitHubRepository(remoteUrl);
  if (slug == null) return null;
  final parts = slug.split('/');
  final host = parts.length == 2 ? 'github.com' : parts.first;
  final owner = parts[parts.length - 2];
  final repository = parts.last;
  return Uri(
    scheme: 'https',
    host: host,
    pathSegments: [owner, repository, 'compare', '$baseRef...$branchName'],
    queryParameters: const {'expand': '1'},
  );
}

extension on ({String? name, String? url, bool branchExists, String? slug}) {
  Uri? compareUrl(String baseRef, String branchName) =>
      buildAgentGitHubCompareUrl(url, baseRef, branchName);
}

Uri? _lastUri(String output) {
  for (final token in output.trim().split(RegExp(r'\s+')).reversed) {
    final uri = Uri.tryParse(token);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return uri;
  }
  return null;
}

String _quotePosix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
