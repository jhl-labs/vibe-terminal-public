import 'session_port.dart';

enum SessionBulkAction { input, interrupt, close }

class SessionBulkTarget {
  const SessionBulkTarget(this.id, this.name, this.connectionIdentity);
  final String id;
  final String name;
  final Object connectionIdentity;
}

/// 검토 시점의 연결과 같은 대상에만 동작한다. 한 세션 실패가 다른 결과를 숨기지 않는다.
class SessionBulkExecutor {
  const SessionBulkExecutor(this.registry, this.close);
  final SessionPortRegistry registry;
  final void Function(String id) close;
  Map<String, String> execute(
    List<SessionBulkTarget> targets,
    SessionBulkAction action, {
    String text = '',
    bool submit = false,
  }) {
    if (targets.length > 64) throw ArgumentError('한 번에 최대 64개 세션을 선택하세요.');
    if (action == SessionBulkAction.input &&
        (text.isEmpty || text.length > 8192 || text.contains('\x00'))) {
      throw ArgumentError('입력은 1~8,192자여야 합니다.');
    }
    final results = <String, String>{};
    for (final target in targets) {
      if (results.containsKey(target.id)) continue;
      final current = registry.byId(target.id);
      if (current == null ||
          current.connectionIdentity != target.connectionIdentity ||
          !current.isConnected) {
        results[target.id] = '건너뜀: 연결이 변경되었거나 종료됨';
        continue;
      }
      try {
        switch (action) {
          case SessionBulkAction.input:
            current.sendText(text);
            if (submit) current.submit();
          case SessionBulkAction.interrupt:
            current.sendText('\x03');
          case SessionBulkAction.close:
            close(target.id);
        }
        results[target.id] = action == SessionBulkAction.interrupt
            ? 'Ctrl+C 전송됨 (프로세스 종료 여부는 확인 필요)'
            : '완료';
      } catch (error) {
        results[target.id] = '실패: $error';
      }
    }
    return results;
  }
}
