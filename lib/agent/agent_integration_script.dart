/// Node를 사용하는 project-local hook 설치기. 사용자 설정을 병합하며 내용을
/// 검토한 이후 변경됐으면 쓰지 않는다. stdout에는 결과 JSON만 출력한다.
const agentIntegrationScript = r'''
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const request = JSON.parse(process.argv[1]);
const root = fs.realpathSync(process.cwd());
const marker = 'vibe-terminal-managed-v1';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function safe(relative) {
  const result = path.resolve(root, relative);
  if (!result.startsWith(root + path.sep)) throw Error('작업공간 밖의 경로입니다.');
  let current = root;
  for (const part of relative.split('/')) {
    current = path.join(current, part);
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) throw Error('심볼릭 링크 설정은 수정하지 않습니다: ' + relative);
  }
  return result;
}
function read(relative) {
  const file = safe(relative);
  if (!fs.existsSync(file)) return null;
  if (!fs.statSync(file).isFile() || fs.statSync(file).size > 1048576) throw Error('설정 파일 크기 또는 형식 오류: ' + relative);
  return fs.readFileSync(file, 'utf8');
}
const provider = request.provider;
if (provider === 'opencode') {
  const relative = '.opencode/plugins/vibe-terminal.js';
  const before = read(relative);
  const source = '// ' + marker + '\n' + request.emitter;
  if (before !== null && !before.startsWith('// ' + marker + '\n')) throw Error('사용자 plugin을 덮어쓰지 않습니다.');
  const after = request.remove ? null : source;
  const revision = hash(JSON.stringify([root, provider, before]));
  const changes = before === after ? [] : [{path:relative, before, after}];
  if (request.expected !== undefined) {
    if (revision !== request.expected) throw Error('검토 이후 plugin이 변경됐습니다.');
    const lock = safe('.vibe-terminal/integration.lock');
    fs.mkdirSync(path.dirname(lock), {recursive:true,mode:0o700});
    const fd = fs.openSync(lock, 'wx', 0o600);
    try {
      if (read(relative) !== before) throw Error('다른 plugin 편집을 감지했습니다.');
      const file = safe(relative);
      if (after === null) { if (before !== null) fs.unlinkSync(file); }
      else {
        fs.mkdirSync(path.dirname(file), {recursive:true,mode:0o700});
        const temp = file + '.vibe-' + crypto.randomBytes(12).toString('hex');
        try {
          const output = fs.openSync(temp, 'wx', 0o600);
          try { fs.writeFileSync(output, after); fs.fsyncSync(output); } finally { fs.closeSync(output); }
          fs.renameSync(temp, file);
        } finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
      }
    } finally { fs.closeSync(fd); fs.unlinkSync(lock); }
  }
  process.stdout.write(JSON.stringify({revision,changes,installed:before === source,node:process.version,provider}));
  process.exit(0);
}
if (!['claude', 'codex'].includes(provider)) throw Error('이 설치기는 Claude와 Codex의 command hook을 지원합니다.');
const config = provider === 'claude' ? '.claude/settings.local.json' : '.codex/hooks.json';
const emitter = '.vibe-terminal/hooks/' + provider + '-event.cjs';
const before = read(config);
const oldEmitter = read(emitter);
if (oldEmitter !== null && !oldEmitter.startsWith('// ' + marker + '\n')) throw Error('기존 사용자 hook 파일을 덮어쓰지 않습니다.');
const settings = before === null ? {} : JSON.parse(before);
if (!settings || typeof settings !== 'object' || Array.isArray(settings)) throw Error('설정은 JSON object여야 합니다.');
const oldHooks = settings.hooks ?? {};
if (!oldHooks || typeof oldHooks !== 'object' || Array.isArray(oldHooks)) throw Error('hooks 형식 오류');
const hooks = {};
for (const [event, groups] of Object.entries(oldHooks)) {
  if (!Array.isArray(groups)) throw Error('hook event 형식 오류: ' + event);
  hooks[event] = groups.map(group => {
    if (!group || !Array.isArray(group.hooks)) throw Error('hook group 형식 오류');
    return {...group, hooks: group.hooks.filter(hook => !String(hook.command ?? '').includes('/*' + marker + '*/'))};
  }).filter(group => group.hooks.length > 0);
  if (hooks[event].length === 0) delete hooks[event];
}
const command = 'node -e "require(Buffer.from(\'' + Buffer.from(safe(emitter)).toString('base64') + '\',\'base64\').toString()) /*' + marker + '*/"';
if (!request.remove) {
  for (const event of ['SessionStart','UserPromptSubmit','PreToolUse','PostToolUse','PermissionRequest','Stop','SessionEnd']) {
    (hooks[event] ??= []).push({hooks: [{type:'command', command, timeout:3}]});
  }
}
settings.hooks = hooks;
if (Object.keys(hooks).length === 0) delete settings.hooks;
const after = JSON.stringify(settings, null, 2) + '\n';
const source = '// ' + marker + '\n' + request.emitter;
const desiredEmitter = request.remove ? null : source;
const unchangedConfig = JSON.stringify(before === null ? {} : JSON.parse(before)) === JSON.stringify(settings);
const changes = [
  {path:config, before, after:unchangedConfig ? before : after},
  {path:emitter, before:oldEmitter, after:desiredEmitter},
].filter(change => change.before !== change.after);
const revision = hash(JSON.stringify([root,provider,before,oldEmitter]));
if (request.expected !== undefined) {
  if (request.expected !== revision) throw Error('검토 이후 설정이 변경됐습니다. 다시 진단하세요.');
  const lock = safe('.vibe-terminal/integration.lock');
  fs.mkdirSync(path.dirname(lock), {recursive:true,mode:0o700});
  const lockFd = fs.openSync(lock, 'wx', 0o600);
  const written = [];
  function write(relative, value) {
    const file = safe(relative);
    if (value === null) { if (fs.existsSync(file)) fs.unlinkSync(file); return; }
    fs.mkdirSync(path.dirname(file), {recursive:true,mode:0o700});
    const temp = file + '.vibe-' + crypto.randomBytes(12).toString('hex');
    const fd = fs.openSync(temp, 'wx', fs.existsSync(file) ? fs.statSync(file).mode & 0o777 : 0o600);
    try { fs.writeFileSync(fd, value); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
    try { fs.renameSync(temp, file); } finally { if (fs.existsSync(temp)) fs.unlinkSync(temp); }
  }
  try {
    if (read(config) !== before || read(emitter) !== oldEmitter) throw Error('다른 설정 편집을 감지했습니다.');
    // 설치 시 실행 파일을 먼저 만들고, 제거 시 등록을 먼저 해제한다.
    const ordered = request.remove ? changes : [...changes].reverse();
    for (const change of ordered) {
      if (read(change.path) !== change.before) throw Error('설정 동시 수정: ' + change.path);
      write(change.path, change.after); written.push(change);
    }
  } catch (error) {
    for (const change of written.reverse()) {
      if (read(change.path) === change.after) write(change.path, change.before);
    }
    throw error;
  } finally { fs.closeSync(lockFd); fs.unlinkSync(lock); }
}
process.stdout.write(JSON.stringify({revision,changes,installed:oldEmitter === source && unchangedConfig,node:process.version,provider}));
''';

