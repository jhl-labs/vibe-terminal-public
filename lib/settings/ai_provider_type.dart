/// AI 채팅 기능이 지원하는 provider 종류.
enum AiProviderType {
  openai,
  gemini,
  claude,
  openAiCompatible;

  String get label => switch (this) {
    AiProviderType.openai => 'OpenAI',
    AiProviderType.gemini => 'Gemini',
    AiProviderType.claude => 'Claude',
    AiProviderType.openAiCompatible => 'OpenAI compatible',
  };

  String get description => switch (this) {
    AiProviderType.openai => 'OpenAI Chat Completions API',
    AiProviderType.gemini => 'Google Gemini generateContent API',
    AiProviderType.claude => 'Anthropic Messages API',
    AiProviderType.openAiCompatible => '로컬 LLM, 사내 게이트웨이, 호환 프록시',
  };

  String get defaultModel => switch (this) {
    AiProviderType.openai => 'gpt-4.1-mini',
    AiProviderType.gemini => 'gemini-2.5-flash',
    AiProviderType.claude => 'claude-sonnet-4-5',
    AiProviderType.openAiCompatible => 'gpt-4.1-mini',
  };

  String get defaultBaseUrl => switch (this) {
    AiProviderType.openAiCompatible => 'https://api.openai.com/v1',
    _ => '',
  };

  bool get needsBaseUrl => this == AiProviderType.openAiCompatible;

  bool get requiresApiToken => this != AiProviderType.openAiCompatible;
}
