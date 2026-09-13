import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'custom_headers.dart';
import 'secret_masker.dart';
import '../settings/app_settings.dart';

enum AiChatRole { user, assistant }

class AiChatMessage {
  const AiChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.isError = false,
  });

  final AiChatRole role;
  final String content;
  final DateTime createdAt;
  final bool isError;
}

enum AiChatFailureKind {
  unknown,
  timeout,
  connection,
  rateLimited,
  server,
  authentication,
  configuration,
  invalidResponse,
}

class AiChatException implements Exception {
  AiChatException(this.message, {this.kind = AiChatFailureKind.unknown});

  final String message;
  final AiChatFailureKind kind;

  @override
  String toString() => message;
}

class AiChatCancelledException extends AiChatException {
  AiChatCancelledException() : super('AI 응답을 중단했습니다.');
}

class AiCancelToken {
  bool _cancelled = false;
  final _callbacks = <AiCancelCallback>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final callbacks = List<AiCancelCallback>.from(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) throw AiChatCancelledException();
  }

  AiCancelCallback onCancel(AiCancelCallback callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  /// 소켓/어댑터가 취소에 응답하지 않아도 호출자는 즉시 빠져나온다.
  Future<T> run<T>(Future<T> Function() operation) async {
    throwIfCancelled();
    final cancelled = Completer<T>();
    final unregister = onCancel(
      () => cancelled.completeError(AiChatCancelledException()),
    );
    try {
      return await Future.any([Future<T>.sync(operation), cancelled.future]);
    } finally {
      unregister();
    }
  }
}

typedef AiCancelCallback = void Function();

class AiChatService {
  AiChatService({
    Future<void> Function(Duration)? retryDelay,
    this.requestTimeout = const Duration(seconds: 60),
  }) : _retryDelay = retryDelay ?? _realDelay;

  /// 연결·헤더·본문을 합친 HTTP 시도 한 번의 전체 제한 시간.
  final Duration requestTimeout;
  static const _maxOutputTokens = 2048;

  /// 서버가 응답 헤더도 보내기 전에 연결을 끊었을 때 한 번 더 시도하기 전 대기.
  ///
  /// Ollama의 `:cloud` 모델처럼 업스트림에 프록시하는 서버는 업스트림이 502를
  /// 내면 소켓을 그냥 닫는 경우가 있다. 생성 요청만 한 번 더 시도한다.
  /// 서버가 이미 처리했을 가능성과 추가 과금은 배제할 수 없다.
  static const _transientRetryDelay = Duration(seconds: 1);
  final Future<void> Function(Duration) _retryDelay;

  static Future<void> _realDelay(Duration duration) =>
      Future<void>.delayed(duration);

  Future<List<String>> listModels(AiSettings settings) async {
    final models = switch (settings.provider) {
      AiProviderType.openai => await _listOpenAiModels(
        Uri.parse('https://api.openai.com/v1/models'),
        settings,
        requiresToken: true,
      ),
      AiProviderType.openAiCompatible => await _listOpenAiModels(
        _compatibleModelsEndpoint(settings.baseUrl),
        settings,
        requiresToken: false,
      ),
      AiProviderType.claude => await _listClaudeModels(settings),
      AiProviderType.gemini => await _listGeminiModels(settings),
    };

    final unique = models.toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (unique.isEmpty) {
      throw AiChatException('AI 서버에서 사용할 수 있는 모델을 찾지 못했습니다.');
    }
    return unique;
  }

