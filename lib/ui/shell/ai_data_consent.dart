import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_edition.dart';

import '../../settings/app_settings.dart';

final aiConsentStoreProvider = Provider<AiConsentStore>(
  (ref) => AiConsentStore(),
);

/// Local consent receipts contain only a hash of the destination and disclosure.
class AiConsentStore {
  AiConsentStore({this.directory});

  final Future<Directory> Function()? directory;
  static const disclosureVersion = 2;

  Future<File> _receipt(String destination) async {
    final root = await (directory?.call() ?? getApplicationSupportDirectory());
    final digest = sha256.convert(utf8.encode(destination));
    return File('${root.path}/ai-consent/v$disclosureVersion-$digest');
  }

  Future<bool> isApproved(String destination) async {
    try {
      return await (await _receipt(destination)).readAsString() == 'approved';
    } catch (_) {
      return false;
    }
  }

  Future<bool> approve(String destination) async {
    try {
      final file = await _receipt(destination);
      await file.parent.create(recursive: true);
      await file.writeAsString('approved', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Remember explicit consent across panel and app restarts, per destination.
/// Bump the disclosure version when the disclosed data processing changes.
class AiDataConsent {
  AiDataConsent({AiConsentStore? store}) : _store = store ?? AiConsentStore();

  final AiConsentStore _store;
  String? _approvedDestination;
  Future<bool>? _pending;

  static String destinationKey(AiSettings settings) =>
      '${settings.provider.name}\n${settings.baseUrl.trim()}';

  Future<bool> request(BuildContext context, AiSettings settings) async {
    final destination = destinationKey(settings);
    if (_approvedDestination == destination) return true;
    // A second action must not start a second request while the dialog is open.
    if (_pending != null) return false;
    final pending = _request(context, settings, destination);
    _pending = pending;
    try {
      return await pending;
    } finally {
      _pending = null;
    }
  }

  Future<bool> _request(
    BuildContext context,
    AiSettings settings,
    String destination,
  ) async {
    if (await _store.isApproved(destination)) {
      _approvedDestination = destination;
      return true;
    }
    if (!context.mounted) return false;
    final uri = Uri.tryParse(settings.baseUrl.trim());
    final custom = settings.provider.needsBaseUrl;
    // Never display embedded URL credentials, paths or query tokens.
    final recipient = custom && uri != null && uri.host.isNotEmpty
        ? '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'
        : settings.provider.label;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('AI 데이터 전송 동의'),
        content: SingleChildScrollView(
          child: Text(
            '수신 서비스: $recipient\n\n'
            '답변 생성을 위해 질문·대화 기록과 터미널 화면의 명령, 서버 응답, '
            '호스트 정보 및 로그 내용이 선택한 AI 서비스로 전송됩니다. '
            '로그 포함을 끈 경우에도 AI가 이전 내역을 요청하면 세션 로그가 '
            '추가 전송될 수 있습니다.\n\n'
            '붙여넣은 파일 내용, 비밀번호, API 키 등 민감한 정보가 포함될 수 '
            '있습니다. 자동 마스킹은 모든 비밀값을 제거하지 못합니다. '
            '서비스의 보관·삭제 정책과 API 이용 요금이 적용될 수 있습니다.\n\n'
            '${custom && uri?.scheme == 'http' ? '이 HTTP 연결은 전송 내용을 암호화하지 않습니다.\n\n' : ''}'
            '동의는 이 기기에 저장되어 같은 AI 서비스와 서버 주소에 적용됩니다. '
            '새 전송 대상이나 데이터 처리 안내가 변경되면 다시 확인합니다. 동의하지 않아도 '
            'SSH와 터미널을 사용할 수 있습니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final edition = AppEdition.current == AppEdition.core
                  ? 'core'
                  : 'pro';
              final opened = await launchUrl(
                Uri.parse(
                  'https://jhl-labs.github.io/vibe-terminal/$edition/privacy/',
                ),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('개인정보처리방침을 열 수 없습니다.')),
                );
              }
            },
            child: const Text('개인정보처리방침'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('동의하고 사용'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    _approvedDestination = destination;
    final saved = await _store.approve(destination);
    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동의를 저장하지 못했습니다. 다음에 다시 확인할 수 있습니다.')),
      );
    }
    return true;
  }
}
