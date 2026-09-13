enum AgentWorkspaceTestOutcome { passed, failed, timedOut, error }

class AgentWorkspaceTestContext {
  const AgentWorkspaceTestContext({
    required this.headSha,
    required this.workspaceFingerprint,
    required this.suggestedCommand,
  });

  final String headSha;
  final String workspaceFingerprint;
  final String? suggestedCommand;
}

class AgentWorkspaceTestResult {
  const AgentWorkspaceTestResult({
    required this.workspaceId,
    required this.command,
    required this.outcome,
    required this.exitCode,
    required this.output,
    required this.outputTruncated,
    required this.startedAt,
    required this.finishedAt,
    required this.headSha,
    required this.workspaceFingerprint,
  });

  final String workspaceId;
  final String command;
  final AgentWorkspaceTestOutcome outcome;
  final int? exitCode;
  final String output;
  final bool outputTruncated;
  final DateTime startedAt;
  final DateTime finishedAt;
  final String headSha;
  final String workspaceFingerprint;

  Duration get duration => finishedAt.difference(startedAt);
  bool get passed => outcome == AgentWorkspaceTestOutcome.passed;

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'command': command,
    'outcome': outcome.name,
    'exitCode': exitCode,
    'output': output,
    'outputTruncated': outputTruncated,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'headSha': headSha,
    'workspaceFingerprint': workspaceFingerprint,
  };

  static AgentWorkspaceTestResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final workspaceId = value['workspaceId'];
    final command = value['command'];
    final output = value['output'];
    final headSha = value['headSha'];
    final fingerprint = value['workspaceFingerprint'];
    final startedAt = DateTime.tryParse(value['startedAt']?.toString() ?? '');
    final finishedAt = DateTime.tryParse(value['finishedAt']?.toString() ?? '');
    final outcomeName = value['outcome'];
    AgentWorkspaceTestOutcome? outcome;
    if (outcomeName is String) {
      for (final candidate in AgentWorkspaceTestOutcome.values) {
        if (candidate.name == outcomeName) outcome = candidate;
      }
    }
    if (workspaceId is! String ||
        workspaceId.isEmpty ||
        command is! String ||
        command.isEmpty ||
        output is! String ||
        headSha is! String ||
        headSha.isEmpty ||
        fingerprint is! String ||
        fingerprint.isEmpty ||
        startedAt == null ||
        finishedAt == null ||
        outcome == null) {
      return null;
    }
    return AgentWorkspaceTestResult(
      workspaceId: workspaceId,
      command: command,
      outcome: outcome,
      exitCode: value['exitCode'] is int ? value['exitCode'] as int : null,
      output: output,
      outputTruncated: value['outputTruncated'] == true,
      startedAt: startedAt,
      finishedAt: finishedAt,
      headSha: headSha,
      workspaceFingerprint: fingerprint,
    );
  }
}

class AgentWorkspaceTestState {
  const AgentWorkspaceTestState({
    required this.suggestedCommand,
    required this.currentFingerprint,
    this.lastResult,
    this.running = false,
  });

  final String? suggestedCommand;
  final String currentFingerprint;
  final AgentWorkspaceTestResult? lastResult;
  final bool running;

  bool get isStale =>
      lastResult != null &&
      lastResult!.workspaceFingerprint != currentFingerprint;
}

String? suggestAgentWorkspaceTestCommand(
  Iterable<String> paths, {
  required bool nativeWindows,
}) {
  final files = paths.toSet();
  if (files.contains('pubspec.yaml')) return 'flutter test';
  if (files.contains('pnpm-lock.yaml')) return 'pnpm test';
  if (files.contains('yarn.lock')) return 'yarn test';
  if (files.contains('package.json')) return 'npm test';
  if (files.contains('Cargo.toml')) return 'cargo test';
  if (files.contains('go.mod')) return 'go test ./...';
  if (files.contains('pyproject.toml') ||
      files.contains('pytest.ini') ||
      files.contains('setup.cfg')) {
    return 'python -m pytest';
  }
  if (files.contains('pom.xml')) return 'mvn test';
  if (files.contains('gradlew') || files.contains('gradlew.bat')) {
    return nativeWindows ? r'.\gradlew.bat test' : './gradlew test';
  }
  if (files.contains('Makefile')) return 'make test';
  return null;
}
