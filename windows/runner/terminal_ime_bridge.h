#ifndef RUNNER_TERMINAL_IME_BRIDGE_H_
#define RUNNER_TERMINAL_IME_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

// 터미널 입력 전용 Windows IME 브리지.
//
// Flutter 엔진은 IME 조합을 자체 편집 모델(TextInputModel)에 반영한 뒤
// 프레임워크와 비동기로 동기화한다. MS 한글 IME로 빠르게 치면 이 동기화가
// 어긋나 음절이 앞뒤로 뒤바뀐다(`한ㄱ` → `ㄱ한`). 터미널은 편집 버퍼가 필요
// 없으므로, Dart가 활성화한 동안에는 Flutter 뷰 창의 WM_IME_* 메시지를 엔진에
// 넘기지 않고 IMM32에서 확정/조합 문자열만 읽어 순서대로 Dart에 전달한다.
// 비활성 상태에서는 모든 메시지를 엔진에 그대로 넘기므로 일반 TextField의
// IME 동작은 바뀌지 않는다.
class TerminalImeBridge {
 public:
  TerminalImeBridge(flutter::BinaryMessenger* messenger, HWND view_window);
  ~TerminalImeBridge();

  TerminalImeBridge(const TerminalImeBridge&) = delete;
  TerminalImeBridge& operator=(const TerminalImeBridge&) = delete;

 private:
  static LRESULT CALLBACK SubclassProc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam,
                                       UINT_PTR subclass_id,
                                       DWORD_PTR ref_data);

  // 메시지를 소비했으면 결과를, 엔진에 넘겨야 하면 std::nullopt를 반환한다.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SetEnabled(bool enabled);
  void CompleteComposition();
  void BeginImeWindow();
  void EndImeWindow();
  void MoveImeWindow();
  std::optional<std::wstring> ReadCompositionString(DWORD type);
  void Trace(UINT message, WPARAM wparam, LPARAM lparam);
  void SendComposition(const std::optional<std::wstring>& commit,
                       const std::optional<std::wstring>& composing);

  HWND view_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool enabled_ = false;
  // 진단 전용: 켜져 있으면 IME 관련 원본 메시지를 Dart 입력 트레이스로 보낸다.
  bool trace_ = false;
  bool caret_created_ = false;
  // 비활성 상태에서 엔진이 조합을 시작해 아직 끝내지 않았는지.
  bool engine_composing_ = false;
  RECT caret_rect_ = {0, 0, 1, 1};
};

#endif  // RUNNER_TERMINAL_IME_BRIDGE_H_
