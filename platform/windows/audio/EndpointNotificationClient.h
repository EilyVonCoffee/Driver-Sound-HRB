#pragma once

#include <mmdeviceapi.h>
#include <propsys.h>

#include <atomic>
#include <cstddef>

namespace iem::windows_audio {

enum class EndpointEventKind : unsigned char {
    Added,
    Removed,
    StateChanged,
    DefaultChanged,
    PropertyChanged,
};

struct EndpointEvent {
    EndpointEventKind kind{};
    EDataFlow flow{eAll};
    ERole role{eConsole};
    DWORD state{0};
    PROPERTYKEY propertyKey{};
    wchar_t endpointId[512]{};
};

using EndpointEventSink = void (*)(void* context,
                                   const EndpointEvent& event) noexcept;

class EndpointNotificationClient final : public IMMNotificationClient {
public:
    EndpointNotificationClient(EndpointEventSink sink, void* context) noexcept;

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override;
    ULONG STDMETHODCALLTYPE AddRef() override;
    ULONG STDMETHODCALLTYPE Release() override;

    HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR endpointId,
                                                    DWORD newState) override;
    HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR endpointId) override;
    HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR endpointId) override;
    HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow,
                                                      ERole role,
                                                      LPCWSTR endpointId) override;
    HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR endpointId,
                                                      const PROPERTYKEY key) override;

private:
    ~EndpointNotificationClient() = default;
    void Publish(EndpointEventKind kind,
                 LPCWSTR endpointId,
                 EDataFlow flow = eAll,
                 ERole role = eConsole,
                 DWORD state = 0,
                 const PROPERTYKEY* key = nullptr) noexcept;

    std::atomic<ULONG> references_{1};
    EndpointEventSink sink_;
    void* context_;
};

// Start/Stop must run on the same thread after COM has been initialized as MTA.
class EndpointWatcher final {
public:
    EndpointWatcher() = default;
    ~EndpointWatcher();

    EndpointWatcher(const EndpointWatcher&) = delete;
    EndpointWatcher& operator=(const EndpointWatcher&) = delete;

    HRESULT Start(EndpointEventSink sink, void* context) noexcept;
    HRESULT Stop() noexcept;

private:
    IMMDeviceEnumerator* enumerator_{nullptr};
    EndpointNotificationClient* client_{nullptr};
};

}  // namespace iem::windows_audio
