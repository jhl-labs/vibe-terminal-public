import 'package:freezed_annotation/freezed_annotation.dart';

part 'snippet.freezed.dart';

// DB에 index로 영속화됨 — 순서 변경/중간 삽입 금지(append-only).
enum SnippetScope { global, host }

// DB에 index로 영속화됨 — 순서 변경/중간 삽입 금지(append-only).
enum SnippetRunMode { paste, run }

@freezed
abstract class Snippet with _$Snippet {
  const factory Snippet({
    required String id,
    required String name,
    required String body,
    @Default(SnippetScope.global) SnippetScope scope,
    String? hostId,
    @Default(SnippetRunMode.paste) SnippetRunMode defaultRunMode,
    @Default(0) int sortOrder,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Snippet;
}
