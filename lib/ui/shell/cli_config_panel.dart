import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../cli_config/cli_config_home.dart';
import '../../cli_config/cli_installation_provider.dart';
import '../../cli_config/wsl_cli_config_home.dart';
import '../../session/session.dart';
import '../../state/providers.dart';

/// 우측 패널: 코딩 에이전트 CLI(Claude Code, Codex, OpenCode)의 전역 설정과
/// 확장(지침·스킬·커맨드·에이전트 등)을 한곳에서 보고 편집한다.
/// 개요(섹션 목록) → 섹션(파일 목록) → 편집기 순으로 들어간다.
class CliConfigPanel extends ConsumerStatefulWidget {
  const CliConfigPanel({
    super.key,
    required this.app,
    this.home,
    this.wslHomeLoader,
    this.wslAvailable,
    this.installedApps,
  });

  final CliConfigApp app;

  /// 테스트나 다른 홈 경로를 쓸 때 주입한다. null이면 환경변수로 결정한다.
  final CliConfigHome? home;

  /// WSL 배포판 안의 홈을 찾는 함수. null이면 [WslCliConfigLocator]를 쓴다.
  final Future<CliConfigHome> Function(CliConfigApp app)? wslHomeLoader;

  /// WSL 전환 아이콘을 보일지. null이면 Windows에 wsl.exe가 있을 때만 보인다.
  final bool? wslAvailable;

  /// 로컬에 설치된 것으로 감지된 CLI 목록. null이면
  /// [installedCliAppsProvider]를 쓴다(테스트 오버라이드용).
  final Set<CliConfigApp>? installedApps;

  @override
  ConsumerState<CliConfigPanel> createState() => _CliConfigPanelState();
}

class _CliConfigPanelState extends ConsumerState<CliConfigPanel> {
  late final CliConfigHome? _nativeHome =
      widget.home ?? CliConfigHome.fromEnvironment(widget.app);
  late final bool _wslAvailable =
      widget.wslAvailable ?? WslCliConfigLocator.isAvailable;

  /// WSL로 전환하면 이 홈을 쓴다. 찾는 중이면 [_wslLoading], 실패하면
  /// [_wslError]가 채워진다. 한 번 찾은 홈은 패널이 살아 있는 동안 재사용한다.
  CliConfigHome? _wslHome;
  bool _useWsl = false;
  bool _wslLoading = false;
  String? _wslError;

  /// Remote(현재 활성 SSH 세션) 소스를 보고 있는지. true면 [_RemoteCliConfigBody]가
  /// 자기 상태를 스스로 관리하므로 아래 local/WSL 필드들은 쓰지 않는다.
  bool _useRemote = false;

  CliConfigSection? _section;
  CliConfigEntry? _entry;
  List<CliConfigEntry> _entries = const [];
  Map<CliConfigSection, int> _counts = const {};
  String? _error;

  CliConfigHome? get _home => _useWsl ? _wslHome : _nativeHome;

  _CliSource get _source => _useRemote
      ? _CliSource.remote
      : (_useWsl ? _CliSource.wsl : _CliSource.local);

  @override
  void initState() {
    super.initState();
    _reloadCounts();
  }

  Future<void> _selectSource(_CliSource target) async {
    if (target == _source) return;
    setState(() {
      _useRemote = target == _CliSource.remote;
      _useWsl = target == _CliSource.wsl;
      _section = null;
      _entry = null;
      _entries = const [];
      _counts = const {};
      _error = null;
    });
    if (target == _CliSource.remote) return;
    if (target == _CliSource.wsl) {
      if (_wslHome != null) {
        _reloadCounts();
      } else {
        await _loadWslHome();
      }
      return;
    }
    _reloadCounts();
  }