  Future<String> testConnection(AiSettings settings) async {
    if (!settings.isConfigured) {
      throw AiChatException(
        'Provider, endpoint, model, API token 설정을 확인하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }

    final reply = await complete(
      settings: settings,
      sessionLabel: 'Settings connection test',
      terminalContext: '',
      messages: [
        AiChatMessage(
          role: AiChatRole.user,
          content: 'Connection test. Reply with a short OK.',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ],
    );
    final firstLine = reply.trim().split('\n').first.trim();
    return firstLine.isEmpty ? '연결 성공' : '연결 성공: $firstLine';
  }

  Future<String> complete({
    required AiSettings settings,
    required String sessionLabel,
    required String terminalContext,
    required List<AiChatMessage> messages,
    AiCancelToken? cancelToken,
    String? additionalSystemPrompt,
    String? systemPromptOverride,
  }) async {
    if (!settings.isConfigured) {
      throw AiChatException(
        'AI 설정에서 provider, model, API token을 먼저 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }

    // Agent Chat 오케스트레이터처럼 시스템 프롬프트를 전적으로 제어해야 하는
    // 호출자는 systemPromptOverride로 기본(터미널 편집) 프롬프트를 대체한다.
    final systemPrompt =
        systemPromptOverride ??
        _buildSystemPrompt(
          settings: settings,
          sessionLabel: sessionLabel,
          terminalContext: terminalContext,
          additionalSystemPrompt: additionalSystemPrompt,
        );

    return switch (settings.provider) {
      AiProviderType.openai => _completeOpenAi(
        endpoint: Uri.parse('https://api.openai.com/v1/chat/completions'),
        settings: settings,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      ),
      AiProviderType.openAiCompatible => _completeOpenAi(
        endpoint: _compatibleEndpoint(settings.baseUrl),
        settings: settings,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      ),
      AiProviderType.claude => _completeClaude(
        settings: settings,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      ),
      AiProviderType.gemini => _completeGemini(
        settings: settings,
        systemPrompt: systemPrompt,
        messages: messages,
        cancelToken: cancelToken,
      ),
    };
  }

  String _buildSystemPrompt({
    required AiSettings settings,
    required String sessionLabel,
    required String terminalContext,
    String? additionalSystemPrompt,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are Vibe Terminal AI Chat, an agent assisting inside a terminal app.',
      )
      ..writeln(
        'You can inspect the currently active terminal session context.',
      )
      ..writeln(
        'The terminal context contains at most the most recent ${settings.maxContextLines} lines.',
      )
      ..writeln(
        'The final terminal line is the highest priority signal: it usually contains the active prompt, current command, or latest error. Analyze it first.',
      )
      ..writeln(
        'Do not claim you executed commands. Only reason from the visible terminal context and the user message.',
      )
      ..writeln(
        'When you want the user to send input to the active terminal, put only the exact terminal input in a fenced code block with language `terminal`.',
      )
      ..writeln(
        'The Vibe Terminal UI will render an OK button for `terminal`, `bash`, `sh`, `zsh`, `powershell`, `pwsh`, and `cmd` code blocks. If the user presses OK, that block will be transmitted to the active terminal session.',
      )
      ..writeln(
        'For full-screen terminal programs such as vim, vi, nvim, nano, less, man, top, and htop, you may control the active program by putting key input in a `terminal` fenced code block.',
      )
      ..writeln(
        'The terminal sender understands these key tokens and escape forms inside `terminal` blocks: <Esc>, <Enter>, <Tab>, <Backspace>, <Delete>, <Insert>, <Up>, <Down>, <Left>, <Right>, <Home>, <End>, <PageUp>, <PageDown>, <C-a> through <C-z>, <C-_>, \\n, \\r, \\t, \\e, and \\xNN.',
      )
      ..writeln(
        'For edits, read the visible terminal context line by line and prefer linewise or semantic editor commands. Do not rely on counted repeated <Backspace> or <Delete> to change text, especially for Korean, CJK, emoji, combining characters, tabs, wrapped lines, or proportional-looking screen columns.',
      )
      ..writeln(
        'Vim examples: scroll down with `<C-f>`, scroll up with `<C-b>`, go to a line with `<Esc>:42<Enter>`, search with `<Esc>/pattern<Enter>`, replace the current line with `<Esc>ccnew text<Esc>`, replace from cursor to end of line with `<Esc>Cnew text<Esc>`, replace a known line with `<Esc>:12s#.*#    <p>This page was created by Vibe Terminal AI.</p>#<Enter>`, and replace exact text with `<Esc>:%s#old text#new text#<Enter>`.',
      )
      ..writeln(
        'Nano examples: search with `<C-w>pattern<Enter>`, go to a known line with `<C-_>12<Enter>`, replace a whole line with `<Home><C-k>new text`, cut a line with `<C-k>`, paste it back with `<C-u>`, and move with arrow keys. Prefer whole-line replacement over character-count deletion.',
      )
      ..writeln(
        'When editing in vim/nano, prefer small reversible key sequences and explain the intent before the block. Do not include save or quit actions such as `:w`, `:q`, `:wq`, `<C-o>`, or `<C-x>` unless the user explicitly asks, because saving and exiting are user decisions.',
      )
      ..writeln(
        r'Do not include a shell prompt such as `$` or `PS>` inside executable code blocks. Explain risky or destructive commands before suggesting them.',
      )
      ..writeln(
        'Use Markdown for structured answers. Use fenced `mermaid` blocks for diagrams and fenced `plotly-json` or `plotly.js` blocks for charts when useful.',
      )
      ..writeln(
        'Prefer concise, actionable Korean answers unless the user asks otherwise.',
      )
      ..writeln()
      ..writeln('Active session: $sessionLabel')
      ..writeln('Recent terminal context begins below.')
      ..writeln('--- terminal context begin ---')
      // 화면에 찍힌 API 키·토큰·비밀번호가 provider로 새지 않도록 가린다.
      ..writeln(
        terminalContext.trim().isEmpty
            ? '(empty)'
            : maskTerminalSecrets(terminalContext),
      )
      ..writeln('--- terminal context end ---');

    final customPrompt = settings.customPrompt.trim();
    if (customPrompt.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Additional user-defined instruction:')
        ..writeln(customPrompt);
    }

    final taskPrompt = additionalSystemPrompt?.trim();
    if (taskPrompt != null && taskPrompt.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Task-specific system instruction:')
        ..writeln(taskPrompt);
    }

    return buffer.toString();
  }

  Future<String> _completeOpenAi({
    required Uri endpoint,
    required AiSettings settings,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    AiCancelToken? cancelToken,
  }) async {
    final payload = {
      'model': settings.model.trim(),
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        for (final message in _conversationWindow(messages))
          {
            'role': message.role == AiChatRole.user ? 'user' : 'assistant',
            'content': message.content,
          },
      ],
      'temperature': 0.2,
    };

    final decoded = await _postJson(
      endpoint,
      settings: settings,
      headers: _openAiAuthHeaders(settings),
      payload: payload,
      cancelToken: cancelToken,
    );

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content.trim();
    }
    throw AiChatException(
      'AI 응답에서 텍스트를 찾지 못했습니다.',
      kind: AiChatFailureKind.invalidResponse,
    );
  }

  Future<String> _completeClaude({
    required AiSettings settings,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    AiCancelToken? cancelToken,
  }) async {
    final payload = {
      'model': settings.model.trim(),
      'max_tokens': _maxOutputTokens,
      'system': systemPrompt,
      'messages': [
        for (final message in _conversationWindow(messages))
          {
            'role': message.role == AiChatRole.user ? 'user' : 'assistant',
            'content': message.content,
          },
      ],
    };

    final decoded = await _postJson(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      settings: settings,
      headers: {
        'x-api-key': settings.apiToken.trim(),
        'anthropic-version': '2023-06-01',
      },
      payload: payload,
      cancelToken: cancelToken,
    );

    final content = decoded['content'];
    if (content is List) {
      final text = content
          .map((part) => part is Map ? part['text'] : null)
          .whereType<String>()
          .join('\n')
          .trim();
      if (text.isNotEmpty) return text;
    }
    throw AiChatException(
      'Claude 응답에서 텍스트를 찾지 못했습니다.',
      kind: AiChatFailureKind.invalidResponse,
    );
  }

  Future<String> _completeGemini({
    required AiSettings settings,
    required String systemPrompt,
    required List<AiChatMessage> messages,
    AiCancelToken? cancelToken,
  }) async {
    final model = settings.model.trim().replaceFirst(RegExp(r'^models/'), '');
    // API 키는 URL 쿼리가 아니라 헤더로 보낸다. 쿼리는 프록시·접근 로그에
    // 그대로 남는다.
    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );
    final payload = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        for (final message in _conversationWindow(messages))
          {
            'role': message.role == AiChatRole.user ? 'user' : 'model',
            'parts': [
              {'text': message.content},
            ],
          },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': _maxOutputTokens,
      },
    };

    final decoded = await _postJson(
      endpoint,
      settings: settings,
      headers: _geminiAuthHeaders(settings),
      payload: payload,
      cancelToken: cancelToken,
    );
    final candidates = decoded['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      final content = first is Map ? first['content'] : null;
      final parts = content is Map ? content['parts'] : null;
      if (parts is List) {
        final text = parts
            .map((part) => part is Map ? part['text'] : null)
            .whereType<String>()
            .join('\n')
            .trim();
        if (text.isNotEmpty) return text;
      }
    }
    throw AiChatException(
      'Gemini 응답에서 텍스트를 찾지 못했습니다.',
      kind: AiChatFailureKind.invalidResponse,
    );
  }

