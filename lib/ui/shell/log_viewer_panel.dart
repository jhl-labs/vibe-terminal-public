import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../data/models/session_log.dart';
import '../../data/repositories/session_log_repository.dart';
import '../../state/providers.dart';

/// 로그 파일 공유 동작. 테스트에서 공유 실패 경로를 재현할 때 바꿔 끼운다.
typedef LogShareHandler = Future<void> Function(SessionLog log);

class LogViewerPanel extends ConsumerStatefulWidget {
  const LogViewerPanel({super.key, this.shareHandler});

  final LogShareHandler? shareHandler;

  @override
  ConsumerState<LogViewerPanel> createState() => _LogViewerPanelState();
}

class _LogViewerPanelState extends ConsumerState<LogViewerPanel> {
  static const _searchDebounce = Duration(milliseconds: 250);
  static const _liveTailInterval = Duration(seconds: 2);
  static const _liveTailMaxLines = 5000;

  final _searchController = TextEditingController();
  final _findController = TextEditingController();
  final _logScrollController = ScrollController();
  Timer? _searchTimer;
  Timer? _liveTailTimer;
  bool _liveTailBusy = false;

  /// 검색 요청 순번. 늦게 끝난 옛 검색이 새 결과를 덮어쓰지 못하게 한다.
  int _searchSeq = 0;
  List<SessionLog> _logs = const [];
  bool _logsLoading = true;
  Object? _logsError;

  SessionLog? _selected;
  String? _detailLogId;
  SessionLogText? _detailText;
  bool _detailLoading = false;
  Object? _detailError;

