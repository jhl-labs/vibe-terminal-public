enum AgentCli { claude, codex, opencode }

extension AgentCliPresentation on AgentCli {
  String get label => switch (this) {
    AgentCli.claude => 'Claude',
    AgentCli.codex => 'Codex',
    AgentCli.opencode => 'OpenCode',
  };

  String get command => switch (this) {
    AgentCli.claude => 'claude',
    AgentCli.codex => 'codex',
    AgentCli.opencode => 'opencode',
  };
}

enum AgentShellFlavor { posix, powershell, cmd }

class AgentLaunchSpec {
  AgentLaunchSpec({
    required this.cli,
    this.isolatedWorktree = false,
    this.branchName,
    this.arguments = const [],
    this.executable,
    this.initialGoal,
    this.repositoryDirectory,
    String? model,
  }) : model = model?.trim().isEmpty ?? true ? null : model!.trim();

  final AgentCli cli;
  final bool isolatedWorktree;
  final String? branchName;
  final List<String> arguments;
  final String? executable;
  final String? initialGoal;

  /// worktree 격리 시 저장소를 찾을 폴더. 사용자가 실행 대화상자에서 확인·수정한
  /// 값이며, null이면 세션이 추적한 현재 작업 디렉터리를 쓴다.
  final String? repositoryDirectory;

  /// CLI에 전달할 모델 이름(예: opus, gpt-5). 비워두면 CLI 기본값을 쓴다.
  final String? model;

  AgentWorkspaceContext toWorkspaceContext() => AgentWorkspaceContext(
    cli: cli,
    isolatedWorktree: isolatedWorktree,
    branchName: isolatedWorktree ? branchName?.trim() : null,
    arguments: List.unmodifiable(arguments),
    executable: executable,
    initialGoal: initialGoal,
    model: model,
  );
}

class AgentWorkspaceContext {
  const AgentWorkspaceContext({
    required this.cli,
    required this.isolatedWorktree,
    this.branchName,
    this.arguments = const [],
    this.executable,
    this.initialGoal,
    this.workspaceId,
    this.repositoryRoot,
    this.worktreePath,
    this.baseRef,
    this.model,
  });

  final AgentCli cli;
  final bool isolatedWorktree;
  final String? branchName;
  final List<String> arguments;
  final String? executable;
  final String? initialGoal;
  final String? workspaceId;
  final String? repositoryRoot;
  final String? worktreePath;
  final String? baseRef;

  /// CLI에 전달할 모델 이름. null이면 CLI 기본값을 쓴다.
  final String? model;

  Map<String, Object?> toJson() => {
    'cli': cli.name,
    if (executable != null) 'executable': executable,
    if (initialGoal != null) 'initialGoal': initialGoal,
    'isolatedWorktree': isolatedWorktree,
    if (branchName != null && branchName!.isNotEmpty) 'branchName': branchName,
    if (arguments.isNotEmpty) 'arguments': arguments,
    if (workspaceId != null && workspaceId!.isNotEmpty)
      'workspaceId': workspaceId,
    if (repositoryRoot != null && repositoryRoot!.isNotEmpty)
      'repositoryRoot': repositoryRoot,
    if (worktreePath != null && worktreePath!.isNotEmpty)
      'worktreePath': worktreePath,
    if (baseRef != null && baseRef!.isNotEmpty) 'baseRef': baseRef,
    if (model != null && model!.isNotEmpty) 'model': model,
  };

