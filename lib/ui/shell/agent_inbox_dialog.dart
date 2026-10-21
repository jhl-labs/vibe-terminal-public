import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_chat_notifier.dart';
import '../../agent/agent_mailbox.dart';
import '../../agent/agent_schedule.dart';
import '../../app/theme.dart';
import 'agent_schedule_dialog.dart';

/// 예약 메시지 다이얼로그의 결과.
class AgentScheduledMessageResult {
  const AgentScheduledMessageResult({
    required this.sessionId,
    required this.body,
    required this.trigger,
  });

  final String sessionId;
  final String body;
  final AgentScheduleTrigger trigger;
}

/// "17시에 s0에게 이 말을 전해" — 시각을 정해 세션 우편함에 넣을 메시지를 만든다.
///
/// 시각이 되면 수신 세션을 포함한 loop가 돌고 있을 때 [INBOX]로 넣고, loop가
/// 없으면 그런 loop가 시작될 때까지 기다린다. 결과를 돌려주고 취소하면 null.
class AgentScheduledMessageDialog extends StatefulWidget {
  const AgentScheduledMessageDialog({
    super.key,
    required this.sessions,
    this.initialSessionId,
    this.initialBody,
    this.initialTrigger,
  });

  /// 고를 수 있는 세션 (id, 표시 이름).
  final List<(String, String)> sessions;
  final String? initialSessionId;
  final String? initialBody;
  final AgentScheduleTrigger? initialTrigger;

  @override
  State<AgentScheduledMessageDialog> createState() =>
      _AgentScheduledMessageDialogState();
}

class _AgentScheduledMessageDialogState
    extends State<AgentScheduledMessageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialBody ?? '',
  );
  late String? _sessionId =
      widget.initialSessionId ??
      (widget.sessions.isEmpty ? null : widget.sessions.first.$1);
  late AgentTimingSelection _timing = AgentTimingSelection(
    trigger:
        widget.initialTrigger ??
        AgentScheduleTrigger.once(DateTime.now().add(const Duration(hours: 1))),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final trigger = _timing.trigger;
    if (_sessionId == null || _controller.text.trim().isEmpty) return false;
    if (trigger == null) return false;
    if (trigger.kind == AgentScheduleKind.once) {
      return trigger.at?.isAfter(DateTime.now()) ?? false;
    }
    return true;
  }

  void _submit() {
    final trigger = _timing.trigger;
    final sessionId = _sessionId;
    if (!_canSubmit || trigger == null || sessionId == null) return;
    Navigator.of(context).pop(
      AgentScheduledMessageResult(
        sessionId: sessionId,
        body: _controller.text.trim(),
        trigger: trigger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(
            Icons.schedule_send_outlined,
            size: 19,
            color: VibeColors.secondary,
          ),
          SizedBox(width: 8),
          Text('예약 메시지'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '정한 시각에 세션 우편함에 넣습니다. 그 세션을 포함한 loop가 돌고 있을 때 '
              '다음 지시에 [INBOX]로 전달되고, loop가 없으면 시작될 때까지 기다립니다.',
              style: TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const ValueKey('agent-scheduled-message-session'),
              initialValue: _sessionId,
              items: [
                for (final (id, name) in widget.sessions)
                  DropdownMenuItem(value: id, child: Text(name)),
              ],
              onChanged: (value) => setState(() => _sessionId = value),
              isDense: true,
              style: const TextStyle(color: VibeColors.onSurface, fontSize: 12),
              dropdownColor: VibeColors.surfaceHigh,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '받을 세션',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('agent-scheduled-message-body'),
              controller: _controller,
              autofocus: widget.initialBody == null,
              minLines: 2,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontSize: 12.5,
              ),
              decoration: const InputDecoration(
                hintText: '예: 17시부터는 배포 대신 문서 정리로 전환해',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  '전달 시점',
                  style: TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                AgentTimingButton(
                  value: _timing,
                  allowNow: false,
                  onChanged: (value) => setState(() => _timing = value),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          key: const ValueKey('agent-scheduled-message-submit'),
          onPressed: _canSubmit ? _submit : null,
          icon: const Icon(Icons.schedule_send_outlined, size: 16),
          label: const Text('예약'),
        ),
      ],
    );
  }
}

