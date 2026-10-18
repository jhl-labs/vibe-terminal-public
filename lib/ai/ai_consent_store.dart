import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/app_settings.dart';

final aiConsentStoreProvider = Provider<AiConsentStore>(
  (ref) => AiConsentStore(),
);

/// Local consent receipts contain only a hash of the destination and disclosure.
class AiConsentStore {
  AiConsentStore({this.directory});

  final Future<Directory> Function()? directory;
  static const disclosureVersion = 2;
  final Set<String> _sessionApprovals = {};
  static String destinationKey(AiSettings settings) =>
      '${settings.provider.name}\n${settings.baseUrl.trim()}';

  Future<File> _receipt(String destination) async {
    final root = await (directory?.call() ?? getApplicationSupportDirectory());
    final digest = sha256.convert(utf8.encode(destination));
    return File('${root.path}/ai-consent/v$disclosureVersion-$digest');
  }

  Future<bool> isApproved(String destination) async {
    if (_sessionApprovals.contains(destination)) return true;
    try {
      return await (await _receipt(destination)).readAsString() == 'approved';
    } catch (_) {
      return false;
    }
  }

  Future<bool> approve(String destination) async {
    _sessionApprovals.add(destination);
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
