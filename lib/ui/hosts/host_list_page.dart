import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../data/models/ssh_key.dart';
import '../../state/providers.dart';
import '../keychain/keychain_page.dart';
import '../keychain/public_key_install_flow.dart';
import '../security/known_hosts_page.dart';
import 'host_edit_page.dart';

enum _HostAction { duplicate, edit, installKey, delete }

const _deleteUndoSnackBarDuration = Duration(seconds: 4);

/// 호스트 전용 Identity(`host-<id>`)를 쓰는지. identityId가 아직 없는 레거시
/// 호스트도 전용으로 본다(저장 시 전용 Identity가 만들어진다).
bool _isHostScoped(Host host) =>
    host.identityId == null || host.identityId == 'host-${host.id}';

/// 호스트 목록. [pickMode]면 탭 시 선택한 Host를 [onPick]으로 넘기고,
/// [onPick]이 없으면 Navigator.pop으로 반환한다.
///
/// [onClose]가 있으면 앱바에 닫기 버튼을 둔다(다이얼로그 안 중첩 Navigator처럼
/// 뒤로가기 화살표가 자동으로 생기지 않는 경우용).
class HostListPage extends ConsumerWidget {
  const HostListPage({
    super.key,
    this.pickMode = false,
    this.onPick,
    this.onClose,
    this.pickFilter,
    this.pickTitle,
  });

  final bool pickMode;
  final ValueChanged<Host>? onPick;
  final VoidCallback? onClose;

  /// [pickMode]에서 목록에 보일 호스트만 남기는 필터.
  final bool Function(Host host)? pickFilter;

  /// [pickMode] 앱바 제목. 없으면 '세션 선택'.
  final String? pickTitle;

