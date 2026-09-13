import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/atomic_file.dart';

/// 전역 설정을 편집할 수 있는 코딩 에이전트 CLI.
///
/// 각 앱은 홈 디렉터리 하나(`~/.claude`, `~/.codex`, `~/.config/opencode`)와
/// 그 아래 섹션 목록으로 기술된다. 섹션은 파일 하나(settings.json 등)이거나
/// 디렉터리 하나(skills, commands 등)다.
enum CliConfigApp {
  claude(title: 'Claude', summary: 'Claude Code 전역 설정'),
  codex(title: 'Codex', summary: 'OpenAI Codex CLI 전역 설정'),
  opencode(title: 'OpenCode', summary: 'OpenCode 전역 설정');

  const CliConfigApp({required this.title, required this.summary});

  final String title;
  final String summary;

  /// 각 CLI가 쓰는 규칙으로 홈 위치를 정한다. 환경변수 override를 먼저 보고,
  /// 없으면 `HOME`/`USERPROFILE` 기준 기본 위치를 쓴다.
  String? resolveRootPath({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    String? override(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final home = env['USERPROFILE'] ?? env['HOME'];
    final hasHome = home != null && home.trim().isNotEmpty;
    switch (this) {
      case CliConfigApp.claude:
        return override('CLAUDE_CONFIG_DIR') ??
            (hasHome ? p.join(home, '.claude') : null);
      case CliConfigApp.codex:
        return override('CODEX_HOME') ??
            (hasHome ? p.join(home, '.codex') : null);
      case CliConfigApp.opencode:
        final explicit = override('OPENCODE_CONFIG_DIR');
        if (explicit != null) return explicit;
        final xdg = override('XDG_CONFIG_HOME');
        if (xdg != null) return p.join(xdg, 'opencode');
        return hasHome ? p.join(home, '.config', 'opencode') : null;
    }
  }

  /// 홈 위치를 바꾸는 환경변수 이름(안내 문구용).
  String get rootEnvironmentHint => switch (this) {
    CliConfigApp.claude => 'HOME 또는 CLAUDE_CONFIG_DIR',
    CliConfigApp.codex => 'HOME 또는 CODEX_HOME',
    CliConfigApp.opencode => 'HOME, XDG_CONFIG_HOME 또는 OPENCODE_CONFIG_DIR',
  };

  List<CliConfigSection> get sections => switch (this) {
    CliConfigApp.claude => _claudeSections,
    CliConfigApp.codex => _codexSections,
    CliConfigApp.opencode => _opencodeSections,
  };

  CliConfigSection? sectionById(String id) {
    for (final section in sections) {
      if (section.id == id) return section;
    }
    return null;
  }
}

/// 홈 아래 편집 대상 하나(파일 또는 디렉터리).
class CliConfigSection {
  const CliConfigSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.relativePath,
    required this.isDirectory,
    this.alternativePaths = const [],
    this.defaultExtension = '.md',
    this.skillLayout = false,
    this.nameHint = '',
    required this.template,
  });

  /// 앱 안에서 유일한 식별자(아이콘·테스트 키에 쓴다).
  final String id;
  final String title;
  final String summary;

  /// 홈 기준 기본 상대 경로. 새로 만들 때 이 이름을 쓴다.
  final String relativePath;

  /// 같은 뜻으로 인정되는 다른 경로. 기본 경로가 없고 이 중 하나가 있으면
  /// 그것을 쓴다(예: OpenCode `agent/`와 `agents/`, `opencode.jsonc`).
  final List<String> alternativePaths;

  final bool isDirectory;

  /// 새 항목 이름에 확장자가 없을 때 붙일 확장자.
  final String defaultExtension;

  /// `이름/SKILL.md` 구조를 쓰는 섹션.
  final bool skillLayout;

  /// 새 항목 다이얼로그의 입력 예시.
  final String nameHint;

  /// 새 파일의 기본 내용. 디렉터리 섹션은 섹션 기준 상대 경로를, 파일 섹션은
  /// 파일 이름을 받는다.
  final String Function(String relative) template;

  List<String> get candidatePaths => [relativePath, ...alternativePaths];
}

