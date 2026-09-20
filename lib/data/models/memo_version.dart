import 'package:freezed_annotation/freezed_annotation.dart';

part 'memo_version.freezed.dart';

/// 메모 본문의 과거 시점 스냅샷. [label]이 있으면 사용자가 직접 남긴 버전,
/// 없으면 자동 저장 중 시간 단위로 병합된 자동 버전이다.
@freezed
abstract class MemoVersion with _$MemoVersion {
  const factory MemoVersion({
    required int id,
    required String hostId,
    required String body,
    required DateTime createdAt,
    String? label,
  }) = _MemoVersion;
}
