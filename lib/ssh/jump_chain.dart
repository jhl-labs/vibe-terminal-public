import '../core/result.dart';
import '../data/models/host.dart';

/// 호스트 id로 Host를 조회하는 함수. 보통 `HostRepository.getById`.
typedef HostLookup = Future<Host?> Function(String id);

/// jump 체인 최대 깊이(방어적 상한).
const int kMaxJumpDepth = 10;

/// [target]의 `jumpHostId` 참조를 따라가며, 연결해야 할 jump 호스트들을
/// 바깥쪽(폰이 먼저 붙는 홉)부터 순서대로 반환한다. jump가 없으면 빈 리스트.
///
/// 순환 / 최대 깊이 초과 / 삭제된 jump / 중간 비SSH 프로필은 모두
/// [JumpChainFailure]로 반환한다.
Future<Result<List<Host>>> resolveJumpChain(
  Host target,
  HostLookup lookup,
) async {
  final innermostFirst = <Host>[];
  final visited = <String>{target.id};
  var current = target;
  var depth = 0;

  while (current.jumpHostId != null) {
    depth++;
    if (depth > kMaxJumpDepth) {
      return const Err(
        JumpChainFailure('jump 체인이 너무 깁니다 (최대 $kMaxJumpDepth홉)'),
      );
    }
    final jumpId = current.jumpHostId!;
    if (visited.contains(jumpId)) {
      return const Err(JumpChainFailure('jump 호스트 순환이 감지되었습니다'));
    }
    final jump = await lookup(jumpId);
    if (jump == null) {
      return Err(JumpChainFailure('jump 호스트를 찾을 수 없습니다 (id: $jumpId)'));
    }
    if (jump.connectionType != HostConnectionType.ssh) {
      return Err(
        JumpChainFailure(
          '${jump.connectionType.label} 프로필은 jump 호스트로 쓸 수 없습니다: '
          '${jump.alias}',
        ),
      );
    }
    visited.add(jumpId);
    innermostFirst.add(jump);
    current = jump;
  }

  return Ok(innermostFirst.reversed.toList());
}
