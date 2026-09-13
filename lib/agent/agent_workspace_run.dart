enum AgentWorkspaceRunOutcome { running, stopped, exited, failed }

class AgentWorkspaceRunContext {
  const AgentWorkspaceRunContext({
    required this.headSha,
    required this.workspaceFingerprint,
    required this.suggestedCommand,
  });

  final String headSha;
  final String workspaceFingerprint;
  final String? suggestedCommand;
}

class AgentWorkspaceRunRecord {
  const AgentWorkspaceRunRecord({
    required this.workspaceId,
    required this.command,
    required this.outcome,
    required this.output,
    required this.outputTruncated,
    required this.urls,
    required this.startedAt,
    required this.headSha,
    required this.workspaceFingerprint,
    this.finishedAt,
    this.exitCode,
  });

  final String workspaceId;
  final String command;
  final AgentWorkspaceRunOutcome outcome;
  final String output;
  final bool outputTruncated;
  final List<Uri> urls;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final String headSha;
  final String workspaceFingerprint;

  bool get running => outcome == AgentWorkspaceRunOutcome.running;

  AgentWorkspaceRunRecord copyWith({
    AgentWorkspaceRunOutcome? outcome,
    String? output,
    bool? outputTruncated,
    List<Uri>? urls,
    Object? finishedAt = _unchanged,
    Object? exitCode = _unchanged,
  }) => AgentWorkspaceRunRecord(
    workspaceId: workspaceId,
    command: command,
    outcome: outcome ?? this.outcome,
    output: output ?? this.output,
    outputTruncated: outputTruncated ?? this.outputTruncated,
    urls: List.unmodifiable(urls ?? this.urls),
    startedAt: startedAt,
    finishedAt: identical(finishedAt, _unchanged)
        ? this.finishedAt
        : finishedAt as DateTime?,
    exitCode: identical(exitCode, _unchanged)
        ? this.exitCode
        : exitCode as int?,
    headSha: headSha,
    workspaceFingerprint: workspaceFingerprint,
  );

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'command': command,
    'outcome': outcome.name,
    'output': output,
    'outputTruncated': outputTruncated,
    'urls': [for (final url in urls) url.toString()],
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    'exitCode': exitCode,
    'headSha': headSha,
    'workspaceFingerprint': workspaceFingerprint,
  };

  static AgentWorkspaceRunRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final workspaceId = value['workspaceId'];
    final command = value['command'];
    final output = value['output'];
    final headSha = value['headSha'];
    final fingerprint = value['workspaceFingerprint'];
    final startedAt = DateTime.tryParse(value['startedAt']?.toString() ?? '');
    final finishedAt = DateTime.tryParse(value['finishedAt']?.toString() ?? '');
    AgentWorkspaceRunOutcome? outcome;
    final outcomeName = value['outcome'];
    if (outcomeName is String) {
      for (final candidate in AgentWorkspaceRunOutcome.values) {
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
        outcome == null) {
      return null;
    }
    final urls = <Uri>[];
    if (value['urls'] is List) {
      for (final raw in value['urls'] as List) {
        final uri = Uri.tryParse('$raw');
        if (uri != null && uri.hasScheme && uri.host.isNotEmpty) urls.add(uri);
      }
    }
    return AgentWorkspaceRunRecord(
      workspaceId: workspaceId,
      command: command,
      outcome: outcome,
      output: output,
      outputTruncated: value['outputTruncated'] == true,
      urls: List.unmodifiable(urls),
      startedAt: startedAt,
      finishedAt: finishedAt,
      exitCode: value['exitCode'] is int ? value['exitCode'] as int : null,
      headSha: headSha,
      workspaceFingerprint: fingerprint,
    );
  }

  static const Object _unchanged = Object();
}

class AgentWorkspaceRunState {
  const AgentWorkspaceRunState({
    required this.suggestedCommand,
    required this.currentFingerprint,
    this.lastRun,
  });

  final String? suggestedCommand;
  final String currentFingerprint;
  final AgentWorkspaceRunRecord? lastRun;

  bool get running => lastRun?.running == true;
  bool get isStale =>
      lastRun != null && lastRun!.workspaceFingerprint != currentFingerprint;
}

String? suggestAgentWorkspaceRunCommand(
  Iterable<String> paths, {
  required bool nativeWindows,
}) {
  final files = paths.toSet();
  if (files.contains('pubspec.yaml')) {
    return 'flutter run -d web-server --web-hostname 0.0.0.0 --web-port 0';
  }
  if (files.contains('pnpm-lock.yaml')) return 'pnpm run dev';
  if (files.contains('yarn.lock')) return 'yarn dev';
  if (files.contains('package.json')) return 'npm run dev';
  if (files.contains('Cargo.toml')) return 'cargo run';
  if (files.contains('go.mod')) return 'go run .';
  if (files.contains('manage.py')) {
    return 'python manage.py runserver 0.0.0.0:8000';
  }
  if (files.contains('pom.xml')) return 'mvn spring-boot:run';
  if (files.contains('gradlew') || files.contains('gradlew.bat')) {
    return nativeWindows ? r'.\gradlew.bat bootRun' : './gradlew bootRun';
  }
  if (files.contains('Makefile')) return 'make run';
  return null;
}

List<Uri> extractAgentWorkspaceRunUrls(String output) {
  final plain = output.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  final matches = RegExp(
    r'https?://(?:\[[0-9a-fA-F:]+\]|[A-Za-z0-9._-]+)(?::\d{1,5})?(?:/[^\s<>"\x27\]\)]*)?',
    caseSensitive: false,
  ).allMatches(plain);
  final urls = <Uri>[];
  final seen = <String>{};
  for (final match in matches) {
    var candidate = match.group(0)!;
    while (candidate.endsWith('.') ||
        candidate.endsWith(',') ||
        candidate.endsWith(';') ||
        candidate.endsWith(':')) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty || uri.port > 65535) continue;
    if (seen.add(uri.toString())) urls.add(uri);
  }
  return List.unmodifiable(urls);
}
