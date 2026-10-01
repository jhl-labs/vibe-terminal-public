import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/ssh_key_repository.dart';
import '../../data/models/ssh_key.dart';
import '../../security/ssh_key_scanner.dart';
import '../../state/providers.dart';
import '../../security/secure_screen.dart';

/// 파일 또는 `~/.ssh` 스캔으로 개인키를 가져온다. 가져온 개수를 돌려준다.
Future<int> showSshKeyImportSheet(
  BuildContext context,
  WidgetRef ref, {
  required Future<String?> Function() pickFile,
}) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ImportSheet(ref: ref, pickFile: pickFile),
  );
  return result ?? 0;
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.ref, required this.pickFile});
  final WidgetRef ref;
  final Future<String?> Function() pickFile;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  List<SshKeyCandidate>? _candidates;
  final _selected = <String>{};
  bool _busy = false;

  Future<void> _scan() async {
    final dir = SshKeyScanner.defaultDirectory();
    final found = dir == null
        ? const <SshKeyCandidate>[]
        : await SshKeyScanner.scan(dir);
    if (!mounted) return;
    setState(() {
      _candidates = found;
      _selected
        ..clear()
        ..addAll(found.map((c) => c.path));
    });
  }

  /// PEM 하나를 저장한다. [name]이 비어 있으면 키 자체의 comment를 이름으로 쓴다
  /// (`SshKeyRepository.create` 규칙). [label]은 스낵바 등 사용자 메시지에만
  /// 쓰는 표시용 이름으로, 빈 문자열이 되지 않도록 파일 가져오기는 '가져온 키',
  /// 스캔은 파일명을 넘긴다. 암호화된 키면 패스프레이즈를 묻고 한 번 더 시도한다.
  /// 저장했으면 true.
  Future<bool> _importPem(
    String pem, {
    required String name,
    required String label,
  }) async {
    final repo = widget.ref.read(sshKeyRepositoryProvider);
    String? passphrase;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await repo.create(
          name: name,
          privateKeyPem: pem,
          passphrase: passphrase,
          source: SshKeySource.imported,
        );
        return true;
      } on DuplicateSshKeyException catch (e) {
        _notify('${e.existing.name} 키와 같아서 건너뛰었습니다');
        return false;
      } on FormatException {
        if (attempt == 1 || !mounted) break;
        passphrase = await _askPassphrase(label);
        if (passphrase == null) return false;
      }
    }
    _notify('$label: 개인키 형식 또는 패스프레이즈를 확인하세요');
    return false;
  }

  Future<String?> _askPassphrase(String label) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label 패스프레이즈'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('건너뛰기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fromFile() async {
    setState(() => _busy = true);
    try {
      final pem = await widget.pickFile();
      if (pem == null) return;
      final ok = await _importPem(pem, name: '', label: '가져온 키');
      if (!mounted) return;
      widget.ref.invalidate(sshKeyListProvider);
      Navigator.pop(context, ok ? 1 : 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromScan() async {
    setState(() => _busy = true);
    var imported = 0;
    try {
      for (final c in _candidates!.where((c) => _selected.contains(c.path))) {
        final pem = await c.read();
        if (await _importPem(pem, name: c.fileName, label: c.fileName)) {
          imported++;
        }
      }
      if (!mounted) return;
      widget.ref.invalidate(sshKeyListProvider);
      Navigator.pop(context, imported);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    return SecureScreenScope(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SSH 키 가져오기',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fromFile,
              icon: const Icon(Icons.file_open),
              label: const Text('파일 선택'),
            ),
            if (_isDesktop) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.folder_open),
                label: const Text('~/.ssh 스캔'),
              ),
            ],
            if (candidates != null) ...[
              const SizedBox(height: 12),
              if (candidates.isEmpty)
                const Text('~/.ssh 에서 개인키를 찾지 못했습니다')
              else ...[
                for (final c in candidates)
                  CheckboxListTile(
                    dense: true,
                    value: _selected.contains(c.path),
                    title: Text(c.fileName),
                    subtitle: c.encrypted
                        ? const Text('암호화됨 — 패스프레이즈를 묻습니다')
                        : null,
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selected.add(c.path)
                          : _selected.remove(c.path),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy || _selected.isEmpty ? null : _fromScan,
                  child: Text('${_selected.length}개 가져오기'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
