import 'package:flutter/material.dart';

import '../../../terminal/gui/terminal_recap_controller.dart';

/// 터미널 우측 하단의 🐶 버튼과 ReCap 말풍선.
///
/// 표시만 담당한다. 요청·취소는 [onRequest]/[onDismiss]로 위임하고 상태는
/// [controller]에서 읽는다. 말풍선은 퍼피 바로 위에 붙어 꼬리로 퍼피를 가리킨다.
class TerminalRecapPuppy extends StatefulWidget {
  const TerminalRecapPuppy({
    super.key,
    required this.controller,
    required this.onRequest,
    required this.onDismiss,
    required this.maxBubbleWidth,
    required this.maxBubbleHeight,
  });

  static const tooltip = 'ReCap: 지금까지 한 작업 3줄 요약';

  /// 퍼피 버튼 한 변 길이. 모바일 빈 공간 long-press 영역을 덜 가리도록 작게 둔다.
  static const buttonSize = 32.0;

  final TerminalRecapController controller;
  final VoidCallback onRequest;
  final VoidCallback onDismiss;
  final double maxBubbleWidth;
  final double maxBubbleHeight;

  @override
  State<TerminalRecapPuppy> createState() => _TerminalRecapPuppyState();
}

class _TerminalRecapPuppyState extends State<TerminalRecapPuppy> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final bubbleHeight =
          widget.maxBubbleHeight - TerminalRecapPuppy.buttonSize - 8;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (controller.open && widget.maxBubbleWidth > 0 && bubbleHeight > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.maxBubbleWidth,
                  maxHeight: bubbleHeight,
                ),
                child: _RecapBubble(
                  controller: controller,
                  onRetry: widget.onRequest,
                  onDismiss: widget.onDismiss,
                ),
              ),
            ),
          _button(context, emphasized: _hovered || controller.open),
        ],
      );
    },
  );

  Widget _button(BuildContext context, {required bool emphasized}) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        // 평소에는 터미널 내용을 가리지 않도록 반투명하게 둔다.
        opacity: emphasized ? 1 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Tooltip(
          message: TerminalRecapPuppy.tooltip,
          child: Semantics(
            button: true,
            label: 'ReCap 퍼피: 지금까지 한 작업 3줄 요약',
            excludeSemantics: true,
            child: Material(
              color: scheme.surfaceContainerHighest,
              elevation: emphasized ? 3 : 1,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('terminal-recap-puppy'),
                onTap: widget.controller.open
                    ? widget.onDismiss
                    : widget.onRequest,
                child: const SizedBox.square(
                  dimension: TerminalRecapPuppy.buttonSize,
                  child: Center(
                    child: Text('🐶', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecapBubble extends StatelessWidget {
  const _RecapBubble({
    required this.controller,
    required this.onRetry,
    required this.onDismiss,
  });

  final TerminalRecapController controller;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = BorderSide(color: theme.dividerColor);
    return Semantics(
      liveRegion: true,
      container: true,
      label: '퍼피 ReCap',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Material(
              key: const ValueKey('terminal-recap-bubble'),
              elevation: 8,
              color: scheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: border,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '퍼피 ReCap',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (!controller.busy && controller.lines.isNotEmpty)
                          IconButton(
                            key: const ValueKey('terminal-recap-refresh'),
                            tooltip: '다시 요약',
                            visualDensity: VisualDensity.compact,
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh, size: 18),
                          ),
                        IconButton(
                          key: const ValueKey('terminal-recap-close'),
                          tooltip: 'ReCap 닫기',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _body(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 퍼피를 가리키는 말풍선 꼬리.
          Padding(
            padding: const EdgeInsets.only(
              right: TerminalRecapPuppy.buttonSize / 2 - 7,
            ),
            child: CustomPaint(
              size: const Size(14, 7),
              painter: _TailPainter(fill: scheme.surface, stroke: border.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.busy) {
      return Row(
        key: const ValueKey('terminal-recap-loading'),
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('🐶 생각 중…', style: theme.textTheme.bodyMedium),
        ],
      );
    }
    if (controller.error case final error?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error,
            key: const ValueKey('terminal-recap-error'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('terminal-recap-retry'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, line) in controller.lines.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
            child: Text(
              line,
              key: ValueKey('terminal-recap-line-$index'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.stroke != stroke;
}
