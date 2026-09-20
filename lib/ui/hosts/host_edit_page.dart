import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/models/host.dart';
import '../../data/repositories/identity_repository.dart';
import '../../kubernetes/kubernetes_exec_relay.dart';
import '../../ssh/ssh_credentials.dart';
import '../../state/providers.dart';
import '../keychain/identity_edit_sheet.dart';
import '../keychain/ssh_key_create_sheet.dart';
import '../keychain/ssh_key_import_sheet.dart';

/// 호스트 편집 결과. 공개키를 새로 붙였으면 목록 페이지가 서버 등록을 제안한다.
class HostEditResult {
  const HostEditResult({this.suggestInstallHostId, this.suggestInstallKeyId});

  /// 새 공개키 바인딩이 생긴 호스트 id. 없으면 null.
  final String? suggestInstallHostId;

  /// 서버에 등록을 제안할 키체인 키 id. 없으면 null.
  final String? suggestInstallKeyId;
}

class HostEditPage extends ConsumerStatefulWidget {
  const HostEditPage({super.key, this.existing});

  final Host? existing;

  @override
  ConsumerState<HostEditPage> createState() => _HostEditPageState();
}

class _HostEditPageState extends ConsumerState<HostEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _alias = TextEditingController();
  final _hostname = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _workingDirectory = TextEditingController();
  final _startupScript = TextEditingController();
  final _kubernetesContext = TextEditingController();
  final _kubernetesNamespace = TextEditingController(text: 'default');
  final _kubernetesResource = TextEditingController();
  final _kubernetesContainer = TextEditingController();
  HostConnectionType _connectionType = HostConnectionType.ssh;
  HostAuthType _authType = HostAuthType.password;
  LocalShellType _localShellType = LocalShellType.powershell;
  String? _jumpHostId;
  KubernetesGateway _kubernetesGateway = _supportsLocalKubectl
      ? KubernetesGateway.local
      : KubernetesGateway.sshHost;
  String? _kubernetesGatewayHostId;
  bool _keepRemoteSession = false;
  bool _agentForwarding = false;
  bool _x11Forwarding = false;
  bool _saving = false;
  // 공유 Identity를 쓸지(true), 이 호스트 전용 자격증명을 쓸지(false).
  bool _useSharedIdentity = false;
  String? _identityId; // 공유 Identity 선택
  String? _selectedKeyId; // 호스트 전용 공개키 인증에서 고른 키

  bool get _editing => widget.existing != null;
  bool get _isSsh => _connectionType != HostConnectionType.localShell;
  bool get _isDirectSsh => _connectionType == HostConnectionType.ssh;
  bool get _isKubernetesSsh =>
      _connectionType == HostConnectionType.kubernetesSsh;
  // 셸 종류 선택(PowerShell/Cmd/WSL)은 Windows에서만 의미가 있다. 그 외
  // 플랫폼에서는 기기의 기본 셸($SHELL)을 실행하므로 선택지를 숨긴다.
  bool get _showShellPicker => Platform.isWindows;
  // 로컬 셸은 데스크톱에서만 의미가 있다. 모바일은 샌드박스(iOS는 프로세스
  // 생성 불가, Android는 빈약한 앱 셸)라 SSH만 노출한다.
  static final bool _supportsLocalShell =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  // 이 기기에서 kubectl을 직접 실행하는 것도 데스크톱에서만 가능하다. 모바일은
  // SSH 호스트를 게이트웨이로 삼아 그곳의 kubectl을 쓴다.
  static final bool _supportsLocalKubectl = _supportsLocalShell;
  static final bool _platformSupportsX11Forwarding =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String get _connectionProfileSubtitle {
    if (!_supportsLocalShell) return 'SSH 또는 Kubernetes Pod 경유 SSH 프로필을 저장합니다.';
    return _showShellPicker
        ? 'SSH, Kubernetes Pod 경유 SSH 또는 이 Windows PC의 로컬 셸 프로필을 저장합니다.'
        : 'SSH, Kubernetes Pod 경유 SSH 또는 이 기기의 로컬 셸 프로필을 저장합니다.';
  }

  // 기존 전용 자격증명을 비워둔 채 유지할 수 있는지. 공유 Identity 호스트의
  // credentialRef는 Identity에서 덧씌운 값이라 전용 자격증명으로 치지 않는다.
  bool get _canKeepCredential {
    final existing = widget.existing;
    if (existing == null || !_isSsh || _useSharedIdentity) return false;
    final identityId = existing.identityId;
    if (identityId != null && !identityId.startsWith('host-')) return false;
    return existing.authType == _authType && existing.credentialRef != null;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _alias.text = existing.alias;
    _hostname.text = existing.hostname;
    _port.text = existing.port.toString();
    _username.text = existing.username;
    _connectionType = existing.connectionType;
    _authType = existing.authType;
    // 저장소가 만든 host-<id> Identity면 전용 모드, 그 외는 공유 Identity 모드.
    final identityId = existing.identityId;
    if (identityId != null && !identityId.startsWith('host-')) {
      _useSharedIdentity = true;
      _identityId = identityId;
    }
    _localShellType = existing.localShellType;
    _jumpHostId = existing.jumpHostId;
    _kubernetesGateway = existing.kubernetesGateway;
    _kubernetesGatewayHostId = existing.kubernetesGatewayHostId;
    _kubernetesContext.text = existing.kubernetesContext ?? '';
    _kubernetesNamespace.text = existing.kubernetesNamespace ?? 'default';
    _kubernetesResource.text = existing.kubernetesResource ?? '';
    _kubernetesContainer.text = existing.kubernetesContainer ?? '';
    _keepRemoteSession = existing.keepsRemoteSession;
    _agentForwarding = existing.agentForwarding;
    _x11Forwarding = existing.x11Forwarding;
    _workingDirectory.text = existing.isLocalShell
        ? existing.workingDirectory ?? _defaultWorkingDirectory(_localShellType)
        : '';
    _startupScript.text = existing.startupScript ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _alias,
      _hostname,
      _port,
      _username,
      _password,
      _workingDirectory,
      _startupScript,
      _kubernetesContext,
      _kubernetesNamespace,
      _kubernetesResource,
      _kubernetesContainer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  String? _validateHostname(String? value) {
    if (!_isSsh) return null;
    final required = _required(value, '주소를 입력하세요');
    if (required != null) return required;
    if (_isKubernetesSsh && !isValidRelayTargetHost(value!.trim())) {
      return 'Pod에서 접속할 호스트명 또는 IP를 입력하세요';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (!_isSsh) return null;
    final required = _required(value, '포트를 입력하세요');
    if (required != null) return required;
    final port = int.tryParse(value!.trim());
    if (port == null || port < 1 || port > 65535) {
      return '포트는 1-65535 사이여야 합니다';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (!_isSsh || _authType != HostAuthType.password || _canKeepCredential) {
      return null;
    }
    if (value == null || value.isEmpty) {
      return '비밀번호를 입력하세요';
    }
    return null;
  }

  String? _validatePrivateKey(String? value) {
    if (!_isSsh || _authType != HostAuthType.publicKey) return null;
    return value == null ? '키를 선택하세요' : null;
  }

  String _localUsername() =>
      Platform.environment['USERNAME'] ??
      Platform.environment['USER'] ??
      'local';

  String _defaultWorkingDirectory(LocalShellType shell) {
    if (shell == LocalShellType.wsl) return '~';
    return Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        _localUsername();
  }

  void _fillDefaultWorkingDirectory({bool overwrite = false}) {
    if (!overwrite && _workingDirectory.text.trim().isNotEmpty) return;
    _workingDirectory.text = _defaultWorkingDirectory(_localShellType);
  }

  Future<String?> _pickPrivateKeyPem() async {
    const maxKeyBytes = 1024 * 1024;
    final result = await FilePicker.pickFiles(
      dialogTitle: 'SSH 개인키 선택',
      type: FileType.any,
      allowMultiple: false,
      withData: true,
      lockParentWindow: true,
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return null;
    final file = files.first;
    if (file.size > maxKeyBytes) {
      throw const FormatException('개인키 파일이 너무 큽니다');
    }

    final bytes = file.bytes;
    if (bytes != null) return utf8.decode(bytes);
    return file.xFile.readAsString();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final id =
          existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      final secureStore = ref.read(secureStoreProvider);
      final previousRef = existing?.credentialRef;

      // 자격증명은 secureStore에만 저장하고 DB에는 credentialRef만 기록한다.
      // 공유 Identity 모드에서는 username/authType이 표시용 사본이고 저장소가
      // Identity를 join해 채운다. 전용 모드에서 비밀번호는 cred-<id>에 두고,
      // 공개키는 키체인 키의 secretRef를 그대로 참조한다.
      String? credRef;
      String? identityId;
      var username = _isSsh ? _username.text.trim() : _localUsername();
      var authType = _isSsh ? _authType : HostAuthType.password;
      if (_isSsh && _useSharedIdentity) {
        identityId = _identityId;
        final identity = await ref
            .read(identityRepositoryProvider)
            .getById(identityId!);
        username = identity?.username ?? username;
        authType = identity?.authType ?? authType;
      } else if (_isSsh) {
        switch (_authType) {
          case HostAuthType.password:
            // 이전 참조는 이전 인증도 비밀번호였을 때만 비밀번호 비밀이다.
            // (레거시 공개키 호스트는 cred-<id>를 키체인 키가 소유한다.)
            credRef =
                existing?.authType == HostAuthType.password &&
                    previousRef?.startsWith('cred-') == true
                ? previousRef
                : null;
            // 기존 호스트 편집에서 인증 방식이 같고 입력을 비워두면 유지한다.
            if (!_canKeepCredential || _password.text.isNotEmpty) {
              credRef ??= await _freshPasswordRef(id);
              await secureStore.writeSecret(
                credRef,
                SshCredentialPayload.password(_password.text),
              );
            }
          case HostAuthType.publicKey:
            final key = await ref
                .read(sshKeyRepositoryProvider)
                .getById(_selectedKeyId!);
            credRef = key?.secretRef;
          case HostAuthType.keyboardInteractive:
            credRef = null;
        }
      }
      final now = DateTime.now();
      final hostname = _isSsh ? _hostname.text.trim() : 'localhost';
      final alias = _alias.text.trim();
      final workingDirectory = _isSsh
          ? null
          : (_workingDirectory.text.trim().isEmpty
                ? _defaultWorkingDirectory(_localShellType)
                : _workingDirectory.text.trim());
      final startupScript = _startupScript.text.trim().isEmpty
          ? null
          : _startupScript.text.trim();
      await ref
          .read(hostRepositoryProvider)
          .upsert(
            Host(
              id: id,
              alias: alias.isEmpty
                  ? (_isSsh
                        ? hostname
                        : (_showShellPicker ? _localShellType.label : '로컬 셸'))
                  : alias,
              hostname: hostname,
              port: _isSsh ? int.parse(_port.text.trim()) : 0,
              username: username,
              identityId: identityId,
              connectionType: _connectionType,
              authType: authType,
              localShellType: _localShellType,
              workingDirectory: workingDirectory,
              startupScript: startupScript,
              credentialRef: credRef,
              jumpHostId: _isDirectSsh ? _jumpHostId : null,
              kubernetesGateway: _isKubernetesSsh
                  ? _kubernetesGateway
                  : KubernetesGateway.local,
              kubernetesGatewayHostId:
                  _isKubernetesSsh &&
                      _kubernetesGateway == KubernetesGateway.sshHost
                  ? _kubernetesGatewayHostId
                  : null,
              kubernetesContext: _isKubernetesSsh
                  ? _optionalText(_kubernetesContext)
                  : null,
              kubernetesNamespace: _isKubernetesSsh
                  ? _kubernetesNamespace.text.trim()
                  : null,
              kubernetesResource: _isKubernetesSsh
                  ? _kubernetesResource.text.trim()
                  : null,
              kubernetesContainer: _isKubernetesSsh
                  ? _optionalText(_kubernetesContainer)
                  : null,
              remoteSessionPersistence: _isSsh && _keepRemoteSession
                  ? RemoteSessionPersistence.tmux
                  : RemoteSessionPersistence.none,
              // 공유 Identity를 골랐으면 그 Identity의 인증 방식이 기준이다.
              agentForwarding:
                  _isSsh &&
                  authType == HostAuthType.publicKey &&
                  _agentForwarding,
              x11Forwarding:
                  _isSsh &&
                      !_keepRemoteSession &&
                      ref.read(buildFeaturesProvider).x11 &&
                      _platformSupportsX11Forwarding
                  ? _x11Forwarding
                  : false,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      // 전용(host-<id>) Identity에서 공유 Identity로 바꿨으면 남은 전용 Identity를
      // 저장소를 통해 정리한다. 저장소는 비밀번호 비밀만 지우므로 키체인 키가
      // 소유한 비밀(레거시 cred-<id>)은 건드리지 않는다.
      if (_isSsh &&
          _useSharedIdentity &&
          existing != null &&
          existing.identityId == 'host-${existing.id}') {
        try {
          await ref
              .read(identityRepositoryProvider)
              .delete(existing.identityId!);
        } on IdentityInUseException {
          // 다른 호스트가 아직 참조하면 남겨 둔다.
        }
      }
      if (!mounted) return;
      // 공개키를 새로 붙였으면 목록 페이지가 서버에 공개키 등록을 제안한다.
      final newKeyBinding =
          _isSsh &&
          !_useSharedIdentity &&
          _authType == HostAuthType.publicKey &&
          (existing == null || existing.authType != HostAuthType.publicKey);
      Navigator.pop(
        context,
        newKeyBinding
            ? HostEditResult(
                suggestInstallHostId: id,
                suggestInstallKeyId: _selectedKeyId,
              )
            : const HostEditResult(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('호스트를 저장하지 못했습니다: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 전용 비밀번호를 저장할 새 참조. 레거시 공개키 호스트는 키체인 키가
  /// `cred-<id>`를 소유하므로, 그 경우 덮어쓰지 않도록 `cred-<id>-pw`를 쓴다.
  Future<String> _freshPasswordRef(String id) async {
    final candidate = 'cred-$id';
    final owner = await ref
        .read(sshKeyRepositoryProvider)
        .findBySecretRef(candidate);
    return owner == null ? candidate : '$candidate-pw';
  }

  static String? _optionalText(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  /// jump 또는 kubectl 게이트웨이 후보: 자기 자신을 제외한 SSH 프로필.
  List<Host> _sshHostCandidates() {
    final hosts = ref.watch(hostListProvider).value ?? const <Host>[];
    return hosts
        .where(
          (h) =>
              h.connectionType == HostConnectionType.ssh &&
              h.id != widget.existing?.id,
        )
        .toList();
  }

  Widget _buildJumpHostDropdown() {
    final candidates = _sshHostCandidates();
    // 참조하던 jump 호스트가 목록에 없으면(삭제 등) 선택을 비운다.
    final value = candidates.any((h) => h.id == _jumpHostId)
        ? _jumpHostId
        : null;
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Jump 호스트 (선택)',
        prefixIcon: Icon(Icons.alt_route),
        helperText: '선택한 SSH 서버를 중계해 이 호스트로 연결합니다',
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('없음')),
        for (final h in candidates)
          DropdownMenuItem<String?>(
            value: h.id,
            child: Text('${h.alias} (${h.endpointLabel})'),
          ),
      ],
      onChanged: _saving ? null : (v) => setState(() => _jumpHostId = v),
    );
  }

  Widget _buildSessionContinuityTile() {
    final enabled = _keepRemoteSession;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: enabled ? VibeColors.surfaceHigh : VibeColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? VibeColors.accent : VibeColors.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: SwitchListTile(
              key: const ValueKey('remote-session-persistence'),
              value: enabled,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _keepRemoteSession = value;
                      if (value) _x11Forwarding = false;
                    }),
              title: const Text('작업 이어가기'),
              subtitle: const Text('네트워크가 끊기거나 앱을 다시 시작해도 실행 중인 작업으로 돌아옵니다.'),
              secondary: Icon(
                Icons.link_rounded,
                color: enabled ? VibeColors.accent : VibeColors.onSurfaceDim,
              ),
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: enabled
                ? const Padding(
                    key: ValueKey('remote-session-persistence-hint'),
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Text(
                      '서버에 tmux가 있으면 작업을 유지합니다. tmux가 없으면 '
                      '일반 SSH로 연결하고 복원 불가 상태를 터미널에 표시합니다.',
                      style: TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 12,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 최종 SSH 대상(주소·포트·사용자명). 일반 SSH에서는 폼 상단에, Kubernetes
  /// 경유에서는 경로 카드의 마지막 단계 안에 놓인다.
  List<Widget> _buildTargetFields() => [
    TextFormField(
      controller: _hostname,
      decoration: InputDecoration(
        labelText: _isKubernetesSsh ? '주소 (Pod 네트워크 기준)' : '주소',
        prefixIcon: const Icon(Icons.dns_outlined),
        helperText: _isKubernetesSsh ? 'Pod 안에서 접속 가능한 호스트명 또는 IP' : null,
      ),
      textInputAction: TextInputAction.next,
      validator: _validateHostname,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _port,
      decoration: const InputDecoration(
        labelText: '포트',
        prefixIcon: Icon(Icons.numbers),
      ),
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      validator: _validatePort,
    ),
  ];

  /// 공유 Identity 드롭다운 + 새 Identity 버튼.
  /// 화면에 반영되는 인증 방식. 공유 Identity를 골랐으면 그 Identity의 방식,
  /// 아니면 이 호스트 전용 선택값이다. (agent forwarding 노출 판단에 쓴다.)
  HostAuthType _effectiveAuthType() {
    if (!_useSharedIdentity) return _authType;
    final identities = ref.watch(identityListProvider).value ?? const [];
    for (final identity in identities) {
      if (identity.id == _identityId) return identity.authType;
    }
    return _authType;
  }

  Widget _buildIdentityDropdown() {
    final identities = ref.watch(identityListProvider).value ?? const [];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const ValueKey('host-identity'),
            initialValue: identities.any((i) => i.id == _identityId)
                ? _identityId
                : null,
            decoration: InputDecoration(
              labelText: 'Identity',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: identities.isEmpty ? '저장된 Identity가 없습니다.' : null,
            ),
            items: [
              for (final i in identities)
                DropdownMenuItem(
                  value: i.id,
                  child: Text('${i.label} · ${i.summary}'),
                ),
            ],
            validator: (v) => v == null ? 'Identity를 선택하세요' : null,
            onChanged: _saving ? null : (v) => setState(() => _identityId = v),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '새 Identity',
          icon: const Icon(Icons.person_add_alt),
          onPressed: _saving
              ? null
              : () async {
                  final created = await showIdentityEditSheet(context, ref);
                  if (created != null && mounted) {
                    setState(() => _identityId = created.id);
                  }
                },
        ),
      ],
    );
  }

  /// 호스트 전용 공개키 인증: 키체인 키 선택 + 만들기/가져오기.
  Widget _buildKeyPicker() {
    final keys = ref.watch(sshKeyListProvider).value ?? const [];
    // 기존 전용 공개키 호스트면 credentialRef와 같은 secretRef의 키를 미리 고른다.
    final previousRef = widget.existing?.credentialRef;
    if (_selectedKeyId == null && previousRef != null) {
      for (final k in keys) {
        if (k.secretRef == previousRef) {
          _selectedKeyId = k.id;
          break;
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('host-ssh-key'),
          initialValue: keys.any((k) => k.id == _selectedKeyId)
              ? _selectedKeyId
              : null,
          decoration: InputDecoration(
            labelText: 'SSH 키',
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            helperText: keys.isEmpty ? '키체인에 키가 없습니다. 만들거나 가져오세요.' : null,
          ),
          items: [
            for (final k in keys)
              DropdownMenuItem(
                value: k.id,
                child: Text('${k.name} · ${k.shortFingerprint}'),
              ),
          ],
          validator: _validatePrivateKey,
          onChanged: _saving ? null : (v) => setState(() => _selectedKeyId = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      final key = await showSshKeyCreateSheet(context, ref);
                      if (key != null && mounted) {
                        setState(() => _selectedKeyId = key.id);
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('키 만들기'),
            ),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => showSshKeyImportSheet(
                      context,
                      ref,
                      pickFile: _pickPrivateKeyPem,
                    ),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('가져오기'),
            ),
          ],
        ),
      ],
    );
  }

  /// kubectl 실행 위치 드롭다운의 값. 로컬/WSL은 고정 키, SSH 호스트는 id.
  static const _gatewayLocalKey = 'local';
  static const _gatewayWslKey = 'wsl';
  static String _gatewaySshKey(String hostId) => 'ssh:$hostId';

  String? get _gatewayKey => switch (_kubernetesGateway) {
    KubernetesGateway.local => _gatewayLocalKey,
    KubernetesGateway.wsl => _gatewayWslKey,
    KubernetesGateway.sshHost =>
      _kubernetesGatewayHostId == null
          ? null
          : _gatewaySshKey(_kubernetesGatewayHostId!),
  };

  void _selectGateway(String? key) {
    setState(() {
      if (key == null || key == _gatewayLocalKey) {
        _kubernetesGateway = KubernetesGateway.local;
        _kubernetesGatewayHostId = null;
      } else if (key == _gatewayWslKey) {
        _kubernetesGateway = KubernetesGateway.wsl;
        _kubernetesGatewayHostId = null;
      } else {
        _kubernetesGateway = KubernetesGateway.sshHost;
        _kubernetesGatewayHostId = key.substring('ssh:'.length);
      }
    });
  }

  Widget _buildKubernetesGatewayDropdown() {
    final candidates = _sshHostCandidates();
    final items = <DropdownMenuItem<String?>>[
      if (_supportsLocalKubectl)
        const DropdownMenuItem(
          value: _gatewayLocalKey,
          child: Text('이 기기에서 kubectl 실행'),
        ),
      if (Platform.isWindows)
        const DropdownMenuItem(
          value: _gatewayWslKey,
          child: Text('WSL에서 kubectl 실행'),
        ),
      for (final h in candidates)
        DropdownMenuItem(
          value: _gatewaySshKey(h.id),
          child: Text('SSH 접속 후 실행: ${h.alias} (${h.endpointLabel})'),
        ),
    ];
    // 참조하던 호스트가 삭제됐거나 이 플랫폼에서 못 쓰는 선택지면 비운다.
    final current = _gatewayKey;
    final value = items.any((item) => item.value == current) ? current : null;
    return DropdownButtonFormField<String?>(
      key: const ValueKey('kubernetes-gateway'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'kubectl 실행 위치',
        prefixIcon: const Icon(Icons.alt_route),
        helperText: candidates.isEmpty && !_supportsLocalKubectl
            ? 'kubectl이 설치된 SSH 호스트 프로필을 먼저 추가하세요'
            : '선택한 곳의 kubectl과 kubeconfig로 Pod에 들어갑니다',
      ),
      hint: const Text('선택하세요'),
      items: items,
      validator: (v) =>
          _isKubernetesSsh && v == null ? 'kubectl 실행 위치를 선택하세요' : null,
      onChanged: _saving ? null : _selectGateway,
    );
  }

  Widget _buildKubernetesRouteFields() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VibeColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kubernetes Pod 경유 연결 경로',
            style: TextStyle(
              color: VibeColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'kubectl exec로 Pod에 들어간 뒤, Pod 네트워크에서 최종 대상에 SSH로 접속합니다. '
            'Pod에 sshd는 필요 없고 nc, socat 또는 bash 중 하나만 있으면 됩니다.',
            style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _RouteStep(
            index: 1,
            title: 'kubectl 게이트웨이',
            child: _buildKubernetesGatewayDropdown(),
          ),
          const SizedBox(height: 16),
          _RouteStep(
            index: 2,
            title: '릴레이 Pod',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _kubernetesContext,
                        decoration: const InputDecoration(
                          labelText: 'context (선택)',
                          prefixIcon: Icon(Icons.hub_outlined),
                          helperText: '비우면 현재 context',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _kubernetesNamespace,
                        decoration: const InputDecoration(
                          labelText: 'namespace',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                        validator: (value) => _isKubernetesSsh
                            ? _required(value, 'namespace를 입력하세요')
                            : null,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _kubernetesResource,
                        decoration: const InputDecoration(
                          labelText: 'Pod',
                          prefixIcon: Icon(Icons.view_in_ar_outlined),
                          helperText: 'Pod 이름 또는 deployment/이름',
                        ),
                        validator: (value) => _isKubernetesSsh
                            ? _required(value, 'Pod를 입력하세요')
                            : null,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _kubernetesContainer,
                        decoration: const InputDecoration(
                          labelText: 'container (선택)',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _RouteStep(
            index: 3,
            title: '최종 SSH 대상',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildTargetFields(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final supportsX11Forwarding =
        ref.watch(buildFeaturesProvider).x11 && _platformSupportsX11Forwarding;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '호스트 수정' : '호스트 추가')),
      body: ColoredBox(
        color: VibeColors.bg,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              // 폼 필드는 스크롤로 사라지면 안 된다(입력/포커스/검증 상태 유지).
              // ListView는 화면 밖 필드를 지연 해제하므로 SingleChildScrollView로
              // 모든 필드를 항상 빌드한 채 둔다.
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Connection profile',
                      style: TextStyle(
                        color: VibeColors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _connectionProfileSubtitle,
                      style: const TextStyle(
                        color: VibeColors.onSurfaceDim,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<HostConnectionType>(
                      segments: [
                        const ButtonSegment(
                          value: HostConnectionType.ssh,
                          icon: Icon(Icons.dns_outlined),
                          label: Text('SSH'),
                        ),
                        const ButtonSegment(
                          value: HostConnectionType.kubernetesSsh,
                          icon: Icon(Icons.hub_outlined),
                          label: Text('Kubernetes'),
                        ),
                        if (_supportsLocalShell)
                          const ButtonSegment(
                            value: HostConnectionType.localShell,
                            icon: Icon(Icons.terminal),
                            label: Text('로컬 셸'),
                          ),
                      ],
                      selected: {_connectionType},
                      onSelectionChanged: _saving
                          ? null
                          : (values) {
                              setState(() {
                                _connectionType = values.single;
                                if (_connectionType ==
                                    HostConnectionType.localShell) {
                                  _fillDefaultWorkingDirectory();
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _alias,
                      decoration: const InputDecoration(
                        labelText: '별칭',
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    if (_isSsh) ...[
                      const SizedBox(height: 12),
                      if (_isDirectSsh) ...[
                        ..._buildTargetFields(),
                        const SizedBox(height: 12),
                        _buildJumpHostDropdown(),
                      ] else
                        _buildKubernetesRouteFields(),
                      const SizedBox(height: 12),
                      _buildSessionContinuityTile(),
                      if (supportsX11Forwarding) ...[
                        const SizedBox(height: 12),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            value: _x11Forwarding,
                            onChanged: _saving || _keepRemoteSession
                                ? null
                                : (value) =>
                                      setState(() => _x11Forwarding = value),
                            title: const Text('X11 forwarding'),
                            subtitle: Text(
                              _keepRemoteSession
                                  ? '작업 이어가기와 동시에 사용할 수 없습니다'
                                  : Platform.isLinux
                                  ? '원격 GUI 앱을 로컬 X11/XWayland 화면으로 전달합니다'
                                  : '외부 X server(XQuartz, VcXsrv 등)가 필요합니다',
                            ),
                            secondary: const Icon(Icons.open_in_new),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('이 호스트 전용')),
                          ButtonSegment(
                            value: true,
                            label: Text('저장된 Identity'),
                          ),
                        ],
                        selected: {_useSharedIdentity},
                        onSelectionChanged: _saving
                            ? null
                            : (v) =>
                                  setState(() => _useSharedIdentity = v.single),
                      ),
                      const SizedBox(height: 12),
                      if (_useSharedIdentity)
                        _buildIdentityDropdown()
                      else ...[
                        TextFormField(
                          controller: _username,
                          decoration: const InputDecoration(
                            labelText: '사용자명',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) => _required(value, '사용자명을 입력하세요'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<HostAuthType>(
                          key: const ValueKey('host-auth-type'),
                          initialValue: _authType,
                          decoration: const InputDecoration(
                            labelText: '인증 방식',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: HostAuthType.password,
                              child: Text('비밀번호'),
                            ),
                            DropdownMenuItem(
                              value: HostAuthType.publicKey,
                              child: Text('공개키'),
                            ),
                            DropdownMenuItem(
                              value: HostAuthType.keyboardInteractive,
                              child: Text('키보드 인터랙티브 / 2FA'),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _authType = value;
                                    if (value != HostAuthType.publicKey) {
                                      _agentForwarding = false;
                                    }
                                  });
                                },
                        ),
                        if (_authType == HostAuthType.password)
                          TextFormField(
                            controller: _password,
                            decoration: InputDecoration(
                              labelText: '비밀번호',
                              prefixIcon: const Icon(Icons.lock_outline),
                              helperText: _canKeepCredential
                                  ? '비워두면 기존 비밀번호를 유지합니다'
                                  : null,
                            ),
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            validator: _validatePassword,
                            onFieldSubmitted: (_) => _saving ? null : _save(),
                          )
                        else if (_authType == HostAuthType.publicKey)
                          _buildKeyPicker()
                        else
                          const _KeyboardInteractiveHint(),
                      ],
                      if (_effectiveAuthType() == HostAuthType.publicKey) ...[
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            key: const ValueKey('ssh-agent-forwarding'),
                            value: _agentForwarding,
                            onChanged: _saving
                                ? null
                                : (value) =>
                                      setState(() => _agentForwarding = value),
                            title: const Text('SSH agent forwarding'),
                            subtitle: const Text(
                              '원격 프로세스가 이 개인키로 서명을 요청할 수 있습니다. 신뢰하는 서버에서만 켜세요.',
                            ),
                            secondary: const Icon(Icons.key_rounded),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ] else ...[
                      if (_showShellPicker) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<LocalShellType>(
                          initialValue: _localShellType,
                          decoration: const InputDecoration(
                            labelText: '셸',
                            prefixIcon: Icon(Icons.terminal),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: LocalShellType.powershell,
                              child: Text('PowerShell'),
                            ),
                            DropdownMenuItem(
                              value: LocalShellType.cmd,
                              child: Text('Command Prompt'),
                            ),
                            DropdownMenuItem(
                              value: LocalShellType.wsl,
                              child: Text('WSL'),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    final previousDefault =
                                        _defaultWorkingDirectory(
                                          _localShellType,
                                        );
                                    final shouldOverwrite =
                                        _workingDirectory.text.trim().isEmpty ||
                                        _workingDirectory.text.trim() ==
                                            previousDefault;
                                    _localShellType = value;
                                    _fillDefaultWorkingDirectory(
                                      overwrite: shouldOverwrite,
                                    );
                                  });
                                },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _workingDirectory,
                        decoration: const InputDecoration(
                          labelText: '시작 디렉터리',
                          prefixIcon: Icon(Icons.folder_outlined),
                          helperText: '비워두면 기본 홈/현재 셸 기본 경로에서 시작합니다',
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _saving ? null : _save(),
                      ),
                      const SizedBox(height: 12),
                      const _LocalShellHint(),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _startupScript,
                      decoration: const InputDecoration(
                        labelText: '시작 스크립트 (선택)',
                        prefixIcon: Icon(Icons.play_circle_outline),
                        helperText: '연결 직후 자동 실행할 명령. 여러 줄은 순차 실행됩니다',
                        alignLabelWithHint: true,
                      ),
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kubernetes 경로 카드의 번호 달린 단계.
class _RouteStep extends StatelessWidget {
  const _RouteStep({
    required this.index,
    required this.title,
    required this.child,
  });

  final int index;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: VibeColors.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$index',
                style: const TextStyle(
                  color: VibeColors.bg,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: VibeColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _KeyboardInteractiveHint extends StatelessWidget {
  const _KeyboardInteractiveHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VibeColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phonelink_lock, size: 18, color: VibeColors.onSurfaceDim),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '비밀번호·OTP·승인 코드 등 서버가 요청하는 값을 연결할 때 입력합니다. 응답은 저장하지 않습니다.',
              style: TextStyle(color: VibeColors.onSurfaceDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalShellHint extends StatelessWidget {
  const _LocalShellHint();

  @override
  Widget build(BuildContext context) {
    final message = Platform.isWindows
        ? '로컬 셸은 이 PC에서 실행됩니다. WSL은 Windows에 wsl.exe와 기본 배포판이 준비되어 있어야 합니다.'
        : '로컬 셸은 이 기기의 기본 셸(\$SHELL)에서 실행됩니다.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VibeColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VibeColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: VibeColors.onSurfaceDim,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: VibeColors.onSurfaceDim,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
