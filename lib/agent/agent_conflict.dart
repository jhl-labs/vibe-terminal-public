enum AgentConflictStageKind { ancestor, ours, theirs }

class AgentConflictStage {
  const AgentConflictStage({
    required this.kind,
    required this.blobSha,
    required this.content,
    required this.truncated,
    required this.binary,
  });

  final AgentConflictStageKind kind;
  final String blobSha;
  final String? content;
  final bool truncated;
  final bool binary;
}

class AgentConflictFile {
  const AgentConflictFile({required this.path, required this.stages});

  final String path;
  final List<AgentConflictStage> stages;

  AgentConflictStage? stage(AgentConflictStageKind kind) {
    for (final stage in stages) {
      if (stage.kind == kind) return stage;
    }
    return null;
  }
}

class AgentConflictSnapshot {
  const AgentConflictSnapshot({
    required this.unresolvedFiles,
    required this.predictedPaths,
  });

  final List<AgentConflictFile> unresolvedFiles;
  final List<String> predictedPaths;

  bool get hasUnresolved => unresolvedFiles.isNotEmpty;
  bool get hasPredicted => predictedPaths.isNotEmpty;
  bool get hasConflicts => hasUnresolved || hasPredicted;
  List<String> get allPaths => List.unmodifiable({
    for (final file in unresolvedFiles) file.path,
    ...predictedPaths,
  });
}
