import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/models/host.dart';
import '../local/managed_process.dart';
import 'agent_conflict.dart';
import 'agent_integration.dart';
import 'agent_integration_script.dart';
import 'agent_launcher.dart';
import 'agent_source_control.dart';
import 'agent_workspace_test.dart';
import 'agent_workspace_files.dart';
import 'agent_workspace_run.dart';
import 'agent_worktree.dart';
import 'reviewed_git_transaction.dart';

class AgentGitResult {
  const AgentGitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef RemoteAgentGitExecutor =
    Future<AgentGitResult> Function({
      required Host host,
      required String? preferredSessionId,
      required List<String> arguments,
      required String? workingDirectory,
    });

class AgentWorktreeLocation {
  const AgentWorktreeLocation({
    required this.repositoryRoot,
    required this.worktreePath,
    required this.baseRef,
  });

  final String repositoryRoot;
  final String worktreePath;
  final String baseRef;
}

class AgentWorktreeInspection {
  const AgentWorktreeInspection({required this.exists, required this.gitState});

  const AgentWorktreeInspection.missing()
    : exists = false,
      gitState = AgentWorktreeGitState.unknown;

  final bool exists;
  final AgentWorktreeGitState gitState;
}

class AgentWorktreeRuntimeException implements Exception {
  const AgentWorktreeRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Git process 실행과 worktree 상태 판정만 담당한다.
///
/// 세션/Registry/UI를 알지 않으며 원격 실행은 주입된 executor에 위임한다.
class AgentWorktreeRuntime {
  const AgentWorktreeRuntime(this._remoteExecutor);

  final RemoteAgentGitExecutor _remoteExecutor;

  static const int _maximumDiffCharacters = 400000;

  Future<Object?> workspaceFiles({
    required AgentWorktreeRecord entry,
    required Host host,
    required Map<String, Object?> request,
  }) async {
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      workingDirectory: entry.worktreePath,
      arguments: gitTransaction(r'exec node -e "$1" "$2"', [
        agentWorkspaceFilesScript,
        jsonEncode(request),
      ]),
    );
    if (result.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        '파일 작업에 실패했습니다. 호스트에 Node.js가 필요합니다. ${result.stderr.trim()}',
      );
    }
    return jsonDecode(result.stdout);
  }

