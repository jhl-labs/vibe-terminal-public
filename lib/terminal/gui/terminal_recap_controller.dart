import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../ai/ai_chat_service.dart';
import '../../ai/secret_masker.dart';
import '../../ai/terminal_recap.dart';
import '../../settings/app_settings.dart';
import 'terminal_gui_document.dart';

/// 세션에서 사용자가 입력한 메시지·명령을 오래된 순으로 돌려준다.
typedef TerminalRecapInputLoader = Future<List<String>> Function();

/// 퍼피 ReCap 말풍선의 세션 단위 요청 상태.
///
/// 사용자가 퍼피를 눌렀을 때만 화면을 읽고 모델을 호출한다. 닫기·세션 전환·
/// 설정 변경은 generation을 올려 진행 중 요청을 취소하고, 늦게 도착한 응답은
/// 버린다. 요약은 표시만 하며 터미널에 아무것도 입력하지 않는다.
class TerminalRecapController extends ChangeNotifier {
  TerminalRecapController(this.terminal, {this.loadInputs});

  final Terminal terminal;
  final TerminalRecapInputLoader? loadInputs;

  AiSettings? _settings;
  AiChatService? _service;
  AiCancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;

  /// 말풍선 표시 여부. 로딩·오류·결과 상태 모두에서 true다.
  bool open = false;
  bool busy = false;
  String? error;
  List<String> lines = const [];

  bool get configured => _settings?.isConfigured == true && _service != null;

  void configure(AiSettings? settings, AiChatService? service) {
    if (!identical(settings, _settings) || !identical(service, _service)) {
      dismiss();
    }
    _settings = settings;
    _service = service;
  }

  /// [consent]가 허락하면 현재 화면과 입력 기록으로 새 요약을 요청한다.
  Future<void> request(Future<bool> Function(AiSettings) consent) async {
    if (_disposed || !configured || busy) return;
    _invalidate();
    final generation = _generation;
    final settings = _settings!;
    final service = _service!;
    open = true;
    busy = true;
    error = null;
    lines = const [];
    notifyListeners();
    bool valid() => !_disposed && generation == _generation;
    try {
      if (!await consent(settings)) {
        // 동의하지 않으면 오류 없이 말풍선을 닫는다.
        if (valid()) dismiss();
        return;
      }
      if (!valid()) return;
      final output = TerminalGuiDocument.capture(
        terminal,
        maxLines: TerminalRecapService.outputLines,
        maxCharacters: 12000,
      ).text;
      final inputs = await _inputs();
      if (!valid()) return;
      final token = _cancel = AiCancelToken();
      final result = await token.run(
        () => TerminalRecapService(service).summarize(
          settings: settings,
          inputs: inputs,
          output: output,
          cancelToken: token,
        ),
      );
      if (valid()) lines = result;
    } on AiChatCancelledException {
      // 닫기·전환으로 취소된 요청은 실패 메시지를 남기지 않는다.
    } catch (e) {
      if (valid()) {
        error = maskTerminalSecrets(
          e is AiChatException
              ? e.message
              : 'ReCap 요약을 가져오지 못했습니다. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (valid()) {
        busy = false;
        _cancel = null;
        notifyListeners();
      }
    }
  }

  /// 세션 로그를 읽지 못해도 화면 출력만으로 요약한다.
  Future<List<String>> _inputs() async {
    try {
      return await loadInputs?.call() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 진행 중 요청을 취소하고 말풍선을 닫는다.
  void dismiss() {
    _invalidate();
    final changed = open || busy || error != null || lines.isNotEmpty;
    open = false;
    busy = false;
    error = null;
    lines = const [];
    if (changed && !_disposed) notifyListeners();
  }

  void _invalidate() {
    _generation++;
    _cancel?.cancel();
    _cancel = null;
  }

  @override
  void dispose() {
    _disposed = true;
    dismiss();
    super.dispose();
  }
}
