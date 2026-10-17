#include "terminal_ime_bridge.h"

#include <commctrl.h>
#include <flutter/standard_method_codec.h>
#include <imm.h>

#include "utils.h"

namespace {

constexpr char kChannelName[] = "vibe_terminal/terminal_ime";
constexpr UINT_PTR kSubclassId = 0x56544945;  // 'VTIE'

// ImmGetContext/ImmReleaseContext RAII.
class ImmContext {
 public:
  explicit ImmContext(HWND window)
      : window_(window), context_(::ImmGetContext(window)) {}
  ~ImmContext() {
    if (context_ != nullptr) {
      ::ImmReleaseContext(window_, context_);
    }
  }
  ImmContext(const ImmContext&) = delete;
  ImmContext& operator=(const ImmContext&) = delete;

  HIMC get() const { return context_; }
  bool IsValid() const { return context_ != nullptr; }

 private:
  HWND window_;
  HIMC context_;
};

const flutter::EncodableValue* FindArg(const flutter::EncodableMap& map,
                                       const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

LONG IntArg(const flutter::EncodableMap& map, const char* key) {
  const auto* value = FindArg(map, key);
  if (value == nullptr) return 0;
  if (const auto* v = std::get_if<int32_t>(value)) return *v;
  if (const auto* v = std::get_if<int64_t>(value)) return static_cast<LONG>(*v);
  if (const auto* v = std::get_if<double>(value)) return static_cast<LONG>(*v);
  return 0;
}

}  // namespace

TerminalImeBridge::TerminalImeBridge(flutter::BinaryMessenger* messenger,
                                     HWND view_window)
    : view_window_(view_window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  ::SetWindowSubclass(view_window_, SubclassProc, kSubclassId,
                      reinterpret_cast<DWORD_PTR>(this));
}

TerminalImeBridge::~TerminalImeBridge() {
  ::RemoveWindowSubclass(view_window_, SubclassProc, kSubclassId);
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

// static
LRESULT CALLBACK TerminalImeBridge::SubclassProc(HWND window, UINT message,
                                                 WPARAM wparam, LPARAM lparam,
                                                 UINT_PTR subclass_id,
                                                 DWORD_PTR ref_data) {
  auto* bridge = reinterpret_cast<TerminalImeBridge*>(ref_data);
  if (bridge != nullptr) {
    std::optional<LRESULT> handled =
        bridge->HandleMessage(message, wparam, lparam);
    if (handled) {
      return *handled;
    }
  }
  return ::DefSubclassProc(window, message, wparam, lparam);
}

std::optional<LRESULT> TerminalImeBridge::HandleMessage(UINT message,
                                                        WPARAM wparam,
                                                        LPARAM lparam) {
  if (trace_) {
    Trace(message, wparam, lparam);
  }
  if (!enabled_) {
    // 엔진이 조합을 시작했는지 기억해 둔다. 조합 도중 활성화되면 그 조합의
    // 종료 메시지를 엔진에도 전달해야 엔진 편집 모델이 조합 상태에 갇히지
    // 않는다.
    if (message == WM_IME_STARTCOMPOSITION) {
      engine_composing_ = true;
    } else if (message == WM_IME_ENDCOMPOSITION) {
      engine_composing_ = false;
    }
    return std::nullopt;
  }

  switch (message) {
    case WM_IME_STARTCOMPOSITION:
      BeginImeWindow();
      // 엔진 핸들러와 같이 DefWindowProc의 기본 조합 창을 띄우지 않는다.
      return TRUE;
    case WM_IME_COMPOSITION: {
      if (lparam == 0) {
        // 조합 취소: 표시 중인 조합 문자열만 지운다.
        SendComposition(std::nullopt, std::wstring());
        return TRUE;
      }
      std::optional<std::wstring> commit;
      std::optional<std::wstring> composing;
      // 일부 IME는 확정과 다음 조합을 한 메시지로 보낸다. 확정을 먼저 처리한다.
      if (lparam & GCS_RESULTSTR) {
        commit = ReadCompositionString(GCS_RESULTSTR);
      }
      if (lparam & GCS_COMPSTR) {
        composing = ReadCompositionString(GCS_COMPSTR);
      }
      if (!commit && !composing) {
        return std::nullopt;
      }
      SendComposition(commit, composing);
      MoveImeWindow();
      // DefWindowProc에 넘기면 확정 문자열이 WM_IME_CHAR/WM_CHAR로 한 번 더
      // 들어온다.
      return TRUE;
    }
    case WM_IME_ENDCOMPOSITION:
      EndImeWindow();
      SendComposition(std::nullopt, std::wstring());
      if (engine_composing_) {
        engine_composing_ = false;
        return std::nullopt;
      }
      return TRUE;
  }
  return std::nullopt;
}

void TerminalImeBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "setEnabled") {
    const auto* enabled = std::get_if<bool>(call.arguments());
    if (enabled == nullptr) {
      result->Error("bad_args", "setEnabled expects a bool");
      return;
    }
    SetEnabled(*enabled);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setTrace") {
    const auto* enabled = std::get_if<bool>(call.arguments());
    trace_ = enabled != nullptr && *enabled;
    result->Success();
    return;
  }
  if (method == "setCaretRect") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "setCaretRect expects a map");
      return;
    }
    const LONG x = IntArg(*args, "x");
    const LONG y = IntArg(*args, "y");
    const LONG width = IntArg(*args, "width");
    const LONG height = IntArg(*args, "height");
    caret_rect_ = {x, y, x + (width > 0 ? width : 1),
                   y + (height > 0 ? height : 1)};
    MoveImeWindow();
    result->Success();
    return;
  }
  result->NotImplemented();
}

