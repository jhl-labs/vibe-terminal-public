import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../state/providers.dart';
import 'host_edit_page.dart';

enum _HostAction { duplicate, edit, delete }

const _deleteUndoSnackBarDuration = Duration(seconds: 4);

/// 호스트 목록. [pickMode]면 탭 시 선택한 Host를 Navigator.pop으로 반환한다.
class HostListPage extends ConsumerWidget {
  const HostListPage({super.key, this.pickMode = false});

  final bool pickMode;

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
      items: const [
        _HostMenuItem(
          value: _HostAction.duplicate,
          icon: Icons.copy_all_outlined,
          label: '호스트 복제',
        ),
        _HostMenuItem(
          value: _HostAction.edit,
          icon: Icons.edit_outlined,
          label: '호스트 편집',
        ),
        _HostMenuItem(
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
      String? credentialRef;
      if (host.credentialRef != null) {
        final secret = await ref
            .read(secureStoreProvider)
            .readSecret(host.credentialRef!);
        if (secret != null) {
          credentialRef = 'cred-$id';
          await ref
              .read(secureStoreProvider)
              .writeSecret(credentialRef, secret);
        }
      }

      final now = DateTime.now();
      await repository.upsert(
        host.copyWith(
          id: id,
          alias: _duplicateAlias(host.alias, allHosts.map((h) => h.alias)),
          credentialRef: credentialRef,
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
      final secureStore = ref.read(secureStoreProvider);
      final credentialRef = host.credentialRef;
      final credential = credentialRef == null
          ? null
          : await secureStore.readSecret(credentialRef);

      await repository.delete(host.id);
      ref.invalidate(hostListProvider);
      if (!context.mounted) return;

      var restored = false;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
      controller;
      Timer? autoDismissTimer;
      controller = messenger.showSnackBar(
        SnackBar(
          content: const Text('호스트를 삭제했습니다'),
          duration: _deleteUndoSnackBarDuration,
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              restored = true;
              unawaited(_restoreDeletedHost(context, ref, host, credential));
            },
          ),
        ),
      );

      autoDismissTimer = Timer(_deleteUndoSnackBarDuration, controller.close);
      unawaited(
        controller.closed.then((_) async {
          autoDismissTimer?.cancel();
          if (credentialRef != null) {
            if (!restored) {
              await secureStore.deleteSecret(credentialRef);
            }
          }
        }),
      );
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
    await ref.read(hostRepositoryProvider).upsert(host);
    ref.invalidate(hostListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('호스트를 복원했습니다')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);
    Future<void> openEditor([Host? host]) async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HostEditPage(existing: host)),
      );
      if (context.mounted) {
        ref.invalidate(hostListProvider);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(pickMode ? '세션 선택' : 'Vibe Terminal')),
      body: hosts.when(
        data: (list) => list.isEmpty
            ? _EmptyHosts(onAdd: () => openEditor())
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final h = list[index];
                  return _HostTile(
                    host: h,
                    pickMode: pickMode,
                    onEdit: () => openEditor(h),
                    onShowMenu: (position) =>
                        _showHostMenu(context, ref, h, position, openEditor),
                    onPick: () => Navigator.pop<Host>(context, h),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('호스트를 불러오지 못했습니다: $e')),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: FilledButton.icon(
            onPressed: () => openEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('호스트 추가'),
          ),
        ),
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
  });

  final Host host;
  final bool pickMode;
  final VoidCallback onEdit;
  final Future<void> Function(Offset position) onShowMenu;
  final VoidCallback onPick;

  String get _authLabel => switch (host.authType) {
    HostAuthType.password => 'password',
    HostAuthType.publicKey => 'key',
    HostAuthType.keyboardInteractive => '2fa',
  };

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
