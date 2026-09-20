import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/host.dart';
import '../../data/models/identity.dart';
import '../../state/providers.dart';

/// Identity 생성/편집 시트. 호스트 편집(Task 11)에서도 재사용한다.
Future<Identity?> showIdentityEditSheet(
  BuildContext context,
  WidgetRef ref, {
  Identity? existing,
}) {
  return showModalBottomSheet<Identity>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IdentitySheet(ref: ref, existing: existing),
  );
}

class _IdentitySheet extends StatefulWidget {
  const _IdentitySheet({required this.ref, this.existing});
  final WidgetRef ref;
  final Identity? existing;

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  final _label = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  HostAuthType _authType = HostAuthType.password;
  String? _keyId;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _label.text = e.label;
      _username.text = e.username;
      _authType = e.authType;
      _keyId = e.keyId;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final username = _username.text.trim();
    if (label.isEmpty || username.isEmpty) {
      setState(() => _error = '라벨과 사용자명을 입력하세요');
      return;
    }
    if (_authType == HostAuthType.publicKey && _keyId == null) {
      setState(() => _error = '사용할 키를 선택하세요');
      return;
    }
    if (_authType == HostAuthType.password &&
        widget.existing?.secretRef == null &&
        _password.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final existing = widget.existing;
      final saved = await widget.ref
          .read(identityRepositoryProvider)
          .upsert(
            Identity(
              id: existing?.id ?? 'identity-${now.microsecondsSinceEpoch}',
              label: label,
              username: username,
              authType: _authType,
              keyId: _authType == HostAuthType.publicKey ? _keyId : null,
              secretRef: _authType == HostAuthType.password
                  ? existing?.secretRef
                  : null,
              hostScoped: existing?.hostScoped ?? false,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
            password: _authType == HostAuthType.password
                ? _password.text
                : null,
          );
      if (!mounted) return;
      widget.ref.invalidate(identityListProvider);
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) setState(() => _error = 'Identity를 저장하지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.ref.read(sshKeyListProvider).value ?? const [];
    return Padding(
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
          Text(
            widget.existing == null ? '새 Identity' : 'Identity 편집',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('identity-label'),
            controller: _label,
            decoration: const InputDecoration(
              labelText: '라벨',
              hintText: '예: 운영 계정',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('identity-username'),
            controller: _username,
            decoration: const InputDecoration(labelText: '사용자명'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HostAuthType>(
            key: const ValueKey('identity-auth-type'),
            initialValue: _authType,
            decoration: const InputDecoration(labelText: '인증 방식'),
            items: const [
              DropdownMenuItem(
                value: HostAuthType.password,
                child: Text('비밀번호'),
              ),
              DropdownMenuItem(
                value: HostAuthType.publicKey,
                child: Text('공개키'),
              ),
              DropdownMenuItem(
                value: HostAuthType.keyboardInteractive,
                child: Text('키보드 인터랙티브 / 2FA'),
              ),
            ],
            onChanged: (v) => setState(() => _authType = v ?? _authType),
          ),
          const SizedBox(height: 12),
          if (_authType == HostAuthType.password)
            TextField(
              key: const ValueKey('identity-password'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '비밀번호',
                helperText: widget.existing?.secretRef != null
                    ? '비워두면 기존 비밀번호를 유지합니다'
                    : null,
              ),
            )
          else if (_authType == HostAuthType.publicKey)
            keys.isEmpty
                ? const Text('키체인에 먼저 키를 만들거나 가져오세요.')
                : DropdownButtonFormField<String>(
                    key: const ValueKey('identity-key'),
                    initialValue: keys.any((k) => k.id == _keyId)
                        ? _keyId
                        : null,
                    decoration: const InputDecoration(labelText: 'SSH 키'),
                    items: [
                      for (final k in keys)
                        DropdownMenuItem(
                          value: k.id,
                          child: Text('${k.name} · ${k.shortFingerprint}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _keyId = v),
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
            onPressed: _busy ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
