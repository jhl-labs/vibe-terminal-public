/// 세션으로 보낼 입력이 파괴적인지 rule-based로 1차 분류한다.
///
/// LLM의 자기 신고와 독립적으로 동작하며, 둘 중 하나라도 위험이면 승인 게이트를
/// 발동한다. 순수 Dart(테스트 가능).
///
/// **보안 경계가 아니다.** 정규식 매칭이므로 변수 치환(`$CMD`), 명령 치환
/// (`$(...)`), base64/eval 인코딩, alias, 셸 함수로 얼마든지 우회할 수 있다.
/// 목적은 사람이 실수로 파괴적인 명령을 흘려보내는 것을 잡는 것이지, 악의적인
/// 우회를 막는 것이 아니다. 실제 방어선은 서버 쪽 권한 설계다.
class RiskVerdict {
  const RiskVerdict({
    required this.destructive,
    this.reason,
    this.usesScreenContext = false,
  });

  final bool destructive;
  final String? reason;

  /// 입력 자체가 아니라 현재 터미널 확인 화면과 결합해 위험해진 경우.
  final bool usesScreenContext;

  static const safe = RiskVerdict(destructive: false);
}

class RiskClassifier {
  const RiskClassifier();

  /// (정규식, 사람이 읽는 근거) 목록. 대소문자 무시.
  static final List<(RegExp, String)> _rules = [
    // 파일/디스크 파괴
    (RegExp(r'\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)\b'), 'rm -rf: 재귀 강제 삭제'),
    (RegExp(r'\brm\s+-[a-z]*r\b'), 'rm -r: 재귀 삭제'),
    (RegExp(r'\bmkfs\b'), 'mkfs: 파일시스템 포맷'),
    (RegExp(r'\bdd\s+if='), 'dd: 저수준 디스크 쓰기'),
    (RegExp(r'\bshred\b'), 'shred: 복구 불가 삭제'),
    (RegExp(r'>\s*/dev/sd[a-z]'), '블록 디바이스 직접 덮어쓰기'),
    (RegExp(r':\(\)\s*\{.*\}\s*;\s*:'), 'fork bomb 의심'),
    // 권한/시스템
    (RegExp(r'\bsudo\b'), 'sudo: 권한 상승'),
    (RegExp(r'\bsu\s+-'), 'su -: 사용자 전환'),
    (RegExp(r'\bchmod\s+-r\s+777\b'), 'chmod -R 777: 광범위 권한 변경'),
    (RegExp(r'\bsystemctl\s+(stop|disable|mask)\b'), 'systemctl 서비스 중단'),
    (RegExp(r'\bkill\s+-9\s+1\b'), 'kill -9 1: init 종료'),
    (RegExp(r'\bshutdown\b|\breboot\b|\bhalt\b|\bpoweroff\b'), '시스템 종료/재시작'),
    // VCS/배포
    (RegExp(r'\bgit\s+push\b.*(--force|-f)\b'), 'git push --force'),
    (RegExp(r'\bgit\s+reset\s+--hard\b'), 'git reset --hard'),
    (RegExp(r'\bgit\s+clean\s+-[a-z]*f'), 'git clean -f: 미추적 파일 삭제'),
    (RegExp(r'\bterraform\s+destroy\b'), 'terraform destroy'),
    (RegExp(r'\bkubectl\s+delete\b'), 'kubectl delete'),
    // DB
    (RegExp(r'\bdrop\s+(table|database|schema)\b'), 'DROP: 스키마 파괴'),
    (RegExp(r'\btruncate\s+table\b|\btruncate\s+\w'), 'TRUNCATE: 테이블 비움'),
    (RegExp(r'\bdelete\s+from\s+\w+\s*;'), 'DELETE FROM (WHERE 없음)'),
    // 정규식으로 원문을 못 보게 만드는 형태. 내용을 알 수 없으므로 위험 취급.
    (RegExp(r'\bbase64\s+(-d|--decode)\b'), 'base64 디코드: 명령 내용을 감춤'),
    (RegExp(r'\|\s*(sudo\s+)?(ba|z|k|da|)sh\b'), '파이프로 셸에 직접 실행'),
    (
      RegExp(r'\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?\w*sh\b'),
      '원격 스크립트를 받아 바로 실행',
    ),
    (RegExp(r'\beval\b'), 'eval: 실행 직전에 만들어지는 명령'),
    // 대량 삭제/이동
    (RegExp(r'\bfind\b[^\n]*\s-delete\b'), 'find -delete: 조건에 걸린 전부 삭제'),
    (RegExp(r'\bfind\b[^\n]*-exec\s+rm\b'), 'find -exec rm: 조건에 걸린 전부 삭제'),
    (RegExp(r'\bxargs\b[^\n]*\brm\b'), 'xargs rm: 목록 전체 삭제'),
    (RegExp(r'>\s*/etc/\w'), '/etc 아래 파일 덮어쓰기'),
    (RegExp(r'\bchown\s+-[a-z]*r\b'), 'chown -R: 광범위 소유자 변경'),
    (RegExp(r'\bchmod\s+-[a-z]*r\b'), 'chmod -R: 광범위 권한 변경'),
    // 컨테이너/클라우드
    (RegExp(r'\bdocker\s+(rm|rmi|system\s+prune)\b'), 'docker 리소스 삭제'),
    (RegExp(r'\bdocker\s+volume\s+(rm|prune)\b'), 'docker 볼륨 삭제'),
    (RegExp(r'\baws\s+s3\s+(rm|rb)\b'), 'aws s3 삭제'),
    (RegExp(r'\bgcloud\b[^\n]*\bdelete\b'), 'gcloud 리소스 삭제'),
    (RegExp(r'\bhelm\s+(uninstall|delete)\b'), 'helm 릴리즈 제거'),
    // 패키지 관리자의 제거·정리
    (
      RegExp(r'\b(apt|apt-get|yum|dnf|apk|pacman)\b[^\n]*\b(remove|purge)\b'),
      '패키지 제거',
    ),
    // classify가 입력을 소문자로 낮추므로 -D와 -d를 구분할 수 없다. 둘 다
    // 브랜치를 지우는 것이니 함께 승인 대상으로 둔다.
    (RegExp(r'\bgit\s+branch\s+-[a-z]*d\b'), 'git branch -d/-D: 브랜치 삭제'),
    (RegExp(r'\bgit\s+checkout\s+--\s'), 'git checkout --: 작업 내용 폐기'),
    (RegExp(r'\bgit\s+restore\b[^\n]*--staged'), 'git restore: 변경 폐기'),
  ];

