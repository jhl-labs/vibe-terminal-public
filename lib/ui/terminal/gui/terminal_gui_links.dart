import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';

Uri? terminalGuiWebUri(String text) {
  final value = text.trim();
  if (RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          const {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty
      ? uri
      : null;
}

class TerminalGuiWebLink {
  const TerminalGuiWebLink(this.start, this.end, this.uri);
  final int start;
  final int end;
  final Uri uri;
}

List<TerminalGuiWebLink> terminalGuiWebLinks(String text) {
  final result = <TerminalGuiWebLink>[];
  for (final match in RegExp(
    r'''https?://[^\s<>"'`]+''',
    caseSensitive: false,
  ).allMatches(text)) {
    var value = match[0]!;
    while (value.endsWith('.') ||
        value.endsWith(',') ||
        value.endsWith(';') ||
        value.endsWith('!')) {
      value = value.substring(0, value.length - 1);
    }
    for (final pair in const [('(', ')'), ('[', ']'), ('{', '}')]) {
      while (value.endsWith(pair.$2) &&
          pair.$2.allMatches(value).length > pair.$1.allMatches(value).length) {
        value = value.substring(0, value.length - 1);
      }
    }
    final uri = terminalGuiWebUri(value);
    if (uri != null) {
      result.add(
        TerminalGuiWebLink(match.start, match.start + value.length, uri),
      );
    }
  }
  return result;
}

Future<void> openTerminalGuiWebLink(BuildContext context, Uri uri) async {
  if (terminalGuiWebUri(uri.toString()) == null) return;
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('브라우저에서 주소를 열 수 없습니다.')));
  }
}

Future<void> showTerminalGuiLinkMenu(
  BuildContext context,
  Uri uri, {
  Offset? position,
}) async {
  if (terminalGuiWebUri(uri.toString()) == null) return;
  ContextMenuController.removeAny();
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final point = position == null
      ? overlay.size.center(Offset.zero)
      : overlay.globalToLocal(position);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(point.dx, point.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        child: Text(
          uri.toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const PopupMenuItem(
        value: 'open',
        child: ListTile(
          leading: Icon(Icons.open_in_new, size: 18),
          title: Text('브라우저에서 열기'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuItem(
        value: 'copy',
        child: ListTile(
          leading: Icon(Icons.link, size: 18),
          title: Text('링크 복사'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
  if (!context.mounted) return;
  if (action == 'open') {
    await openTerminalGuiWebLink(context, uri);
  } else if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
  }
}

Widget terminalGuiSelectionToolbar(
  BuildContext context,
  TextSelectionToolbarAnchors anchors,
  List<ContextMenuButtonItem> items, {
  required String selectedText,
  required VoidCallback hideToolbar,
}) {
  final uri = terminalGuiWebUri(selectedText);
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: [
      ...items.where(
        (item) => const {
          ContextMenuButtonType.copy,
          ContextMenuButtonType.selectAll,
          ContextMenuButtonType.cut,
          ContextMenuButtonType.paste,
        }.contains(item.type),
      ),
      if (uri != null)
        ContextMenuButtonItem(
          label: '브라우저에서 열기',
          onPressed: () {
            hideToolbar();
            unawaited(openTerminalGuiWebLink(context, uri));
          },
        ),
    ],
  );
}

/// Links can span ANSI style runs; the underlying selectable text stays intact.
class TerminalGuiLinkText extends StatefulWidget {
  const TerminalGuiLinkText({
    super.key,
    required this.spans,
    required this.style,
    this.onLink,
  });
  final List<TextSpan> spans;
  final TextStyle style;
  final Future<void> Function(Uri uri, Offset? position)? onLink;
  @override
  State<TerminalGuiLinkText> createState() => _TerminalGuiLinkTextState();
}

class _TerminalGuiLinkTextState extends State<TerminalGuiLinkText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<TerminalGuiWebLink> _links = const [];
  late List<TextSpan> _spans;
  @override
  void initState() {
    super.initState();
    _project();
  }

  @override
  void didUpdateWidget(covariant TerminalGuiLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _project();
  }

  void _project() {
    final text = widget.spans.map((span) => span.text ?? '').join();
    final links = terminalGuiWebLinks(text);
    final sameLinks =
        links.length == _links.length &&
        links.asMap().entries.every((entry) {
          final old = _links[entry.key];
          final next = entry.value;
          return old.start == next.start &&
              old.end == next.end &&
              old.uri == next.uri;
        });
    if (!sameLinks) {
      for (final recognizer in _recognizers) {
        recognizer.dispose();
      }
      _recognizers.clear();
      for (final link in links) {
        Offset? position;
        final recognizer = TapGestureRecognizer();
        recognizer.onTapDown = (details) {
          position = details.globalPosition;
        };
        recognizer.onTap = () {
          unawaited(
            widget.onLink?.call(link.uri, position) ??
                showTerminalGuiLinkMenu(context, link.uri, position: position),
          );
        };
        recognizer.onSecondaryTapUp = (details) {
          unawaited(
            widget.onLink?.call(link.uri, details.globalPosition) ??
                showTerminalGuiLinkMenu(
                  context,
                  link.uri,
                  position: details.globalPosition,
                ),
          );
        };
        _recognizers.add(recognizer);
      }
    }
    _links = links;
    _spans = [];
    var offset = 0;
    var linkIndex = 0;
    for (final span in widget.spans) {
      final value = span.text ?? '';
      var start = offset;
      final end = offset + value.length;
      while (linkIndex < links.length && links[linkIndex].end <= start) {
        linkIndex++;
      }
      for (var i = linkIndex; i < links.length && links[i].start < end; i++) {
        final link = links[i];
        if (link.end <= start || link.start >= end) continue;
        if (link.start > start) {
          _spans.add(
            TextSpan(
              text: text.substring(start, link.start),
              style: span.style,
            ),
          );
        }
        final from = link.start.clamp(start, end);
        final to = link.end.clamp(start, end);
        _spans.add(
          TextSpan(
            text: text.substring(from, to),
            style: (span.style ?? const TextStyle()).copyWith(
              color: VibeColors.accent,
              decoration: TextDecoration.combine([
                span.style?.decoration ?? TextDecoration.none,
                TextDecoration.underline,
              ]),
            ),
            recognizer: _recognizers[i],
          ),
        );
        start = to;
      }
      if (start < end) {
        _spans.add(
          TextSpan(text: text.substring(start, end), style: span.style),
        );
      }
      offset = end;
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(children: _spans), style: widget.style);
}
