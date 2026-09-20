import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../data/models/ssh_key.dart';
import '../../security/host_key_store.dart';
import '../../ssh/public_key_installer.dart';
import '../../state/providers.dart';
import '../security/host_key_prompt.dart';
import '../security/keyboard_interactive_prompt.dart';

/// 키 선택 → 비밀번호 입력 → 등록 → 성공 알림 또는 fallback 안내.
///
/// [key]가 null이면 키체인에서 고르는 다이얼로그를 먼저 띄운다. 비밀번호는
/// 이번 접속에만 쓰고 저장하지 않는다.
Future<void> showPublicKeyInstallFlow(
  BuildContext context,
  WidgetRef ref, {
  required Host host,
  SshKey? key,
}) async {
  final selected = key ?? await _pickKey(context, ref);
  if (selected == null || !context.mounted) return;
  if (_usesSharedIdentity(host)) {
    final proceed = await _confirmSharedIdentitySwitch(context);
    if (!proceed || !context.mounted) return;
  }
  final password = await _askPassword(context, host);
  if (password == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text('${host.alias}에 공개키를 등록하는 중…'),
      duration: const Duration(minutes: 2),
    ),
  );
  final result = await ref
      .read(publicKeyInstallerProvider)
      .install(
        host: host,
        key: selected,
        password: password,
        onHostKey: (alias, type, fingerprint, verdict) async {
          if (verdict == HostKeyVerdict.trustedKnown) return true;
          if (!context.mounted) return false;
          return showHostKeyPrompt(
            context,
            hostAlias: alias,
            fingerprint: fingerprint,
            verdict: verdict,
          );
        },
        onKeyboardInteractive: (alias, request) async {
          if (!context.mounted) return null;
          return showKeyboardInteractivePrompt(
            context,
            hostAlias: alias,
            request: request,
          );
        },
      );
  messenger.clearSnackBars();
  ref.invalidate(hostListProvider);
  ref.invalidate(identityListProvider);
  if (!context.mounted) return;
  switch (result) {
    case PublicKeyInstalled():
      messenger.showSnackBar(
        SnackBar(content: Text('${host.alias}: 이제 ${selected.name} 키로 접속합니다')),
      );
    case PublicKeyInstallFailed(:final stage, :final message):
      await _showFallback(
        context,
        host: host,
        key: selected,
        stage: stage,
        message: message,
      );
  }
}

Future<SshKey?> _pickKey(BuildContext context, WidgetRef ref) async {
  final keys = await ref.read(sshKeyRepositoryProvider).getAll();
  if (!context.mounted) return null;
  if (keys.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('키체인에 키가 없습니다. 먼저 키를 만드세요.')));
    return null;
  }
  return showDialog<SshKey>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('등록할 키 선택'),
      children: [
        for (final k in keys)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, k),
            child: Text('${k.name} · ${k.shortFingerprint}'),
          ),
      ],
    ),
  );
}

bool _usesSharedIdentity(Host host) =>
    host.identityId != null && host.identityId != 'host-${host.id}';

/// 공유 Identity 호스트는 등록 후 호스트 전용 Identity로 바뀐다. 진행 전에 알린다.
Future<bool> _confirmSharedIdentitySwitch(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('호스트 전용 Identity로 전환'),
      content: const Text(
        '이 호스트는 공유 Identity를 사용 중입니다. 등록 후에는 이 호스트만 새 키로 '
        '접속하도록 전용 Identity로 전환됩니다. 공유 Identity는 그대로 남습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('계속'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _askPassword(BuildContext context, Host host) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PasswordDialog(host: host),
  );
}

/// 컨트롤러 수명을 다이얼로그에 맞추기 위한 StatefulWidget.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.host});

  final Host host;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    return AlertDialog(
      title: Text('${host.alias} 비밀번호'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${host.username}@${host.hostname} 에 한 번만 비밀번호로 접속해 '
            '공개키를 등록합니다. 비밀번호는 저장하지 않습니다.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '비밀번호'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('등록')),
      ],
    );
  }
}

Future<void> _showFallback(
  BuildContext context, {
  required Host host,
  required SshKey key,
  required PublicKeyInstallStage stage,
  required String message,
}) {
  final reason = switch (stage) {
    PublicKeyInstallStage.connect =>
      '비밀번호 접속에 실패했습니다. 서버가 비밀번호 로그인을 막았거나 비밀번호가 틀렸을 수 있습니다.',
    PublicKeyInstallStage.command =>
      'authorized_keys 파일을 수정하지 못했습니다. 홈 디렉터리 권한이나 셸 제한을 확인하세요.',
    PublicKeyInstallStage.verify =>
      '키가 등록됐지만 키 접속 검증에 실패했습니다. 서버 sshd 설정(PubkeyAuthentication)을 확인하세요.',
  };
  final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  const mono = TextStyle(
    fontFamily: kMonoFontFamily,
    fontFamilyFallback: kMonoFontFallback,
    fontSize: 11,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '자동 등록에 실패했습니다',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(reason),
            const SizedBox(height: 4),
            Text(message, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 16),
            const Text(
              '직접 등록하려면 서버의 ~/.ssh/authorized_keys 파일에 아래 한 줄을 추가하세요:',
            ),
            const SizedBox(height: 8),
            SelectableText(key.publicKey, style: mono),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key.publicKey));
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('공개키를 복사했습니다')));
              },
              icon: const Icon(Icons.content_copy),
              label: const Text('공개키 복사'),
            ),
            if (isDesktop) ...[
              const SizedBox(height: 12),
              const Text('또는 터미널에서:'),
              const SizedBox(height: 4),
              SelectableText(
                PublicKeyInstaller.sshCopyIdHint(
                  username: host.username,
                  hostname: host.hostname,
                  port: host.port,
                ),
                style: mono,
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    ),
  );
}