/// 세션 우편함의 미배달 메시지 목록.
///
/// 배지 숫자만으로는 "어떤 말이 어느 세션의 다음 지시에 실려 갈지"를 알 수 없다.
/// 여기서 발신자·시각·본문을 보고, 잘못 넣었거나 상황이 바뀐 메시지는 배달 전에
/// 거둬들인다. loop가 도는 동안은 우편함이 실시간으로 바뀌므로 상태를 구독한다.
class AgentInboxDialog extends ConsumerWidget {
  const AgentInboxDialog({
    super.key,
    this.filterSessionId,
    this.onCompose,
    this.onScheduleMessage,
  });

  /// 특정 세션만 보여준다. null이면 모든 세션.
  final String? filterSessionId;

  /// 세션 우편함에 새 메시지를 넣는 진입점. null이면 버튼을 숨긴다.
  final ValueChanged<String>? onCompose;

  /// 시각을 정해 넣을 메시지를 만드는 진입점. 목록을 닫은 뒤 불린다.
  final VoidCallback? onScheduleMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(agentChatProvider);
    final messages = [
      for (final message in loop.undeliveredMessages)
        if (filterSessionId == null || message.to == filterSessionId) message,
    ];
    final groups = <String, List<AgentMessage>>{};
    for (final message in messages) {
      groups.putIfAbsent(message.to, () => []).add(message);
    }
    String nameOf(String sessionId) =>
        loop.sessionTasks[sessionId]?.displayName ?? sessionId;
    final filterName = filterSessionId == null
        ? null
        : nameOf(filterSessionId!);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.mail_outline, size: 19, color: VibeColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filterName == null ? '세션 우편함' : '$filterName 우편함',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${messages.length}건 대기',
            key: const ValueKey('agent-inbox-count'),
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: SizedBox(
          width: 520,
          child: messages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    loop.isRunning
                        ? '배달을 기다리는 메시지가 없습니다. 세션 보드의 우편함 버튼이나 '
                              '아래 버튼으로 세션 안의 에이전트에게 전할 말을 넣을 수 있습니다.'
                        : '배달을 기다리는 메시지가 없습니다. loop가 실행 중일 때 넣은 '
                              '메시지는 다음 지시에 [INBOX]로 전달됩니다.',
                    style: const TextStyle(
                      color: VibeColors.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in groups.entries) ...[
                      _GroupHeader(
                        sessionId: entry.key,
                        name: nameOf(entry.key),
                        count: entry.value.length,
                        onCompose: onCompose == null || !loop.isRunning
                            ? null
                            : () => onCompose!(entry.key),
                      ),
                      for (final message in entry.value)
                        _MessageTile(
                          message: message,
                          senderName: message.from == AgentMessage.user
                              ? '사용자'
                              : message.from == AgentMessage.orchestrator
                              ? '오케스트레이터'
                              : nameOf(message.from),
                          onWithdraw: () {
                            final removed = ref
                                .read(agentChatProvider.notifier)
                                .withdrawInboxMessage(message.id);
                            if (!removed && context.mounted) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('이미 배달되었거나 회수할 수 없는 메시지입니다.'),
                                ),
                              );
                            }
                          },
                        ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        if (onScheduleMessage != null)
          TextButton.icon(
            key: const ValueKey('agent-inbox-schedule-message'),
            onPressed: () {
              Navigator.of(context).pop();
              onScheduleMessage!();
            },
            icon: const Icon(Icons.schedule_send_outlined, size: 16),
            label: const Text('예약 메시지'),
          ),
        if (onCompose != null && loop.isRunning && filterSessionId != null)
          TextButton.icon(
            key: const ValueKey('agent-inbox-compose'),
            onPressed: () => onCompose!(filterSessionId!),
            icon: const Icon(Icons.forward_to_inbox_outlined, size: 16),
            label: const Text('메시지 넣기'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.sessionId,
    required this.name,
    required this.count,
    required this.onCompose,
  });

  final String sessionId;
  final String name;
  final int count;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 4),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 14, color: VibeColors.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '→ $name · $count건',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onCompose != null)
            IconButton(
              key: ValueKey('agent-inbox-compose-$sessionId'),
              tooltip: '$name 우편함에 메시지 넣기',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.forward_to_inbox_outlined, size: 16),
              color: VibeColors.secondary,
              onPressed: onCompose,
            ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.senderName,
    required this.onWithdraw,
  });

  final AgentMessage message;
  final String senderName;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final at = message.at.toLocal();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return Container(
      key: ValueKey('agent-inbox-message-${message.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        border: Border.all(color: VibeColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$senderName · $time',
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  message.body,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('agent-inbox-withdraw-${message.id}'),
            tooltip: '배달 전에 회수',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.undo, size: 17),
            color: VibeColors.onSurfaceDim,
            onPressed: onWithdraw,
          ),
        ],
      ),
    );
  }
}
