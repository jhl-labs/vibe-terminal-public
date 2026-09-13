import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';

class AiMessageRenderer extends StatelessWidget {
  const AiMessageRenderer({
    super.key,
    required this.markdown,
    required this.isAssistant,
    required this.isError,
    required this.onSubmitTerminalInput,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
  });

  final String markdown;
  final bool isAssistant;
  final bool isError;
  final ValueChanged<String> onSubmitTerminalInput;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final parts = _splitFencedBlocks(markdown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          switch (parts[i]) {
            _MarkdownPart(:final text) => _MarkdownText(
              text: text,
              isError: isError,
              fontFamily: fontFamily,
              fontFallback: fontFallback,
              fontSize: fontSize,
            ),
            _CodePart(:final language, :final code) => _CodeBlock(
              language: language,
              code: code,
              showSubmit: isAssistant && _isTerminalInputLanguage(language),
              onSubmit: onSubmitTerminalInput,
              fontFamily: fontFamily,
              fontFallback: fontFallback,
              fontSize: fontSize,
            ),
          },
        ],
      ],
    );
  }
}

sealed class _MessagePart {
  const _MessagePart();
}

class _MarkdownPart extends _MessagePart {
  const _MarkdownPart(this.text);

  final String text;
}

class _CodePart extends _MessagePart {
  const _CodePart({required this.language, required this.code});

  final String language;
  final String code;
}

List<_MessagePart> _splitFencedBlocks(String source) {
  final parts = <_MessagePart>[];
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final markdownBuffer = StringBuffer();
  final codeBuffer = StringBuffer();
  var inFence = false;
  var language = '';

  void flushMarkdown() {
    final text = markdownBuffer.toString().trimRight();
    if (text.trim().isNotEmpty) parts.add(_MarkdownPart(text));
    markdownBuffer.clear();
  }

  void flushCode() {
    parts.add(
      _CodePart(language: language, code: codeBuffer.toString().trimRight()),
    );
    codeBuffer.clear();
    language = '';
  }

  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      final fence = line.trimLeft();
      if (!inFence) {
        flushMarkdown();
        language = fence.substring(3).trim();
        inFence = true;
      } else {
        flushCode();
        inFence = false;
      }
      continue;
    }

    if (inFence) {
      codeBuffer.writeln(line);
    } else {
      markdownBuffer.writeln(line);
    }
  }

  if (inFence) {
    markdownBuffer
      ..writeln('```$language')
      ..write(codeBuffer);
  }
  flushMarkdown();
  return parts;
}

String _normalizedLanguage(String language) {
  final token = language.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
  return token.toLowerCase();
}

bool _isTerminalInputLanguage(String language) {
  const terminalLanguages = {
    'terminal',
    'shell',
    'bash',
    'sh',
    'zsh',
    'fish',
    'powershell',
    'pwsh',
    'cmd',
  };
  return terminalLanguages.contains(_normalizedLanguage(language));
}

bool _isMermaidLanguage(String language) =>
    _normalizedLanguage(language) == 'mermaid';