  Future<void> _loadWslHome() async {
    setState(() {
      _wslLoading = true;
      _wslError = null;
    });
    final loader = widget.wslHomeLoader ?? WslCliConfigLocator().locate;
    try {
      final home = await loader(widget.app);
      if (!mounted) return;
      _wslHome = home;
      _wslLoading = false;
      _reloadCounts();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _wslLoading = false;
        _wslError = error is WslCliConfigException
            ? error.message
            : 'WSL 설정을 찾지 못했습니다: $error';
      });
    }
  }

  void _reloadCounts() {
    final home = _home;
    if (home == null) return;
    try {
      _counts = {
        for (final section in widget.app.sections)
          section: home.countEntries(section),
      };
      _error = null;
    } catch (error) {
      _error = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _reloadEntries() {
    final home = _home;
    final section = _section;
    if (home == null || section == null) return;
    try {
      _entries = home.listEntries(section);
      _error = null;
    } catch (error) {
      _entries = const [];
      _error = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _openSection(CliConfigSection section) {
    final home = _home;
    if (home == null) return;
    setState(() {
      _section = section;
      _entry = section.isDirectory ? null : home.fileEntry(section);
    });
    if (section.isDirectory) _reloadEntries();
  }

  void _openEntry(CliConfigEntry entry) {
    setState(() => _entry = entry);
  }

  void _back() {
    setState(() {
      if (_entry != null && _section?.isDirectory == true) {
        _entry = null;
      } else {
        _entry = null;
        _section = null;
      }
    });
    if (_section != null) {
      _reloadEntries();
    } else {
      _reloadCounts();
    }
  }

  Future<void> _createEntry() async {
    final home = _home;
    final section = _section;
    if (home == null || section == null || !section.isDirectory) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewEntryDialog(section: section),
    );
    if (name == null || !mounted) return;
    try {
      final entry = home.create(section, name);
      _reloadEntries();
      _openEntry(entry);
    } catch (error) {
      _showMessage(error is FormatException ? error.message : '$error');
    }
  }

  Future<void> _deleteEntry(CliConfigEntry entry) async {
    final home = _home;
    if (home == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text('${entry.name} 파일을 삭제할까요?\n되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const ValueKey('cli-config-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      home.delete(entry);
      if (_entry == entry) _entry = null;
      _reloadEntries();
      _showMessage('${entry.name} 을(를) 삭제했습니다.');
    } catch (error) {
      _showMessage('삭제 실패: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _showMessage('경로를 복사했습니다');
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final sessions = ref.watch(sessionManagerProvider);
    SessionInfo? activeSession;
    for (final session in sessions) {
      if (session.id == activeSessionId) {
        activeSession = session;
        break;
      }
    }
    final remoteAvailable =
        activeSession != null && !activeSession.host.isLocalShell;
    final sourceSelector = (_wslAvailable || remoteAvailable)
        ? _CliSourceSelector(
            source: _source,
            wslEnabled: _wslAvailable && !_wslLoading,
            remoteEnabled: remoteAvailable,
            onChanged: (source) => unawaited(_selectSource(source)),
          )
        : null;
    // 설치 감지는 로컬 PATH 기준이라 아직 로딩 중일 수 있다. 로딩 중에는
    // 잠깐 "미설치" 화면이 깜빡이지 않도록 결과가 도착할 때까지 기다린다.
    final installedApps =
        widget.installedApps ??
        ref.watch(installedCliAppsProvider).asData?.value;
    final notInstalledNative =
        !_useWsl &&
        !_useRemote &&
        home != null &&
        installedApps != null &&
        !installedApps.contains(widget.app);
    final body = _useRemote
        ? const Center(
            key: ValueKey('cli-config-remote-pro-only'),
            child: Text('Remote 설정은 Pro 에디션에서 제공합니다.'),
          )
        : home == null
        ? _MissingHome(
            app: widget.app,
            wsl: _useWsl,
            loading: _wslLoading,
            message: _useWsl ? _wslError : null,
            onRetry: _useWsl && !_wslLoading ? _loadWslHome : null,
          )
        : notInstalledNative
        ? _NotInstalled(app: widget.app, wslAvailable: _wslAvailable)
        : _entry != null
        ? _CliFileEditor(
            key: ValueKey('cli-config-editor:${_entry!.path}'),
            onRead: (entry) => SynchronousFuture(home.read(entry)),
            initialContentFor: home.initialContentFor,
            onWrite: (entry, contents) {
              home.write(entry, contents);
              return SynchronousFuture(null);
            },
            entry: _entry!,
            onBack: _back,
            onCopyPath: _copyPath,
          )
        : _section != null
        ? _SectionView(
            home: home,
            section: _section!,
            entries: _entries,
            error: _error,
            onBack: _back,
            onRefresh: _reloadEntries,
            onCopyPath: _copyPath,
            onOpen: _openEntry,
            onCreate: _createEntry,
            onDelete: _deleteEntry,
          )
        : _OverviewView(
            home: home,
            wsl: _useWsl,
            counts: _counts,
            error: _error,
            onRefresh: _reloadCounts,
            onCopyPath: _copyPath,
            onOpen: _openSection,
          );
    return Material(
      color: VibeColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sourceSelector != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: sourceSelector,
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// 홈을 찾지 못했거나(환경변수 없음, WSL 실패) WSL 홈을 찾는 중일 때의 화면.
/// 헤더는 그대로 두어 WSL ↔ Windows 전환은 언제나 가능하게 한다.
class _MissingHome extends StatelessWidget {
  const _MissingHome({
    required this.app,
    required this.wsl,
    required this.loading,
    required this.message,
    required this.onRetry,
  });

  final CliConfigApp app;
  final bool wsl;
  final bool loading;

  /// WSL 실패 사유. null이면 환경변수 안내를 보여 준다.
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: appIconFor(app),
          title: _appTitle(app, wsl: wsl),
          subtitle: loading ? 'WSL 홈 디렉터리를 찾는 중…' : '—',
        ),
        Expanded(
          child: loading
              ? const Center(
                  key: ValueKey('cli-config-wsl-loading'),
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message ??
                            '${app.title} 홈 디렉터리를 찾지 못했습니다. '
                                '${app.rootEnvironmentHint} 환경변수를 확인하세요.',
                        key: const ValueKey('cli-config-missing-home'),
                        style: const TextStyle(
                          color: VibeColors.onSurfaceMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      if (onRetry != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('cli-config-wsl-retry'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('다시 시도'),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

String _appTitle(CliConfigApp app, {required bool wsl}) =>
    wsl ? '${app.title} (WSL)' : app.title;

/// PATH에서 CLI 실행 파일을 찾지 못했을 때 보여주는 안내 화면. 설정 파일
/// 편집 UI 대신 설치 여부와 설치 방법을 명확히 알려, 빈 화면이나 오류로
/// 오인하지 않게 한다.
class _NotInstalled extends StatelessWidget {
  const _NotInstalled({required this.app, required this.wslAvailable});

  final CliConfigApp app;
  final bool wslAvailable;

  String get _installHint => switch (app) {
    CliConfigApp.claude => 'npm install -g @anthropic-ai/claude-code',
    CliConfigApp.codex => 'npm install -g @openai/codex',
    CliConfigApp.opencode => 'npm install -g opencode-ai',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: appIconFor(app),
          title: app.title,
          subtitle: '설치되지 않음',
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${app.title}가 설치되지 않아 사용할 수 없습니다.',
                  key: const ValueKey('cli-config-not-installed'),
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'PATH에서 실행 파일을 찾지 못했습니다. 설치한 뒤 이 패널을 다시 열면 '
                  '자동으로 인식됩니다.',
                  style: TextStyle(
                    color: VibeColors.onSurfaceMuted,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: VibeColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    _installHint,
                    style: const TextStyle(
                      color: VibeColors.onSurface,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                if (wslAvailable) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Windows라면 WSL 배포판 안에 설치되어 있을 수 있습니다. '
                    '위의 소스 선택기에서 WSL로 전환해 확인하세요.',
                    style: TextStyle(
                      color: VibeColors.onSurfaceMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Windows 홈과 WSL 배포판 홈 사이를 오가는 토글. 선택되면 accent 색으로 채워
/// 지금 WSL 쪽을 보고 있음을 드러낸다.
enum _CliSource { local, wsl, remote }

/// Local/WSL/Remote 중 어느 소스를 보고 있는지 고르는 3단 선택기. WSL은
/// wsl.exe가 있을 때만, Remote는 활성 세션이 SSH일 때만 켜진다(숨기지 않고
/// 항상 세 값을 보여준 채 비활성화한다).
class _CliSourceSelector extends StatelessWidget {
  const _CliSourceSelector({
    required this.source,
    required this.wslEnabled,
    required this.remoteEnabled,
    required this.onChanged,
  });

  final _CliSource source;
  final bool wslEnabled;
  final bool remoteEnabled;
  final ValueChanged<_CliSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_CliSource>(
      key: const ValueKey('cli-config-source-selector'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        const ButtonSegment(value: _CliSource.local, label: Text('Local')),
        ButtonSegment(
          value: _CliSource.wsl,
          label: const Text('WSL'),
          enabled: wslEnabled,
        ),
        ButtonSegment(
          value: _CliSource.remote,
          label: const Text('Remote'),
          enabled: remoteEnabled,
        ),
      ],
      selected: {source},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

// ---------------------------------------------------------------------------
// 아이콘
// ---------------------------------------------------------------------------

IconData appIconFor(CliConfigApp app) => switch (app) {
  CliConfigApp.claude => Icons.tune,
  CliConfigApp.codex => Icons.data_object,
  CliConfigApp.opencode => Icons.developer_mode,
};

IconData _sectionIcon(CliConfigSection section) => switch (section.id) {
  'settings' || 'config' => Icons.tune,
  'memory' || 'instructions' => Icons.psychology_outlined,
  'rules' => Icons.rule,
  'commands' || 'prompts' => Icons.terminal,
  'skills' => Icons.auto_awesome,
  'agents' => Icons.smart_toy_outlined,
  'keybindings' => Icons.keyboard,
  'plugins' => Icons.extension_outlined,
  'tools' => Icons.handyman_outlined,
  'themes' => Icons.palette_outlined,
  _ => Icons.folder_outlined,
};

// ---------------------------------------------------------------------------
// 공통 헤더
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const ValueKey('cli-config-back'),
              tooltip: '뒤로',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(icon, color: VibeColors.accent, size: 20),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        message,
        style: const TextStyle(color: VibeColors.statusError, fontSize: 12),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 개요: 섹션 목록
// ---------------------------------------------------------------------------

class _OverviewView extends StatelessWidget {
  const _OverviewView({
    required this.home,
    required this.wsl,
    required this.counts,
    required this.error,
    required this.onRefresh,
    required this.onCopyPath,
    required this.onOpen,
  });

  final CliConfigHome home;
  final bool wsl;
  final Map<CliConfigSection, int> counts;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<String> onCopyPath;
  final ValueChanged<CliConfigSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: appIconFor(home.app),
          title: _appTitle(home.app, wsl: wsl),
          subtitle: home.rootPath,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => onCopyPath(home.rootPath),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '새로고침',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        if (error != null) _ErrorNote(error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              for (final section in home.app.sections)
                _SectionTile(
                  section: section,
                  count: counts[section],
                  onTap: () => onOpen(section),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.count,
    required this.onTap,
  });

  final CliConfigSection section;
  final int? count;
  final VoidCallback onTap;

  String get _countLabel {
    final n = count;
    if (n == null) return '';
    if (!section.isDirectory) return n > 0 ? '있음' : '없음';
    return '$n개';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('cli-config-section-${section.id}'),
      color: VibeColors.surfaceHigh,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: VibeColors.borderSoft),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          _sectionIcon(section),
          color: VibeColors.accent,
          size: 20,
        ),
        title: Text(
          section.title,
          style: const TextStyle(
            color: VibeColors.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          section.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _countLabel,
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: VibeColors.onSurfaceDim,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 섹션: 파일 목록
// ---------------------------------------------------------------------------

class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.home,
    required this.section,
    required this.entries,
    required this.error,
    required this.onBack,
    required this.onRefresh,
    required this.onCopyPath,
    required this.onOpen,
    required this.onCreate,
    required this.onDelete,
  });

  final CliConfigHome home;
  final CliConfigSection section;
  final List<CliConfigEntry> entries;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<String> onCopyPath;
  final ValueChanged<CliConfigEntry> onOpen;
  final VoidCallback onCreate;
  final ValueChanged<CliConfigEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final path = home.sectionPath(section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: _sectionIcon(section),
          title: section.title,
          subtitle: path,
          onBack: onBack,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => onCopyPath(path),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '새로고침',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.summary,
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('cli-config-new-entry'),
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 16),
                label: Text(section.skillLayout ? '새 스킬' : '새 파일'),
              ),
            ],
          ),
        ),
        if (error != null) _ErrorNote(error!),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    '아직 항목이 없습니다.',
                    style: TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _EntryTile(
                      entry: entry,
                      onTap: () => onOpen(entry),
                      onDelete: () => onDelete(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap, this.onDelete});

  final CliConfigEntry entry;
  final VoidCallback onTap;

  /// null이면 삭제 버튼을 감춘다(예: Remote 소스는 삭제를 지원하지 않는다).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final description = entry.description;
    return ListTile(
      key: ValueKey('cli-config-entry:${entry.name}'),
      dense: true,
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 12, right: 4),
      leading: Icon(
        entry.isSkillManifest
            ? Icons.auto_awesome
            : entry.isJson
            ? Icons.data_object
            : Icons.description_outlined,
        color: entry.isSkillManifest
            ? VibeColors.accent
            : VibeColors.onSurfaceMuted,
        size: 18,
      ),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: VibeColors.onSurface,
          fontFamily: kMonoFontFamily,
          fontFamilyFallback: kMonoFontFallback,
          fontSize: 12.5,
        ),
      ),
      subtitle: description == null
          ? null
          : Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 11,
              ),
            ),
      trailing: onDelete == null
          ? null
          : IconButton(
              key: ValueKey('cli-config-delete:${entry.name}'),
              tooltip: '삭제',
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: VibeColors.onSurfaceDim,
              ),
            ),
    );
  }
}

class _NewEntryDialog extends StatefulWidget {
  const _NewEntryDialog({required this.section});

  final CliConfigSection section;

  @override
  State<_NewEntryDialog> createState() => _NewEntryDialogState();
}

class _NewEntryDialogState extends State<_NewEntryDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      CliConfigHome.normalizeNewEntryName(widget.section, _controller.text);
      Navigator.of(context).pop(_controller.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return AlertDialog(
      title: Text(section.skillLayout ? '새 스킬' : '새 ${section.title} 파일'),
      content: TextField(
        key: const ValueKey('cli-config-new-entry-name'),
        controller: _controller,
        autofocus: true,
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '이름',
          hintText: section.nameHint,
          helperText: section.skillLayout
              ? '이름/SKILL.md 가 만들어집니다.'
              : '확장자를 생략하면 ${section.defaultExtension} 가 붙습니다. '
                    '하위 폴더는 / 로 구분합니다.',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const ValueKey('cli-config-new-entry-submit'),
          onPressed: _submit,
          child: const Text('만들기'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 편집기
// ---------------------------------------------------------------------------

class _CliFileEditor extends StatefulWidget {
  const _CliFileEditor({
    super.key,
    required this.onRead,
    required this.initialContentFor,
    required this.onWrite,
    required this.entry,
    required this.onBack,
    required this.onCopyPath,
  });

  /// Local/WSL은 [SynchronousFuture]로 감싼 동기 파일 IO, Remote는 SFTP로
  /// 실제 네트워크를 타는 비동기 읽기/쓰기다. 편집기는 그 차이를 모른다.
  final Future<String> Function(CliConfigEntry entry) onRead;
  final String Function(CliConfigSection section) initialContentFor;
  final Future<void> Function(CliConfigEntry entry, String contents) onWrite;
  final CliConfigEntry entry;
  final VoidCallback onBack;
  final ValueChanged<String> onCopyPath;

  @override
  State<_CliFileEditor> createState() => _CliFileEditorState();
}

class _CliFileEditorState extends State<_CliFileEditor> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  bool _saving = false;
  bool _dirty = false;
  bool _valid = true;
  bool _exists = false;
  String? _status;
  bool _statusOk = true;

  bool get _isJson => widget.entry.isJson;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entry = widget.entry;
      final text = await widget.onRead(entry);
      _exists = text.isNotEmpty || entry.exists;
      final content = text.isEmpty && !entry.exists
          ? widget.initialContentFor(entry.section)
          : text;
      final validation = _isJson ? JsonObjectValidation.of(content) : null;
      _controller.text = content;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _valid = validation?.valid ?? true;
      _dirty = false;
      _statusOk = _valid;
      _status = !_exists
          ? '파일이 없습니다. 저장하면 새로 생성됩니다.'
          : validation?.message ?? '${_controller.text.length}자';
    } catch (error) {
      _valid = false;
      _statusOk = false;
      _status = '읽기 실패: $error';
    }
    if (mounted) setState(() {});
  }

  void _onChanged(String value) {
    final validation = _isJson ? JsonObjectValidation.of(value) : null;
    setState(() {
      _dirty = true;
      _valid = validation?.valid ?? true;
      _statusOk = _valid;
      _status = validation?.message ?? '저장하지 않은 변경이 있습니다.';
    });
  }

  Future<void> _save() async {
    if (_isJson) {
      final validation = JsonObjectValidation.of(_controller.text);
      if (!validation.valid) {
        setState(() {
          _valid = false;
          _statusOk = false;
          _status = validation.message;
        });
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.onWrite(widget.entry, _controller.text);
      _exists = true;
      _dirty = false;
      _statusOk = true;
      _status = '저장했습니다.';
    } catch (error) {
      _statusOk = false;
      _status = '저장 실패: $error';
    }
    _saving = false;
    if (mounted) setState(() {});
  }

  void _formatJson() {
    final validation = JsonObjectValidation.of(_controller.text);
    if (!validation.valid) {
      setState(() {
        _valid = false;
        _statusOk = false;
        _status = validation.message;
      });
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    final formatted = '${encoder.convert(validation.value)}\n';
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() {
      _dirty = true;
      _valid = true;
      _statusOk = true;
      _status = 'JSON 형식을 정리했습니다.';
    });
  }

  Future<void> _back() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('저장하지 않은 변경'),
          content: const Text('변경 내용을 버리고 나갈까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('계속 편집'),
            ),
            FilledButton(
              key: const ValueKey('cli-config-discard-confirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('버리기'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          icon: _sectionIcon(entry.section),
          title: entry.section.isDirectory ? entry.name : entry.section.title,
          subtitle: entry.path,
          onBack: _back,
          actions: [
            IconButton(
              tooltip: '경로 복사',
              onPressed: () => widget.onCopyPath(entry.path),
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: '다시 읽기',
              onPressed: _saving ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _ValidationBanner(
            valid: _valid,
            ok: _statusOk,
            message: _status ?? '편집하세요.',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              key: const ValueKey('cli-config-editor-field'),
              controller: _controller,
              scrollController: _scrollController,
              onChanged: _onChanged,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 12.5,
                height: 1.38,
              ),
              decoration: InputDecoration(
                hintText: _isJson ? '{\n  "permissions": {}\n}' : '# 제목',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              if (_isJson) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _formatJson,
                    icon: const Icon(Icons.auto_fix_high, size: 17),
                    label: const Text('Format'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('cli-config-save'),
                  onPressed: _saving || !_valid || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 17),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ValidationBanner extends StatelessWidget {
  const _ValidationBanner({
    required this.valid,
    required this.ok,
    required this.message,
  });

  final bool valid;
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = valid && ok
        ? VibeColors.statusConnected
        : valid
        ? VibeColors.warning
        : VibeColors.statusError;
    final icon = valid && ok
        ? Icons.check_circle_outline
        : valid
        ? Icons.info_outline
        : Icons.error_outline;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