/// 편집 대상 파일 하나.
class CliConfigEntry {
  const CliConfigEntry({
    required this.section,
    required this.path,
    required this.name,
    required this.exists,
    this.description,
  });

  final CliConfigSection section;

  /// 절대 경로.
  final String path;

  /// 섹션 루트 기준 상대 이름. 파일 섹션이면 파일 이름 자체.
  final String name;

  final bool exists;

  /// frontmatter의 `description:` 값(있을 때).
  final String? description;

  /// 엄격한 JSON 검증을 적용할 파일. `.jsonc`는 주석을 허용하므로 제외한다.
  bool get isJson => path.toLowerCase().endsWith('.json');

  bool get isSkillManifest =>
      section.skillLayout && p.basename(path) == 'SKILL.md';

  @override
  bool operator ==(Object other) =>
      other is CliConfigEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// 한 CLI 앱의 홈 디렉터리를 읽고 쓰는 저장소.
///
/// 로컬 설정 파일은 작고 곧바로 화면에 필요하므로 동기 IO를 쓴다. 덕분에
/// 위젯 테스트에서 실제 임시 디렉터리로 동작을 검증할 수 있다.
class CliConfigHome {
  CliConfigHome({required this.app, required this.rootPath});

  final CliConfigApp app;
  final String rootPath;

  /// 텍스트로 편집할 수 있다고 보는 확장자. 스킬·플러그인 디렉터리에는
  /// 스크립트나 참고 파일이 함께 들어 있어 .md 외에도 열 수 있게 한다.
  static const editableExtensions = {
    '.md',
    '.markdown',
    '.txt',
    '.json',
    '.jsonc',
    '.yaml',
    '.yml',
    '.toml',
    '.rules',
    '.sh',
    '.py',
    '.js',
    '.mjs',
    '.ts',
  };

  static CliConfigHome? fromEnvironment(
    CliConfigApp app, {
    Map<String, String>? environment,
  }) {
    final root = app.resolveRootPath(environment: environment);
    return root == null ? null : CliConfigHome(app: app, rootPath: root);
  }

  /// 섹션의 실제 경로. 기본 경로가 없고 대체 경로가 있으면 그쪽을 쓴다.
  String sectionPath(CliConfigSection section) {
    final primary = p.join(rootPath, section.relativePath);
    if (FileSystemEntity.typeSync(primary) != FileSystemEntityType.notFound) {
      return primary;
    }
    for (final alternative in section.alternativePaths) {
      final path = p.join(rootPath, alternative);
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        return path;
      }
    }
    return primary;
  }

  /// 파일 섹션의 유일한 항목. 파일이 없어도 저장하면 생성되므로 항상 반환한다.
  CliConfigEntry fileEntry(CliConfigSection section) {
    assert(!section.isDirectory);
    final path = sectionPath(section);
    return CliConfigEntry(
      section: section,
      path: path,
      name: p.basename(path),
      exists: File(path).existsSync(),
    );
  }

