import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class BoundedCommandOutput {
  BoundedCommandOutput(Stream<List<int>> stream, this.limit) {
    subscription = stream.listen(
      (chunk) {
        if (finished.isCompleted) return;
        if (bytes.length + chunk.length > limit) {
          finished.completeError(StateError('명령 출력이 $limit bytes를 초과했습니다.'));
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!finished.isCompleted) finished.completeError(error, stack);
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete(true);
      },
    );
  }
  final int limit;
  final bytes = BytesBuilder(copy: false);
  final finished = Completer<bool>();
  late StreamSubscription<List<int>> subscription;
  Future<bool> get done => finished.future;
  String get text => utf8.decode(bytes.toBytes(), allowMalformed: true);
  Future<void> cancel() => subscription.cancel();
}