  Future<AgentIntegrationPlan> configureIntegration({
    required AgentWorktreeRecord entry,
    required Host host,
    bool remove = false,
    String? expectedRevision,
  }) async {
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      workingDirectory: entry.worktreePath,
      arguments: gitTransaction(r'exec node -e "$1" "$2"', [
        agentIntegrationScript,
        jsonEncode({
          'provider': entry.cli.name,
          'emitter': agentHookEmitter(entry.cli.name),
          'remove': remove,
          'expected': ?expectedRevision,
        }),
      ]),
    );
    if (result.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        'CLI 연동 설정을 처리하지 못했습니다. 실행 호스트에 Node.js가 필요합니다. ${result.stderr.trim()}',
      );
    }
    return AgentIntegrationPlan.fromJson(
      jsonDecode(result.stdout) as Map<String, dynamic>,
      remove: remove,
    );
  }

  Future<void> abortMerge({
    required AgentWorktreeRecord entry,
    required Host host,
    required String expectedFingerprint,
  }) async {
    final current = await workspaceTestContext(entry: entry, host: host);
    if (current.workspaceFingerprint != expectedFingerprint) {
      throw const AgentWorktreeRuntimeException(
        '검토 이후 작업공간이 변경되었습니다. 다시 확인하세요.',
      );
    }
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['merge', '--abort'],
      workingDirectory: entry.worktreePath,
    );
    if (result.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(result, '진행 중인 병합을 취소하지 못했습니다.'),
      );
    }
  }

  Future<AgentWorkspaceRunContext> workspaceRunContext({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final content = await workspaceTestContext(entry: entry, host: host);
    final allFiles = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const [
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '-z',
      ],
      workingDirectory: entry.worktreePath,
    );
    if (allFiles.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(allFiles, '실행 명령을 제안할 프로젝트 파일을 읽지 못했습니다.'),
      );
    }
    final paths = allFiles.stdout
        .split('\u0000')
        .where((path) => path.isNotEmpty);
    return AgentWorkspaceRunContext(
      headSha: content.headSha,
      workspaceFingerprint: content.workspaceFingerprint,
      suggestedCommand: suggestAgentWorkspaceRunCommand(
        paths,
        nativeWindows:
            host.isLocalShell &&
            Platform.isWindows &&
            host.localShellType != LocalShellType.wsl,
      ),
    );
  }

  Future<AgentWorkspaceTestContext> workspaceTestContext({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final snapshot = await sourceControlSnapshot(
      entry: entry,
      host: host,
      captureReview: true,
    );
    if (snapshot.branchName != entry.branchName) {
      throw AgentWorktreeRuntimeException(
        'worktree의 현재 브랜치(${snapshot.branchName})가 기록된 브랜치'
        '(${entry.branchName})와 다릅니다. 터미널에서 브랜치를 확인해 주세요.',
      );
    }
    final allFiles = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const [
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
        '-z',
      ],
      workingDirectory: entry.worktreePath,
    );
    if (allFiles.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(allFiles, '테스트 대상 파일 목록을 읽지 못했습니다.'),
      );
    }
    final deletedFiles = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['ls-files', '--deleted', '-z'],
      workingDirectory: entry.worktreePath,
    );
    if (deletedFiles.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(deletedFiles, '삭제된 테스트 대상 파일을 확인하지 못했습니다.'),
      );
    }
    final deleted = deletedFiles.stdout
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .toSet();
    final hashPaths =
        allFiles.stdout
            .split('\u0000')
            .where((path) => path.isNotEmpty && !deleted.contains(path))
            .toSet()
            .toList()
          ..sort();
    final contentHashes = StringBuffer();
    for (var offset = 0; offset < hashPaths.length; offset += 100) {
      final candidateEnd = offset + 100;
      final end = candidateEnd < hashPaths.length
          ? candidateEnd
          : hashPaths.length;
      await _appendWorkspaceFileHashes(
        output: contentHashes,
        paths: hashPaths.sublist(offset, end),
        host: host,
        entry: entry,
      );
    }
    final fingerprint = sha256
        .convert(
          utf8.encode(
            '${snapshot.reviewedTreeSha ?? "conflicted"}\u0000$contentHashes',
          ),
        )
        .toString();
    return AgentWorkspaceTestContext(
      headSha: snapshot.headSha,
      workspaceFingerprint: fingerprint,
      suggestedCommand: suggestAgentWorkspaceTestCommand(
        hashPaths,
        nativeWindows:
            host.isLocalShell &&
            Platform.isWindows &&
            host.localShellType != LocalShellType.wsl,
      ),
    );
  }

  Future<void> _appendWorkspaceFileHashes({
    required StringBuffer output,
    required List<String> paths,
    required Host host,
    required AgentWorktreeRecord entry,
  }) async {
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: ['hash-object', '--no-filters', '--', ...paths],
      workingDirectory: entry.worktreePath,
    );
    final hashes = result.stdout
        .split('\n')
        .map((hash) => hash.trim())
        .where((hash) => hash.isNotEmpty)
        .toList();
    if (result.exitCode == 0 && hashes.length == paths.length) {
      for (var index = 0; index < paths.length; index++) {
        output
          ..write(paths[index])
          ..write('\u0000')
          ..write(hashes[index])
          ..write('\u0000');
      }
      return;
    }

    // submodule·동시 삭제 등 한 경로가 묶음 hash를 실패시켜도 나머지 파일의
    // fingerprint를 잃지 않도록 해당 묶음만 개별 확인한다.
    for (final path in paths) {
      final single = await _runGit(
        host: host,
        preferredSessionId: entry.sessionId,
        arguments: ['hash-object', '--no-filters', '--', path],
        workingDirectory: entry.worktreePath,
      );
      output
        ..write(path)
        ..write('\u0000')
        ..write(
          single.exitCode == 0
              ? single.stdout.trim()
              : '<unreadable:${single.stderr.trim()}>',
        )
        ..write('\u0000');
    }
  }

  Future<AgentSourceControlSnapshot> sourceControlSnapshot({
    required AgentWorktreeRecord entry,
    required Host host,
    bool captureReview = false,
  }) async {
    final status = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const [
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
      ],
      workingDirectory: entry.worktreePath,
    );
    if (status.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(status, '변경 파일을 읽지 못했습니다.'),
      );
    }
    final branch = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      workingDirectory: entry.worktreePath,
    );
    if (branch.exitCode != 0 || branch.stdout.trim().isEmpty) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(branch, '현재 브랜치를 확인하지 못했습니다. detached HEAD일 수 있습니다.'),
      );
    }
    final head = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['rev-parse', '--short=10', 'HEAD'],
      workingDirectory: entry.worktreePath,
    );
    if (head.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(head, '현재 commit을 확인하지 못했습니다.'),
      );
    }
    String? reviewedTree;
    var headSha = head.stdout.trim();
    final files = parseAgentGitStatus(status.stdout);
    if (captureReview && !files.any((file) => file.isConflicted)) {
      final captured = await _runGit(
        host: host,
        preferredSessionId: entry.sessionId,
        arguments: gitTransaction(captureReviewedTreeScript, const []),
        workingDirectory: entry.worktreePath,
      );
      final ids = captured.stdout.trim().split('\n');
      if (captured.exitCode != 0 ||
          ids.length != 2 ||
          ids.any((id) => !RegExp(r'^[a-f0-9]{40,64}$').hasMatch(id))) {
        throw AgentWorktreeRuntimeException(
          _failureMessage(captured, '검토할 내용을 고정하지 못했습니다.'),
        );
      }
      headSha = ids[0];
      reviewedTree = ids[1];
    }
    return AgentSourceControlSnapshot(
      branchName: branch.stdout.trim(),
      headSha: headSha,
      files: files,
      reviewedTreeSha: reviewedTree,
    );
  }

  /// index의 unmerged stage(1=base, 2=ours, 3=theirs)를 구조화해서 읽는다.
  /// 파일이나 index를 변경하지 않는 읽기 전용 진단이다.
  Future<List<AgentConflictFile>> unresolvedConflicts({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['ls-files', '--unmerged', '-z'],
      workingDirectory: entry.worktreePath,
    );
    if (result.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(result, '충돌 파일을 읽지 못했습니다.'),
      );
    }
    final grouped = <String, List<({int stage, String sha})>>{};
    for (final record in result.stdout.split('\u0000')) {
      if (record.isEmpty) continue;
      final tab = record.indexOf('\t');
      if (tab < 0) continue;
      final fields = record.substring(0, tab).split(RegExp(r'\s+'));
      if (fields.length < 3) continue;
      final stage = int.tryParse(fields[2]);
      if (stage == null || stage < 1 || stage > 3) continue;
      final path = record.substring(tab + 1);
      grouped.putIfAbsent(path, () => []).add((stage: stage, sha: fields[1]));
    }

    final files = <AgentConflictFile>[];
    for (final entryByPath in grouped.entries) {
      final stages = <AgentConflictStage>[];
      for (final indexed in entryByPath.value) {
        final contentResult = await _runGit(
          host: host,
          preferredSessionId: entry.sessionId,
          arguments: ['show', ':${indexed.stage}:${entryByPath.key}'],
          workingDirectory: entry.worktreePath,
        );
        if (contentResult.exitCode != 0) continue;
        final raw = contentResult.stdout;
        final binary = raw.contains('\u0000');
        const maximumCharacters = 120000;
        final truncated = raw.length > maximumCharacters;
        stages.add(
          AgentConflictStage(
            kind: AgentConflictStageKind.values[indexed.stage - 1],
            blobSha: indexed.sha,
            content: binary
                ? null
                : truncated
                ? raw.substring(0, maximumCharacters)
                : raw,
            truncated: truncated,
            binary: binary,
          ),
        );
      }
      stages.sort((left, right) => left.kind.index.compareTo(right.kind.index));
      files.add(AgentConflictFile(path: entryByPath.key, stages: stages));
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<AgentFileDiff> fileDiff({
    required AgentWorktreeRecord entry,
    required Host host,
    required AgentFileChange change,
    AgentSourceControlSnapshot? reviewedSnapshot,
  }) async {
    final paths = [?change.originalPath, change.path];
    final tree = reviewedSnapshot?.reviewedTreeSha;
    final result = tree != null
        ? await _runGit(
            host: host,
            preferredSessionId: entry.sessionId,
            arguments: [
              'diff',
              '--no-ext-diff',
              '--no-color',
              '--unified=3',
              reviewedSnapshot!.headSha,
              tree,
              '--',
              ...paths,
            ],
            workingDirectory: entry.worktreePath,
          )
        : change.kind == AgentFileChangeKind.untracked
        ? await _runGit(
            host: host,
            preferredSessionId: entry.sessionId,
            arguments: [
              'diff',
              '--no-index',
              '--no-ext-diff',
              '--no-color',
              '--unified=3',
              '--',
              _nullDevice(host),
              change.path,
            ],
            workingDirectory: entry.worktreePath,
          )
        : await _runGit(
            host: host,
            preferredSessionId: entry.sessionId,
            arguments: [
              'diff',
              '--no-ext-diff',
              '--no-color',
              '--unified=3',
              'HEAD',
              '--',
              ...paths,
            ],
            workingDirectory: entry.worktreePath,
          );
    final expectedDifference =
        change.kind == AgentFileChangeKind.untracked && result.exitCode == 1;
    if (result.exitCode != 0 && !expectedDifference) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(result, '${change.path} diff를 읽지 못했습니다.'),
      );
    }
    final content = result.stdout.isEmpty
        ? '(표시할 텍스트 diff가 없습니다. 바이너리 파일일 수 있습니다.)'
        : result.stdout;
    final truncated = content.length > _maximumDiffCharacters;
    return AgentFileDiff(
      path: change.path,
      content: truncated
          ? content.substring(0, _maximumDiffCharacters)
          : content,
      truncated: truncated,
    );
  }

  /// 선택된 파일만 stage한 뒤 commit한다. 이미 stage된 선택 밖 파일이 있으면
  /// 예상치 못한 변경이 함께 들어가지 않도록 commit 전에 중단한다.
  Future<AgentCommitResult> commitSelected({
    required AgentWorktreeRecord entry,
    required Host host,
    required Set<String> selectedPaths,
    required String message,
    AgentSourceControlSnapshot? reviewedSnapshot,
  }) async {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      throw const AgentWorktreeRuntimeException('커밋 메시지를 입력해 주세요.');
    }
    if (normalizedMessage.contains('\u0000')) {
      throw const AgentWorktreeRuntimeException('커밋 메시지에 NUL 문자를 사용할 수 없습니다.');
    }
    if (selectedPaths.isEmpty) {
      throw const AgentWorktreeRuntimeException('커밋할 파일을 선택해 주세요.');
    }

    final snapshot = await sourceControlSnapshot(
      entry: entry,
      host: host,
      captureReview: true,
    );
    final reviewed = reviewedSnapshot ?? snapshot;
    if (reviewed.reviewedTreeSha == null ||
        snapshot.reviewedTreeSha != reviewed.reviewedTreeSha ||
        snapshot.headSha != reviewed.headSha ||
        snapshot.branchName != reviewed.branchName) {
      throw const AgentWorktreeRuntimeException(
        '검토 이후 작업공간이 변경되었습니다. 새로고침하고 다시 검토하세요.',
      );
    }
    if (snapshot.branchName != entry.branchName) {
      throw AgentWorktreeRuntimeException(
        'worktree의 현재 브랜치(${snapshot.branchName})가 기록된 브랜치'
        '(${entry.branchName})와 다릅니다. 터미널에서 브랜치를 확인해 주세요.',
      );
    }
    final byPath = {for (final change in snapshot.files) change.path: change};
    final selected = <AgentFileChange>[];
    for (final path in selectedPaths) {
      final change = byPath[path];
      if (change == null) {
        throw AgentWorktreeRuntimeException('$path 변경 상태가 달라졌습니다. 새로고침해 주세요.');
      }
      if (change.isConflicted) {
        throw AgentWorktreeRuntimeException('$path 충돌을 먼저 해결해 주세요.');
      }
      selected.add(change);
    }
    final gitPaths = <String>{
      for (final change in selected) ...change.gitPaths,
    };
    final indexHash = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: gitTransaction(
        r'git hash-object -- "$(git rev-parse --path-format=absolute --git-path index)"',
        const [],
      ),
      workingDirectory: entry.worktreePath,
    );
    if (indexHash.exitCode != 0) {
      throw const AgentWorktreeRuntimeException('Git index를 확인하지 못했습니다.');
    }
    await _ensureNoStagedPathsOutside(
      entry: entry,
      host: host,
      allowedPaths: gitPaths,
    );

    final committed = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: gitTransaction(commitReviewedTreeScript, [
        reviewed.headSha,
        reviewed.reviewedTreeSha!,
        'refs/heads/${entry.branchName}',
        normalizedMessage,
        indexHash.stdout.trim(),
        ...gitPaths,
      ]),
      workingDirectory: entry.worktreePath,
    );
    final sha = committed.stdout.trim().split('\n').last;
    if (committed.exitCode != 0 ||
        !RegExp(r'^[a-f0-9]{40,64}$').hasMatch(sha)) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(committed, '검토한 내용을 커밋하지 못했습니다.'),
      );
    }
    return AgentCommitResult(
      shortSha: sha.substring(0, 10),
      subject: normalizedMessage.split('\n').first,
    );
  }

  Future<void> _ensureNoStagedPathsOutside({
    required AgentWorktreeRecord entry,
    required Host host,
    required Set<String> allowedPaths,
  }) async {
    final result = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const [
        'diff',
        '--cached',
        '--name-only',
        '-z',
        '--diff-filter=ACDMRTUXB',
      ],
      workingDirectory: entry.worktreePath,
    );
    if (result.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(result, 'stage 상태를 읽지 못했습니다.'),
      );
    }
    final outside = result.stdout
        .split('\u0000')
        .where((path) => path.isNotEmpty && !allowedPaths.contains(path))
        .toList();
    if (outside.isNotEmpty) {
      final sample = outside.take(3).join(', ');
      throw AgentWorktreeRuntimeException(
        '선택 밖에 이미 stage된 파일이 있습니다: $sample. '
        '해당 파일도 선택하거나 터미널에서 unstage해 주세요.',
      );
    }
  }

  Future<AgentWorktreeLocation> resolveLocation({
    required Host host,
    required String? preferredSessionId,
    required String? workingDirectory,
    required AgentLaunchSpec spec,
  }) async {
    final rootResult = await _runGit(
      host: host,
      preferredSessionId: preferredSessionId,
      arguments: const ['rev-parse', '--show-toplevel'],
      workingDirectory: workingDirectory,
    );
    final repositoryRoot = rootResult.stdout.trim();
    if (rootResult.exitCode != 0 || repositoryRoot.isEmpty) {
      final where = workingDirectory?.trim();
      throw AgentWorktreeRuntimeException(
        _failureMessage(
          rootResult,
          where == null || where.isEmpty
              ? '현재 위치가 Git 저장소가 아닙니다. 실행 대화상자에서 저장소 폴더를 지정하세요.'
              : "'$where'은(는) Git 저장소가 아닙니다. 실행 대화상자에서 저장소 폴더를 확인하세요.",
        ),
      );
    }

    var baseResult = await _runGit(
      host: host,
      preferredSessionId: preferredSessionId,
      arguments: const ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      workingDirectory: repositoryRoot,
    );
    if (baseResult.exitCode != 0 || baseResult.stdout.trim().isEmpty) {
      baseResult = await _runGit(
        host: host,
        preferredSessionId: preferredSessionId,
        arguments: const ['rev-parse', 'HEAD'],
        workingDirectory: repositoryRoot,
      );
    }
    final baseRef = baseResult.stdout.trim();
    if (baseResult.exitCode != 0 || baseRef.isEmpty) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(baseResult, '기준 Git ref를 확인하지 못했습니다.'),
      );
    }

    final directoryName = spec.branchName!.trim().replaceAll('/', '-');
    final nativeWindows =
        host.isLocalShell &&
        Platform.isWindows &&
        host.localShellType != LocalShellType.wsl;
    final worktreePath = nativeWindows
        ? p.windows.join(
            p.windows.dirname(repositoryRoot),
            '.vibe-worktrees',
            directoryName,
          )
        : p.posix.join(
            p.posix.dirname(repositoryRoot),
            '.vibe-worktrees',
            directoryName,
          );
    return AgentWorktreeLocation(
      repositoryRoot: repositoryRoot,
      worktreePath: worktreePath,
      baseRef: baseRef,
    );
  }

  Future<AgentWorktreeInspection> inspect({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final exists = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['rev-parse', '--is-inside-work-tree'],
      workingDirectory: entry.worktreePath,
    );
    if (exists.exitCode != 0 || exists.stdout.trim() != 'true') {
      return const AgentWorktreeInspection.missing();
    }

    final status = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['status', '--porcelain=v1', '--untracked-files=normal'],
      workingDirectory: entry.worktreePath,
    );
    if (status.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(status, 'Git 상태를 읽지 못했습니다.'),
      );
    }
    if (status.stdout.trim().isNotEmpty) {
      return const AgentWorktreeInspection(
        exists: true,
        gitState: AgentWorktreeGitState.dirty,
      );
    }

    final merged = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: [
        'merge-base',
        '--is-ancestor',
        entry.branchName,
        entry.baseRef,
      ],
      workingDirectory: entry.repositoryRoot,
    );
    if (merged.exitCode != 0 && merged.exitCode != 1) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(merged, '브랜치 병합 여부를 확인하지 못했습니다.'),
      );
    }
    return AgentWorktreeInspection(
      exists: true,
      gitState: merged.exitCode == 0
          ? AgentWorktreeGitState.merged
          : AgentWorktreeGitState.cleanUnmerged,
    );
  }

  Future<void> remove({
    required AgentWorktreeRecord entry,
    required Host host,
  }) async {
    final removed = await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: ['worktree', 'remove', entry.worktreePath],
      workingDirectory: entry.repositoryRoot,
    );
    if (removed.exitCode != 0) {
      throw AgentWorktreeRuntimeException(
        _failureMessage(removed, 'worktree를 제거하지 못했습니다.'),
      );
    }
    await _runGit(
      host: host,
      preferredSessionId: entry.sessionId,
      arguments: const ['worktree', 'prune'],
      workingDirectory: entry.repositoryRoot,
    );
  }

  Future<AgentGitResult> _runGit({
    required Host host,
    required String? preferredSessionId,
    required List<String> arguments,
    required String? workingDirectory,
  }) async {
    if (!host.isLocalShell) {
      return _remoteExecutor(
        host: host,
        preferredSessionId: preferredSessionId,
        arguments: arguments,
        workingDirectory: workingDirectory,
      );
    }

    final directory = workingDirectory?.trim();
    ProcessResult result;
    if (Platform.isWindows && host.localShellType == LocalShellType.wsl) {
      final command = [
        'git',
        if (directory != null && directory.isNotEmpty) ...[
          '-C',
          _posixPathArgument(directory),
        ],
        for (final argument in arguments) _quotePosix(argument),
      ].join(' ');
      result = await runManagedCommand('wsl.exe', [
        '--',
        'sh',
        '-lc',
        managedPosixCommand(command),
      ]);
    } else {
      result = await runManagedCommand('git', [
        if (directory != null && directory.isNotEmpty) ...['-C', directory],
        ...arguments,
      ]);
    }
    return AgentGitResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  String _failureMessage(AgentGitResult result, String fallback) {
    final detail = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    return detail.isEmpty ? fallback : '$fallback $detail';
  }

  static String _posixPathArgument(String value) {
    if (value == '~') return '~';
    if (value.startsWith('~/')) return '~/${_quotePosix(value.substring(2))}';
    return _quotePosix(value);
  }

  static String _quotePosix(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static String _nullDevice(Host host) =>
      host.isLocalShell &&
          Platform.isWindows &&
          host.localShellType != LocalShellType.wsl
      ? 'NUL'
      : '/dev/null';
}