  /// 섹션의 항목 목록. 디렉터리 섹션은 재귀적으로 편집 가능한 파일을 상대
  /// 경로 순으로 나열한다. 파일 섹션은 [fileEntry] 하나를 돌려준다.
  List<CliConfigEntry> listEntries(CliConfigSection section) {
    if (!section.isDirectory) return [fileEntry(section)];
    final root = Directory(sectionPath(section));
    if (!root.existsSync()) return const [];
    final entries = <CliConfigEntry>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isEditableFile(entity.path)) continue;
      final relative = p.relative(entity.path, from: root.path);
      // 숨김 파일(.DS_Store 등)과 숨김 디렉터리는 건너뛴다.
      if (p.split(relative).any((part) => part.startsWith('.'))) continue;
      entries.add(
        CliConfigEntry(
          section: section,
          path: entity.path,
          name: p.toUri(relative).path,
          exists: true,
          description: _readDescription(entity),
        ),
      );
    }
    entries.sort((a, b) => _compareEntryNames(a.name, b.name));
    return entries;
  }

  /// 개요 화면용: 섹션별 항목 수(파일 섹션은 존재하면 1, 없으면 0).
  int countEntries(CliConfigSection section) {
    if (!section.isDirectory) return fileEntry(section).exists ? 1 : 0;
    return listEntries(section).length;
  }

  static bool isEditableFile(String path) =>
      editableExtensions.contains(p.extension(path).toLowerCase());

  String read(CliConfigEntry entry) {
    final file = File(entry.path);
    if (!file.existsSync()) return '';
    return file.readAsStringSync();
  }

  /// 사용자의 실제 CLI 설정이므로 원자적으로 바꾼다. 저장 중 프로세스가
  /// 죽어 파일이 잘리면 CLI 쪽 설정이 통째로 망가진다.
  void write(CliConfigEntry entry, String contents) {
    writeFileAtomicallySync(File(entry.path), contents);
  }

  /// 파일 섹션이 아직 없을 때 편집기에 채울 초기 내용.
  String initialContentFor(CliConfigSection section) =>
      section.template(p.basename(sectionPath(section)));

  /// 디렉터리 섹션에 새 항목을 만든다. [name]은 섹션 루트 기준 상대 이름이며
  /// `git/commit`처럼 하위 경로를 포함할 수 있다. 확장자가 없으면 섹션 기본
  /// 확장자를 붙이고, 스킬 섹션은 `이름/SKILL.md`를 만든다. 이미 있으면
  /// [StateError].
  CliConfigEntry create(CliConfigSection section, String name) {
    assert(section.isDirectory);
    final relative = normalizeNewEntryName(section, name);
    final path = p.join(sectionPath(section), relative);
    final file = File(path);
    if (file.existsSync()) {
      throw StateError('이미 있는 파일입니다: $relative');
    }
    writeFileAtomicallySync(file, section.template(relative));
    return CliConfigEntry(
      section: section,
      path: path,
      name: p.toUri(relative).path,
      exists: true,
      description: _readDescription(file),
    );
  }

  /// [create]가 쓸 상대 경로를 만든다. 잘못된 이름이면 [FormatException].
  static String normalizeNewEntryName(
    CliConfigSection section,
    String rawName,
  ) {
    var name = rawName.trim().replaceAll('\\', '/');
    while (name.startsWith('/')) {
      name = name.substring(1);
    }
    while (name.endsWith('/')) {
      name = name.substring(0, name.length - 1);
    }
    if (name.isEmpty) throw const FormatException('이름을 입력하세요.');
    final parts = name.split('/');
    for (final part in parts) {
      if (part.isEmpty || part == '.' || part == '..') {
        throw const FormatException('경로에 빈 이름이나 ".."을 쓸 수 없습니다.');
      }
      if (part.startsWith('.')) {
        throw const FormatException('숨김 파일 이름은 만들 수 없습니다.');
      }
      if (RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part)) {
        throw const FormatException('파일 이름에 쓸 수 없는 문자가 있습니다.');
      }
    }
    if (section.skillLayout) {
      if (p.extension(name).isNotEmpty && parts.length > 1) {
        // 스킬 디렉터리 안의 개별 파일(예: my-skill/reference.md)도 허용한다.
        return p.joinAll(parts);
      }
      return p.joinAll([...parts, 'SKILL.md']);
    }
    if (p.extension(name).isEmpty) name = '$name${section.defaultExtension}';
    return p.joinAll(name.split('/'));
  }

  /// 항목을 지운다. 디렉터리 섹션에서 파일을 지운 뒤 상위 디렉터리가 비면
  /// 섹션 루트까지 정리해 빈 스킬 폴더가 남지 않게 한다.
  void delete(CliConfigEntry entry) {
    final file = File(entry.path);
    if (file.existsSync()) file.deleteSync();
    if (!entry.section.isDirectory) return;
    final root = p.normalize(sectionPath(entry.section));
    var dir = file.parent;
    while (p.normalize(dir.path) != root && p.isWithin(root, dir.path)) {
      if (dir.existsSync() && dir.listSync().isNotEmpty) break;
      if (dir.existsSync()) dir.deleteSync();
      dir = dir.parent;
    }
  }

  static int _compareEntryNames(String a, String b) {
    // 스킬은 SKILL.md가 같은 디렉터리의 다른 파일보다 먼저 오게 한다.
    final da = p.dirname(a), db = p.dirname(b);
    if (da != db) return a.compareTo(b);
    final ba = p.basename(a), bb = p.basename(b);
    if (ba == 'SKILL.md') return -1;
    if (bb == 'SKILL.md') return 1;
    return a.compareTo(b);
  }

  String? _readDescription(File file) {
    if (!file.path.toLowerCase().endsWith('.md')) return null;
    try {
      final raf = file.openSync();
      try {
        // frontmatter는 파일 머리에 있으므로 앞부분만 읽는다.
        final bytes = raf.readSync(4096);
        return frontmatterDescription(utf8.decode(bytes, allowMalformed: true));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }

  /// `---` 로 감싼 YAML frontmatter에서 `description:` 값을 꺼낸다.
  /// 완전한 YAML 파서는 아니고, 이런 파일에서 흔한 한 줄 값만 다룬다.
  static String? frontmatterDescription(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first.trim() != '---') return null;
    for (final line in lines.skip(1)) {
      if (line.trim() == '---') break;
      final match = RegExp(r'^description\s*:\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value.isEmpty ? null : value;
    }
    return null;
  }
}

/// JSON 편집기의 검증 결과.
class JsonObjectValidation {
  const JsonObjectValidation._({
    required this.valid,
    required this.message,
    this.value,
  });

  const JsonObjectValidation.invalid(String message)
    : this._(valid: false, message: message);

  const JsonObjectValidation.valid(Object? value, String message)
    : this._(valid: true, value: value, message: message);

  final bool valid;
  final String message;
  final Object? value;

  /// 최상위가 object인 JSON만 통과시킨다. 설정 파일은 모두 object 형식이다.
  static JsonObjectValidation of(String text) {
    if (text.trim().isEmpty) {
      return const JsonObjectValidation.invalid('JSON 내용이 비어 있습니다.');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const JsonObjectValidation.invalid('최상위 JSON 값은 object여야 합니다.');
      }
      return JsonObjectValidation.valid(decoded, '유효한 JSON object입니다.');
    } on FormatException catch (error) {
      return JsonObjectValidation.invalid(
        'JSON 오류 ${error.offset ?? ''}: ${error.message}',
      );
    } catch (error) {
      return JsonObjectValidation.invalid('JSON 오류: $error');
    }
  }
}