/// Hook stdout은 모델의 문맥으로 쓰일 수 있어 출력하지 않는다. 이벤트만
/// controlling TTY로 보내며 입력 본문·도구 인자 등 민감한 payload는 전달하지 않는다.
String agentHookEmitter(String provider) => provider == 'opencode'
    ? agentOpenCodePlugin
    : r'''
const fs = require('node:fs');
let body = '';
const timer = setTimeout(() => process.exit(0), 2000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { body += chunk; if (body.length > 262144) process.exit(0); });
process.stdin.on('error', () => process.exit(0));
process.stdin.on('end', () => {
  clearTimeout(timer);
  try {
    const input = JSON.parse(body);
    if (input.agent_id || input.subagent_id) return;
    const id = input.session_id;
    if (typeof id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,159}$/.test(id)) return;
    const event = input.hook_event_name;
    if (!['SessionStart','UserPromptSubmit','PreToolUse','PostToolUse','PermissionRequest','Stop','SessionEnd'].includes(event)) return;
    const envelope = {v:1,provider:PROVIDER,event,session_id:id};
    let wire = '\x1b]777;vibe-agent-event;' + Buffer.from(JSON.stringify(envelope)).toString('base64url') + '\x07';
    if (process.env.TMUX) wire = '\x1bPtmux;' + wire.replaceAll('\x1b','\x1b\x1b') + '\x1b\\';
    const fd = fs.openSync(process.platform === 'win32' ? 'CONOUT$' : '/dev/tty', 'w');
    try { fs.writeSync(fd, wire); } finally { fs.closeSync(fd); }
  } catch (_) { /* telemetry cannot block or approve the Agent's operation */ }
});
'''
          .replaceAll('PROVIDER', "'$provider'");