  RiskVerdict classify(String input, {String screenContext = ''}) {
    final normalized = input.toLowerCase();
    // 주석 줄(#, //)만 있는 경우는 실행되지 않으므로 위험 아님.
    for (final (pattern, reason) in _rules) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      if (_isInsideComment(normalized, match.start)) continue;
      return RiskVerdict(destructive: true, reason: reason);
    }
    if (_confirmsDestructivePrompt(input, screenContext)) {
      return const RiskVerdict(
        destructive: true,
        reason: '현재 화면의 삭제·덮어쓰기 확인에 동의하는 입력',
        usesScreenContext: true,
      );
    }
    return RiskVerdict.safe;
  }

  bool _confirmsDestructivePrompt(String input, String screenContext) {
    if (screenContext.trim().isEmpty) return false;
    final normalizedInput = input.trim().toLowerCase();
    final confirmsWithYes = RegExp(
      r'^(y|yes)(<enter>|\\r|\\n)?$',
    ).hasMatch(normalizedInput);
    final confirmsWithEnter =
        normalizedInput == '<enter>' ||
        normalizedInput == '<return>' ||
        normalizedInput == r'\r' ||
        normalizedInput == r'\n' ||
        input == '\r' ||
        input == '\n' ||
        input == '\r\n';
    if (!confirmsWithYes && !confirmsWithEnter) return false;

    final tail = _screenTail(screenContext, maxLines: 10);
    final lowerTail = tail.toLowerCase();
    final hasDestructiveIntent = RegExp(
      r'\b(delete|remove|removed|destroy|overwrite|erase|drop|truncate|format|uninstall)\b|'
      r'force[ -]?push|reset\s+--hard|clean\s+-[a-z]*f|'
      r'삭제|제거|파기|덮어쓰|초기화|포맷|비우|강제\s*푸시',
    ).hasMatch(lowerTail);
    if (!hasDestructiveIntent) return false;

    final asksForConfirmation = RegExp(
      r'are\s+you\s+sure|confirm|continue\s*\?|proceed\s*\?|'
      r'[\[(]\s*y(?:es)?\s*/\s*n(?:o)?\s*[\])]|type\s+(yes|y)|'
      r'정말|확인|계속하시|진행하시|실행하시',
    ).hasMatch(lowerTail);
    if (!asksForConfirmation) return false;
    if (confirmsWithYes) return true;

    // Enter는 기본 선택이 Yes이거나 Enter 자체가 확인 키로 안내된 경우만 차단한다.
    return RegExp(r'[\[(]\s*Y\s*/\s*n\s*[\])]').hasMatch(tail) ||
        RegExp(
          r'(press|hit)\s+enter\s+to\s+(confirm|continue|proceed)|'
          r'enter\s+to\s+(confirm|continue|proceed)|엔터.*(확인|계속|진행)',
          caseSensitive: false,
        ).hasMatch(tail);
  }

  String _screenTail(String screen, {required int maxLines}) {
    final lines = screen
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  }

  /// 매치가 위치한 줄이 주석(#, // 로 시작)이면 실행되지 않으므로 위험이 아니다.
  /// echo/문자열 인용 안의 위험 문자열은 보수적으로 위험으로 유지한다.
  bool _isInsideComment(String text, int index) {
    final lineStart = text.lastIndexOf('\n', index) + 1;
    final line = text.substring(lineStart, index).trimLeft();
    return line.startsWith('#') || line.startsWith('//');
  }
}
