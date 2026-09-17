class AgentIntegrationChange {
  const AgentIntegrationChange(this.path, this.before, this.after);
  final String path;
  final String? before;
  final String? after;
}

class AgentIntegrationPlan {
  const AgentIntegrationPlan({
    required this.revision,
    required this.installed,
    required this.nodeVersion,
    required this.remove,
    required this.changes,
  });
  final String revision;
  final bool installed;
  final String nodeVersion;
  final bool remove;
  final List<AgentIntegrationChange> changes;
  factory AgentIntegrationPlan.fromJson(
    Map<String, dynamic> json, {
    required bool remove,
  }) => AgentIntegrationPlan(
    revision: json['revision'] as String,
    installed: json['installed'] == true,
    nodeVersion: json['node'] as String,
    remove: remove,
    changes: [
      for (final row in json['changes'] as List)
        AgentIntegrationChange(
          row['path'] as String,
          row['before'] as String?,
          row['after'] as String?,
        ),
    ],
  );
}
