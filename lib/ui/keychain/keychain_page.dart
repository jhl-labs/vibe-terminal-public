import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/identity.dart';
import '../../data/models/ssh_key.dart';
import '../../data/repositories/identity_repository.dart';
import '../../data/repositories/ssh_key_repository.dart';
import '../../state/providers.dart';
import '../../telemetry/telemetry.dart';
import 'identity_edit_sheet.dart';
import 'ssh_key_create_sheet.dart';
import 'ssh_key_import_sheet.dart';

/// 키체인 탭: SSH 키와 Identity 목록. 호스트 목록 페이지의 탭 본문.
class KeychainPage extends ConsumerStatefulWidget {
  const KeychainPage({super.key, this.privateKeyFilePicker, this.onInstallKey});

  /// 테스트에서 파일 선택기를 대체한다. null이면 file_picker를 쓴다.
  final Future<String?> Function()? privateKeyFilePicker;

  /// "서버에 등록" 흐름(Task 12). null이면 버튼을 숨긴다.
  final Future<void> Function(SshKey key)? onInstallKey;

  @override
  ConsumerState<KeychainPage> createState() => _KeychainPageState();
}

class _KeychainPageState extends ConsumerState<KeychainPage> {
  static const _maxKeyBytes = 256 * 1024;

  Future<String?> _pickPrivateKeyFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    if (bytes.length > _maxKeyBytes) {
      throw const FormatException('개인키 파일이 너무 큽니다');
    }
    return utf8.decode(bytes);
  }

  Future<void> _create() async {
    final created = await showSshKeyCreateSheet(
      context,
      ref,
      onInstall: widget.onInstallKey,
    );
    if (created != null) {
      ref.read(telemetryProvider).logEvent(TelemetryEvent.keychainKeyCreate());
    }
  }

  Future<void> _import() async {
    final count = await showSshKeyImportSheet(
      context,
      ref,
      pickFile: widget.privateKeyFilePicker ?? _pickPrivateKeyFile,
    );
    if (!mounted || count == 0) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$count개 키를 가져왔습니다')));
  }

  Future<void> _rename(SshKey key) async {
    final controller = TextEditingController(text: key.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('키 이름 변경'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    await ref.read(sshKeyRepositoryProvider).rename(key.id, name);
    if (!mounted) return;
    ref.invalidate(sshKeyListProvider);
  }

  Future<void> _delete(SshKey key) async {
    final repo = ref.read(sshKeyRepositoryProvider);
    final used = await repo.usageCount(key.id);
    if (!mounted) return;
    if (used > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이 키를 사용하는 Identity/호스트가 $used개 있어 삭제할 수 없습니다')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${key.name} 키 삭제'),
        content: const Text('개인키가 이 기기에서 지워집니다. 되돌릴 수 없습니다.'),
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
    if (!mounted) return;
    try {
      await repo.delete(key.id);
      if (!mounted) return;
      ref.invalidate(sshKeyListProvider);
    } on SshKeyInUseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteIdentity(Identity identity) async {
    final repo = ref.read(identityRepositoryProvider);
    try {
      await repo.delete(identity.id);
      if (!mounted) return;
      ref.invalidate(identityListProvider);
    } on IdentityInUseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(sshKeyListProvider);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _SectionHeader(
          title: 'SSH 키',
          actions: [
            TextButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('가져오기'),
            ),
            FilledButton.tonalIcon(
              onPressed: _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('키 만들기'),
            ),
          ],
        ),
        keys.when(
          data: (list) => list.isEmpty
              ? _EmptyKeys(onCreate: _create)
              : Column(
                  children: [
                    for (final key in list) ...[
                      _KeyTile(
                        sshKey: key,
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: key.publicKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('공개키를 복사했습니다')),
                          );
                        },
                        onRename: () => _rename(key),
                        onDelete: () => _delete(key),
                        onInstall: widget.onInstallKey == null
                            ? null
                            : () => widget.onInstallKey!(key),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('키를 불러오지 못했습니다: $e'),
        ),
        const SizedBox(height: 20),
        _SectionHeader(
          title: 'Identity',
          actions: [
            FilledButton.tonalIcon(
              onPressed: () async {
                await showIdentityEditSheet(context, ref);
              },
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Identity 추가'),
            ),
          ],
        ),
        ref
            .watch(identityListProvider)
            .when(
              data: (list) => list.isEmpty
                  ? const Text(
                      '사용자명과 인증 방식을 묶어 여러 호스트에서 재사용합니다.',
                      style: TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 12,
                      ),
                    )
                  : Column(
                      children: [
                        for (final identity in list) ...[
                          ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(
                                color: VibeColors.borderSoft,
                              ),
                            ),
                            tileColor: VibeColors.surfaceHigh,
                            leading: const Icon(Icons.person_outline),
                            title: Text(identity.label),
                            subtitle: Text(identity.summary),
                            onTap: () => showIdentityEditSheet(
                              context,
                              ref,
                              existing: identity,
                            ),
                            trailing: IconButton(
                              tooltip: '삭제',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _deleteIdentity(identity),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Identity를 불러오지 못했습니다: $e'),
            ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class _EmptyKeys extends StatelessWidget {
  const _EmptyKeys({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: VibeColors.borderSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('공개키 인증이란?', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          '비밀번호 대신 쓰는 열쇠 한 쌍입니다. 개인키는 이 기기에만 남고, 공개키를 서버에 등록하면 '
          '비밀번호 입력 없이 안전하게 접속할 수 있습니다.',
          style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('키 만들기'),
        ),
      ],
    ),
  );
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({
    required this.sshKey,
    required this.onCopy,
    required this.onRename,
    required this.onDelete,
    this.onInstall,
  });
  final SshKey sshKey;
  final VoidCallback onCopy;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: VibeColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: VibeColors.borderSoft),
    ),
    child: Row(
      children: [
        const Icon(Icons.vpn_key_outlined, color: VibeColors.onSurfaceDim),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sshKey.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${sshKey.keyType} · ${sshKey.shortFingerprint}',
                style: const TextStyle(
                  color: VibeColors.onSurfaceDim,
                  fontSize: 12,
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'copy' => onCopy(),
            'install' => onInstall?.call(),
            'rename' => onRename(),
            'delete' => onDelete(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('공개키 복사')),
            if (onInstall != null)
              const PopupMenuItem(value: 'install', child: Text('서버에 등록')),
            const PopupMenuItem(value: 'rename', child: Text('이름 변경')),
            const PopupMenuItem(value: 'delete', child: Text('삭제')),
          ],
        ),
      ],
    ),
  );
}