// ---------------------------------------------------------------------------
// 템플릿
// ---------------------------------------------------------------------------

String _skillTemplate(String relative) {
  if (p.basename(relative) != 'SKILL.md') return '';
  final skill = p.basename(p.dirname(relative));
  return '---\n'
      'name: $skill\n'
      'description: 이 스킬이 언제·무엇을 하는지 한 줄로 설명합니다.\n'
      '---\n\n'
      '# $skill\n\n'
      '## 절차\n\n'
      '1. \n';
}

String _promptTemplate(String relative) {
  final base = p.basenameWithoutExtension(relative);
  return '---\n'
      'description: $base 설명\n'
      '---\n\n'
      '\$ARGUMENTS 로 인자를 받을 수 있습니다.\n';
}

String _instructionsTemplate(String _) => '# 전역 지침\n\n- \n';

String _jsonTemplate(String _) => '{}\n';

// ---------------------------------------------------------------------------
// Claude Code — ~/.claude
// ---------------------------------------------------------------------------

const _claudeSections = <CliConfigSection>[
  CliConfigSection(
    id: 'settings',
    title: 'Settings',
    summary: '권한·훅·모델·환경변수 등 settings.json',
    relativePath: 'settings.json',
    isDirectory: false,
    template: _jsonTemplate,
  ),
  CliConfigSection(
    id: 'memory',
    title: 'CLAUDE.md',
    summary: '모든 프로젝트에 적용되는 전역 지침',
    relativePath: 'CLAUDE.md',
    isDirectory: false,
    template: _instructionsTemplate,
  ),
  CliConfigSection(
    id: 'rules',
    title: 'Rules',
    summary: '항상 로드되는 규칙 파일(.md)',
    relativePath: 'rules',
    isDirectory: true,
    nameHint: 'style-guide',
    template: _claudeRuleTemplate,
  ),
  CliConfigSection(
    id: 'commands',
    title: 'Commands',
    summary: '/이름 으로 실행하는 슬래시 커맨드',
    relativePath: 'commands',
    isDirectory: true,
    nameHint: 'review 또는 git/commit',
    template: _promptTemplate,
  ),
  CliConfigSection(
    id: 'skills',
    title: 'Skills',
    summary: '이름/SKILL.md 로 구성되는 스킬',
    relativePath: 'skills',
    isDirectory: true,
    skillLayout: true,
    nameHint: 'my-skill',
    template: _skillTemplate,
  ),
  CliConfigSection(
    id: 'agents',
    title: 'Agents',
    summary: '서브에이전트 정의(.md)',
    relativePath: 'agents',
    isDirectory: true,
    nameHint: 'code-reviewer',
    template: _claudeAgentTemplate,
  ),
  CliConfigSection(
    id: 'keybindings',
    title: 'Keybindings',
    summary: '키보드 단축키 keybindings.json',
    relativePath: 'keybindings.json',
    isDirectory: false,
    template: _jsonTemplate,
  ),
];