void TerminalImeBridge::SetEnabled(bool enabled) {
  if (enabled == enabled_) {
    return;
  }
  // 전환 시점에 진행 중인 조합은 현재 소유자(엔진 또는 브리지)에게 확정시켜
  // 끝낸다. IMM은 이 호출 안에서 확정/종료 메시지를 동기적으로 보낸다.
  CompleteComposition();
  if (!enabled) {
    EndImeWindow();
  }
  enabled_ = enabled;
}

void TerminalImeBridge::CompleteComposition() {
  ImmContext context(view_window_);
  if (!context.IsValid()) {
    return;
  }
  const LONG bytes =
      ::ImmGetCompositionStringW(context.get(), GCS_COMPSTR, nullptr, 0);
  if (bytes > 0) {
    ::ImmNotifyIME(context.get(), NI_COMPOSITIONSTR, CPS_COMPLETE, 0);
  }
}

void TerminalImeBridge::BeginImeWindow() {
  // 일부 IME는 ImmSetCandidateWindow 대신 시스템 캐럿 위치를 쓴다(엔진과 동일).
  if (!caret_created_) {
    caret_created_ = ::CreateCaret(view_window_, nullptr, 1, 1) != FALSE;
  }
  MoveImeWindow();
}

void TerminalImeBridge::EndImeWindow() {
  if (caret_created_) {
    ::DestroyCaret();
    caret_created_ = false;
  }
}

void TerminalImeBridge::MoveImeWindow() {
  if (::GetFocus() != view_window_) {
    return;
  }
  ImmContext context(view_window_);
  if (!context.IsValid()) {
    return;
  }
  if (caret_created_) {
    ::SetCaretPos(caret_rect_.left, caret_rect_.bottom);
  }
  COMPOSITIONFORM composition_form = {
      CFS_POINT, {caret_rect_.left, caret_rect_.top}};
  ::ImmSetCompositionWindow(context.get(), &composition_form);
  CANDIDATEFORM candidate_form = {
      0, CFS_EXCLUDE, {caret_rect_.left, caret_rect_.bottom}, caret_rect_};
  ::ImmSetCandidateWindow(context.get(), &candidate_form);
}

std::optional<std::wstring> TerminalImeBridge::ReadCompositionString(
    DWORD type) {
  ImmContext context(view_window_);
  if (!context.IsValid()) {
    return std::nullopt;
  }
  const LONG bytes = ::ImmGetCompositionStringW(context.get(), type, nullptr, 0);
  if (bytes < 0) {
    return std::nullopt;
  }
  std::wstring text(bytes / sizeof(wchar_t), L'\0');
  if (bytes > 0) {
    ::ImmGetCompositionStringW(context.get(), type, text.data(), bytes);
  }
  return text;
}

void TerminalImeBridge::Trace(UINT message, WPARAM wparam, LPARAM lparam) {
  const char* name = nullptr;
  switch (message) {
    case WM_IME_STARTCOMPOSITION:
      name = "START";
      break;
    case WM_IME_COMPOSITION:
      name = "COMPOSITION";
      break;
    case WM_IME_ENDCOMPOSITION:
      name = "END";
      break;
    case WM_IME_CHAR:
      name = "IME_CHAR";
      break;
    case WM_IME_NOTIFY:
      name = "IME_NOTIFY";
      break;
    case WM_CHAR:
      name = "CHAR";
      break;
    case WM_KEYDOWN:
      name = "KEYDOWN";
      break;
    default:
      return;
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("message")] = flutter::EncodableValue(name);
  payload[flutter::EncodableValue("wparam")] =
      flutter::EncodableValue(static_cast<int64_t>(wparam));
  payload[flutter::EncodableValue("lparam")] =
      flutter::EncodableValue(static_cast<int64_t>(lparam));
  payload[flutter::EncodableValue("enabled")] = flutter::EncodableValue(enabled_);
  if (message == WM_IME_COMPOSITION) {
    if (auto result = ReadCompositionString(GCS_RESULTSTR)) {
      payload[flutter::EncodableValue("result")] =
          flutter::EncodableValue(Utf8FromUtf16(result->c_str()));
    }
    if (auto comp = ReadCompositionString(GCS_COMPSTR)) {
      payload[flutter::EncodableValue("comp")] =
          flutter::EncodableValue(Utf8FromUtf16(comp->c_str()));
    }
  }
  channel_->InvokeMethod(
      "trace", std::make_unique<flutter::EncodableValue>(std::move(payload)));
}

void TerminalImeBridge::SendComposition(
    const std::optional<std::wstring>& commit,
    const std::optional<std::wstring>& composing) {
  flutter::EncodableMap payload;
  if (commit) {
    payload[flutter::EncodableValue("commit")] =
        flutter::EncodableValue(Utf8FromUtf16(commit->c_str()));
  }
  if (composing) {
    payload[flutter::EncodableValue("composing")] =
        flutter::EncodableValue(Utf8FromUtf16(composing->c_str()));
  }
  channel_->InvokeMethod(
      "composition",
      std::make_unique<flutter::EncodableValue>(std::move(payload)));
}