  String _findQuery = '';
  bool _findCaseSensitive = false;
  bool _findOnlyMatches = false;
  int _activeMatchIndex = 0;
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _stopLiveTail();
    _searchController.dispose();
    _findController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final seq = ++_searchSeq;
    setState(() {
      _logsLoading = true;
      _logsError = null;
    });
    List<SessionLog> logs;
    try {
      logs = await ref
          .read(sessionLogRepositoryProvider)
          .search(_searchController.text);
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _logsLoading = false;
        _logsError = e;
      });
      return;
    }
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _logsLoading = false;
      _logs = logs;
    });
  }

  void _reload({bool clearSelection = false}) {
    ref.invalidate(sessionLogListProvider);
    if (clearSelection) _closeDetail();
    _loadLogs();
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) _reload(clearSelection: true);
    });
  }

  void _selectLog(SessionLog log) {
    setState(() {
      _selected = log;
      _detailLogId = log.id;
      _detailText = null;
      _detailError = null;
      _detailLoading = true;
      _findController.clear();
      _findQuery = '';
      _findOnlyMatches = false;
      _activeMatchIndex = 0;
      _lineKeys.clear();
    });
    if (_logScrollController.hasClients) {
      _logScrollController.jumpTo(0);
    }
    _loadDetail(log);
    _syncLiveTail();
  }

  void _closeDetail() {
    _stopLiveTail();
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _detailLogId = null;
      _detailText = null;
      _detailError = null;
      _detailLoading = false;
    });
  }

  Future<void> _loadDetail(SessionLog log) async {
    SessionLogText text;
    try {
      text = await ref
          .read(sessionLogRepositoryProvider)
          .readPlainTextDetailed(log);
    } catch (e) {
      if (!mounted || _detailLogId != log.id) return;
      setState(() {
        _detailLoading = false;
        _detailError = e;
      });
      return;
    }
    if (!mounted || _detailLogId != log.id) return;
    setState(() {
      _detailLoading = false;
      _detailText = text;
    });
  }

  bool get _liveTailing => _liveTailTimer != null;

  /// 기록 중인 로그를 보고 있는 동안만 주기적으로 꼬리를 다시 읽는다.
  void _syncLiveTail() {
    final log = _selected;
    if (log == null || !log.active) {
      _stopLiveTail();
      return;
    }
    if (_liveTailTimer != null) return;
    _liveTailTimer = Timer.periodic(_liveTailInterval, (_) => _liveTailTick());
  }

  void _stopLiveTail() {
    _liveTailTimer?.cancel();
    _liveTailTimer = null;
  }

  Future<void> _liveTailTick() async {
    final log = _selected;
    if (log == null || !log.active || _liveTailBusy || !mounted) return;
    _liveTailBusy = true;
    try {
      final repo = ref.read(sessionLogRepositoryProvider);
      final latest = await repo.getById(log.id) ?? log;
      final text = await repo.readPlainTextTail(
        latest,
        maxLines: _liveTailMaxLines,
      );
      if (!mounted || _detailLogId != log.id) return;
      final atBottom = _isScrolledToBottom();
      setState(() {
        _selected = latest;
        _detailText = text;
        _detailLoading = false;
        _detailError = null;
        _lineKeys.clear();
      });
      if (atBottom) _scrollToBottomAfterFrame();
      if (!latest.active) _stopLiveTail();
    } catch (_) {
      // 일시적인 읽기 실패는 다음 주기에 다시 시도한다.
    } finally {
      _liveTailBusy = false;
    }
  }

  bool _isScrolledToBottom() {
    if (!_logScrollController.hasClients) return true;
    final position = _logScrollController.position;
    return position.pixels >= position.maxScrollExtent - 4;
  }

  void _scrollToBottomAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logScrollController.hasClients) return;
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }

  void _onFindChanged(String value) {
    setState(() {
      _findQuery = value;
      _activeMatchIndex = 0;
      _lineKeys.clear();
    });
    _scrollToActiveMatch();
  }

  void _setFindQuery(String value) {
    _findController.text = value;
    _findController.selection = TextSelection.collapsed(offset: value.length);
    _onFindChanged(value);
  }

  void _moveMatch(int delta, int matchCount) {
    if (matchCount == 0) return;
    setState(() {
      _activeMatchIndex = (_activeMatchIndex + delta) % matchCount;
      if (_activeMatchIndex < 0) _activeMatchIndex += matchCount;
    });
    _scrollToActiveMatch();
  }

  void _scrollToActiveMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _lineKeys[_activeMatchIndex];
      final context = key?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(SessionLog log) async {
    final text = await ref
        .read(sessionLogRepositoryProvider)
        .readPlainText(log);
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('로그 내용을 복사했습니다');
  }

  Future<void> _shareFile(SessionLog log) async {
    final handler = widget.shareHandler;
    if (handler != null) {
      await handler(log);
      return;
    }
    final file = log.file;
    if (!await file.exists()) {
      throw FileSystemException('로그 파일이 없습니다', log.logPath);
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: '${log.hostAlias} 세션 로그',
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('share unavailable');
    }
  }

  /// 파일 공유를 시도하고, 플랫폼이 지원하지 않으면 본문을 클립보드로 대신
  /// 내보낸다.
  Future<void> _export(SessionLog log) async {
    try {
      await _shareFile(log);
      return;
    } catch (_) {
      // 아래에서 클립보드로 대체한다.
    }
    if (!mounted) return;
    final text = await ref
        .read(sessionLogRepositoryProvider)
        .readPlainText(log);
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('공유할 수 없어 로그 내용을 클립보드에 복사했습니다');
  }

  Future<void> _delete(SessionLog log) async {
    if (log.active) {
      _showSnack('기록 중인 로그는 삭제할 수 없습니다');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그 삭제'),
        content: Text('${log.hostAlias} 세션 로그를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    String message;
    try {
      await ref.read(sessionLogRepositoryProvider).delete(log);
      message = '로그를 삭제했습니다';
    } on ActiveSessionLogDeleteException {
      message = '기록 중인 로그는 삭제할 수 없습니다';
    } on FileSystemException {
      message = '로그 파일을 사용 중이라 삭제하지 못했습니다';
    }
    if (!mounted) return;
    // 실패했더라도 목록을 다시 읽어 실제 상태와 어긋나지 않게 한다.
    _reload(clearSelection: true);
    _showSnack(message);
  }

  Future<void> _deleteInactive() async {
    final count = _logs.where((log) => !log.active).length;
    if (count == 0) {
      _showSnack('삭제할 종료 로그가 없습니다');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('종료 로그 모두 삭제'),
        content: Text('기록 중이 아닌 로그 $count개를 모두 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('모두 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = await ref
        .read(sessionLogRepositoryProvider)
        .deleteInactive();
    if (!mounted) return;
    _reload(clearSelection: true);
    _showSnack(
      removed == count
          ? '로그 $removed개를 삭제했습니다'
          : '로그 $removed개를 삭제했습니다. ${count - removed}개는 파일을 사용 중이라 남겼습니다',
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Container(
      color: VibeColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LogHeader(
            selected: selected,
            onBack: selected == null ? null : _closeDetail,
            onRefresh: () => _reload(),
            onDeleteInactive: selected == null ? _deleteInactive : null,
          ),
          Expanded(
            child: selected == null ? _listView() : _detailView(selected),
          ),
        ],
      ),
    );
  }

  Widget _listView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '검색 지우기',
                      onPressed: () {
                        _searchController.clear();
                        _reload(clearSelection: true);
                      },
                      icon: const Icon(Icons.clear),
                    ),
              hintText: '로그 검색',
              helperText:
                  _searchController.text.trim().isNotEmpty &&
                      _searchController.text.trim().length <
                          sessionLogContentSearchMinLength
                  ? '$sessionLogContentSearchMinLength자 이상 입력하면 본문도 검색합니다'
                  : null,
              isDense: true,
            ),
          ),
        ),
        Expanded(child: _logList()),
      ],
    );
  }

  Widget _logList() {
    if (_logsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logsError != null) {
      return Center(child: Text('오류: $_logsError'));
    }
    if (_logs.isEmpty) {
      return const _LogEmptyState();
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _logs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = _logs[index];
        return _LogTile(
          log: log,
          onTap: () => _selectLog(log),
          onCopy: () => _copy(log),
          onExport: () => _export(log),
          onDelete: () => _delete(log),
        );
      },
    );
  }

  Widget _detailView(SessionLog log) {
    final loading = _detailLoading;
    final detail = _detailText ?? SessionLogText.empty;
    final text = detail.text;
    final search = _LogSearchResult.fromText(
      text,
      query: _findQuery,
      caseSensitive: _findCaseSensitive,
    );
    if (_activeMatchIndex >= search.matchCount && search.matchCount > 0) {
      _activeMatchIndex = search.matchCount - 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: _LogSummary(log: log, live: _liveTailing),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => _copy(log),
                  icon: const Icon(Icons.content_copy, size: 17),
                  label: const Text('복사'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading ? null : () => _export(log),
                  icon: const Icon(Icons.ios_share, size: 17),
                  label: const Text('내보내기'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '로그 삭제',
                onPressed: log.active ? null : () => _delete(log),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _LogFindBar(
            controller: _findController,
            loading: loading,
            result: search,
            activeMatchIndex: _activeMatchIndex,
            caseSensitive: _findCaseSensitive,
            onlyMatches: _findOnlyMatches,
            onChanged: _onFindChanged,
            onClear: () => _setFindQuery(''),
            onPrevious: () => _moveMatch(-1, search.matchCount),
            onNext: () => _moveMatch(1, search.matchCount),
            onToggleCaseSensitive: () {
              setState(() {
                _findCaseSensitive = !_findCaseSensitive;
                _activeMatchIndex = 0;
                _lineKeys.clear();
              });
              _scrollToActiveMatch();
            },
            onToggleOnlyMatches: () {
              setState(() {
                _findOnlyMatches = !_findOnlyMatches;
                _lineKeys.clear();
              });
              _scrollToActiveMatch();
            },
          ),
        ),
        if (!loading && detail.truncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _LogTruncatedBanner(lineCount: detail.lineCount),
          ),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: VibeColors.terminal),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _detailError != null
                ? Center(
                    child: Text(
                      '오류: $_detailError',
                      style: const TextStyle(color: VibeColors.onSurfaceDim),
                    ),
                  )
                : text.isEmpty
                ? const Center(
                    child: Text(
                      '기록된 출력이 없습니다',
                      style: TextStyle(color: VibeColors.onSurfaceDim),
                    ),
                  )
                : _LogTextViewer(
                    search: search,
                    activeMatchIndex: _activeMatchIndex,
                    onlyMatches: _findOnlyMatches,
                    lineKeys: _lineKeys,
                    controller: _logScrollController,
                  ),
          ),
        ),
      ],
    );
  }
}

