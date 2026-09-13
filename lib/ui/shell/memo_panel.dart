import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/memo.dart';
import '../../data/repositories/memo_repository.dart';
import '../../session/session.dart';
import '../../state/providers.dart';

/// 저장 상태. 헤더에 작게 표시해 편집이 실제로 저장됐는지 알 수 있게 한다.
enum _SaveStatus { idle, saving, saved, failed }

/// 우측 패널. 활성 세션의 Host에 연결된 자유 텍스트 메모를 보여준다.
/// 같은 Host로 연결된 모든 세션이 같은 메모를 공유하며, 입력이 멈추면
/// 디바운스 후 자동 저장한다. 활성 세션이 없으면 메모가 있는 호스트 목록을
/// 보여주고, 골라서 열어볼 수 있다.
class MemoPanel extends ConsumerStatefulWidget {
  const MemoPanel({super.key});

  @override
  ConsumerState<MemoPanel> createState() => _MemoPanelState();
}

class _MemoPanelState extends ConsumerState<MemoPanel>
    with WidgetsBindingObserver {
  static const _saveDebounce = Duration(milliseconds: 500);

  final TextEditingController _controller = TextEditingController();
  Timer? _saveTimer;

  /// 마지막으로 로드를 요청한 hostId. 응답이 돌아왔을 때 이 값과 다르면
  /// 그 사이 host가 바뀐 것이므로 결과를 버린다.
  String? _requestedHostId;

  /// 현재 컨트롤러에 로드된 메모의 hostId. host가 바뀌면 다시 로드한다.
  String? _loadedHostId;
  Object? _loadError;

  /// 활성 세션이 없을 때 목록에서 골라 연 host.
  String? _pickedHostId;

  /// 활성 세션이 없을 때 보여줄 메모 목록. null이면 아직 요청 전.
  Future<List<Memo>>? _allMemos;

  /// 마지막 저장 이후 편집이 있었는지. 변경이 없으면 저장하지 않는다.
  bool _dirty = false;
  _SaveStatus _saveStatus = _SaveStatus.idle;
  DateTime? _updatedAt;

  /// 실패한 저장의 (hostId, body). 다시 시도 버튼이 이 값을 재저장한다.
  (String, String)? _failedSave;

  /// dispose 시점에는 ref.read가 불안전하므로 저장소를 미리 캐시해 둔다.
  MemoRepository? _repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = ref.read(memoRepositoryProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    // 보류 중인 변경을 즉시 저장.
    unawaited(_flush());
    _controller.dispose();
    super.dispose();
  }

  /// 앱이 백그라운드로 가거나 비활성화되면 디바운스를 기다리지 않고 저장한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTimer?.cancel();
      unawaited(_flush());
    }
  }

  Future<void> _loadFor(String hostId) async {
    _requestedHostId = hostId;
    setState(() => _loadError = null);
    Memo? memo;
    try {
      memo = await ref.read(memoRepositoryProvider).getForHost(hostId);
    } catch (e) {
      // 응답을 기다리는 사이 host가 바뀌었으면 이 오류는 더 이상 의미가 없다.
      if (!mounted || _requestedHostId != hostId) return;
      setState(() => _loadError = e);
      return;
    }
    if (!mounted || _requestedHostId != hostId) return;
    setState(() {
      _loadedHostId = hostId;
      _controller.text = memo?.body ?? '';
      _updatedAt = memo?.updatedAt;
      _dirty = false;
      _saveStatus = _SaveStatus.idle;
      _failedSave = null;
    });
  }

  void _onChanged(String _) {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(_flush()));
  }

  /// 보류 중인 변경이 있으면 즉시 저장한다. 실패하면 편집 내용을 버리지 않고
  /// 헤더에 "저장 실패"를 띄워 다시 시도할 수 있게 한다.
  Future<void> _flush() async {
    final hostId = _loadedHostId;
    final repo = _repo;
    if (hostId == null || repo == null || !_dirty) return;
    _dirty = false;
    final body = _controller.text;
    await _save(repo, hostId, body);
  }

  Future<void> _save(MemoRepository repo, String hostId, String body) async {
    final now = DateTime.now();
    if (mounted) setState(() => _saveStatus = _SaveStatus.saving);
    try {
      await repo.save(hostId, body, now);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveStatus = _SaveStatus.failed;
        _failedSave = (hostId, body);
        // 같은 host를 아직 보고 있으면 dirty를 되살려 다음 flush에서 재시도한다.
        if (_loadedHostId == hostId) _dirty = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _failedSave = null;
      // 저장 중에 다른 host로 넘어갔거나 새 편집이 생겼으면 상태를 덮지 않는다.
      if (_loadedHostId == hostId) {
        _updatedAt = now;
        if (!_dirty) _saveStatus = _SaveStatus.saved;
      }
    });
  }

  /// "저장 실패 – 다시 시도". 같은 host를 보고 있으면 현재 편집 내용을,
  /// 아니면 실패 당시의 본문을 저장한다.
  Future<void> _retrySave() async {
    final repo = _repo;
    final failed = _failedSave;
    if (repo == null || failed == null) return;
    _saveTimer?.cancel();
    final (hostId, body) = failed;
    if (_loadedHostId == hostId) {
      _dirty = false;
      await _save(repo, hostId, _controller.text);
    } else {
      await _save(repo, hostId, body);
    }
  }

  void _refreshList() {
    _allMemos = ref.read(memoRepositoryProvider).listAll();
  }

  /// 활성 세션이 없을 때 목록에서 메모를 골라 연다.
  void _pick(String hostId) {
    setState(() => _pickedHostId = hostId);
  }

  /// 목록으로 돌아간다. 보류 중인 편집은 먼저 저장한다.
  void _backToList() {
    _saveTimer?.cancel();
    unawaited(_flush());
    setState(() {
      _pickedHostId = null;
      _refreshList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 활성 세션/host 변화에 반응.
    final sessions = ref.watch(sessionManagerProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    SessionInfo? active;
    for (final s in sessions) {
      if (s.id == activeId) {
        active = s;
        break;
      }
    }
    // 세션이 생기면 목록에서 고른 host는 잊고 활성 세션의 host를 따른다.
    if (active != null) _pickedHostId = null;
    final hostId = active?.host.id ?? _pickedHostId;

    // host가 바뀌면 이전 메모를 flush하고 새 host 메모를 로드한다.
    if (hostId != null && hostId != _requestedHostId) {
      if (_loadedHostId != null) {
        _saveTimer?.cancel();
        unawaited(_flush());
      }
      _requestedHostId = hostId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _requestedHostId == hostId) _loadFor(hostId);
      });
    }
    if (hostId == null && _allMemos == null) _refreshList();

    // hostId → 별칭. 호스트 목록이 아직 없거나 삭제된 host면 id를 그대로 쓴다.
    final hosts = ref.watch(hostListProvider).asData?.value ?? const [];
    String aliasFor(String id) {
      for (final h in hosts) {
        if (h.id == id) return h.alias;
      }
      return id;
    }

    final String? hostAlias;
    if (active != null) {
      hostAlias = active.host.alias;
    } else if (hostId != null) {
      hostAlias = aliasFor(hostId);
    } else {
      hostAlias = null;
    }

    final Widget body;
    if (hostId == null) {
      body = _MemoList(
        memos: _allMemos!,
        aliasOf: aliasFor,
        onTap: _pick,
        onRetry: () => setState(_refreshList),
      );
    } else if (_loadError != null && _loadedHostId != hostId) {
      body = _LoadError(error: _loadError!, onRetry: () => _loadFor(hostId));
    } else if (_loadedHostId != hostId) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: TextField(
          controller: _controller,
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
            fontSize: 13,
            height: 1.4,
          ),
          decoration: const InputDecoration(
            hintText: '이 호스트에 대한 메모를 남겨보세요…',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      );
    }

    return Container(
      color: VibeColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoHeader(
            hostAlias: hostAlias,
            updatedAt: hostId != null && _loadedHostId == hostId
                ? _updatedAt
                : null,
            saveStatus: hostId != null ? _saveStatus : _SaveStatus.idle,
            onRetry: _retrySave,
            onBack: active == null && _pickedHostId != null
                ? _backToList
                : null,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

String _formatUpdatedAt(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class _MemoHeader extends StatelessWidget {
  const _MemoHeader({
    required this.hostAlias,
    required this.updatedAt,
    required this.saveStatus,
    required this.onRetry,
    required this.onBack,
  });

  final String? hostAlias;
  final DateTime? updatedAt;
  final _SaveStatus saveStatus;
  final VoidCallback onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    const subtitleStyle = TextStyle(
      color: VibeColors.onSurfaceDim,
      fontFamily: kMonoFontFamily,
      fontFamilyFallback: kMonoFontFallback,
      fontSize: 11,
    );
    final at = updatedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: '메모 목록',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 20),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            )
          else
            const Icon(
              Icons.sticky_note_2_outlined,
              color: VibeColors.accent,
              size: 20,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Memo',
                  style: TextStyle(
                    color: VibeColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hostAlias ?? 'shared per host',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                    // 마지막 저장 시각. 메모가 아직 없으면 표시하지 않는다.
                    if (at != null) ...[
                      const Text(' · ', style: subtitleStyle),
                      Text(_formatUpdatedAt(at), style: subtitleStyle),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SaveStatusChip(status: saveStatus, onRetry: onRetry),
        ],
      ),
    );
  }
}

