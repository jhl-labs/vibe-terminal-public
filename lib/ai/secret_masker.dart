/// 터미널 화면·로그를 AI provider로 보내기 전에 흔한 비밀값을 가린다.
///
/// 보안 경계가 아니라 실수 방지용 그물이다. 화면에 찍힌 API 키·토큰·개인키·
/// 비밀번호 인자가 그대로 외부 서비스에 전송되는 일을 줄이는 것이 목적이며,
/// 모든 형태의 비밀값을 잡아내지는 못한다.
library;

const String kMaskedSecretPlaceholder = '[REDACTED]';

/// 정규식과 치환 함수 쌍. 앞에서부터 순서대로 적용한다.
final List<_SecretRule> _rules = [
  // PEM 개인키 블록 전체(BEGIN ... END 사이 본문 포함).
  _SecretRule(
    RegExp(
      r'-----BEGIN ([A-Z ]*)PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
    ),
    (match) =>
        '-----BEGIN ${match.group(1)}PRIVATE KEY-----\n'
        '$kMaskedSecretPlaceholder\n'
        '-----END ${match.group(1)}PRIVATE KEY-----',
  ),
  // GitHub fine-grained PAT. `ghp_` 규칙보다 먼저 두어 접두사 충돌을 피한다.
  _SecretRule(
    RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
    (_) => 'github_pat_$kMaskedSecretPlaceholder',
  ),
  // GitHub classic PAT.
  _SecretRule(
    RegExp(r'ghp_[A-Za-z0-9]{20,}'),
    (_) => 'ghp_$kMaskedSecretPlaceholder',
  ),
  // OpenAI/Anthropic 스타일 `sk-...` 키.
  _SecretRule(
    RegExp(r'sk-[A-Za-z0-9_-]{8,}'),
    (_) => 'sk-$kMaskedSecretPlaceholder',
  ),
  // AWS access key id.
  _SecretRule(
    RegExp(r'AKIA[0-9A-Z]{16}'),
    (_) => 'AKIA$kMaskedSecretPlaceholder',
  ),
  // `Authorization: Bearer <token>` 등 Bearer 토큰.
  _SecretRule(
    RegExp(r'\bBearer\s+[A-Za-z0-9\-._~+/=]+', caseSensitive: false),
    (match) => '${match.group(0)!.substring(0, 6)} $kMaskedSecretPlaceholder',
  ),
  // `password=...`, `passwd=...`, `token=...` 형태의 값(따옴표 포함 가능).
  _SecretRule(
    RegExp(
      r'''\b(password|passwd|token)(\s*=\s*)("[^"\n]*"|'[^'\n]*'|[^\s'"&;,]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}$kMaskedSecretPlaceholder',
  ),
];

/// [text] 안의 흔한 비밀값을 `[REDACTED]`로 바꾼 사본을 돌려준다.
///
/// 순수 함수이며, 비밀값이 없으면 입력을 그대로 돌려준다.
String maskTerminalSecrets(String text) {
  if (text.isEmpty) return text;
  var masked = text;
  for (final rule in _rules) {
    masked = masked.replaceAllMapped(rule.pattern, rule.replace);
  }
  return masked;
}

class _SecretRule {
  const _SecretRule(this.pattern, this.replace);

  final RegExp pattern;
  final String Function(Match match) replace;
}