class _LogTruncatedBanner extends StatelessWidget {
  const _LogTruncatedBanner({required this.lineCount});

  final int lineCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: VibeColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '앞부분이 잘렸습니다. 마지막 $lineCount줄만 표시하며 찾기도 이 범위에서만 동작합니다.',
              style: const TextStyle(
                color: VibeColors.onSurfaceMuted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: VibeColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VibeColors.statusConnected),
      ),
      child: const Text(
        '실시간',
        style: TextStyle(
          color: VibeColors.statusConnected,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LogHeader extends StatelessWidget {
  const _LogHeader({
    required this.selected,
    required this.onBack,
    required this.onRefresh,
    required this.onDeleteInactive,
  });

  final SessionLog? selected;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;
  final VoidCallback? onDeleteInactive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: '목록으로',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.receipt_long_outlined,
                color: VibeColors.accent,
                size: 20,
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected == null ? 'Session Logs' : selected!.hostAlias,
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
                  selected == null ? 'output history only' : selected!.endpoint,
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
          IconButton(
            tooltip: '새로고침',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
          ),
          if (onDeleteInactive != null)
            PopupMenuButton<String>(
              tooltip: '로그 목록 메뉴',
              color: VibeColors.surfaceHigh,
              onSelected: (value) {
                if (value == 'delete-inactive') onDeleteInactive!();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete-inactive',
                  child: Text('기록 중이 아닌 로그 모두 삭제'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.log,
    required this.onTap,
    required this.onCopy,
    required this.onExport,
    required this.onDelete,
  });

  final SessionLog log;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VibeColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    log.active ? Icons.radio_button_checked : Icons.article,
                    size: 17,
                    color: log.active
                        ? VibeColors.statusConnected
                        : VibeColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.hostAlias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    log.endLabel,
                    style: TextStyle(
                      color: log.active
                          ? VibeColors.statusConnected
                          : VibeColors.onSurfaceDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '로그 메뉴',
                    color: VibeColors.surfaceHigh,
                    onSelected: (value) {
                      switch (value) {
                        case 'copy':
                          onCopy();
                        case 'export':
                          onExport();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'copy', child: Text('복사')),
                      PopupMenuItem(value: 'export', child: Text('내보내기')),
                      PopupMenuItem(value: 'delete', child: Text('삭제')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                log.endpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _LogChip(
                    icon: Icons.schedule,
                    label: _formatDate(log.startedAt),
                  ),
                  _LogChip(
                    icon: Icons.storage,
                    label: _formatBytes(log.byteCount),
                  ),
                  if (log.lineCount > 0)
                    _LogChip(
                      icon: Icons.format_list_numbered,
                      label: '${log.lineCount} lines',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogSummary extends StatelessWidget {
  const _LogSummary({required this.log, required this.live});

  final SessionLog log;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Column(
        children: [
          _LogMetaRow(label: '시작', value: _formatDateTime(log.startedAt)),
          _LogMetaRow(
            label: '종료',
            value: log.endedAt == null ? '기록 중' : _formatDateTime(log.endedAt!),
            trailing: live ? const _LiveBadge() : null,
          ),
          _LogMetaRow(label: '상태', value: log.endLabel),
          _LogMetaRow(label: '크기', value: _formatBytes(log.byteCount)),
          if (log.lineCount > 0)
            _LogMetaRow(label: '줄 수', value: '${log.lineCount} lines'),
        ],
      ),
    );
  }
}

class _LogFindBar extends StatelessWidget {
  const _LogFindBar({
    required this.controller,
    required this.loading,
    required this.result,
    required this.activeMatchIndex,
    required this.caseSensitive,
    required this.onlyMatches,
    required this.onChanged,
    required this.onClear,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleCaseSensitive,
    required this.onToggleOnlyMatches,
  });

  final TextEditingController controller;
  final bool loading;
  final _LogSearchResult result;
  final int activeMatchIndex;
  final bool caseSensitive;
  final bool onlyMatches;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onToggleOnlyMatches;

  @override
  Widget build(BuildContext context) {
    final hasQuery = result.hasQuery;
    final hasMatches = result.matchCount > 0;
    final counter = !hasQuery
        ? '본문 찾기'
        : hasMatches
        ? '${activeMatchIndex + 1} / ${result.matchCount}'
        : '일치 없음';
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        border: Border.all(color: VibeColors.borderSoft),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !loading,
                  onChanged: onChanged,
                  onSubmitted: (_) => onNext(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '찾기 지우기',
                            onPressed: onClear,
                            icon: const Icon(Icons.clear, size: 18),
                          ),
                    hintText: '로그 안에서 찾기',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 64,
                child: Text(
                  counter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasMatches
                        ? VibeColors.accent
                        : VibeColors.onSurfaceDim,
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '이전 결과',
                onPressed: hasMatches ? onPrevious : null,
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              ),
              IconButton(
                tooltip: '다음 결과',
                onPressed: hasMatches ? onNext : null,
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FindToggleChip(
                label: 'Aa',
                selected: caseSensitive,
                onTap: loading ? null : onToggleCaseSensitive,
              ),
              _FindToggleChip(
                label: '일치 줄만',
                selected: onlyMatches,
                onTap: loading || !hasQuery ? null : onToggleOnlyMatches,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FindToggleChip extends StatelessWidget {
  const _FindToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: selected ? VibeColors.accentSoft : VibeColors.surface,
      side: BorderSide(color: selected ? VibeColors.accent : VibeColors.border),
      labelStyle: TextStyle(
        color: selected ? VibeColors.accent : VibeColors.onSurfaceMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _LogTextViewer extends StatelessWidget {
  const _LogTextViewer({
    required this.search,
    required this.activeMatchIndex,
    required this.onlyMatches,
    required this.lineKeys,
    required this.controller,
  });

  final _LogSearchResult search;
  final int activeMatchIndex;
  final bool onlyMatches;
  final Map<int, GlobalKey> lineKeys;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final visibleLines = <int>[
      for (var i = 0; i < search.lines.length; i++)
        if (!onlyMatches || !search.hasQuery || search.lineHasMatch(i)) i,
    ];
    if (visibleLines.isEmpty) {
      return const Center(
        child: Text(
          '일치하는 줄이 없습니다',
          style: TextStyle(color: VibeColors.onSurfaceDim),
        ),
      );
    }

    final lineNumberWidth = (search.lines.length.toString().length * 8.0) + 14;
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 14),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final lineIndex in visibleLines)
              _LogLineRow(
                key: _lineKeyFor(lineIndex),
                lineNumber: lineIndex + 1,
                lineNumberWidth: lineNumberWidth,
                line: search.lines[lineIndex],
                matches: search.matchesForLine(lineIndex),
                activeMatchIndex: activeMatchIndex,
              ),
          ],
        ),
      ),
    );
  }

  Key? _lineKeyFor(int lineIndex) {
    final matches = search.matchesForLine(lineIndex);
    if (matches.isEmpty) return null;
    final key = lineKeys.putIfAbsent(matches.first.globalIndex, GlobalKey.new);
    for (final match in matches.skip(1)) {
      lineKeys[match.globalIndex] = key;
    }
    return key;
  }
}

class _LogLineRow extends StatelessWidget {
  const _LogLineRow({
    super.key,
    required this.lineNumber,
    required this.lineNumberWidth,
    required this.line,
    required this.matches,
    required this.activeMatchIndex,
  });

  final int lineNumber;
  final double lineNumberWidth;
  final String line;
  final List<_LogMatch> matches;
  final int activeMatchIndex;

  @override
  Widget build(BuildContext context) {
    final hasCurrent = matches.any((match) {
      return match.globalIndex == activeMatchIndex;
    });
    return Container(
      color: hasCurrent ? VibeColors.accentSoft : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: hasCurrent ? VibeColors.accent : VibeColors.onSurfaceDim,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: _spans()),
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _spans() {
    if (line.isEmpty) return const [TextSpan(text: ' ')];
    if (matches.isEmpty) return [TextSpan(text: line)];

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, match.start)));
      }
      final current = match.globalIndex == activeMatchIndex;
      spans.add(
        TextSpan(
          text: line.substring(match.start, match.end),
          style: TextStyle(
            color: current ? VibeColors.terminal : VibeColors.onSurface,
            backgroundColor: current
                ? VibeColors.warning
                : const Color(0xAA8A6A18),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor)));
    }
    return spans;
  }
}

class _LogMetaRow extends StatelessWidget {
  const _LogMetaRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontFamily: kMonoFontFamily,
                fontFamilyFallback: kMonoFontFallback,
                fontSize: 11,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _LogChip extends StatelessWidget {
  const _LogChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: VibeColors.onSurfaceDim),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: VibeColors.onSurfaceDim,
            fontSize: 11,
            fontFamily: kMonoFontFamily,
            fontFamilyFallback: kMonoFontFallback,
          ),
        ),
      ],
    );
  }
}