  List<AiChatMessage> _conversationWindow(List<AiChatMessage> messages) {
    final visible = messages.where((message) => !message.isError).toList();
    if (visible.length <= 20) return visible;
    return visible.sublist(visible.length - 20);
  }

  Future<List<String>> _listOpenAiModels(
    Uri endpoint,
    AiSettings settings, {
    required bool requiresToken,
  }) async {
    final token = settings.apiToken.trim();
    if (requiresToken && token.isEmpty) {
      throw AiChatException(
        'API token을 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }
    final decoded = await _getJson(
      endpoint,
      settings: settings,
      headers: token.isEmpty ? const {} : {'authorization': 'Bearer $token'},
    );
    return _extractModelIds(decoded['data']);
  }

  Future<List<String>> _listClaudeModels(AiSettings settings) async {
    final token = settings.apiToken.trim();
    if (token.isEmpty) {
      throw AiChatException(
        'Claude API token을 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }
    final decoded = await _getJson(
      Uri.parse('https://api.anthropic.com/v1/models'),
      settings: settings,
      headers: {'x-api-key': token, 'anthropic-version': '2023-06-01'},
    );
    return _extractModelIds(decoded['data']);
  }

  Future<List<String>> _listGeminiModels(AiSettings settings) async {
    final token = settings.apiToken.trim();
    if (token.isEmpty) {
      throw AiChatException(
        'Gemini API token을 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }
    final decoded = await _getJson(
      Uri.https('generativelanguage.googleapis.com', '/v1beta/models'),
      settings: settings,
      headers: _geminiAuthHeaders(settings),
    );
    final models = decoded['models'];
    if (models is! List) return const [];
    return [
      for (final model in models)
        if (model is Map &&
            _supportsGeminiGenerateContent(model['supportedGenerationMethods']))
          if (model['name'] is String)
            (model['name'] as String).replaceFirst(RegExp(r'^models/'), ''),
    ];
  }

  bool _supportsGeminiGenerateContent(Object? methods) {
    if (methods is! List) return true;
    return methods.contains('generateContent');
  }

  List<String> _extractModelIds(Object? data) {
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map && item['id'] is String) (item['id'] as String).trim(),
    ].where((id) => id.isNotEmpty).toList();
  }

  Uri _compatibleEndpoint(String baseUrl) {
    final uri = _compatibleBaseUri(baseUrl);
    if (uri.path.endsWith('/chat/completions')) return uri;
    final basePath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: '$basePath/chat/completions');
  }

  Uri _compatibleModelsEndpoint(String baseUrl) {
    final uri = _compatibleBaseUri(baseUrl);
    if (uri.path.endsWith('/models')) return uri;
    var basePath = uri.path;
    if (basePath.endsWith('/chat/completions')) {
      basePath = basePath.substring(
        0,
        basePath.length - '/chat/completions'.length,
      );
    }
    if (basePath.endsWith('/')) {
      basePath = basePath.substring(0, basePath.length - 1);
    }
    final modelPath = basePath.isEmpty ? '/models' : '$basePath/models';
    return uri.replace(path: modelPath);
  }

  Uri _compatibleBaseUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw AiChatException(
        'OpenAI compatible 서버의 base URL을 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw AiChatException(
        'OpenAI compatible 서버의 base URL에 유효한 http(s) 주소를 입력하세요.',
        kind: AiChatFailureKind.configuration,
      );
    }
    return uri;
  }

  Future<Map<String, Object?>> _getJson(
    Uri endpoint, {
    required AiSettings settings,
    required Map<String, String> headers,
  }) async {
    final requestHeaders = _requestHeaders(settings, headers);
    final client = _createClient(settings);
    try {
      return await (() async {
        final request = await client.getUrl(endpoint);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        for (final entry in requestHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }

        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        final decoded = _decodeResponseBody(body, response.statusCode);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _serverError(response.statusCode, decoded, body);
        }
        if (decoded is Map) return Map<String, Object?>.from(decoded);
        throw AiChatException(
          'AI 서버 응답 형식이 올바르지 않습니다.',
          kind: AiChatFailureKind.invalidResponse,
        );
      })().timeout(requestTimeout);
    } on TimeoutException {
      throw AiChatException(
        'AI 서버 응답 시간이 초과되었습니다.',
        kind: AiChatFailureKind.timeout,
      );
    } on SocketException catch (e) {
      throw AiChatException(
        'AI 서버에 연결할 수 없습니다: ${e.message}',
        kind: AiChatFailureKind.connection,
      );
    } on HttpException catch (e) {
      throw AiChatException(
        _connectionDroppedMessage(e),
        kind: AiChatFailureKind.connection,
      );
    } on FormatException catch (e) {
      throw AiChatException(
        'AI 서버 JSON 응답을 해석할 수 없습니다: ${e.message}',
        kind: AiChatFailureKind.invalidResponse,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 응답 헤더를 받기 전에 서버가 연결을 끊은 경우인지.
  ///
  /// 생성 요청의 재시도 후보다. 응답 부재가 서버의 미처리를 보장하지는 않는다.
  /// 헤더를 받은 뒤 본문이 잘린 경우는 여기 들지 않는다.
  static bool _isConnectionClosedBeforeHeaders(HttpException error) =>
      error.message.toLowerCase().contains('connection closed before');

  static String _connectionDroppedMessage(HttpException error) =>
      'AI 서버가 응답 전에 연결을 끊었습니다: ${error.message}';

  Future<Map<String, Object?>> _postJson(
    Uri endpoint, {
    required AiSettings settings,
    required Map<String, String> headers,
    required Map<String, Object?> payload,
    AiCancelToken? cancelToken,
  }) async {
    try {
      return await _postJsonOnce(
        endpoint,
        settings: settings,
        headers: headers,
        payload: payload,
        cancelToken: cancelToken,
      );
    } on HttpException catch (error) {
      if (!_isConnectionClosedBeforeHeaders(error)) {
        throw AiChatException(
          _connectionDroppedMessage(error),
          kind: AiChatFailureKind.connection,
        );
      }
      // 헤더 전에 끊긴 요청은 한 번만 더 보낸다. 두 번째도 끊기면 그대로 알린다.
      if (cancelToken == null) {
        await _retryDelay(_transientRetryDelay);
      } else {
        await cancelToken.run(() => _retryDelay(_transientRetryDelay));
      }
      cancelToken?.throwIfCancelled();
      try {
        return await _postJsonOnce(
          endpoint,
          settings: settings,
          headers: headers,
          payload: payload,
          cancelToken: cancelToken,
        );
      } on HttpException catch (retryError) {
        throw AiChatException(
          _connectionDroppedMessage(retryError),
          kind: AiChatFailureKind.connection,
        );
      }
    }
  }

  Future<Map<String, Object?>> _postJsonOnce(
    Uri endpoint, {
    required AiSettings settings,
    required Map<String, String> headers,
    required Map<String, Object?> payload,
    AiCancelToken? cancelToken,
  }) async {
    final requestHeaders = _requestHeaders(settings, headers);
    final client = _createClient(settings);
    final unregisterCancel = cancelToken?.onCancel(
      () => client.close(force: true),
    );
    try {
      Future<Map<String, Object?>> requestOnce() async {
        cancelToken?.throwIfCancelled();
        final request = await client.postUrl(endpoint);
        cancelToken?.throwIfCancelled();
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        for (final entry in requestHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }
        request.write(jsonEncode(payload));

        final response = await request.close();
        cancelToken?.throwIfCancelled();
        final body = await utf8.decoder.bind(response).join();
        cancelToken?.throwIfCancelled();
        final decoded = _decodeResponseBody(body, response.statusCode);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _serverError(response.statusCode, decoded, body);
        }
        if (decoded is Map) return Map<String, Object?>.from(decoded);
        throw AiChatException(
          'AI 서버 응답 형식이 올바르지 않습니다.',
          kind: AiChatFailureKind.invalidResponse,
        );
      }

      return await (cancelToken == null
              ? requestOnce()
              : cancelToken.run(requestOnce))
          .timeout(requestTimeout);
    } on TimeoutException {
      cancelToken?.throwIfCancelled();
      throw AiChatException(
        'AI 서버 응답 시간이 초과되었습니다.',
        kind: AiChatFailureKind.timeout,
      );
    } on SocketException catch (e) {
      cancelToken?.throwIfCancelled();
      throw AiChatException(
        'AI 서버에 연결할 수 없습니다: ${e.message}',
        kind: AiChatFailureKind.connection,
      );
    } on HttpException {
      // 사용자가 중단해 소켓을 닫은 경우는 중단으로 보고, 그 외는 [_postJson]이
      // 재시도 여부를 정한다.
      cancelToken?.throwIfCancelled();
      rethrow;
    } on FormatException catch (e) {
      cancelToken?.throwIfCancelled();
      throw AiChatException(
        'AI 서버 JSON 응답을 해석할 수 없습니다: ${e.message}',
        kind: AiChatFailureKind.invalidResponse,
      );
    } finally {
      unregisterCancel?.call();
      client.close(force: true);
    }
  }

  Object? _decodeResponseBody(String body, int status) {
    try {
      return body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      // 프록시의 HTML/평문 오류도 429/5xx 등 원래 HTTP 분류를 유지한다.
      if (status < 200 || status >= 300) return null;
      rethrow;
    }
  }

  AiChatException _serverError(int status, Object? decoded, String body) =>
      AiChatException(
        'AI 서버 오류 $status: ${_errorMessage(decoded, body)}',
        kind: switch (status) {
          401 || 403 => AiChatFailureKind.authentication,
          408 => AiChatFailureKind.timeout,
          429 => AiChatFailureKind.rateLimited,
          >= 500 => AiChatFailureKind.server,
          _ => AiChatFailureKind.configuration,
        },
      );

  Map<String, String> _openAiAuthHeaders(AiSettings settings) {
    final token = settings.apiToken.trim();
    if (token.isEmpty) return const {};
    return {'authorization': 'Bearer $token'};
  }

  Map<String, String> _geminiAuthHeaders(AiSettings settings) => {
    'x-goog-api-key': settings.apiToken.trim(),
  };

  Map<String, String> _requestHeaders(
    AiSettings settings,
    Map<String, String> providerHeaders,
  ) {
    return {..._customHeaders(settings.customHeaders), ...providerHeaders};
  }

  Map<String, String> _customHeaders(String rawHeaders) {
    try {
      return parseCustomHeaders(rawHeaders);
    } on CustomHeaderFormatException catch (error) {
      throw AiChatException(
        error.message,
        kind: AiChatFailureKind.configuration,
      );
    }
  }

  HttpClient _createClient(AiSettings settings) {
    final client = HttpClient()..connectionTimeout = requestTimeout;
    final proxyEnvironment = _proxyEnvironment(settings);
    client.findProxy = (uri) =>
        HttpClient.findProxyFromEnvironment(uri, environment: proxyEnvironment);
    return client;
  }

  Map<String, String> _proxyEnvironment(AiSettings settings) {
    final environment = <String, String>{};
    final httpProxy = settings.httpProxy.trim();
    final httpsProxy = settings.httpsProxy.trim();
    if (httpProxy.isNotEmpty) {
      environment['http_proxy'] = httpProxy;
      environment['HTTP_PROXY'] = httpProxy;
    }
    if (httpsProxy.isNotEmpty) {
      environment['https_proxy'] = httpsProxy;
      environment['HTTPS_PROXY'] = httpsProxy;
    }
    return environment;
  }

  String _errorMessage(Object? decoded, String body) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (error is String) return error;
      final message = decoded['message'];
      if (message is String) return message;
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'empty response';
    return trimmed.length > 500 ? '${trimmed.substring(0, 500)}...' : trimmed;
  }
}
