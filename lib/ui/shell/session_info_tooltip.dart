import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../session/session.dart';
import '../../session/session_attention.dart';
import '../../session/session_os_info.dart';
import '../../state/providers.dart';
import 'session_status_indicators.dart';

/// 세션 정보 툴팁의 한 줄(항목명, 값).
class SessionInfoLine {
  const SessionInfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SessionInfoLine && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

const sessionOsLoadingLabel = '확인 중…';

/// 세션 탭 툴팁에 보일 항목: 연결 종류, 주소(점프 호스트), OS, 상태.
/// 이름은 툴팁 제목으로 따로 보인다.
///
/// 원격 OS는 [osLookup]이 있을 때만 보인다. 연결된 원격 세션인데 아직
/// 결과가 없으면 "확인 중…", 조회에 실패하면 줄을 생략한다.
List<SessionInfoLine> sessionInfoLines(
  SessionInfo session, {
  SessionAttention? attention,
  SessionOsLookup? osLookup,
  String? jumpHostAlias,
  String? operatingSystem,
}) {
  final host = session.host;
  final os = host.isLocalShell
      ? localOperatingSystemLabel(host, operatingSystem: operatingSystem)
      : _remoteOsLabel(session, osLookup);
  final route = host.kubernetesPodLabel;
  return [
    SessionInfoLine(
      '연결',
      sessionConnectionKindLabel(host, operatingSystem: operatingSystem),
    ),
    if (!host.isLocalShell)
      SessionInfoLine('주소', '${host.username}@${host.hostname}:${host.port}'),
    if (host.isKubernetesSsh && route.isNotEmpty) SessionInfoLine('Pod', route),
    if (!host.isLocalShell && jumpHostAlias != null)
      SessionInfoLine('점프 호스트', jumpHostAlias),
    if (os != null) SessionInfoLine('OS', os),
    SessionInfoLine(
      '상태',
      [
        sessionStatusLabel(session.status),
        if (attention != null) 'Agent ${attention.state.label}',
      ].join(' · '),
    ),
  ];
}

String? _remoteOsLabel(SessionInfo session, SessionOsLookup? lookup) {
  if (session.status != SessionStatus.connected) return null;
  final current = lookup?.connectedAt == session.connectedAt ? lookup : null;
  return switch (current?.status) {
    null || SessionOsLookupStatus.loading => sessionOsLoadingLabel,
    SessionOsLookupStatus.loaded => current!.operatingSystem,
    SessionOsLookupStatus.failed => null,
  };
}

/// 세션 탭 위에 마우스를 올리면 잠시 뒤 세션 정보를 보이는 툴팁.
///
/// 클릭·드래그와 겹치지 않도록 [waitDuration]만큼 머문 뒤에 뜨고, 터치의
/// 길게 누르기에는 반응하지 않는다. 원격 OS는
/// 처음 마우스를 올렸을 때 한 번 읽는다([SessionOsInfoController]).
class SessionInfoTooltip extends ConsumerWidget {
  const SessionInfoTooltip({
    super.key,
    required this.session,
    required this.child,
    this.attention,
    this.waitDuration = const Duration(milliseconds: 500),
    this.preferBelow = true,
  });

  final SessionInfo session;
  final SessionAttention? attention;
  final Widget child;
  final Duration waitDuration;
  final bool preferBelow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final osLookup = ref.watch(
      sessionOsInfoProvider.select((lookups) => lookups[session.id]),
    );
    final jumpHostId = session.host.jumpHostId;
    // 점프 호스트가 있는 세션만 호스트 목록을 읽는다.
    final jumpHostAlias = jumpHostId == null
        ? null
        : ref
              .watch(hostListProvider)
              .value
              ?.where((host) => host.id == jumpHostId)
              .firstOrNull
              ?.alias;
    final lines = sessionInfoLines(
      session,
      attention: attention,
      osLookup: osLookup,
      jumpHostAlias: jumpHostAlias,
    );
    return MouseRegion(
      onEnter: (_) =>
          ref.read(sessionOsInfoProvider.notifier).ensureLoaded(session),
      child: Tooltip(
        key: ValueKey('session-info-tooltip-${session.id}'),
        waitDuration: waitDuration,
        // 마우스 hover로만 보인다. 터치의 길게 누르기는 행 드래그·메뉴가 쓴다.
        triggerMode: TooltipTriggerMode.manual,
        preferBelow: preferBelow,
        richMessage: _message(lines),
        child: child,
      ),
    );
  }

  TextSpan _message(List<SessionInfoLine> lines) => TextSpan(
    children: [
      TextSpan(
        text: session.displayName,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
      for (final line in lines) ...[
        const TextSpan(text: '\n'),
        TextSpan(
          text: '${line.label}  ',
          style: const TextStyle(color: VibeColors.onSurfaceDim, fontSize: 11),
        ),
        TextSpan(text: line.value, style: const TextStyle(fontSize: 11)),
      ],
    ],
  );
}
