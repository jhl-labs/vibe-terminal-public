import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/app_version.dart';
import '../../app/theme.dart';
import '../../settings/app_settings.dart';
import '../../settings/shortcut_bindings.dart';
import '../../state/providers.dart';
import '../../sync/github_sync_service.dart';
import '../adaptive/breakpoints.dart';
import 'action_bar_editor_page.dart';

Future<void> showVibeTerminalSettings(BuildContext context) {
  if (context.isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: _SettingsPanel(compact: true),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(
      insetPadding: EdgeInsets.all(24),
      child: SizedBox(width: 780, height: 700, child: _SettingsPanel()),
    ),
  );
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel({this.compact = false});

  static int _lastTabIndex = 0;

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final features = ref.watch(buildFeaturesProvider);
    final tabs = <Widget>[];
    final views = <Widget>[];

    if (features.settingsTerminal) {
      tabs.add(const Tab(icon: Icon(Icons.terminal), text: '터미널'));
      views.add(_TerminalSettingsTab(settings: settings));
    }
    if (features.settingsInteraction) {
      tabs.add(const Tab(icon: Icon(Icons.touch_app_outlined), text: '상호작용'));
      views.add(_InteractionSettingsTab(settings: settings));
    }
    if (features.settingsShortcut) {
      tabs.add(const Tab(icon: Icon(Icons.keyboard_alt_outlined), text: '단축키'));
      views.add(_ShortcutSettingsTab(settings: settings));
    }
    if (features.settingsNotifications) {
      tabs.add(const Tab(icon: Icon(Icons.notifications_outlined), text: '알림'));
      views.add(_NotificationSettingsTab(settings: settings));
    }
    if (features.settingsGithub) {
      tabs.add(const Tab(icon: Icon(Icons.hub_outlined), text: 'GitHub'));
      views.add(_GitHubSyncSettingsTab(settings: settings));
    }
    if (features.settingsAi) {
      tabs.add(const Tab(icon: Icon(Icons.auto_awesome), text: 'AI'));
      views.add(_AiSettingsTab(settings: settings));
    }
    if (features.settingsAbout) {
      tabs.add(const Tab(icon: Icon(Icons.info_outline), text: '정보'));
      views.add(const _AboutSettingsTab());
    }
    if (tabs.isEmpty) {
      tabs.add(
        const Tab(icon: Icon(Icons.visibility_off_outlined), text: '비활성'),
      );
      views.add(const _NoVisibleSettingsTab());
    }

    final initialSettingsTabIndex = _lastTabIndex < tabs.length
        ? _lastTabIndex
        : 0;

    return Material(
      color: VibeColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 0 : 8),
        side: compact
            ? BorderSide.none
            : const BorderSide(color: VibeColors.borderSoft),
      ),
      child: DefaultTabController(
        initialIndex: initialSettingsTabIndex,
        length: tabs.length,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: VibeColors.accent),
                  const SizedBox(width: 10),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: VibeColors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'v${appVersionLabel(kAppVersion, kAppBuildNumber)}',
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: controller.reset,
                    child: const Text('초기화'),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              onTap: (index) => _lastTabIndex = index,
              tabs: tabs,
            ),
            Expanded(child: TabBarView(children: views)),
          ],
        ),
      ),
    );
  }
}