/// 헤더 우측의 작은 저장 상태. 실패 시 눌러서 다시 시도할 수 있다.
class _SaveStatusChip extends StatelessWidget {
  const _SaveStatusChip({required this.status, required this.onRetry});

  final _SaveStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: VibeColors.onSurfaceDim);
    return switch (status) {
      _SaveStatus.idle => const SizedBox.shrink(),
      _SaveStatus.saving => const Text('저장 중', style: style),
      _SaveStatus.saved => const Text('저장됨', style: style),
      _SaveStatus.failed => InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            '저장 실패 – 다시 시도',
            style: TextStyle(
              fontSize: 11,
              color: VibeColors.statusError,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    };
  }
}

/// 메모 로드 실패. 재시도 버튼을 함께 보여준다.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: VibeColors.statusError,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              '메모를 불러오지 못했습니다\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

/// 활성 세션이 없을 때: 메모가 있는 호스트 목록. 탭하면 그 메모를 연다.
class _MemoList extends StatelessWidget {
  const _MemoList({
    required this.memos,
    required this.aliasOf,
    required this.onTap,
    required this.onRetry,
  });

  final Future<List<Memo>> memos;
  final String Function(String hostId) aliasOf;
  final ValueChanged<String> onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Memo>>(
      future: memos,
      builder: (context, snap) {
        if (snap.hasError) {
          return _LoadError(error: snap.error!, onRetry: onRetry);
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    color: VibeColors.onSurfaceDim,
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '메모',
                    style: TextStyle(
                      color: VibeColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '세션을 선택하면 호스트별 메모를 작성할 수 있습니다.',
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
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final memo = list[index];
            final preview = memo.body.trim().split('\n').first;
            return Material(
              color: VibeColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(memo.hostId),
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
                          const Icon(
                            Icons.dns,
                            size: 16,
                            color: VibeColors.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              aliasOf(memo.hostId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: VibeColors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _formatUpdatedAt(memo.updatedAt),
                            style: const TextStyle(
                              color: VibeColors.onSurfaceDim,
                              fontFamily: kMonoFontFamily,
                              fontFamilyFallback: kMonoFontFallback,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VibeColors.onSurfaceDim,
                            fontFamily: kMonoFontFamily,
                            fontFamilyFallback: kMonoFontFallback,
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
