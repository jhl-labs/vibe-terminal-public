import 'package:freezed_annotation/freezed_annotation.dart';
import 'host.dart';

part 'identity.freezed.dart';

/// 사용자명 + 인증 방식 묶음. 여러 호스트가 공유할 수 있다.
///
/// [hostScoped]가 true면 호스트 편집에서 "이 호스트 전용 인증"으로 만든
/// 숨김 Identity라 키체인 목록에 보이지 않는다.
@freezed
abstract class Identity with _$Identity {
  const Identity._();

  const factory Identity({
    required String id,
    required String label,
    required String username,
    @Default(HostAuthType.password) HostAuthType authType,
    String? keyId,
    String? secretRef,
    @Default(false) bool hostScoped,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Identity;

  String get summary => '$username@ · ${authType.label}';
}