  static AgentWorkspaceContext? fromJson(Object? value) {
    if (value is! Map) return null;
    final cliName = value['cli'];
    AgentCli? cli;
    for (final candidate in AgentCli.values) {
      if (candidate.name == cliName) cli = candidate;
    }
    if (cli == null) return null;
    final rawArguments = value['arguments'];
    return AgentWorkspaceContext(
      cli: cli,
      executable: _optionalString(value['executable']),
      initialGoal: _optionalString(value['initialGoal']),
      isolatedWorktree: value['isolatedWorktree'] == true,
      branchName: value['branchName'] is String
          ? (value['branchName'] as String).trim()
          : null,
      arguments: rawArguments is List
          ? [
              for (final item in rawArguments)
                if (item is String) item,
            ]
          : const [],
      workspaceId: _optionalString(value['workspaceId']),
      repositoryRoot: _optionalString(value['repositoryRoot']),
      worktreePath: _optionalString(value['worktreePath']),
      baseRef: _optionalString(value['baseRef']),
      model: _optionalString(value['model']),
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

/// Agent 실행 의도를 각 셸에 맞는 명령으로 변환한다.
///
/// UI와 세션 수명 관리는 몰라야 하며, 사용자가 명시적으로 worktree 격리를
/// 선택한 경우에만 Git 브랜치와 디렉터리를 생성한다.
class AgentLaunchCommandBuilder {
  const AgentLaunchCommandBuilder();

  String build(AgentLaunchSpec spec, AgentShellFlavor shell) {
    _validateArguments(spec.arguments, shell);
    if (!spec.isolatedWorktree) return _agentInvocation(spec, shell);

    final branch = spec.branchName?.trim() ?? '';
    final validationError = validateBranchName(branch);
    if (validationError != null) {
      throw ArgumentError.value(branch, 'branchName', validationError);
    }

    final directoryName = branch.replaceAll('/', '-');
    return switch (shell) {
      AgentShellFlavor.posix => _buildPosix(spec, branch, directoryName),
      AgentShellFlavor.powershell => _buildPowerShell(
        spec,
        branch,
        directoryName,
      ),
      AgentShellFlavor.cmd => _buildCmd(spec, branch, directoryName),
    };
  }

  String reviewCommand(AgentShellFlavor shell) => switch (shell) {
    AgentShellFlavor.powershell =>
      'git status --short --branch; git diff --stat; git diff --color=always',
    AgentShellFlavor.posix || AgentShellFlavor.cmd =>
      'git status --short --branch && git diff --stat && '
          'git diff --color=always',
  };

  String invocation(AgentLaunchSpec spec, AgentShellFlavor shell) {
    _validateArguments(spec.arguments, shell);
    return _agentInvocation(spec, shell);
  }

  static String? validateBranchName(String value) {
    final branch = value.trim();
    if (branch.isEmpty) return '브랜치 이름을 입력하세요.';
    if (branch.length > 100) return '브랜치 이름은 100자 이하여야 합니다.';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(branch)) {
      return '영문, 숫자, 점, 밑줄, 하이픈, 슬래시만 사용할 수 있습니다.';
    }
    if (branch.contains('..') ||
        branch.contains('//') ||
        branch.endsWith('/') ||
        branch.endsWith('.') ||
        branch
            .split('/')
            .any(
              (part) =>
                  part.isEmpty ||
                  part.startsWith('.') ||
                  part.endsWith('.lock'),
            )) {
      return 'Git 브랜치로 사용할 수 없는 이름입니다.';
    }
    return null;
  }

  String _buildPosix(
    AgentLaunchSpec spec,
    String branch,
    String directoryName,
  ) {
    final quotedBranch = _quotePosix(branch);
    final quotedDirectory = _quotePosix(directoryName);
    return 'vibe_repo="\$(git rev-parse --show-toplevel)" && '
        'vibe_worktrees="\$(dirname "\$vibe_repo")/.vibe-worktrees" && '
        'mkdir -p "\$vibe_worktrees" && '
        'vibe_worktree="\$vibe_worktrees"/$quotedDirectory && '
        'git -C "\$vibe_repo" worktree add -b $quotedBranch '
        '"\$vibe_worktree" HEAD && '
        'cd "\$vibe_worktree" && ${_agentInvocation(spec, AgentShellFlavor.posix)}';
  }

  String _buildPowerShell(
    AgentLaunchSpec spec,
    String branch,
    String directoryName,
  ) {
    final quotedBranch = _quotePowerShell(branch);
    final quotedDirectory = _quotePowerShell(directoryName);
    return r'$vibeRepo = (git rev-parse --show-toplevel); '
        r'if ($LASTEXITCODE -ne 0) { throw "Git 저장소가 아닙니다." }; '
        r'$vibeWorktrees = Join-Path (Split-Path $vibeRepo -Parent) '
        "'.vibe-worktrees'; "
        r'New-Item -ItemType Directory -Force $vibeWorktrees | Out-Null; '
        r'$vibeWorktree = Join-Path $vibeWorktrees '
        '$quotedDirectory; '
        r'git -C $vibeRepo worktree add -b '
        '$quotedBranch '
        r'$vibeWorktree HEAD; '
        r'if ($LASTEXITCODE -eq 0) { Set-Location $vibeWorktree; '
        '${_agentInvocation(spec, AgentShellFlavor.powershell)} }';
  }

  String _buildCmd(AgentLaunchSpec spec, String branch, String directoryName) {
    return 'for /f "delims=" %R in (\'git rev-parse --show-toplevel\') do '
        '(if not exist "%R\\..\\.vibe-worktrees" '
        'mkdir "%R\\..\\.vibe-worktrees" && '
        'git -C "%R" worktree add -b "$branch" '
        '"%R\\..\\.vibe-worktrees\\$directoryName" HEAD && '
        'cd /d "%R\\..\\.vibe-worktrees\\$directoryName" && '
        '${_agentInvocation(spec, AgentShellFlavor.cmd)})';
  }

  /// CLI별 모델 지정 인자. 현재는 claude/codex/opencode 모두 동일하게
  /// `--model <value>` 형식을 쓴다.
  static List<String> modelArgumentsFor(AgentCli cli, String model) => [
    '--model',
    model,
  ];

  String _agentInvocation(AgentLaunchSpec spec, AgentShellFlavor shell) {
    final arguments = [
      ...spec.arguments,
      if (spec.model != null) ...modelArgumentsFor(spec.cli, spec.model!),
      if (spec.initialGoal?.isNotEmpty == true) ...[
        if (spec.cli == AgentCli.opencode)
          '--prompt=${spec.initialGoal!}'
        else ...[
          '--',
          spec.initialGoal!,
        ],
      ],
    ];
    _validateArguments(arguments, shell);
    final executable = spec.executable?.trim();
    if (executable != null) _validateArguments([executable], shell);
    final command = executable == null
        ? spec.cli.command
        : switch (shell) {
            AgentShellFlavor.posix => _quotePosix(executable),
            AgentShellFlavor.powershell => '& ${_quotePowerShell(executable)}',
            AgentShellFlavor.cmd => _quoteCmd(executable),
          };
    final quotedArguments = [
      for (final argument in arguments)
        switch (shell) {
          AgentShellFlavor.posix => _quotePosix(argument),
          AgentShellFlavor.powershell => _quotePowerShell(argument),
          AgentShellFlavor.cmd => _quoteCmd(argument),
        },
    ];
    return [command, ...quotedArguments].join(' ');
  }

  void _validateArguments(List<String> arguments, AgentShellFlavor shell) {
    for (final argument in arguments) {
      if (argument.isEmpty ||
          argument.contains('\n') ||
          argument.contains('\r') ||
          argument.contains('\u0000')) {
        throw ArgumentError.value(argument, 'arguments', 'CLI 인자가 올바르지 않습니다.');
      }
      if (shell == AgentShellFlavor.cmd &&
          (argument.contains('"') ||
              argument.contains('%') ||
              argument.contains('!'))) {
        throw ArgumentError.value(
          argument,
          'arguments',
          'Command Prompt 인자에는 큰따옴표, %, !를 사용할 수 없습니다.',
        );
      }
    }
  }

  String _quotePosix(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  String _quotePowerShell(String value) => "'${value.replaceAll("'", "''")}'";

  String _quoteCmd(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:=@+,\-]+$').hasMatch(value)) return value;
    return '"$value"';
  }
}
