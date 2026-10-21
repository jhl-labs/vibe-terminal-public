/// AI Chat 루틴 등록·편집 대화상자.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_schedule.dart';
import '../../agent/agent_schedule_notifier.dart';
import '../../app/theme.dart';
import '../../state/providers.dart';
import '../../ui/shell/ai_data_consent.dart';
import '../../ui/shell/agent_schedule_dialog.dart';

/// 대화상자가 돌려주는 값.
class AiChatRoutineDraft {
  const AiChatRoutineDraft({
    required this.prompt,
    required this.trigger,
    required this.terminalToolCall,
  });

  final String prompt;
  final AgentScheduleTrigger trigger;
  final bool terminalToolCall;
}

/// 루틴을 만들거나 고친 뒤 저장까지 한다. 저장했으면 true.
Future<bool> showAiChatRoutineEditor(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String sessionName,
  AgentScheduledTask? existing,
  String? initialPrompt,
}) async {
  final draft = await showDialog<AiChatRoutineDraft>(
    context: context,
    builder: (_) => AiChatRoutineDialog(
      sessionName: sessionName,
      existing: existing,
      initialPrompt: initialPrompt,
    ),
  );
  if (draft == null || !context.mounted) return false;
  final settings = ref.read(appSettingsProvider).ai;
  if (!await AiDataConsent(
    store: ref.read(aiConsentStoreProvider),
  ).request(context, settings)) {
    return false;
  }
  if (!context.mounted ||
      AiDataConsent.destinationKey(settings) !=
          AiDataConsent.destinationKey(ref.read(appSettingsProvider).ai)) {
    return false;
  }
  final notifier = ref.read(agentScheduleProvider.notifier);
  try {
    if (existing == null) {
      await notifier.addAiChatRoutine(
        sessionId: sessionId,
        prompt: draft.prompt,
        trigger: draft.trigger,
        terminalToolCall: draft.terminalToolCall,
      );
    } else {
      await notifier.updateAiChatRoutine(
        existing.id,
        sessionId: sessionId,
        prompt: draft.prompt,
        trigger: draft.trigger,
        terminalToolCall: draft.terminalToolCall,
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('루틴 저장 실패: $error')));
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${existing == null ? '루틴 등록' : '루틴 수정'}: ${draft.trigger.label} · $sessionName',
        ),
      ),
    );
  }
  return true;
}

class AiChatRoutineDialog extends StatefulWidget {
  const AiChatRoutineDialog({
    super.key,
    required this.sessionName,
    this.existing,
    this.initialPrompt,
  });

  final String sessionName;
  final AgentScheduledTask? existing;
  final String? initialPrompt;

  @override
  State<AiChatRoutineDialog> createState() => _AiChatRoutineDialogState();
}

class _AiChatRoutineDialogState extends State<AiChatRoutineDialog> {
  late final TextEditingController _prompt = TextEditingController(
    text: widget.existing?.messageBody ?? widget.initialPrompt ?? '',
  );
  late AgentTimingSelection _timing = AgentTimingSelection(
    trigger:
        widget.existing?.trigger ??
        const AgentScheduleTrigger.daily(hour: 9, minute: 0),
  );
  late bool _terminalToolCall = widget.existing?.terminalToolCall ?? false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _prompt.text.trim().isNotEmpty &&
      _timing.valid &&
      _timing.trigger != null;

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      AiChatRoutineDraft(
        prompt: _prompt.text.trim(),
        trigger: _timing.trigger!,
        terminalToolCall: _terminalToolCall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.schedule_outlined,
            size: 19,
            color: VibeColors.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.existing == null
                  ? '${widget.sessionName} AI Chat 루틴'
                  : '루틴 편집 · ${widget.sessionName}',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '정해진 시각마다 이 세션의 화면을 보고 아래 프롬프트로 AI Chat 턴을 '
                '돌립니다. 결과는 세션의 AI Chat 대화에 남고, 보고 있지 않으면 알립니다.',
                style: TextStyle(
                  color: VibeColors.onSurfaceMuted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ai-chat-routine-prompt'),
                controller: _prompt,
                autofocus: widget.existing == null,
                minLines: 2,
                maxLines: 6,
                style: const TextStyle(
                  color: VibeColors.onSurface,
                  fontSize: 12.5,
                ),
                decoration: const InputDecoration(
                  labelText: '프롬프트',
                  hintText: '예: git status와 최근 빌드 로그를 보고 문제가 있으면 요약해줘',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              AgentTimingSection(
                value: _timing,
                allowNow: false,
                onChanged: (value) => setState(() => _timing = value),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                key: const ValueKey('ai-chat-routine-tool-call'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _terminalToolCall,
                onChanged: (value) => setState(() => _terminalToolCall = value),
                title: const Text(
                  '터미널 입력 허용',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: const Text(
                  '켜면 모델이 필요할 때 명령을 직접 보냅니다. 파괴적 명령은 보내지 않고 '
                  '제안으로 남깁니다.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: VibeColors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          key: const ValueKey('ai-chat-routine-save'),
          onPressed: _canSave ? _submit : null,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(widget.existing == null ? '루틴 등록' : '저장'),
        ),
      ],
    );
  }
}
