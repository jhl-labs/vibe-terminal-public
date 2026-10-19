import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/terminal_input_bindings.dart';
import '../../state/providers.dart';
import '../../terminal/terminal_mapped_key.dart';

class TerminalInputSettings extends ConsumerWidget {
  const TerminalInputSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(
      appSettingsProvider.select((s) => s.inputBindings),
    );
    final controller = ref.read(appSettingsProvider.notifier);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    void update(TerminalInputTrigger trigger, TerminalInputBinding binding) =>
        controller.setTerminalInputBindings(
          bindings.withBinding(trigger, binding),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('제스처와 물리 버튼', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          '일반 터미널 화면에서 사용할 동작입니다. 기본 더블 탭·클릭은 단어 선택을 유지합니다. GUI 문서 모드·설정·다른 입력창에는 적용하지 않습니다.',
        ),
        const SizedBox(height: 16),
        for (final trigger in TerminalInputTrigger.values)
          if (!trigger.physical || android)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  DropdownButtonFormField<TerminalInputAction>(
                    key: ValueKey(
                      'input-binding-${trigger.name}-${bindings.forTrigger(trigger).action.name}',
                    ),
                    initialValue: bindings.forTrigger(trigger).action,
                    decoration: InputDecoration(labelText: trigger.label),
                    isExpanded: true,
                    items: [
                      for (final action in TerminalInputAction.values)
                        DropdownMenuItem(
                          value: action,
                          child: Text(
                            action == TerminalInputAction.defaultBehavior
                                ? (trigger.physical ? '시스템 볼륨 조절' : '기본 단어 선택')
                                : action.label,
                          ),
                        ),
                    ],
                    onChanged: (action) {
                      if (action != null) {
                        update(
                          trigger,
                          TerminalInputBinding(
                            action,
                            shortcut: bindings.forTrigger(trigger).shortcut,
                          ),
                        );
                      }
                    },
                  ),
                  if (bindings.forTrigger(trigger).action ==
                      TerminalInputAction.customKey)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        key: ValueKey('input-custom-${trigger.name}'),
                        initialValue: bindings.forTrigger(trigger).shortcut,
                        decoration: const InputDecoration(
                          labelText: '키 조합',
                          hintText: '예: Ctrl+D, Shift+Left, Alt+Enter, F1',
                        ),
                        maxLength: 80,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) =>
                            terminalMappedKey(value ?? '') == null
                            ? '지원되는 키 하나와 Ctrl·Alt·Shift를 입력해 주세요.'
                            : null,
                        onChanged: (value) => update(
                          trigger,
                          TerminalInputBinding(
                            TerminalInputAction.customKey,
                            shortcut: value,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        if (android) ...[
          Text('물리 버튼 두 번 누르기 간격: ${bindings.doublePressMilliseconds}ms'),
          Slider(
            value: bindings.doublePressMilliseconds.toDouble(),
            min: 200,
            max: 600,
            divisions: 8,
            label: '${bindings.doublePressMilliseconds}ms',
            onChanged: (value) => controller.setTerminalInputBindings(
              bindings.withDelay(value.round()),
            ),
          ),
          const Text(
            '두 번 누르기를 지정하면 한 번 누르기 동작은 이 간격만큼 기다립니다. 길게 누르기는 반복 전송하지 않습니다. 전원 버튼은 지원하지 않습니다.',
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () {
                var next = const TerminalInputBindings()
                    .withBinding(
                      TerminalInputTrigger.touchDoubleTap,
                      const TerminalInputBinding(TerminalInputAction.tab),
                    )
                    .withBinding(
                      TerminalInputTrigger.mouseDoubleClick,
                      const TerminalInputBinding(TerminalInputAction.tab),
                    );
                if (android) {
                  next = next
                      .withBinding(
                        TerminalInputTrigger.volumeDownSingle,
                        const TerminalInputBinding(TerminalInputAction.enter),
                      )
                      .withBinding(
                        TerminalInputTrigger.volumeUpSingle,
                        const TerminalInputBinding(TerminalInputAction.escape),
                      )
                      .withBinding(
                        TerminalInputTrigger.volumeUpDouble,
                        const TerminalInputBinding(
                          TerminalInputAction.interrupt,
                        ),
                      );
                }
                controller.setTerminalInputBindings(next);
              },
              child: Text(android ? '탭 완성·볼륨 전송 프리셋' : '더블 클릭·탭으로 Tab'),
            ),
            TextButton(
              onPressed: () => controller.setTerminalInputBindings(
                const TerminalInputBindings(),
              ),
              child: const Text('기본값 복원'),
            ),
          ],
        ),
      ],
    );
  }
}
