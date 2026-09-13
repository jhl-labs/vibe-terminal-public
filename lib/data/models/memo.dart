import 'package:freezed_annotation/freezed_annotation.dart';

part 'memo.freezed.dart';

/// Host에 연결된 자유 텍스트 메모. Host당 하나뿐이며, 같은 Host로 연결된
/// 모든 세션이 공유한다(hostId 기준).
@freezed
abstract class Memo with _$Memo {
  const factory Memo({
    required String hostId,
    required String body,
    required DateTime updatedAt,
  }) = _Memo;
}