class _LogEmptyState extends StatelessWidget {
  const _LogEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: VibeColors.onSurfaceDim,
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              '기록된 로그가 없습니다',
              style: TextStyle(
                color: VibeColors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '새 세션을 열면 출력 로그가 자동으로 기록됩니다. 입력 내용은 저장하지 않습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogSearchResult {
  _LogSearchResult._({
    required this.query,
    required this.lines,
    required this.matches,
    required this._matchesByLine,
  });

  factory _LogSearchResult.fromText(
    String text, {
    required String query,
    required bool caseSensitive,
  }) {
    final lines = text.split('\n');
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return _LogSearchResult._(
        query: '',
        lines: lines,
        matches: const [],
        matchesByLine: const {},
      );
    }

    final matches = <_LogMatch>[];
    final matchesByLine = <int, List<_LogMatch>>{};
    final needle = caseSensitive
        ? normalizedQuery
        : normalizedQuery.toLowerCase();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final haystack = caseSensitive ? line : line.toLowerCase();
      var start = haystack.indexOf(needle);
      while (start >= 0) {
        final match = _LogMatch(
          globalIndex: matches.length,
          lineIndex: lineIndex,
          start: start,
          end: start + needle.length,
        );
        matches.add(match);
        matchesByLine.putIfAbsent(lineIndex, () => []).add(match);
        start = haystack.indexOf(needle, start + needle.length);
      }
    }
    return _LogSearchResult._(
      query: normalizedQuery,
      lines: lines,
      matches: matches,
      matchesByLine: matchesByLine,
    );
  }

  final String query;
  final List<String> lines;
  final List<_LogMatch> matches;
  final Map<int, List<_LogMatch>> _matchesByLine;

  bool get hasQuery => query.isNotEmpty;
  int get matchCount => matches.length;

  bool lineHasMatch(int lineIndex) {
    return _matchesByLine.containsKey(lineIndex);
  }

  List<_LogMatch> matchesForLine(int lineIndex) {
    return _matchesByLine[lineIndex] ?? const [];
  }
}

class _LogMatch {
  const _LogMatch({
    required this.globalIndex,
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  final int globalIndex;
  final int lineIndex;
  final int start;
  final int end;
}

String _formatDate(DateTime value) {
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return '${_two(value.hour)}:${_two(value.minute)}';
  }
  return '${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';
}

String _formatDateTime(DateTime value) {
  return '${value.year}-${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(1)} MB';
}

String _two(int value) => value.toString().padLeft(2, '0');
