import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../data/db/app_database.dart';
import '../../state/providers.dart';

/// 핀된 서버 호스트 키 목록. 호스트 목록 페이지의 "Known Hosts" 탭 본문.
class KnownHostsPage extends ConsumerStatefulWidget {
  const KnownHostsPage({super.key});

  @override
  ConsumerState<KnownHostsPage> createState() => _KnownHostsPageState();
}

class _KnownHostsPageState extends ConsumerState<KnownHostsPage> {
  String _query = '';

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _remove(HostKeyRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${row.hostname}:${row.port} 키 삭제'),
        content: const Text('다음 접속 시 서버 키를 다시 확인합니다.'),
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
    if (confirmed != true || !mounted) return;
    await ref
        .read(hostKeyStoreProvider)
        .remove(hostname: row.hostname, port: row.port);
    if (!mounted) return;
    ref.invalidate(knownHostListProvider);
  }

  Future<void> _import({String? path}) async {
    String? content;
    try {
      if (path != null) {
        content = await File(path).readAsString();
      } else {
        final picked = await FilePicker.pickFiles(withData: true);
        final bytes = picked?.files.single.bytes;
        if (bytes == null) return;
        content = utf8.decode(bytes);
      }
      final result = await ref
          .read(hostKeyStoreProvider)
          .importOpenSshKnownHosts(content);
      if (!mounted) return;
      ref.invalidate(knownHostListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.imported}개 가져옴, ${result.skipped}개 건너뜀'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('known_hosts를 가져오지 못했습니다: $e')));
    }
  }

  String? get _defaultKnownHostsPath {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return null;
    final file = File(p.join(home, '.ssh', 'known_hosts'));
    return file.existsSync() ? file.path : null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(knownHostListProvider);
    final defaultPath = _isDesktop ? _defaultKnownHostsPath : null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '호스트 검색',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '가져오기',
                icon: const Icon(Icons.file_download_outlined),
                onSelected: (value) =>
                    _import(path: value == 'default' ? defaultPath : null),
                itemBuilder: (_) => [
                  if (defaultPath != null)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('~/.ssh/known_hosts 가져오기'),
                    ),
                  const PopupMenuItem(
                    value: 'file',
                    child: Text('known_hosts 파일 선택…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.when(
            data: (list) {
              final filtered = list
                  .where(
                    (r) =>
                        _query.isEmpty ||
                        r.hostname.toLowerCase().contains(_query),
                  )
                  .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    list.isEmpty
                        ? '저장된 호스트 키가 없습니다.\n서버에 처음 접속하면 여기에 기록됩니다.'
                        : '검색 결과가 없습니다',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: VibeColors.onSurfaceDim),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _KnownHostTile(
                  row: filtered[i],
                  onCopy: () => Clipboard.setData(
                    ClipboardData(text: filtered[i].fingerprint),
                  ),
                  onDelete: () => _remove(filtered[i]),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('호스트 키를 불러오지 못했습니다: $e')),
          ),
        ),
      ],
    );
  }
}

class _KnownHostTile extends StatelessWidget {
  const _KnownHostTile({
    required this.row,
    required this.onCopy,
    required this.onDelete,
  });

  final HostKeyRow row;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  String _date(DateTime? t) => t == null
      ? '-'
      : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VibeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.hostname}:${row.port}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.keyType} · 저장 ${_date(row.pinnedAt)} · 마지막 확인 ${_date(row.lastSeenAt)}',
                  style: const TextStyle(
                    color: VibeColors.onSurfaceDim,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  row.fingerprint,
                  style: const TextStyle(
                    fontFamily: kMonoFontFamily,
                    fontFamilyFallback: kMonoFontFallback,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '지문 복사',
            icon: const Icon(Icons.content_copy, size: 18),
            onPressed: onCopy,
          ),
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