/// OpenCode project plugin. Unknown sessions are verified through the SDK; child
/// sessions and another root conversation cannot replace this terminal's identity.
const agentOpenCodePlugin = r"""
import fs from 'node:fs';
export const VibeTerminal = async ({client}) => {
  const sessions = new Map();
  let rootId = null;
  let pending = Promise.resolve();
  async function emit(id, event, info) {
    try {
      if (typeof id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,159}$/.test(id)) return;
      if (info) sessions.set(id, info);
      if (!sessions.has(id)) {
        let timer;
        let result;
        try { result = await Promise.race([client.session.get({path:{id}}), new Promise(resolve => { timer = setTimeout(() => resolve(null), 1000); })]); } finally { clearTimeout(timer); }
        if (!result?.data || result.data.id !== id) return;
        sessions.set(id, result.data);
      }
      const session = sessions.get(id);
      if (session.parentID) return;
      if (rootId !== null && rootId !== id) return;
      rootId = id;
      const envelope = {v:1,provider:'opencode',event,session_id:id};
      let wire = '\x1b]777;vibe-agent-event;' + Buffer.from(JSON.stringify(envelope)).toString('base64url') + '\x07';
      if (process.env.TMUX) wire = '\x1bPtmux;' + wire.replaceAll('\x1b','\x1b\x1b') + '\x1b\\';
      const fd = fs.openSync(process.platform === 'win32' ? 'CONOUT$' : '/dev/tty', 'w');
      try { fs.writeSync(fd, wire); } finally { fs.closeSync(fd); }
      if (event === 'SessionEnd') { rootId = null; sessions.delete(id); }
    } catch (_) { /* diagnostic events never block or approve tools */ }
  }
  function enqueue(id, name, info) {
    pending = pending.then(() => emit(id, name, info)).catch(() => {});
    return pending;
  }
  return {
    event: async ({event}) => {
      const p = event.properties ?? {};
      const id = p.sessionID ?? p.info?.id;
      const name = {
        'session.created':'SessionStart', 'session.updated':'SessionStart',
        'session.idle':'Stop', 'session.error':'error',
        'session.deleted':'SessionEnd', 'permission.asked':'PermissionRequest',
        'permission.replied':'PreToolUse',
      }[event.type];
      if (event.type === 'session.status') {
        const status = p.status?.type;
        if (status === 'idle') await enqueue(id, 'Stop');
        else if (status === 'busy' || status === 'retry') await enqueue(id, 'PreToolUse');
      } else if (name) await enqueue(id, name, p.info);
    },
    'tool.execute.before': async (input) => { await enqueue(input.sessionID, 'PreToolUse'); },
    'tool.execute.after': async (input) => { await enqueue(input.sessionID, 'PostToolUse'); },
  };
};
""";