String _claudeRuleTemplate(String relative) =>
    '# ${p.basenameWithoutExtension(relative)}\n\n- \n';

String _claudeAgentTemplate(String relative) {
  final base = p.basenameWithoutExtension(relative);
  return '---\n'
      'name: $base\n'
      'description: 이 에이전트를 언제 쓰는지 설명합니다.\n'
      'tools: Read, Grep, Glob, Bash\n'
      '---\n\n'
      '당신은 $base 입니다.\n';
}

// ---------------------------------------------------------------------------
// OpenAI Codex CLI — ~/.codex
// ---------------------------------------------------------------------------

const _codexSections = <CliConfigSection>[
  CliConfigSection(
    id: 'config',
    title: 'config.toml',
    summary: '모델·승인 정책·MCP 서버·프로필 등 전역 설정',
    relativePath: 'config.toml',
    isDirectory: false,
    template: _codexConfigTemplate,
  ),
  CliConfigSection(
    id: 'instructions',
    title: 'AGENTS.md',
    summary: '모든 프로젝트에 적용되는 전역 지침',
    relativePath: 'AGENTS.md',
    isDirectory: false,
    template: _instructionsTemplate,
  ),
  CliConfigSection(
    id: 'prompts',
    title: 'Prompts',
    summary: '/prompts:이름 으로 부르는 커스텀 프롬프트',
    relativePath: 'prompts',
    isDirectory: true,
    nameHint: 'review',
    template: _promptTemplate,
  ),
  CliConfigSection(
    id: 'skills',
    title: 'Skills',
    summary: '이름/SKILL.md 로 구성되는 스킬',
    relativePath: 'skills',
    isDirectory: true,
    skillLayout: true,
    nameHint: 'my-skill',
    template: _skillTemplate,
  ),
  CliConfigSection(
    id: 'rules',
    title: 'Rules',
    summary: '명령 실행 정책(execpolicy) .rules 파일',
    relativePath: 'rules',
    isDirectory: true,
    defaultExtension: '.rules',
    nameHint: 'git',
    template: _codexRuleTemplate,
  ),
];

String _codexConfigTemplate(String _) =>
    '# Codex CLI 전역 설정. 예:\n'
    '# model = "gpt-5-codex"\n'
    '# approval_policy = "on-request"\n'
    '# sandbox_mode = "workspace-write"\n';

String _codexRuleTemplate(String _) =>
    '# execpolicy 규칙. 예: git status 를 항상 허용\n'
    'prefix_rule(\n'
    '    pattern = ["git", "status"],\n'
    '    decision = "allow",\n'
    ')\n';

// ---------------------------------------------------------------------------
// OpenCode — ~/.config/opencode
// ---------------------------------------------------------------------------

