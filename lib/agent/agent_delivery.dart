enum AgentDeliveryMergeReadiness {
  ready,
  alreadyMerged,
  worktreeDirty,
  baseNotCheckedOut,
  baseDirty,
  diverged,
}

class AgentDeliveryCommit {
  const AgentDeliveryCommit({
    required this.sha,
    required this.shortSha,
    required this.subject,
    required this.author,
    required this.authoredAt,
  });

  final String sha;
  final String shortSha;
  final String subject;
  final String author;
  final DateTime? authoredAt;
}

class AgentDeliveryPreview {
  const AgentDeliveryPreview({
    required this.branchName,
    required this.baseRef,
    required this.headSha,
    required this.baseSha,
    required this.aheadCount,
    required this.behindCount,
    required this.changedFiles,
    required this.additions,
    required this.deletions,
    required this.commits,
    required this.mergeReadiness,
    required this.remoteName,
    required this.remoteUrl,
    required this.remoteBranchExists,
    required this.compareUrl,
    required this.existingPullRequestUrl,
    this.conflictPaths = const [],
  });

  final String branchName;
  final String baseRef;
  final String headSha;
  final String baseSha;
  final int aheadCount;
  final int behindCount;
  final int changedFiles;
  final int additions;
  final int deletions;
  final List<AgentDeliveryCommit> commits;
  final AgentDeliveryMergeReadiness mergeReadiness;
  final String? remoteName;
  final String? remoteUrl;
  final bool remoteBranchExists;
  final Uri? compareUrl;
  final Uri? existingPullRequestUrl;
  final List<String> conflictPaths;

  bool get hasCommits => aheadCount > 0;
  bool get canMerge => mergeReadiness == AgentDeliveryMergeReadiness.ready;
  bool get canPush => remoteName != null && hasCommits;
  bool get canCreatePullRequest =>
      remoteBranchExists && compareUrl != null && hasCommits;
}

class AgentDeliveryResult {
  const AgentDeliveryResult({
    required this.summary,
    required this.detail,
    this.url,
  });

  final String summary;
  final String detail;
  final Uri? url;
}

class AgentPullRequestDraft {
  const AgentPullRequestDraft({required this.title, required this.body});

  final String title;
  final String body;
}
