#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cwctype>
#include <string>
#include <thread>
#include <windows.h>
#include <UIAutomation.h>
#include <UIAutomationClient.h>

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Foundation.h>

namespace {

std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

bool SessionBelongsToProcess(const std::string& source_app_id,
                             const std::string& process_name) {
  auto app_id = Lower(source_app_id);
  auto process = Lower(process_name);
  const auto extension = process.rfind(".exe");
  if (extension != std::string::npos) {
    process.resize(extension);
  }

  // Browser AUMIDs do not always match their executable names exactly.
  if (process == "msedge") {
    return app_id.find("edge") != std::string::npos;
  }
  if (process == "chrome") {
    return app_id.find("chrome") != std::string::npos;
  }
  if (process == "brave") {
    return app_id.find("brave") != std::string::npos;
  }
  if (process == "firefox") {
    return app_id.find("firefox") != std::string::npos;
  }
  return !process.empty() && app_id.find(process) != std::string::npos;
}

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(std::towlower(c));
  });
  return value;
}

bool IsPlayingForProcess(const std::string& process_name) {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  bool is_playing = false;
  try {
    const auto manager =
        winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    for (const auto& session : manager.GetSessions()) {
      if (!SessionBelongsToProcess(
              winrt::to_string(session.SourceAppUserModelId()), process_name)) {
        continue;
      }

      if (session.GetPlaybackInfo().PlaybackStatus() ==
          winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing) {
        is_playing = true;
        break;
      }
    }
  } catch (...) {
  }
  winrt::uninit_apartment();
  return is_playing;
}

}  // namespace

extern "C" __declspec(dllexport) int __cdecl IsMediaSessionPlayingForProcess(
    const char* process_name) {
  if (process_name == nullptr || process_name[0] == '\0') {
    return 0;
  }

  int is_playing = 0;
  std::thread query([&]() {
    try {
      is_playing = IsPlayingForProcess(process_name);
    } catch (...) {
      is_playing = 0;
    }
  });
  query.join();
  return is_playing;
}

extern "C" __declspec(dllexport) int __cdecl GetBrowserAddressBarValue(
    std::uintptr_t window_handle, wchar_t* output, int output_capacity) {
  if (window_handle == 0 || output == nullptr || output_capacity < 2) {
    return 0;
  }
  output[0] = L'\0';

  const HRESULT apartment_result =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninitialize_apartment =
      apartment_result == S_OK || apartment_result == S_FALSE;

  IUIAutomation* automation = nullptr;
  IUIAutomationElement* root = nullptr;
  IUIAutomationCondition* edit_condition = nullptr;
  IUIAutomationElementArray* elements = nullptr;
  int copied_characters = 0;

  do {
    if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation)))) {
      break;
    }
    if (FAILED(automation->ElementFromHandle(
            reinterpret_cast<HWND>(window_handle), &root))) {
      break;
    }

    VARIANT edit_type;
    VariantInit(&edit_type);
    edit_type.vt = VT_I4;
    edit_type.lVal = UIA_EditControlTypeId;
    const HRESULT condition_result = automation->CreatePropertyCondition(
        UIA_ControlTypePropertyId, edit_type, &edit_condition);
    VariantClear(&edit_type);
    if (FAILED(condition_result) || edit_condition == nullptr) {
      break;
    }
    if (FAILED(root->FindAll(TreeScope_Descendants, edit_condition, &elements)) ||
        elements == nullptr) {
      break;
    }

    int element_count = 0;
    if (FAILED(elements->get_Length(&element_count))) {
      break;
    }
    for (int index = 0; index < element_count; ++index) {
      IUIAutomationElement* element = nullptr;
      BSTR name = nullptr;
      BSTR automation_id = nullptr;
      IUnknown* unknown_pattern = nullptr;
      IUIAutomationValuePattern* value_pattern = nullptr;
      BSTR value = nullptr;

      if (SUCCEEDED(elements->GetElement(index, &element)) && element != nullptr) {
        element->get_CurrentName(&name);
        element->get_CurrentAutomationId(&automation_id);
        const auto lower_name = Lower(name == nullptr ? L"" : name);
        const auto lower_id = Lower(automation_id == nullptr ? L"" : automation_id);
        const bool looks_like_address_bar =
            lower_id.find(L"omnibox") != std::wstring::npos ||
            lower_id.find(L"address") != std::wstring::npos ||
            lower_name.find(L"address and search bar") != std::wstring::npos ||
            lower_name.find(L"address bar") != std::wstring::npos ||
            lower_name.find(L"enter address") != std::wstring::npos;

        if (looks_like_address_bar &&
            SUCCEEDED(element->GetCurrentPattern(UIA_ValuePatternId,
                                                  &unknown_pattern)) &&
            unknown_pattern != nullptr &&
            SUCCEEDED(unknown_pattern->QueryInterface(
                IID_PPV_ARGS(&value_pattern))) &&
            value_pattern != nullptr &&
            SUCCEEDED(value_pattern->get_CurrentValue(&value)) &&
            value != nullptr) {
          const auto value_length = SysStringLen(value);
          copied_characters = static_cast<int>(std::min<UINT>(
              value_length, static_cast<UINT>(output_capacity - 1)));
          std::copy_n(value, copied_characters, output);
          output[copied_characters] = L'\0';
        }
      }

      if (value != nullptr) SysFreeString(value);
      if (value_pattern != nullptr) value_pattern->Release();
      if (unknown_pattern != nullptr) unknown_pattern->Release();
      if (automation_id != nullptr) SysFreeString(automation_id);
      if (name != nullptr) SysFreeString(name);
      if (element != nullptr) element->Release();
      if (copied_characters > 0) break;
    }
  } while (false);

  if (elements != nullptr) elements->Release();
  if (edit_condition != nullptr) edit_condition->Release();
  if (root != nullptr) root->Release();
  if (automation != nullptr) automation->Release();
  if (uninitialize_apartment) CoUninitialize();
  return copied_characters;
}
