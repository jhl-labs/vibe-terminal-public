import '../../risk_classifier.dart';
import 'approval_prompt.dart';

/// 자율사용 승인 결정. [allow]가 false면 사람에게 알리고 키를 보내지 않는다.
class ApprovalDecision {
  const ApprovalDecision.allow() : allow = true, reason = '일반 요청';
  const ApprovalDecision.notify(this.reason) : allow = false;

  final bool allow;
  final String reason;
}

/// "위험하지 않으면 이번만 승인" 규칙. 위에서부터 처음 걸리는 규칙으로 결정한다.
/// 검사 순서(우회 → 비밀 → 배포)는 알림 사유 문구에만 영향을 준다.
///
/// 보안 경계가 아니다([RiskClassifier]와 같은 한계). 사람이 세션 단위로 켜는
/// 편의 기능에서 명백히 되돌리기 어려운 요청을 걸러 내는 1차 필터다.
class ApprovalPolicy {
  const ApprovalPolicy({this.risk = const RiskClassifier()});

  final RiskClassifier risk;

  static final List<(RegExp, String)> _secretPaths = [
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.ssh(?:/|\b)'), '비밀 경로: ~/.ssh'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.kube(?:/|\b)'), '비밀 경로: ~/.kube'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.env(?:\.[\w-]+)?\b'), '비밀 경로: .env'),
    (RegExp(r'\bid_(?:rsa|ed25519|ecdsa)\b'), '비밀 경로: SSH 개인키'),
    (RegExp(r'\bcredentials\b'), '비밀 경로: credentials'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.netrc\b'), '비밀 경로: .netrc'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.aws/'), '비밀 경로: ~/.aws'),
    (RegExp(r'\.docker/config\.json'), '비밀 경로: docker config'),
    (
      RegExp(r'\b(?:vault|openbao|bao)[-_]?token\b|\.vault-token\b'),
      '비밀 경로: vault 토큰',
    ),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.npmrc\b'), '비밀 경로: .npmrc'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.pypirc\b'), '비밀 경로: .pypirc'),
    (RegExp(r'\bgh/hosts\.ya?ml\b'), '비밀 경로: gh 인증'),
    (
      RegExp(r'\.(?:pem|key|p12|pfx)(?=$|[\s\x27\x22;&|)])'),
      '비밀 경로: 개인키·인증서 파일',
    ),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.envrc\b'), '비밀 경로: .envrc'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])\.gnupg\b'), '비밀 경로: ~/.gnupg'),
    (RegExp(r'/proc/[^/\s]+/environ\b'), '비밀: 프로세스 환경 변수'),
    // 인자 없는 env/printenv는 환경 변수 전체(토큰 포함)를 출력한다.
    // `env FOO=1 cmd`처럼 명령 앞에 변수를 붙이는 쓰임은 허용한다.
    (
      RegExp(r'(?:^|[;&|(]\s*)(?:env|printenv)\s*(?=$|[|;&>)])'),
      '비밀: 환경 변수 전체 출력',
    ),
    (
      RegExp(r'\bprintenv\s+\w*(?:token|secret|pass|key|cred)\w*'),
      '비밀: 비밀 환경 변수 출력',
    ),
  ];

  static final List<(RegExp, String)> _deploy = [
    (RegExp(r'\bgit\b[^\n;&|]*\bpush\b'), '배포: git push'),
    (RegExp(r'\bhelm\b[^\n;&|]*\b(?:install|upgrade|rollback)\b'), '배포: helm'),
    (
      RegExp(
        r'\bkubectl\b[^\n;&|]*\b(?:apply|create|patch|replace|rollout|scale'
        r'|set|edit|label|annotate|delete|drain|cordon|taint)\b',
      ),
      '배포: kubectl',
    ),
    (
      RegExp(
        r'\bnpm\s+publish\b|\bdart\s+pub\s+publish\b|\bflutter\s+pub\s+publish\b',
      ),
      '배포: 패키지 발행',
    ),
    (RegExp(r'\b(?:docker|podman)\s+(?:image\s+)?push\b'), '배포: 이미지 push'),
    (RegExp(r'\b(?:docker\s+)?buildx\b[^\n;&|]*--push\b'), '배포: 이미지 push'),
    (
      RegExp(r'\b(?:terraform|tofu)\b[^\n;&|]*\b(?:apply|destroy)\b'),
      '배포: terraform',
    ),
    (RegExp(r'\bargocd\s+app\s+(?:sync|rollback|set|delete)\b'), '배포: argocd'),
    (
      RegExp(r'\b(?:pnpm|yarn|cargo)\s+publish\b|\btwine\s+upload\b'),
      '배포: 패키지 발행',
    ),
    (RegExp(r'\bgh\s+release\b'), '배포: gh release'),
    (RegExp(r'\bgh\s+pr\s+merge\b'), '배포: gh pr merge'),
  ];

  static final List<(RegExp, String)> _harness = [
    (RegExp(r'--dangerously-skip-permissions\b'), '우회: 권한 확인 끄기'),
    (RegExp(r'--yolo\b|--dangerously-bypass-approvals'), '우회: 승인 끄기'),
    // 값은 공백·`=` 뒤에 따옴표로 감쌀 수 있다.
    (
      RegExp(r'--permission-mode[\s=]+[\x27\x22]?bypasspermissions'),
      '우회: 권한 확인 끄기',
    ),
    (
      RegExp(
        r'--ask-for-approval[\s=]+[\x27\x22]?never\b'
        r'|\bcodex\b[^\n]*\s-a[\s=]+[\x27\x22]?never\b',
      ),
      '우회: 승인 끄기',
    ),
    (RegExp(r'--full-auto\b'), '우회: 승인 끄기'),
    (RegExp(r'\bdanger-full-access\b'), '우회: 샌드박스 끄기'),
    (RegExp(r'\.claude\.json\b'), '우회: Claude 전역 설정'),
    (RegExp(r'\.claude/settings(?:\.local)?\.json'), '우회: Claude 권한 설정'),
    (RegExp(r'\.codex/config\.toml'), '우회: Codex 설정'),
    (RegExp(r'(?:^|[/\s\x27\x22=>])opencode\.jsonc?\b'), '우회: OpenCode 권한 설정'),
  ];

  ApprovalDecision decide(ApprovalPrompt prompt) {
    final subject = prompt.subject.trim();
    if (subject.isEmpty) {
      return const ApprovalDecision.notify('요청 내용을 판별하지 못함');
    }
    if (prompt.kind == ApprovalKind.other) {
      return const ApprovalDecision.notify('요청 종류를 판별하지 못함');
    }
    // Windows 경로(`\`)도 같은 규칙으로 걸리도록 `/`로 맞춘다.
    final lower = subject.replaceAll(r'\', '/').toLowerCase();
    if (prompt.kind == ApprovalKind.command) {
      final verdict = risk.classify(subject);
      if (verdict.destructive) {
        return ApprovalDecision.notify('위험 명령: ${verdict.reason}');
      }
    }
    for (final table in [_harness, _secretPaths, _deploy]) {
      for (final (pattern, reason) in table) {
        if (pattern.hasMatch(lower)) return ApprovalDecision.notify(reason);
      }
    }
    return const ApprovalDecision.allow();
  }
}
