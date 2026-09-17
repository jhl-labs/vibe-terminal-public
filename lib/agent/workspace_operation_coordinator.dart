import 'dart:async';

/// 앱의 모든 진입점이 공유하는 쓰기 작업 경계. 예약·UI·API는 같은 인스턴스를 쓴다.
/// 잠금은 첫 await 전에 획득하며 실패/취소 후에도 반드시 반환한다.
class WorkspaceOperationCoordinator {
  final Map<String, String> _operations = {};

  String? activeOperation(String resource) => _operations[resource];

  Future<T> run<T>(
    String resource,
    String operation,
    Future<T> Function() action,
  ) async {
    final active = _operations[resource];
    if (active != null) {
      throw StateError('$active 작업이 끝난 뒤 $operation 작업을 실행해 주세요.');
    }
    _operations[resource] = operation;
    try {
      return await action();
    } finally {
      _operations.remove(resource);
    }
  }
}