class _TerminalSettingsTab extends ConsumerWidget {
  const _TerminalSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appSettingsProvider.notifier);
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '터미널 화면',
          description: '접속 세션에서 바로 반영되는 테마와 글꼴 설정입니다.',
          children: [
            DropdownButtonFormField<TerminalThemePreset>(
              initialValue: settings.terminalTheme,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '터미널 테마'),
              selectedItemBuilder: (context) => [
                for (final preset in TerminalThemePreset.values)
                  Text(preset.label, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final preset in TerminalThemePreset.values)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(
                      '${preset.label} - ${preset.description}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setTerminalTheme(value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: settings.terminalFontFamily,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '폰트'),
              selectedItemBuilder: (context) => [
                for (final font in AppSettings.fontFamilies)
                  Text(font, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final font in AppSettings.fontFamilies)
                  DropdownMenuItem(
                    value: font,
                    child: Text(font, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setTerminalFontFamily(value);
              },
            ),
            const SizedBox(height: 18),
            _SliderSetting(
              label: '폰트 크기',
              value: settings.terminalFontSize,
              min: AppSettings.minFontSize,
              max: AppSettings.maxFontSize,
              divisions: (AppSettings.maxFontSize - AppSettings.minFontSize)
                  .round(),
              valueLabel: settings.terminalFontSize.toStringAsFixed(0),
              onChanged: controller.setTerminalFontSize,
            ),
            const SizedBox(height: 12),
            _SliderSetting(
              label: '줄 간격',
              value: settings.terminalLineHeight,
              min: AppSettings.minLineHeight,
              max: AppSettings.maxLineHeight,
              divisions: 12,
              valueLabel: settings.terminalLineHeight.toStringAsFixed(2),
              onChanged: controller.setTerminalLineHeight,
            ),
          ],
        ),
        _SettingsSection(
          title: '스크롤백',
          description:
              '터미널에서 위로 되감을 수 있는 줄 수입니다. '
              '세션마다 이만큼을 메모리에 보관하므로, 크게 잡으면 세션 수만큼 메모리 사용이 늘어납니다.',
          children: [
            _ScrollbackSetting(lines: settings.terminalScrollbackLines),
            const SizedBox(height: 8),
            const Text(
              '변경한 값은 이후에 새로 여는 세션부터 적용됩니다. '
              '이미 열려 있는 세션은 다시 연결해야 반영됩니다.',
              style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

/// 스크롤백 빠른 선택지. 직접 입력 필드를 채워 준다.
const _scrollbackChoices = <int>[1000, 5000, 10000, 25000, 50000, 100000];

/// 스크롤백 줄 수를 직접 입력하거나 빠른 선택지로 고른다.
///
/// 타이핑 도중에는 값을 잘라내지 않는다. `50000`을 치려고 `5`를 누른 순간
/// 하한(500)으로 보정해 버리면 그 뒤 입력을 계속 방해하기 때문이다. 범위 안에
/// 들어온 값만 즉시 반영하고, 입력을 마쳤을 때(엔터·포커스 해제) 범위 밖이면
/// 그때 보정한다.
class _ScrollbackSetting extends ConsumerStatefulWidget {
  const _ScrollbackSetting({required this.lines});

  final int lines;

  @override
  ConsumerState<_ScrollbackSetting> createState() => _ScrollbackSettingState();
}

class _ScrollbackSettingState extends ConsumerState<_ScrollbackSetting> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.lines.toString());
    _focusNode = FocusNode()..addListener(_commitOnFocusLoss);
  }

  @override
  void didUpdateWidget(_ScrollbackSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 경로(동기화·초기화 등)로 값이 바뀌면 따라간다. 편집 중에는 건드리지
    // 않아 커서가 튀지 않게 한다.
    if (widget.lines != oldWidget.lines &&
        !_focusNode.hasFocus &&
        _controller.text != widget.lines.toString()) {
      _controller.text = widget.lines.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_commitOnFocusLoss);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitOnFocusLoss() {
    if (_focusNode.hasFocus) return;
    _commit();
  }

  /// 입력을 확정한다. 비었거나 범위 밖이면 보정한 값을 필드에도 되쓴다.
  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    final resolved = (parsed ?? widget.lines).clamp(
      AppSettings.minScrollbackLines,
      AppSettings.maxScrollbackLines,
    );
    if (_controller.text != resolved.toString()) {
      _controller.text = resolved.toString();
    }
    ref.read(appSettingsProvider.notifier).setTerminalScrollbackLines(resolved);
  }

  void _applyPreset(int lines) {
    _controller.text = lines.toString();
    ref.read(appSettingsProvider.notifier).setTerminalScrollbackLines(lines);
  }

  @override
  Widget build(BuildContext context) {
    final min = AppSettings.minScrollbackLines;
    final max = AppSettings.maxScrollbackLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: const ValueKey('terminal-scrollback-field'),
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: '보관할 줄 수',
            prefixIcon: const Icon(Icons.format_list_numbered),
            helperText:
                '${_formatLineCount(min)} ~ ${_formatLineCount(max)}줄 '
                '(기본 ${_formatLineCount(AppSettings.defaultScrollbackLines)}줄)',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            final parsed = int.tryParse(value);
            // 범위 안일 때만 즉시 반영한다. 그 밖은 입력이 끝날 때 보정한다.
            if (parsed != null && parsed >= min && parsed <= max) {
              ref
                  .read(appSettingsProvider.notifier)
                  .setTerminalScrollbackLines(parsed);
            }
          },
          onEditingComplete: _commit,
          onTapOutside: (_) => _focusNode.unfocus(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lines in _scrollbackChoices)
              ActionChip(
                label: Text('${_formatLineCount(lines)}줄'),
                onPressed: () => _applyPreset(lines),
              ),
          ],
        ),
      ],
    );
  }
}

String _formatLineCount(int lines) {
  final text = lines.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

class _InteractionSettingsTab extends ConsumerWidget {
  const _InteractionSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appSettingsProvider.notifier);
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '클립보드',
          description: '일반 데스크톱 터미널의 복사/붙여넣기 흐름을 조정합니다.',
          children: [
            _SwitchSetting(
              title: '선택 즉시 복사',
              subtitle: '마우스로 선택한 터미널 텍스트를 자동으로 클립보드에 복사합니다.',
              value: settings.copyOnSelection,
              onChanged: controller.setCopyOnSelection,
            ),
            _SwitchSetting(
              title: '우클릭 붙여넣기',
              subtitle: '터미널 영역을 우클릭하면 클립보드 텍스트를 붙여넣습니다.',
              value: settings.rightClickPaste,
              onChanged: controller.setRightClickPaste,
            ),
            _SwitchSetting(
              title: '여러 줄 붙여넣기 전 확인',
              subtitle: '엔터가 포함된 텍스트가 바로 실행되지 않도록 확인창을 띄웁니다.',
              value: settings.confirmMultilinePaste,
              onChanged: controller.setConfirmMultilinePaste,
            ),
          ],
        ),
      ],
    );
  }
}