bool _isPlotlyLanguage(String language) {
  final normalized = _normalizedLanguage(language);
  return normalized == 'plotly' ||
      normalized == 'plotly-json' ||
      normalized == 'plotly.js' ||
      normalized == 'plotlyjs';
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({
    required this.text,
    required this.isError,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
  });

  final String text;
  final bool isError;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(
      color: isError ? VibeColors.statusError : VibeColors.onSurface,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      fontSize: fontSize,
      height: 1.38,
    );
    final dimStyle = bodyStyle.copyWith(color: VibeColors.onSurfaceMuted);
    final codeStyle = bodyStyle.copyWith(
      color: VibeColors.accent,
      backgroundColor: VibeColors.surfacePressed,
      fontSize: (fontSize - 1).clamp(10.0, 18.0),
      height: 1.32,
    );

    return MarkdownBody(
      data: text,
      selectable: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: bodyStyle,
        strong: bodyStyle.copyWith(
          color: VibeColors.onSurface,
          fontWeight: FontWeight.w800,
        ),
        em: dimStyle.copyWith(fontStyle: FontStyle.italic),
        a: const TextStyle(color: VibeColors.secondary),
        h1: bodyStyle.copyWith(
          color: VibeColors.onSurface,
          fontSize: fontSize + 5,
          fontWeight: FontWeight.w800,
        ),
        h2: bodyStyle.copyWith(
          color: VibeColors.onSurface,
          fontSize: fontSize + 3,
          fontWeight: FontWeight.w800,
        ),
        h3: bodyStyle.copyWith(
          color: VibeColors.onSurface,
          fontSize: fontSize + 1,
          fontWeight: FontWeight.w800,
        ),
        listBullet: bodyStyle,
        tableHead: bodyStyle.copyWith(
          color: VibeColors.onSurface,
          fontWeight: FontWeight.w800,
        ),
        tableBody: bodyStyle.copyWith(height: 1.25),
        tableHeadAlign: TextAlign.left,
        tablePadding: const EdgeInsets.only(bottom: 6),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        tableHeadCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        tableBorder: TableBorder.all(
          color: VibeColors.borderSoft,
          width: 0.8,
          borderRadius: BorderRadius.circular(6),
        ),
        tableCellsDecoration: const BoxDecoration(color: VibeColors.surface),
        tableHeadCellsDecoration: const BoxDecoration(
          color: VibeColors.surfacePressed,
        ),
        blockquote: dimStyle,
        blockquoteDecoration: const BoxDecoration(
          color: VibeColors.surfacePressed,
          border: Border(
            left: BorderSide(color: VibeColors.secondary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        code: codeStyle,
        codeblockDecoration: BoxDecoration(
          color: VibeColors.surfacePressed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VibeColors.borderSoft),
        ),
        codeblockPadding: const EdgeInsets.all(10),
      ),
      onTapLink: (text, href, title) async {
        final uri = Uri.tryParse(href ?? '');
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.showSubmit,
    required this.onSubmit,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
  });

  final String language;
  final String code;
  final bool showSubmit;
  final ValueChanged<String> onSubmit;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizedLanguage(language);
    final visual = _isMermaidLanguage(language) || _isPlotlyLanguage(language);
    return Container(
      decoration: BoxDecoration(
        color: VibeColors.terminal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: showSubmit ? VibeColors.accent : VibeColors.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
            child: Row(
              children: [
                Icon(
                  visual ? Icons.insights : Icons.code,
                  size: 16,
                  color: showSubmit
                      ? VibeColors.accent
                      : VibeColors.onSurfaceDim,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    normalized.isEmpty ? 'code' : normalized,
                    style: const TextStyle(
                      color: VibeColors.onSurfaceDim,
                      fontFamily: kMonoFontFamily,
                      fontFamilyFallback: kMonoFontFallback,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '복사',
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy, size: 16),
                ),
                if (visual)
                  TextButton.icon(
                    onPressed: () =>
                        _openVisualPreview(context, language, code),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('미리보기'),
                  ),
                if (showSubmit)
                  FilledButton.icon(
                    onPressed: () => onSubmit(code),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('OK'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: VibeColors.borderSoft),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              code,
              style: TextStyle(
                color: VibeColors.onSurface,
                fontFamily: fontFamily,
                fontFamilyFallback: fontFallback,
                fontSize: (fontSize - 1).clamp(10.0, 18.0),
                height: 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openVisualPreview(
  BuildContext context,
  String language,
  String code,
) async {
  final html = _isMermaidLanguage(language)
      ? _mermaidHtml(code)
      : _plotlyHtml(language, code);
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}vibe-terminal-preview-${DateTime.now().microsecondsSinceEpoch}.html',
  );
  await file.writeAsString(html, encoding: utf8);

  final launched = await launchUrl(
    file.uri,
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('미리보기를 열 수 없습니다')));
  }
}

String _htmlEscape(String value) => const HtmlEscape().convert(value);

String _jsString(String value) => jsonEncode(value);

String _mermaidHtml(String diagram) =>
    '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Vibe Terminal Mermaid Preview</title>
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: true, theme: 'dark' });
  </script>
  <style>
    body { margin: 0; padding: 24px; background: #080B10; color: #E6EDF3; font-family: system-ui, sans-serif; }
    .mermaid { background: #101720; padding: 20px; border-radius: 8px; }
  </style>
</head>
<body>
  <pre class="mermaid">${_htmlEscape(diagram)}</pre>
</body>
</html>
''';

String _plotlyHtml(String language, String source) {
  final normalized = _normalizedLanguage(language);
  final isJson = normalized == 'plotly' || normalized == 'plotly-json';
  final script = isJson
      ? '''
const figure = ${source.trim()};
Plotly.newPlot('plot', figure.data || figure, figure.layout || {}, figure.config || {responsive: true});
'''
      : source;
  final scriptBody = isJson
      ? script
      : 'const plot = document.getElementById("plot");\n$script';
  return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Vibe Terminal Plotly Preview</title>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    body { margin: 0; padding: 24px; background: #080B10; color: #E6EDF3; font-family: system-ui, sans-serif; }
    #plot { width: min(1100px, 100%); height: 720px; margin: 0 auto; background: #101720; border-radius: 8px; }
    pre { white-space: pre-wrap; color: #ff8c8c; }
  </style>
</head>
<body>
  <div id="plot"></div>
  <script>
    try {
      $scriptBody
    } catch (error) {
      document.body.innerHTML = '<pre>' + ${_jsString('Plotly preview failed: ')} + String(error) + '</pre>';
    }
  </script>
</body>
</html>
''';
}
