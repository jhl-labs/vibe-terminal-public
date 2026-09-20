import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/theme.dart';
import '../../app/update_checker.dart';
import '../../state/providers.dart';

/// 릴리즈 목록을 가져오는 함수. 화면은 [UpdateChecker.listReleases]를 쓰고,
/// 테스트는 가짜를 넣는다.
typedef ReleaseNotesLoader = Future<List<ReleaseInfo>> Function();

/// 헤더의 버전 라벨을 눌렀을 때 여는 릴리즈 노트 화면(Core 전용).
///
/// GitHub Release 본문을 그대로 보여 준다. 기본 선택은 현재 실행 중인 버전이고,
/// 상단 드롭다운으로 다른 버전(새 버전 포함)의 노트를 볼 수 있다.
Future<void> showReleaseNotesDialog({
  required BuildContext context,
  required String currentVersion,
  required ReleaseNotesLoader load,
  required ExternalUrlLauncher openUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ReleaseNotesDialog(
      currentVersion: currentVersion,
      load: load,
      openUrl: openUrl,
    ),
  );
}

class ReleaseNotesDialog extends StatefulWidget {
  const ReleaseNotesDialog({
    super.key,
    required this.currentVersion,
    required this.load,
    required this.openUrl,
  });

  final String currentVersion;
  final ReleaseNotesLoader load;
  final ExternalUrlLauncher openUrl;

  @override
  State<ReleaseNotesDialog> createState() => _ReleaseNotesDialogState();
}

class _ReleaseNotesDialogState extends State<ReleaseNotesDialog> {
  late Future<List<ReleaseInfo>> _releases;
  String? _selectedVersion;

  @override
  void initState() {
    super.initState();
    _releases = widget.load();
  }

  void _reload() {
    setState(() {
      _releases = widget.load();
      _selectedVersion = null;
    });
  }

  /// 현재 버전이 목록에 있으면 그것, 없으면(아직 릴리즈 전 로컬 빌드 등)
  /// 가장 최신 릴리즈를 고른다.
  ReleaseInfo? _select(List<ReleaseInfo> releases) {
    if (releases.isEmpty) return null;
    final wanted = _selectedVersion ?? widget.currentVersion;
    for (final release in releases) {
      if (release.version == wanted) return release;
    }
    return releases.first;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: VibeColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: FutureBuilder<List<ReleaseInfo>>(
          future: _releases,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _Frame(
                header: _Title(),
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _Frame(
                header: const _Title(),
                body: _Message(
                  icon: Icons.cloud_off_outlined,
                  text: '릴리즈 노트를 불러오지 못했습니다.\n네트워크 연결을 확인해 주세요.',
                  action: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('다시 시도'),
                  ),
                ),
              );
            }
            final releases = snapshot.data ?? const [];
            final selected = _select(releases);
            if (selected == null) {
              return const _Frame(
                header: _Title(),
                body: _Message(
                  icon: Icons.notes_outlined,
                  text: '아직 발행된 릴리즈가 없습니다.',
                ),
              );
            }
            return _Frame(
              header: _Title(
                trailing: _VersionPicker(
                  releases: releases,
                  selected: selected,
                  currentVersion: widget.currentVersion,
                  onChanged: (version) =>
                      setState(() => _selectedVersion = version),
                ),
              ),
              body: _ReleaseBody(release: selected, openUrl: widget.openUrl),
              footer: Row(
                children: [
                  if (selected.publishedAt != null)
                    Text(
                      _formatDate(selected.publishedAt!),
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 12,
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => widget.openUrl(selected.htmlUrl),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('GitHub에서 보기'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatDate(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

class _Frame extends StatelessWidget {
  const _Frame({required this.header, required this.body, this.footer});

  final Widget header;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: header,
        ),
        const Divider(height: 1, color: VibeColors.borderSoft),
        Flexible(child: body),
        if (footer != null) ...[
          const Divider(height: 1, color: VibeColors.borderSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
            child: footer,
          ),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.new_releases_outlined, color: VibeColors.accent),
        const SizedBox(width: 10),
        const Text(
          '릴리즈 노트',
          style: TextStyle(
            color: VibeColors.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const Spacer(),
        if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
        IconButton(
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }
}

class _VersionPicker extends StatelessWidget {
  const _VersionPicker({
    required this.releases,
    required this.selected,
    required this.currentVersion,
    required this.onChanged,
  });

  final List<ReleaseInfo> releases;
  final ReleaseInfo selected;
  final String currentVersion;
  final ValueChanged<String> onChanged;

  String _tag(ReleaseInfo release) {
    if (release.version == currentVersion) return ' (현재)';
    if (compareVersions(release.version, currentVersion) > 0) return ' (새 버전)';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected.version,
        isDense: true,
        dropdownColor: VibeColors.surfaceHigh,
        style: const TextStyle(
          color: VibeColors.onSurface,
          fontFamily: kMonoFontFamily,
          fontFamilyFallback: kMonoFontFallback,
          fontSize: 12,
        ),
        items: [
          for (final release in releases)
            DropdownMenuItem(
              value: release.version,
              child: Text('v${release.version}${_tag(release)}'),
            ),
        ],
        onChanged: (version) {
          if (version != null) onChanged(version);
        },
      ),
    );
  }
}

class _ReleaseBody extends StatelessWidget {
  const _ReleaseBody({required this.release, required this.openUrl});

  final ReleaseInfo release;
  final ExternalUrlLauncher openUrl;

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(
      color: VibeColors.onSurfaceMuted,
      fontSize: 13,
      height: 1.45,
    );
    final heading = body.copyWith(
      color: VibeColors.onSurface,
      fontWeight: FontWeight.w800,
    );
    final text = release.body.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(release.name, style: heading.copyWith(fontSize: 16)),
          const SizedBox(height: 10),
          if (text.isEmpty)
            const Text('이 릴리즈에는 작성된 노트가 없습니다.', style: body)
          else
            MarkdownBody(
              data: text,
              selectable: true,
              shrinkWrap: true,
              onTapLink: (_, href, _) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null) openUrl(uri);
              },
              styleSheet: MarkdownStyleSheet(
                p: body,
                listBullet: body,
                strong: heading,
                a: const TextStyle(color: VibeColors.secondary),
                h1: heading.copyWith(fontSize: 17),
                h2: heading.copyWith(fontSize: 15),
                h3: heading.copyWith(fontSize: 14),
                code: body.copyWith(
                  fontFamily: kMonoFontFamily,
                  fontFamilyFallback: kMonoFontFallback,
                  color: VibeColors.accent,
                  backgroundColor: VibeColors.surfacePressed,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: VibeColors.onSurfaceDim),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VibeColors.onSurfaceMuted),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