const _opencodeSections = <CliConfigSection>[
  CliConfigSection(
    id: 'config',
    title: 'opencode.json',
    summary: '모델·프로바이더·권한·MCP·테마 등 전역 설정',
    relativePath: 'opencode.json',
    alternativePaths: ['opencode.jsonc', 'config.json'],
    isDirectory: false,
    template: _opencodeConfigTemplate,
  ),
  CliConfigSection(
    id: 'instructions',
    title: 'AGENTS.md',
    summary: '모든 프로젝트에 적용되는 전역 지침',
    relativePath: 'AGENTS.md',
    isDirectory: false,
    template: _instructionsTemplate,
  ),
  CliConfigSection(
    id: 'agents',
    title: 'Agents',
    summary: '커스텀 에이전트(.md, frontmatter로 모델·모드 지정)',
    relativePath: 'agent',
    alternativePaths: ['agents'],
    isDirectory: true,
    nameHint: 'reviewer',
    template: _opencodeAgentTemplate,
  ),
  CliConfigSection(
    id: 'commands',
    title: 'Commands',
    summary: '/이름 으로 실행하는 커스텀 커맨드',
    relativePath: 'command',
    alternativePaths: ['commands'],
    isDirectory: true,
    nameHint: 'test',
    template: _promptTemplate,
  ),
  CliConfigSection(
    id: 'skills',
    title: 'Skills',
    summary: '이름/SKILL.md 로 구성되는 스킬',
    relativePath: 'skill',
    alternativePaths: ['skills'],
    isDirectory: true,
    skillLayout: true,
    nameHint: 'my-skill',
    template: _skillTemplate,
  ),
  CliConfigSection(
    id: 'plugins',
    title: 'Plugins',
    summary: '이벤트 훅·커스텀 툴을 넣는 플러그인(.ts/.js)',
    relativePath: 'plugin',
    alternativePaths: ['plugins'],
    isDirectory: true,
    defaultExtension: '.ts',
    nameHint: 'notify',
    template: _opencodePluginTemplate,
  ),
  CliConfigSection(
    id: 'tools',
    title: 'Tools',
    summary: '커스텀 툴 정의(.ts/.js)',
    relativePath: 'tool',
    alternativePaths: ['tools'],
    isDirectory: true,
    defaultExtension: '.ts',
    nameHint: 'database',
    template: _opencodeToolTemplate,
  ),
  CliConfigSection(
    id: 'themes',
    title: 'Themes',
    summary: '커스텀 테마(.json)',
    relativePath: 'themes',
    alternativePaths: ['theme'],
    isDirectory: true,
    defaultExtension: '.json',
    nameHint: 'my-theme',
    template: _opencodeThemeTemplate,
  ),
];

String _opencodeConfigTemplate(String _) =>
    '{\n  "\$schema": "https://opencode.ai/config.json"\n}\n';

String _opencodeAgentTemplate(String relative) {
  final base = p.basenameWithoutExtension(relative);
  return '---\n'
      'description: $base 에이전트 설명\n'
      'mode: subagent\n'
      '---\n\n'
      '당신은 $base 입니다.\n';
}

String _opencodePluginTemplate(String relative) {
  final base = p.basenameWithoutExtension(relative);
  return 'import type { Plugin } from "@opencode-ai/plugin"\n\n'
      'export const ${_identifier(base)}: Plugin = async ({ client, \$ }) => {\n'
      '  return {\n'
      '    // "tool.execute.after": async (input, output) => {},\n'
      '  }\n'
      '}\n';
}

String _opencodeToolTemplate(String relative) {
  final base = p.basenameWithoutExtension(relative);
  return 'import { tool } from "@opencode-ai/plugin"\n\n'
      'export default tool({\n'
      '  description: "$base 툴 설명",\n'
      '  args: {},\n'
      '  async execute(args) {\n'
      '    return ""\n'
      '  },\n'
      '})\n';
}

String _opencodeThemeTemplate(String _) =>
    '{\n  "\$schema": "https://opencode.ai/theme.json",\n  "theme": {}\n}\n';

/// 파일 이름을 JS 식별자로 바꾼다(`my-plugin` → `MyPlugin`).
String _identifier(String name) {
  final parts = name.split(RegExp(r'[^A-Za-z0-9]+')).where((s) => s.isNotEmpty);
  final joined = parts.map((s) => s[0].toUpperCase() + s.substring(1)).join();
  return joined.isEmpty ? 'MyPlugin' : joined;
}