  RelativeRect _menuPosition(BuildContext context, Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _showHostMenu(
    BuildContext context,
    WidgetRef ref,
    Host host,
    Offset globalPosition,
    Future<void> Function(Host host) openEditor,
  ) async {
    final action = await showMenu<_HostAction>(
      context: context,
      position: _menuPosition(context, globalPosition),
      color: VibeColors.surfaceHigh,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      constraints: const BoxConstraints(minWidth: 220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: VibeColors.borderSoft),
      ),
      items: [
        const _HostMenuItem(
          value: _HostAction.duplicate,
          icon: Icons.copy_all_outlined,
          label: '호스트 복제',
        ),
        const _HostMenuItem(
          value: _HostAction.edit,
          icon: Icons.edit_outlined,
          label: '호스트 편집',
        ),
        if (host.connectionType == HostConnectionType.ssh)
          const _HostMenuItem(
            value: _HostAction.installKey,
            icon: Icons.cloud_upload_outlined,
            label: '공개키 등록',
          ),
        const _HostMenuItem(
          value: _HostAction.delete,
          icon: Icons.delete_outline,
          label: '호스트 삭제',
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _HostAction.duplicate:
        await _duplicateHost(context, ref, host);
      case _HostAction.edit:
        await openEditor(host);
      case _HostAction.installKey:
        await showPublicKeyInstallFlow(context, ref, host: host);
      case _HostAction.delete:
        await _deleteHost(context, ref, host);
    }
  }

  String _duplicateAlias(String alias, Iterable<String> aliases) {
    final suffixPattern = RegExp(r'^(.*) \((\d+)\)$');
    final match = suffixPattern.firstMatch(alias.trim());
    final base = (match?.group(1) ?? alias).trim();
    final fallbackBase = base.isEmpty ? '호스트' : base;
    final taken = aliases.toSet();
    for (var i = 1; i < 10000; i += 1) {
      final candidate = '$fallbackBase ($i)';
      if (!taken.contains(candidate)) return candidate;
    }
    return '$fallbackBase (${DateTime.now().microsecondsSinceEpoch})';
  }

  Future<void> _duplicateHost(
    BuildContext context,
    WidgetRef ref,
    Host host,
  ) async {
    try {
      final repository = ref.read(hostRepositoryProvider);
      final allHosts = await repository.getAll();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final hostScoped = _isHostScoped(host);

      // 공유 Identity를 쓰는 호스트는 복제본도 같은 Identity를 공유한다.
      // 호스트 전용 Identity는 복제본이 자신만의 전용 Identity를 새로 받는다:
      //  - 비밀번호: 비밀을 새 ref로 복사한다.
      //  - 공개키: credentialRef(=키체인 키의 secretRef)를 그대로 넘기면
      //    저장소가 같은 키를 다시 연결한다. 개인키를 복사하지 않는다.
      String? credentialRef = hostScoped ? host.credentialRef : null;
      if (hostScoped &&
          host.authType == HostAuthType.password &&
          host.credentialRef != null) {
        final secureStore = ref.read(secureStoreProvider);
        final secret = await secureStore.readSecret(host.credentialRef!);
        credentialRef = null;
        if (secret != null) {
          credentialRef = 'cred-$id';
          await secureStore.writeSecret(credentialRef, secret);
        }
      }

      final now = DateTime.now();
      await repository.upsert(
        host.copyWith(
          id: id,
          alias: _duplicateAlias(host.alias, allHosts.map((h) => h.alias)),
          credentialRef: credentialRef,
          identityId: hostScoped ? null : host.identityId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      ref.invalidate(hostListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('호스트를 복제했습니다')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('호스트를 복제하지 못했습니다: $e')));
    }
  }

  Future<void> _deleteHost(
    BuildContext context,
    WidgetRef ref,
    Host host,
  ) async {
    try {
      final repository = ref.read(hostRepositoryProvider);
      // 비밀 삭제는 저장소(HostRepository.delete → host-<id> Identity 삭제)가
      // 맡는다. 여기서는 되돌리기를 위해 호스트 전용 비밀번호만 잠시 기억한다.
      // 키체인 키나 공유 Identity의 비밀은 절대 읽거나 지우지 않는다.
      final credentialRef = host.credentialRef;
      final keepCredential =
          _isHostScoped(host) && host.authType == HostAuthType.password;
      final credential = keepCredential && credentialRef != null
          ? await ref.read(secureStoreProvider).readSecret(credentialRef)
          : null;

      await repository.delete(host.id);
      ref.invalidate(hostListProvider);
      if (!context.mounted) return;

      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
      controller;
      controller = messenger.showSnackBar(
        SnackBar(
          content: const Text('호스트를 삭제했습니다'),
          duration: _deleteUndoSnackBarDuration,
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              unawaited(_restoreDeletedHost(context, ref, host, credential));
            },
          ),
        ),
      );
      final autoDismissTimer = Timer(
        _deleteUndoSnackBarDuration,
        controller.close,
      );
      unawaited(controller.closed.then((_) => autoDismissTimer.cancel()));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('호스트를 삭제하지 못했습니다: $e')));
    }
  }

  Future<void> _restoreDeletedHost(
    BuildContext context,
    WidgetRef ref,
    Host host,
    String? credential,
  ) async {
    final credentialRef = host.credentialRef;
    if (credentialRef != null && credential != null) {
      await ref
          .read(secureStoreProvider)
          .writeSecret(credentialRef, credential);
    }
    // 삭제 시 host-<id> Identity도 지워졌으므로 identityId를 비워 저장소가
    // 호스트 필드로 전용 Identity를 다시 만들게 한다. 공유 Identity는 유지.
    await ref
        .read(hostRepositoryProvider)
        .upsert(
          host.copyWith(
            identityId: _isHostScoped(host) ? null : host.identityId,
          ),
        );
    ref.invalidate(hostListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('호스트를 복원했습니다')));
  }

  /// 호스트 편집이 새 키 바인딩을 만들었을 때의 "등록" 제안. 편집 화면이 닫힌 뒤
  /// 호출되므로 호스트/키를 저장소에서 다시 읽는다.
  Future<void> _installSuggestedKey(
    BuildContext context,
    WidgetRef ref,
    String hostId,
    String keyId,
  ) async {
    final host = await ref.read(hostRepositoryProvider).getById(hostId);
    final key = await ref.read(sshKeyRepositoryProvider).getById(keyId);
    if (!context.mounted) return;
    if (host == null || key == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('호스트나 키를 찾을 수 없습니다')));
      return;
    }
    await showPublicKeyInstallFlow(context, ref, host: host, key: key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);
    final identityLabels = <String, String>{
      for (final identity in ref.watch(identityListProvider).value ?? const [])
        identity.id: identity.label,
    };
    Future<void> openEditor([Host? host]) async {
      final result = await Navigator.push<HostEditResult>(
        context,
        MaterialPageRoute(builder: (_) => HostEditPage(existing: host)),
      );
      if (!context.mounted) return;
      ref.invalidate(hostListProvider);
      final suggestHostId = result?.suggestInstallHostId;
      final suggestKeyId = result?.suggestInstallKeyId;
      if (suggestHostId == null || suggestKeyId == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('이 키를 서버에 등록할까요?'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: '등록',
              onPressed: () => unawaited(
                _installSuggestedKey(context, ref, suggestHostId, suggestKeyId),
              ),
            ),
          ),
        );
    }

    Future<void> installKeyFromKeychain(SshKey key) async {
      final host = await Navigator.push<Host>(
        context,
        MaterialPageRoute(
          builder: (_) => HostListPage(
            pickMode: true,
            pickTitle: '공개키를 등록할 호스트 선택',
            pickFilter: (h) => h.connectionType == HostConnectionType.ssh,
          ),
        ),
      );
      if (host == null || !context.mounted) return;
      await showPublicKeyInstallFlow(context, ref, host: host, key: key);
    }

    final filter = pickMode ? pickFilter : null;
    final hostBody = hosts.when(
      data: (all) {
        final list = filter == null ? all : all.where(filter).toList();
        if (list.isEmpty) {
          return all.isEmpty || filter == null
              ? _EmptyHosts(onAdd: () => openEditor())
              : const Center(
                  child: Text(
                    '등록할 수 있는 SSH 호스트가 없습니다',
                    style: TextStyle(color: VibeColors.onSurfaceDim),
                  ),
                );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final h = list[index];
            return _HostTile(
              host: h,
              pickMode: pickMode,
              identityLabel: identityLabels[h.identityId],
              onEdit: () => openEditor(h),
              onShowMenu: (position) =>
                  _showHostMenu(context, ref, h, position, openEditor),
              onPick: () =>
                  onPick != null ? onPick!(h) : Navigator.pop<Host>(context, h),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('호스트를 불러오지 못했습니다: $e')),
    );

    final addHostBar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: FilledButton.icon(
          onPressed: () => openEditor(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('호스트 추가'),
        ),
      ),
    );

    final closeAction = onClose == null
        ? <Widget>[]
        : [
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ];

    if (pickMode) {
      return Scaffold(
        appBar: AppBar(title: Text(pickTitle ?? '세션 선택'), actions: closeAction),
        body: hostBody,
        bottomNavigationBar: addHostBar,
      );
    }

    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Vibe Terminal'),
                  actions: closeAction,
                  bottom: const TabBar(
                    tabs: [
                      Tab(text: '호스트'),
                      Tab(text: '키체인'),
                      Tab(text: 'Known Hosts'),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    hostBody,
                    KeychainPage(onInstallKey: installKeyFromKeychain),
                    const KnownHostsPage(),
                  ],
                ),
                bottomNavigationBar: controller.index == 0 ? addHostBar : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  const _HostTile({
    required this.host,
    required this.pickMode,
    required this.onEdit,
    required this.onShowMenu,
    required this.onPick,
    this.identityLabel,
  });

  final Host host;
  final bool pickMode;
  final VoidCallback onEdit;
  final Future<void> Function(Offset position) onShowMenu;
  final VoidCallback onPick;
  final String? identityLabel;

  String get _authLabel {
    final base = switch (host.authType) {
      HostAuthType.password => 'password',
      HostAuthType.publicKey => 'key',
      HostAuthType.keyboardInteractive => '2fa',
    };
    return identityLabel == null ? base : '$identityLabel · $base';
  }

  String get _badgeLabel => switch (host.connectionType) {
    HostConnectionType.localShell => host.connectionLabel,
    HostConnectionType.kubernetesSsh => 'k8s',
    HostConnectionType.ssh => _authLabel,
  };

  IconData get _icon => switch (host.connectionType) {
    HostConnectionType.localShell => Icons.terminal,
    HostConnectionType.kubernetesSsh => Icons.hub_outlined,
    HostConnectionType.ssh => Icons.dns_outlined,
  };

  void _showMenuAtCenter(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    unawaited(onShowMenu(box.localToGlobal(box.size.center(Offset.zero))));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VibeColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: pickMode ? onPick : onEdit,
        onSecondaryTapDown: (details) =>
            unawaited(onShowMenu(details.globalPosition)),
        onLongPress: () => _showMenuAtCenter(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VibeColors.border),
          ),
          child: Row(
            children: [
              Icon(_icon, color: VibeColors.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host.endpointLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: kMonoFontFamily,
                        fontFamilyFallback: kMonoFontFallback,
                        fontSize: 12,
                        color: VibeColors.onSurfaceDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AuthBadge(label: _badgeLabel),
              const SizedBox(width: 2),
              pickMode
                  ? const Icon(Icons.chevron_right, size: 18)
                  : IconButton(
                      tooltip: '호스트 수정',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: onEdit,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostMenuItem extends PopupMenuItem<_HostAction> {
  const _HostMenuItem({
    required _HostAction super.value,
    required this.icon,
    required this.label,
  }) : super(child: const SizedBox.shrink());

  final IconData icon;
  final String label;

  @override
  PopupMenuItemState<_HostAction, _HostMenuItem> createState() =>
      _HostMenuItemState();
}

class _HostMenuItemState
    extends PopupMenuItemState<_HostAction, _HostMenuItem> {
  @override
  Widget buildChild() {
    final destructive = widget.value == _HostAction.delete;
    final color = destructive ? VibeColors.statusError : VibeColors.onSurface;
    return Row(
      children: [
        Icon(widget.icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          widget.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _AuthBadge extends StatelessWidget {
  const _AuthBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: VibeColors.onSurfaceDim,
          fontFamily: kMonoFontFamily,
          fontFamilyFallback: kMonoFontFallback,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 등록된 호스트가 없을 때의 빈 상태 — 다음 행동을 안내한다.
class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.dns_outlined,
            size: 44,
            color: VibeColors.onSurfaceDim,
          ),
          const SizedBox(height: 16),
          const Text(
            '등록된 호스트가 없습니다',
            style: TextStyle(color: VibeColors.onSurface, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'SSH 호스트나 로컬 셸 프로필을 추가하세요',
            style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('호스트 추가'),
          ),
        ],
      ),
    );
  }
}
