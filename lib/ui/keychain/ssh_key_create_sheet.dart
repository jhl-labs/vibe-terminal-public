import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ssh_key.dart';
import '../../security/ssh_key_generator.dart';
import '../../state/providers.dart';
import '../../security/secure_screen.dart';

/// 이름·패스프레이즈를 받아 Ed25519 키를 만들고 바로 키체인에 저장한다.
/// 저장된 키를 돌려주고, 취소하면 null.
Future<SshKey?> showSshKeyCreateSheet(
  BuildContext context,
  WidgetRef ref, {
  Future<void> Function(SshKey key)? onInstall,
}) {
  return showModalBottomSheet<SshKey>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CreateSheet(ref: ref, onInstall: onInstall),
  );
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.ref, this.onInstall});
  final WidgetRef ref;
  final Future<void> Function(SshKey key)? onInstall;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _name = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  SshKey? _created;

  @override
  void dispose() {
    _name.dispose();
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '키 이름을 입력하세요');
      return;
    }
    if (_passphrase.text != _confirm.text) {
      setState(() => _error = '패스프레이즈가 일치하지 않습니다');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final generated = await SshKeyGenerator.generateEd25519(
        comment: 'vibe-terminal-$name',
        passphrase: _passphrase.text,
      );
      final key = await widget.ref
          .read(sshKeyRepositoryProvider)
          .create(
            name: name,
            privateKeyPem: generated.privateKeyPem,
            passphrase: _passphrase.text,
            source: SshKeySource.generated,
          );
      widget.ref.invalidate(sshKeyListProvider);
      if (!mounted) return;
      setState(() => _created = key);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '키를 만들지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return SecureScreenScope(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: created == null ? _form() : _result(created),
      ),
    );
  }

  Widget _form() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '새 SSH 키 만들기',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text(
        'Ed25519 키를 이 기기에서 만들고 키체인에 안전하게 보관합니다.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('ssh-key-name'),
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '키 이름',
          hintText: '예: 노트북',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('ssh-key-passphrase'),
        controller: _passphrase,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '패스프레이즈 (선택)',
          helperText: '키 파일이 유출돼도 이 암호 없이는 쓸 수 없습니다',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('ssh-key-passphrase-confirm'),
        controller: _confirm,
        obscureText: true,
        decoration: const InputDecoration(labelText: '패스프레이즈 확인'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _generate,
        child: const Text('생성'),
      ),
    ],
  );

  Widget _result(SshKey key) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${key.name} 키를 만들었습니다',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        '아래 공개키를 서버의 ~/.ssh/authorized_keys 에 등록하면 비밀번호 없이 접속할 수 있습니다.',
      ),
      const SizedBox(height: 12),
      SelectableText(
        key.publicKey,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key.publicKey));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('공개키를 복사했습니다')));
            },
            icon: const Icon(Icons.content_copy),
            label: const Text('공개키 복사'),
          ),
          if (widget.onInstall != null)
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context, key);
                await widget.onInstall!(key);
              },
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('서버에 등록'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, key),
            child: const Text('닫기'),
          ),
        ],
      ),
    ],
  );
}
