class AgentWorkspaceFileEntry {
  const AgentWorkspaceFileEntry({
    required this.path,
    required this.name,
    required this.kind,
    required this.size,
  });
  final String path;
  final String name;
  final String kind;
  final int size;
  bool get isDirectory => kind == 'directory';
  bool get isFile => kind == 'file';
}

class AgentWorkspaceFileContent {
  const AgentWorkspaceFileContent({
    required this.path,
    required this.text,
    required this.revision,
    required this.editable,
    this.imageBase64,
    this.truncated = false,
  });
  final String path;
  final String text;
  final String revision;
  final bool editable;
  final String? imageBase64;
  final bool truncated;
}

/// 탐색은 한 디렉터리씩 수행한다. .git과 symlink는 편집하지 않는다.
/// 사용자 입력은 JSON 위치 인자이며 shell 코드에 삽입하지 않는다.
const agentWorkspaceFilesScript = r'''
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const req = JSON.parse(process.argv[1]);
const root = fs.realpathSync(process.cwd());
function resolve(relative, allowRoot=false) {
  if (typeof relative !== 'string' || relative.includes('\0') || relative.includes('\\')) throw Error('유효하지 않은 파일 경로');
  if (relative === '' && allowRoot) return root;
  const parts = relative.split('/');
  if (parts.some(part => !part || part === '.' || part === '..' || part.toLowerCase() === '.git') || path.isAbsolute(relative)) throw Error('작업공간 상대 경로를 사용하세요.');
  let file = root;
  for (const part of parts) {
    file = path.join(file,part);
    try { if (fs.lstatSync(file).isSymbolicLink()) throw Error('심볼릭 링크는 편집하지 않습니다.'); }
    catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
  return file;
}
function read(file) {
  const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0));
  try {
    const stat = fs.fstatSync(fd);
    if (!stat.isFile()) throw Error('일반 파일만 열 수 있습니다.');
    const buffer = Buffer.alloc(262145);
    let length=0;
    while (length < buffer.length) { const count=fs.readSync(fd,buffer,length,buffer.length-length,null); if (!count) break; length+=count; }
    const truncated = stat.size > 262144 || length > 262144;
    const bytes = buffer.subarray(0,Math.min(length,262144));
    const image = bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || (bytes[0]===255 && bytes[1]===216 && bytes[2]===255) || ['GIF87a','GIF89a'].includes(bytes.subarray(0,6).toString()) || (bytes.subarray(0,4).toString()==='RIFF' && bytes.subarray(8,12).toString()==='WEBP');
    if (image) {
      if (truncated) throw Error('이미지 미리보기는 256 KiB까지 지원합니다.');
      return {text:'',revision:crypto.createHash('sha256').update(bytes).digest('hex'),editable:false,imageBase64:bytes.toString('base64')};
    }
    if (bytes.includes(0)) throw Error('바이너리 파일은 텍스트 편집기로 열 수 없습니다.');
    const text = new TextDecoder('utf-8',{fatal:!truncated,ignoreBOM:true}).decode(bytes);
    return {text,revision:crypto.createHash('sha256').update(bytes).update(':'+stat.mode).digest('hex'),mode:stat.mode,truncated,editable:!truncated && bytes.length <= 65536};
  } finally { fs.closeSync(fd); }
}
let result;
const file = resolve(req.path,req.action === 'list');
if (req.action === 'list') {
  const entries = fs.readdirSync(file,{withFileTypes:true}).filter(e => e.name.toLowerCase() !== '.git');
  if (entries.length > 2000) throw Error('한 디렉터리에 2,000개가 넘는 항목이 있습니다. 터미널에서 범위를 좁혀 주세요.');
  result = entries.map(e => ({name:e.name,path:[req.path,e.name].filter(Boolean).join('/'),kind:e.isSymbolicLink()?'link':e.isDirectory()?'directory':e.isFile()?'file':'other',size:e.isFile()?fs.lstatSync(path.join(file,e.name)).size:0}));
  result.sort((a,b)=>(a.kind==='directory'?0:1)-(b.kind==='directory'?0:1)||a.name.localeCompare(b.name));
} else if (req.action === 'read') {
  result = {...read(file),path:req.path};
} else if (['resolve','resolveDelete','resolveMissing'].includes(req.action)) {
  const cp = require('node:child_process');
  const git = args => cp.execFileSync('git',args,{encoding:'utf8',maxBuffer:1048576});
  const missing = req.action === 'resolveMissing';
  const deleting = missing || req.action === 'resolveDelete';
  const current = missing ? null : read(file);
  if (deleting && current && !current.editable) throw Error('읽기 전용 미리보기 파일은 삭제할 수 없습니다.');
  if (missing && fs.existsSync(file)) throw Error('File exists; review before deletion');
  if (current && current.revision !== req.revision) throw Error('검토 이후 파일이 변경됐습니다.');
  if (!deleting && /^(<{7}|={7}|>{7}|\|{7})(?: |$)/m.test(current.text)) throw Error('충돌 마커를 먼저 해결하세요.');
  const unmerged = git(['--literal-pathspecs','ls-files','--unmerged','--',req.path]);
  if (missing) {
    const stages = unmerged.trim().split('\n').map(row => { const meta=row.split('\t')[0].split(' '); return [Number(meta[2]),meta[1]]; });
    if (JSON.stringify(stages) !== JSON.stringify(req.stages)) throw Error('Conflict stages changed after review');
  }
  if (!unmerged) throw Error('충돌 상태인 파일이 아닙니다.');
  const index = git(['rev-parse','--path-format=absolute','--git-path','index']).trim();
  const lock = index + '.lock';
  const fd = fs.openSync(lock,'wx',0o600);
  const temp = index + '.vibe-' + crypto.randomBytes(12).toString('hex');
  try {
    if (git(['--literal-pathspecs','ls-files','--unmerged','--',req.path]) !== unmerged) throw Error('충돌 stage가 변경되었습니다. 다시 검토하세요.');
    fs.copyFileSync(index,temp);
    if (current && read(file).revision !== req.revision) throw Error('파일 동시 수정을 감지했습니다.');
    const env = {...process.env,GIT_INDEX_FILE:temp};
    cp.execFileSync('git',deleting ? ['--literal-pathspecs','update-index','--force-remove','--',req.path] : ['--literal-pathspecs','add','--',req.path],{env,maxBuffer:1048576});
    // stage한 blob이 검토한 원문과 같아야 한다. clean filter가 바꾸면 별도 검토한다.
    if (!deleting) {
    const staged = cp.execFileSync('git',['show',':'+req.path],{env,maxBuffer:1048576});
    if (!staged.equals(Buffer.from(current.text,'utf8')) || read(file).revision !== req.revision) throw Error('stage 내용이 검토한 내용과 다릅니다.');
    } else if (current) {
      if (read(file).revision !== req.revision) throw Error('File changed before deletion');
      fs.unlinkSync(file);
    } else if (fs.existsSync(file)) throw Error('File appeared during review');
    try { fs.renameSync(temp,index); } catch (error) {
      if (deleting && current && !fs.existsSync(file)) fs.writeFileSync(file,current.text,{flag:'wx',mode:current.mode & 0o777});
      throw error;
    }
    result = {resolved:true};
  } finally { fs.closeSync(fd); fs.unlinkSync(lock); if(fs.existsSync(temp))fs.unlinkSync(temp); if(fs.existsSync(temp+'.lock'))fs.unlinkSync(temp+'.lock'); }
} else if (req.action === 'write') {
  const bytes = Buffer.from(req.contentBase64,'base64');
  if (bytes.length > 65536 || bytes.includes(0)) throw Error('편집 내용은 NUL 없는 64 KiB 이하 텍스트여야 합니다.');
  new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  const current = req.revision === null ? null : read(file);
  if (current && !current.editable) throw Error('큰 파일과 이미지는 미리보기 전용입니다.');
  if (current && current.revision !== req.revision) throw Error('파일이 다른 곳에서 변경됐습니다. 다시 열어 내용을 합쳐 주세요.');
  if (!current) {
    const fd = fs.openSync(file,'wx',0o644);
    try { fs.writeFileSync(fd,bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  } else {
    const temporary = file + '.vibe-' + crypto.randomBytes(12).toString('hex');
    const fd = fs.openSync(temporary,'wx',current.mode & 0o777);
    try { fs.writeFileSync(fd,bytes); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
    try {
      resolve(req.path);
      if (read(file).revision !== req.revision) throw Error('저장 중 외부 변경을 감지했습니다.');
      fs.renameSync(temporary,file);
    } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  }
  result = {...read(file),path:req.path};
} else { throw Error('지원하지 않는 파일 작업입니다.'); }
process.stdout.write(JSON.stringify(result));
''';