class _ShortcutSettingsTab extends ConsumerWidget {
  const _ShortcutSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appSettingsProvider.notifier);
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '키보드',
          description: '터미널 입력과 앱 전역 동작에 사용할 키를 사용자가 선택합니다.',
          children: [
            DropdownButtonFormField<CtrlCBehavior>(
              initialValue: settings.ctrlCBehavior,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ctrl+C 동작'),
              selectedItemBuilder: (context) => [
                for (final behavior in CtrlCBehavior.values)
                  Text(behavior.label, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final behavior in CtrlCBehavior.values)
                  DropdownMenuItem(
                    value: behavior,
                    child: Text(
                      '${behavior.label} - ${behavior.description}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setCtrlCBehavior(value);
              },
            ),
            const SizedBox(height: 18),
            _ShortcutBindingField(
              actionId: 'copy',
              label: '복사',
              bindings: settings.shortcutBindings['copy']!,
              defaultBindings: kDefaultShortcutBindings['copy']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'paste',
              label: '붙여넣기',
              bindings: settings.shortcutBindings['paste']!,
              defaultBindings: kDefaultShortcutBindings['paste']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'zoomIn',
              label: '확대',
              bindings: settings.shortcutBindings['zoomIn']!,
              defaultBindings: kDefaultShortcutBindings['zoomIn']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'zoomOut',
              label: '축소',
              bindings: settings.shortcutBindings['zoomOut']!,
              defaultBindings: kDefaultShortcutBindings['zoomOut']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'zoomReset',
              label: '줌 초기화',
              bindings: settings.shortcutBindings['zoomReset']!,
              defaultBindings: kDefaultShortcutBindings['zoomReset']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'sessionPrevious',
              label: '직전 세션',
              bindings: settings.shortcutBindings['sessionPrevious']!,
              defaultBindings: kDefaultShortcutBindings['sessionPrevious']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 12),
            _ShortcutBindingField(
              actionId: 'commandPalette',
              label: '명령 팔레트',
              bindings: settings.shortcutBindings['commandPalette']!,
              defaultBindings: kDefaultShortcutBindings['commandPalette']!,
              onChanged: controller.setShortcutBinding,
            ),
            const SizedBox(height: 8),
            const _ShortcutRow(action: '인터럽트', keys: 'Ctrl+C'),
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: '버튼 바 커스터마이징',
          description: '하단 보조키바와 상단 헤더에 표시할 버튼을 직접 고르고 정렬합니다.',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune, color: VibeColors.accent),
              title: const Text('버튼 바 편집'),
              subtitle: const Text('보조키바 / 상단 헤더 항목 선택·정렬·사용자 키 추가'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ActionBarEditorPage(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NotificationSettingsTab extends ConsumerWidget {
  const _NotificationSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appSettingsProvider.notifier);
    final notifications = settings.notifications;
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '알림',
          description: '백그라운드 작업과 에이전트 상태를 시스템 알림으로 받을지 관리합니다.',
          children: [
            _SwitchSetting(
              title: '시스템 알림',
              subtitle: 'Vibe Terminal에서 보내는 로컬 알림을 모두 켜거나 끕니다.',
              value: notifications.enabled,
              onChanged: controller.setNotificationsEnabled,
            ),
            _SwitchSetting(
              title: '작업 완료 알림',
              subtitle: '보고 있지 않은 터미널 세션에서 긴 작업이 끝나면 알립니다.',
              value: notifications.taskCompleteEnabled,
              onChanged: notifications.enabled
                  ? controller.setTaskCompleteNotificationsEnabled
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _GitHubSyncSettingsTab extends ConsumerStatefulWidget {
  const _GitHubSyncSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_GitHubSyncSettingsTab> createState() =>
      _GitHubSyncSettingsTabState();
}

class _GitHubSyncSettingsTabState
    extends ConsumerState<_GitHubSyncSettingsTab> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _appClientIdController;
  late final TextEditingController _tokenController;
  late final TextEditingController _ownerController;
  late final TextEditingController _repoController;
  late final TextEditingController _branchController;
  late final TextEditingController _pathController;
  late final TextEditingController _encryptionKeyController;
  bool _checkingUsage = false;
  bool _authorizing = false;
  bool _uploading = false;
  GitHubRateLimit? _rateLimit;
  GitHubDeviceCode? _deviceCode;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    final sync = widget.settings.cloudSync;
    final github = sync.github;
    _serverUrlController = TextEditingController(text: github.serverUrl);
    _appClientIdController = TextEditingController(text: github.appClientId);
    _tokenController = TextEditingController(text: github.token);
    _ownerController = TextEditingController(text: github.owner);
    _repoController = TextEditingController(text: github.repo);
    _branchController = TextEditingController(text: github.branch);
    _pathController = TextEditingController(text: github.path);
    _encryptionKeyController = TextEditingController(text: sync.encryptionKey);
  }

  @override
  void didUpdateWidget(covariant _GitHubSyncSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sync = widget.settings.cloudSync;
    final oldSync = oldWidget.settings.cloudSync;
    final github = sync.github;
    if (oldSync.github.serverUrl != github.serverUrl) {
      _setControllerText(_serverUrlController, github.serverUrl);
    }
    if (oldSync.github.appClientId != github.appClientId) {
      _setControllerText(_appClientIdController, github.appClientId);
    }
    if (oldSync.github.token != github.token) {
      _setControllerText(_tokenController, github.token);
    }
    if (oldSync.github.owner != github.owner) {
      _setControllerText(_ownerController, github.owner);
    }
    if (oldSync.github.repo != github.repo) {
      _setControllerText(_repoController, github.repo);
    }
    if (oldSync.github.branch != github.branch) {
      _setControllerText(_branchController, github.branch);
    }
    if (oldSync.github.path != github.path) {
      _setControllerText(_pathController, github.path);
    }
    if (oldSync.encryptionKey != sync.encryptionKey) {
      _setControllerText(_encryptionKeyController, sync.encryptionKey);
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _appClientIdController.dispose();
    _tokenController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    _pathController.dispose();
    _encryptionKeyController.dispose();
    super.dispose();
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  GitHubSyncSettings _effectiveGitHubSettings() =>
      widget.settings.cloudSync.github.copyWith(
        serverUrl: widget.settings.cloudSync.github.isGitHubDotCom
            ? GitHubSyncSettings.githubComServerUrl
            : _serverUrlController.text.trim(),
        appClientId: widget.settings.cloudSync.github.isGitHubDotCom
            ? ''
            : _appClientIdController.text.trim(),
        token: _tokenController.text,
        owner: _ownerController.text.trim(),
        repo: _repoController.text.trim(),
        branch: _branchController.text.trim(),
        path: _pathController.text.trim(),
      );

  AppSettings _effectiveAppSettings() {
    final sync = widget.settings.cloudSync.copyWith(
      encryptionKey: _encryptionKeyController.text,
      github: _effectiveGitHubSettings(),
    );
    return widget.settings.copyWith(cloudSync: sync);
  }

  Future<GitHubSyncSettings> _freshGitHubSettings() async {
    final settings = _effectiveGitHubSettings();
    final expiresAt = settings.tokenExpiresAt;
    final shouldRefresh =
        expiresAt != null &&
        settings.refreshToken.trim().isNotEmpty &&
        expiresAt.isBefore(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );
    if (!shouldRefresh) return settings;

    final authorization = await ref
        .read(gitHubSyncServiceProvider)
        .refreshUserAccessToken(settings: settings);
    ref
        .read(appSettingsProvider.notifier)
        .setGitHubSyncAuthorization(authorization);
    return settings.copyWith(
      token: authorization.accessToken,
      refreshToken: authorization.refreshToken ?? settings.refreshToken,
      tokenExpiresAt: authorization.expiresAt,
      refreshTokenExpiresAt:
          authorization.refreshTokenExpiresAt ?? settings.refreshTokenExpiresAt,
    );
  }

  Future<void> _checkUsage() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _checkingUsage = true;
      _deviceCode = null;
      _status = null;
    });
    try {
      final settings = await _freshGitHubSettings();
      final usage = await ref
          .read(gitHubSyncServiceProvider)
          .validateToken(settings);
      if (!mounted) return;
      setState(() {
        _rateLimit = usage;
        _status = 'GitHub token과 저장소 권한을 확인했습니다.';
        _statusOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString();
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _checkingUsage = false);
    }
  }

  Future<void> _authorizeGitHubApp() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _authorizing = true;
      _deviceCode = null;
      _status = null;
    });
    try {
      final service = ref.read(gitHubSyncServiceProvider);
      final settings = _effectiveGitHubSettings();
      final code = await service.requestDeviceCode(settings: settings);
      unawaited(
        Clipboard.setData(
          ClipboardData(text: code.userCode),
        ).catchError((_) {}),
      );
      final launched = await ref
          .read(externalUrlLauncherProvider)
          .call(code.verificationUri);
      if (!mounted) return;
      setState(() {
        _deviceCode = code;
        _status = launched
            ? '브라우저에서 GitHub 인증을 완료하세요. 표시된 인증 코드를 입력하세요.'
            : '브라우저를 열지 못했습니다. 표시된 URL과 코드를 사용하세요.';
        _statusOk = launched;
      });

      final authorization = await service.waitForDeviceAuthorization(
        settings: settings,
        deviceCode: code,
      );
      ref
          .read(appSettingsProvider.notifier)
          .setGitHubSyncAuthorization(authorization);
      final usage = await ref
          .read(gitHubSyncServiceProvider)
          .fetchRateLimit(settings.copyWith(token: authorization.accessToken));
      if (!mounted) return;
      setState(() {
        _deviceCode = null;
        _rateLimit = usage;
        _status = authorization.expiresAt == null
            ? 'GitHub App token을 연결했습니다.'
            : 'GitHub App token을 연결했습니다. 만료: ${authorization.expiresAt!.toLocal()}';
        _statusOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString();
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _authorizing = false);
    }
  }

  Future<void> _uploadSnapshot() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _uploading = true;
      _status = null;
    });
    try {
      final effective = _effectiveAppSettings();
      final settings = await _freshGitHubSettings();
      final blob = await ref
          .read(cloudSyncSnapshotServiceProvider)
          .buildEncryptedSnapshot(effective, _encryptionKeyController.text);
      final result = await ref
          .read(gitHubSyncServiceProvider)
          .uploadEncryptedSnapshot(settings: settings, blob: blob);
      if (!mounted) return;
      setState(() {
        _rateLimit = result.rateLimit ?? _rateLimit;
        final shortSha = result.commitSha.length <= 7
            ? result.commitSha
            : result.commitSha.substring(0, 7);
        _status = '업로드 완료: ${result.path} @ $shortSha';
        _statusOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString();
        _statusOk = false;
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(appSettingsProvider.notifier);
    final sync = widget.settings.cloudSync;
    final githubEnabled = sync.provider == CloudSyncProviderType.github;
    final github = sync.github;
    final githubDotCom = github.isGitHubDotCom;
    final canUpload =
        githubEnabled &&
        _effectiveGitHubSettings().isConfigured &&
        _encryptionKeyController.text.trim().length >= 12 &&
        !_uploading;
    final canAuthorize =
        githubEnabled &&
        _effectiveGitHubSettings().effectiveAppClientId.isNotEmpty &&
        !_authorizing;
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: 'Cloud Sync',
          description: '동기화 provider와 암호화된 원격 저장 위치를 설정합니다.',
          children: [
            DropdownButtonFormField<CloudSyncProviderType>(
              initialValue: sync.provider,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Provider'),
              selectedItemBuilder: (context) => [
                for (final provider in CloudSyncProviderType.values)
                  Text(provider.label, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final provider in CloudSyncProviderType.values)
                  DropdownMenuItem(
                    value: provider,
                    enabled: provider.enabled,
                    child: Text(
                      provider.enabled
                          ? '${provider.label} - ${provider.metricLabel}'
                          : '${provider.label} - 준비 중',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setCloudSyncProvider(value);
              },
            ),
            const SizedBox(height: 12),
            _SwitchSetting(
              title: 'Sync 활성화',
              subtitle: '저장된 앱 데이터를 암호화한 뒤 선택한 provider에 보관합니다.',
              value: sync.enabled,
              onChanged: controller.setCloudSyncEnabled,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: 'GitHub',
          description:
              'GitHub.com 또는 GitHub Enterprise의 org/repo를 동기화 대상으로 사용합니다.',
          children: [
            DropdownButtonFormField<GitHubSyncHostType>(
              initialValue: github.hostType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'GitHub provider',
                prefixIcon: Icon(Icons.public_outlined),
              ),
              items: [
                for (final hostType in GitHubSyncHostType.values)
                  DropdownMenuItem(
                    value: hostType,
                    child: Text(hostType.label),
                  ),
              ],
              onChanged: githubEnabled
                  ? (value) {
                      if (value != null) {
                        controller.setGitHubSyncHostType(value);
                      }
                    }
                  : null,
            ),
            if (!githubDotCom) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('github-sync-server-url-field'),
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'GitHub Enterprise URL',
                  hintText: 'https://github.enterprise.local',
                  prefixIcon: Icon(Icons.public_outlined),
                ),
                keyboardType: TextInputType.url,
                enabled: githubEnabled,
                onChanged: controller.setGitHubSyncServerUrl,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('github-app-client-id-field'),
                controller: _appClientIdController,
                decoration: const InputDecoration(
                  labelText: 'GitHub App Client ID',
                  hintText: 'Iv1.xxxxxxxxxxxxxxxx',
                  prefixIcon: Icon(Icons.app_registration_outlined),
                ),
                enabled: githubEnabled,
                onChanged: controller.setGitHubSyncAppClientId,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canAuthorize ? _authorizeGitHubApp : null,
              icon: _authorizing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_outlined),
              label: const Text('GitHub App으로 로그인'),
            ),
            if (_deviceCode != null) ...[
              const SizedBox(height: 12),
              _GitHubDeviceCodeCard(code: _deviceCode!),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('github-sync-token-field'),
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Access token',
                hintText: '자동 연동 token 또는 개발용 PAT',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: githubEnabled,
              onChanged: controller.setGitHubSyncToken,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('github-sync-owner-field'),
                    controller: _ownerController,
                    decoration: const InputDecoration(
                      labelText: 'Org / Owner',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    enabled: githubEnabled,
                    onChanged: controller.setGitHubSyncOwner,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('github-sync-repo-field'),
                    controller: _repoController,
                    decoration: const InputDecoration(
                      labelText: 'Repository',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                    enabled: githubEnabled,
                    onChanged: controller.setGitHubSyncRepo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    key: const ValueKey('github-sync-branch-field'),
                    controller: _branchController,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      prefixIcon: Icon(Icons.call_split_outlined),
                    ),
                    enabled: githubEnabled,
                    onChanged: controller.setGitHubSyncBranch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('github-sync-path-field'),
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'Sync file path',
                      prefixIcon: Icon(Icons.insert_drive_file_outlined),
                    ),
                    enabled: githubEnabled,
                    onChanged: controller.setGitHubSyncPath,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GitHubUsageCard(rateLimit: _rateLimit),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: githubEnabled && !_checkingUsage ? _checkUsage : null,
              icon: _checkingUsage
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed_outlined),
              label: const Text('Token 유효성 검사'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 10),
              _AsyncStatusText(message: _status!, success: _statusOk),
            ],
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: 'Encryption',
          description: '원격 저장소에는 암호화된 sync snapshot만 업로드합니다.',
          children: [
            TextFormField(
              key: const ValueKey('cloud-sync-encryption-key-field'),
              controller: _encryptionKeyController,
              decoration: const InputDecoration(
                labelText: 'Encrypt key',
                hintText: '12자 이상',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: controller.setCloudSyncEncryptionKey,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canUpload ? _uploadSnapshot : null,
              icon: _uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('암호화 스냅샷 업로드'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GitHubUsageCard extends StatelessWidget {
  const _GitHubUsageCard({required this.rateLimit});

  final GitHubRateLimit? rateLimit;

  @override
  Widget build(BuildContext context) {
    final limit = rateLimit;
    final hasUsage = limit != null && limit.limit > 0;
    final value = hasUsage ? limit.remaining / limit.limit : null;
    final resetText = limit == null
        ? '확인 전'
        : 'Reset ${TimeOfDay.fromDateTime(limit.resetAt.toLocal()).format(context)} · ${limit.resource}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: VibeColors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_outlined, color: VibeColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  limit == null
                      ? 'Token usage'
                      : '${limit.remaining} / ${limit.limit}',
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                'GitHub API',
                style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: value ?? 0),
          const SizedBox(height: 8),
          Text(
            resetText,
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitHubDeviceCodeCard extends StatelessWidget {
  const _GitHubDeviceCodeCard({required this.code});

  final GitHubDeviceCode code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VibeColors.accentSoft,
        border: Border.all(color: VibeColors.accent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: VibeColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  code.userCode,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: code.userCode)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('복사'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            code.verificationUri.toString(),
            style: const TextStyle(
              color: VibeColors.onSurfaceDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSettingsTab extends ConsumerStatefulWidget {
  const _AiSettingsTab({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_AiSettingsTab> createState() => _AiSettingsTabState();
}

class _AiSettingsTabState extends ConsumerState<_AiSettingsTab> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiTokenController;
  late final TextEditingController _customHeadersController;
  late final TextEditingController _httpProxyController;
  late final TextEditingController _httpsProxyController;
  late final TextEditingController _customPromptController;
  List<String> _models = const [];
  bool _loadingModels = false;
  bool _testingConnection = false;
  String? _modelStatus;
  bool _modelStatusOk = false;
  String? _testStatus;
  bool _testStatusOk = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.settings.ai.baseUrl,
    );
    _modelController = TextEditingController(text: widget.settings.ai.model);
    _apiTokenController = TextEditingController(
      text: widget.settings.ai.apiToken,
    );
    _customHeadersController = TextEditingController(
      text: widget.settings.ai.customHeaders,
    );
    _httpProxyController = TextEditingController(
      text: widget.settings.ai.httpProxy,
    );
    _httpsProxyController = TextEditingController(
      text: widget.settings.ai.httpsProxy,
    );
    _customPromptController = TextEditingController(
      text: widget.settings.ai.customPrompt,
    );
  }

  @override
  void didUpdateWidget(covariant _AiSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAi = oldWidget.settings.ai;
    final ai = widget.settings.ai;
    if (_baseUrlController.text != ai.baseUrl) {
      _baseUrlController.value = TextEditingValue(
        text: ai.baseUrl,
        selection: TextSelection.collapsed(offset: ai.baseUrl.length),
      );
    }
    if (_modelController.text != ai.model) {
      _modelController.value = TextEditingValue(
        text: ai.model,
        selection: TextSelection.collapsed(offset: ai.model.length),
      );
    }
    if (_apiTokenController.text != ai.apiToken) {
      _apiTokenController.value = TextEditingValue(
        text: ai.apiToken,
        selection: TextSelection.collapsed(offset: ai.apiToken.length),
      );
    }
    if (_customHeadersController.text != ai.customHeaders) {
      _customHeadersController.value = TextEditingValue(
        text: ai.customHeaders,
        selection: TextSelection.collapsed(offset: ai.customHeaders.length),
      );
    }
    if (_httpProxyController.text != ai.httpProxy) {
      _httpProxyController.value = TextEditingValue(
        text: ai.httpProxy,
        selection: TextSelection.collapsed(offset: ai.httpProxy.length),
      );
    }
    if (_httpsProxyController.text != ai.httpsProxy) {
      _httpsProxyController.value = TextEditingValue(
        text: ai.httpsProxy,
        selection: TextSelection.collapsed(offset: ai.httpsProxy.length),
      );
    }
    if (_customPromptController.text != ai.customPrompt) {
      _customPromptController.value = TextEditingValue(
        text: ai.customPrompt,
        selection: TextSelection.collapsed(offset: ai.customPrompt.length),
      );
    }
    if (oldAi.provider != ai.provider ||
        oldAi.baseUrl != ai.baseUrl ||
        oldAi.apiToken != ai.apiToken) {
      _models = const [];
      _modelStatus = null;
      _testStatus = null;
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiTokenController.dispose();
    _customHeadersController.dispose();
    _httpProxyController.dispose();
    _httpsProxyController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  AiSettings _effectiveAiSettings() => widget.settings.ai.copyWith(
    baseUrl: _baseUrlController.text.trim(),
    model: _modelController.text.trim(),
    apiToken: _apiTokenController.text,
    customHeaders: _customHeadersController.text,
    httpProxy: _httpProxyController.text,
    httpsProxy: _httpsProxyController.text,
    customPrompt: _customPromptController.text,
  );

  Future<void> _loadModels() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loadingModels = true;
      _modelStatus = null;
    });
    try {
      final models = await ref
          .read(aiChatServiceProvider)
          .listModels(_effectiveAiSettings());
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelStatus = '${models.length}개 모델을 불러왔습니다.';
        _modelStatusOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _modelStatus = e.toString();
        _modelStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _testConnection() async {
    FocusManager.instance.primaryFocus?.unfocus();
    ref
        .read(appSettingsProvider.notifier)
        .setAiModel(_modelController.text.trim());
    setState(() {
      _testingConnection = true;
      _testStatus = null;
    });
    try {
      final result = await ref
          .read(aiChatServiceProvider)
          .testConnection(_effectiveAiSettings());
      if (!mounted) return;
      setState(() {
        _testStatus = result;
        _testStatusOk = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = e.toString();
        _testStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  void _selectModel(String model) {
    _modelController.value = TextEditingValue(
      text: model,
      selection: TextSelection.collapsed(offset: model.length),
    );
    ref.read(appSettingsProvider.notifier).setAiModel(model);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(appSettingsProvider.notifier);
    final ai = widget.settings.ai;
    final apiTokenLabel = ai.provider.requiresApiToken
        ? 'API token'
        : 'API token (선택)';
    final apiTokenHint = ai.provider.requiresApiToken
        ? 'sk-...'
        : '비워두면 Authorization 헤더를 보내지 않음';
    final selectedLoadedModel = _models.contains(_modelController.text.trim())
        ? _modelController.text.trim()
        : null;
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: 'AI 연결',
          description: 'Provider, endpoint, token, model을 연결 테스트 순서에 맞게 설정합니다.',
          children: [
            DropdownButtonFormField<AiProviderType>(
              initialValue: ai.provider,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Provider'),
              selectedItemBuilder: (context) => [
                for (final provider in AiProviderType.values)
                  Text(provider.label, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final provider in AiProviderType.values)
                  DropdownMenuItem(
                    value: provider,
                    child: Text(
                      '${provider.label} - ${provider.description}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setAiProvider(value);
              },
            ),
            const SizedBox(height: 12),
            if (ai.provider.needsBaseUrl) ...[
              TextFormField(
                key: const ValueKey('ai-base-url-field'),
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.example.com/v1',
                  prefixIcon: Icon(Icons.http),
                ),
                keyboardType: TextInputType.url,
                onChanged: controller.setAiBaseUrl,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              key: const ValueKey('ai-api-token-field'),
              controller: _apiTokenController,
              decoration: InputDecoration(
                labelText: apiTokenLabel,
                hintText: apiTokenHint,
                prefixIcon: const Icon(Icons.key),
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: controller.setAiApiToken,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ai-model-field'),
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'gpt-4.1-mini',
                prefixIcon: Icon(Icons.memory_outlined),
              ),
              onChanged: controller.setAiModel,
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'loaded-model-${_models.length}-$selectedLoadedModel',
                ),
                initialValue: selectedLoadedModel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '불러온 모델',
                  prefixIcon: Icon(Icons.view_list_outlined),
                ),
                hint: const Text('목록에서 모델 선택'),
                items: [
                  for (final model in _models)
                    DropdownMenuItem(
                      value: model,
                      child: Text(model, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _selectModel(value);
                },
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _loadingModels ? null : _loadModels,
                  icon: _loadingModels
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: const Text('모델 목록 불러오기'),
                ),
                OutlinedButton.icon(
                  onPressed: _testingConnection ? null : _testConnection,
                  icon: _testingConnection
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_outlined),
                  label: const Text('연결 테스트'),
                ),
              ],
            ),
            if (_modelStatus != null) ...[
              const SizedBox(height: 8),
              _AsyncStatusText(message: _modelStatus!, success: _modelStatusOk),
            ],
            if (_testStatus != null) ...[
              const SizedBox(height: 8),
              _AsyncStatusText(message: _testStatus!, success: _testStatusOk),
            ],
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: '고급 네트워크',
          description: '사내 게이트웨이 헤더와 프록시를 AI HTTP 요청에 적용합니다.',
          children: [
            TextFormField(
              key: const ValueKey('ai-custom-headers-field'),
              controller: _customHeadersController,
              decoration: const InputDecoration(
                labelText: 'Custom headers',
                hintText:
                    'X-Workspace: dev\nX-Gateway-Key: value\n{"X-Team":"dev"}',
                prefixIcon: Icon(Icons.short_text_outlined),
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 6,
              onChanged: controller.setAiCustomHeaders,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ai-http-proxy-field'),
              controller: _httpProxyController,
              decoration: const InputDecoration(
                labelText: 'http_proxy',
                hintText: 'http://127.0.0.1:8080',
                prefixIcon: Icon(Icons.settings_ethernet_outlined),
              ),
              keyboardType: TextInputType.url,
              onChanged: controller.setAiHttpProxy,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ai-https-proxy-field'),
              controller: _httpsProxyController,
              decoration: const InputDecoration(
                labelText: 'https_proxy',
                hintText: 'http://127.0.0.1:8080',
                prefixIcon: Icon(Icons.settings_ethernet_outlined),
              ),
              keyboardType: TextInputType.url,
              onChanged: controller.setAiHttpsProxy,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: 'AI Chat 동작',
          description: '터미널 컨텍스트 범위와 시스템 프롬프트를 조정합니다.',
          children: [
            _SliderSetting(
              label: '터미널 컨텍스트',
              value: ai.maxContextLines.toDouble(),
              min: AiSettings.minContextLines.toDouble(),
              max: AiSettings.maxContextLineLimit.toDouble(),
              divisions:
                  (AiSettings.maxContextLineLimit -
                      AiSettings.minContextLines) ~/
                  50,
              valueLabel: '${ai.maxContextLines}줄',
              onChanged: (value) =>
                  controller.setAiMaxContextLines(value.round()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ai-custom-prompt-field'),
              controller: _customPromptController,
              decoration: const InputDecoration(
                labelText: '사용자 정의 프롬프트',
                hintText: '예: 답변은 항상 체크리스트로 정리해줘.',
                alignLabelWithHint: true,
              ),
              minLines: 4,
              maxLines: 7,
              onChanged: controller.setAiCustomPrompt,
            ),
            const SizedBox(height: 12),
            const Text(
              'AI Chat은 명령을 직접 실행하지 않고, 현재 터미널 버퍼를 읽어 해석과 다음 행동 제안을 제공합니다.',
              style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          title: 'AI Chat 표시',
          description: '표, 코드, 긴 답변을 읽기 위한 텍스트 렌더링 설정입니다.',
          children: [
            DropdownButtonFormField<String>(
              initialValue: ai.chatFontFamily,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'AI Chat 글꼴'),
              selectedItemBuilder: (context) => [
                for (final font in AppSettings.fontFamilies)
                  Text(font, overflow: TextOverflow.ellipsis),
              ],
              items: [
                for (final font in AppSettings.fontFamilies)
                  DropdownMenuItem(
                    value: font,
                    child: Text(font, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setAiChatFontFamily(value);
              },
            ),
            const SizedBox(height: 18),
            _SliderSetting(
              label: 'AI Chat 글자 크기',
              value: ai.chatFontSize,
              min: AiSettings.minChatFontSize,
              max: AiSettings.maxChatFontSize,
              divisions:
                  (AiSettings.maxChatFontSize - AiSettings.minChatFontSize)
                      .round(),
              valueLabel: ai.chatFontSize.toStringAsFixed(0),
              onChanged: controller.setAiChatFontSize,
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutSettingsTab extends ConsumerStatefulWidget {
  const _AboutSettingsTab();

  @override
  ConsumerState<_AboutSettingsTab> createState() => _AboutSettingsTabState();
}

class _AboutSettingsTabState extends ConsumerState<_AboutSettingsTab> {
  bool _checking = false;
  String? _status;
  bool _statusOk = true;

  void _openLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'Vibe Terminal',
      applicationVersion: appVersionLabel(kAppVersion, kAppBuildNumber),
      applicationLegalese: 'Copyright 2026 Vibe Terminal contributors',
      useRootNavigator: true,
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final result = await ref.read(updateCheckerProvider).check(kAppVersion);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _status = '업데이트 정보를 확인하지 못했습니다.';
          _statusOk = false;
        });
        return;
      }
      if (!result.updateAvailable) {
        setState(() {
          _status = '현재 최신 정식 버전입니다. (v${result.currentVersion})';
          _statusOk = true;
        });
        return;
      }
      final release = result.latestRelease;
      setState(() {
        _status = '새 정식 버전 v${release.version}이 있습니다.';
        _statusOk = true;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('업데이트가 있습니다'),
          content: Text(
            '현재 v${result.currentVersion}에서 v${release.version}로 업데이트할 수 있습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(externalUrlLauncherProvider)(release.htmlUrl);
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('릴리즈 열기'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = ref.watch(buildFeaturesProvider);
    return _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '앱 정보',
          description: '출시 빌드와 법적 고지입니다.',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.terminal, color: VibeColors.accent),
              title: const Text('Vibe Terminal'),
              subtitle: Text(
                'v${appVersionLabel(kAppVersion, kAppBuildNumber)}',
              ),
            ),
            if (features.github) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _checking
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.system_update_alt,
                        color: VibeColors.accent,
                      ),
                title: const Text('업데이트 확인'),
                subtitle: Text(_status ?? 'GitHub Releases에서 최신 정식 버전을 확인합니다.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _checking ? null : _checkForUpdates,
              ),
              if (_status != null)
                _AsyncStatusText(message: _status!, success: _statusOk),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.article_outlined,
                color: VibeColors.accent,
              ),
              title: const Text('오픈소스 라이선스'),
              subtitle: const Text('사용 중인 Flutter 및 패키지 라이선스 고지'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLicenses(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _AsyncStatusText extends StatelessWidget {
  const _AsyncStatusText({required this.message, required this.success});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          color: success ? VibeColors.statusConnected : VibeColors.statusError,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: success
                  ? VibeColors.statusConnected
                  : VibeColors.statusError,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTabScroll extends StatelessWidget {
  const _SettingsTabScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
      children: children,
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: VibeColors.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: VibeColors.onSurface)),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ShortcutBindingField extends StatefulWidget {
  const _ShortcutBindingField({
    required this.actionId,
    required this.label,
    required this.bindings,
    required this.defaultBindings,
    required this.onChanged,
  });

  final String actionId;
  final String label;
  final List<String> bindings;
  final List<String> defaultBindings;
  final void Function(String actionId, List<String> bindings) onChanged;

  @override
  State<_ShortcutBindingField> createState() => _ShortcutBindingFieldState();
}

class _ShortcutBindingFieldState extends State<_ShortcutBindingField> {
  late final FocusNode _focusNode;
  bool _capturing = false;
  bool _appendCapture = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'shortcut-${widget.actionId}');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startCapture({required bool append}) {
    setState(() {
      _capturing = true;
      _appendCapture = append;
    });
    _focusNode.requestFocus();
  }

  void _stopCapture() {
    setState(() {
      _capturing = false;
      _appendCapture = false;
    });
  }

  void _commitBinding(String binding) {
    final next = _appendCapture
        ? [
            for (final item in widget.bindings)
              if (item != binding) item,
            binding,
          ]
        : [binding];
    widget.onChanged(widget.actionId, List.unmodifiable(next));
    _stopCapture();
  }

  void _removeBinding(String binding) {
    final next = [
      for (final item in widget.bindings)
        if (item != binding) item,
    ];
    widget.onChanged(
      widget.actionId,
      next.isEmpty ? widget.defaultBindings : List.unmodifiable(next),
    );
  }

  KeyEventResult _handleCaptureKey(FocusNode node, KeyEvent event) {
    if (!_capturing) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;

    final binding = shortcutBindingFromKeyEvent(event);
    if (binding == null) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('지원하지 않는 단축키입니다. 다른 키 조합을 누르세요.')),
        );
      }
      return KeyEventResult.handled;
    }

    _commitBinding(binding);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _capturing ? VibeColors.accent : VibeColors.borderSoft;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleCaptureKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.label,
                    style: const TextStyle(color: VibeColors.onSurface),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final binding in widget.bindings)
                          InputChip(
                            label: Text(
                              binding,
                              style: const TextStyle(
                                fontFamily: kMonoFontFamily,
                                fontFamilyFallback: kMonoFontFallback,
                                fontSize: 12,
                              ),
                            ),
                            onDeleted: widget.bindings.length > 1
                                ? () => _removeBinding(binding)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _startCapture(append: false),
                          icon: const Icon(Icons.keyboard, size: 16),
                          label: Text(
                            _capturing && !_appendCapture ? '키를 누르세요' : '교체',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _startCapture(append: true),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            _capturing && _appendCapture ? '추가할 키를 누르세요' : '추가',
                          ),
                        ),
                        IconButton(
                          tooltip: '기본값 복원',
                          onPressed: () => widget.onChanged(
                            widget.actionId,
                            widget.defaultBindings,
                          ),
                          icon: const Icon(Icons.restart_alt, size: 18),
                        ),
                        if (_capturing)
                          TextButton(
                            onPressed: _stopCapture,
                            child: const Text('취소'),
                          ),
                      ],
                    ),
                    if (_capturing) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '원하는 키 조합을 누르면 바로 저장됩니다. 예: Ctrl+Tab, Ctrl+Enter',
                        style: TextStyle(
                          color: VibeColors.onSurfaceDim,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.action, required this.keys});

  final String action;
  final String keys;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              action,
              style: const TextStyle(color: VibeColors.onSurface),
            ),
          ),
          Expanded(
            child: Text(
              keys,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoVisibleSettingsTab extends StatelessWidget {
  const _NoVisibleSettingsTab();

  @override
  Widget build(BuildContext context) {
    return const _SettingsTabScroll(
      children: [
        _SettingsSection(
          title: '표시 가능한 설정 없음',
          description: '현재 build-env에서 설정 탭이 비활성화되어 있어 설정 탭이 표시되지 않습니다.',
          children: [
            Text(
              'SETTINGS_* 플래그를 enable로 변경하면 해당 탭이 다시 노출됩니다.',
              style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}
