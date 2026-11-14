#include "EndpointNotificationClient.h"

#include <iterator>
#include <new>

namespace iem::windows_audio {

EndpointNotificationClient::EndpointNotificationClient(EndpointEventSink sink,
                                                       void* context) noexcept
    : sink_(sink), context_(context) {}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::QueryInterface(REFIID iid,
                                                                     void** object) {
    if (object == nullptr) return E_POINTER;
    *object = nullptr;
    if (iid == __uuidof(IUnknown) || iid == __uuidof(IMMNotificationClient)) {
        *object = static_cast<IMMNotificationClient*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

ULONG STDMETHODCALLTYPE EndpointNotificationClient::AddRef() {
    return references_.fetch_add(1, std::memory_order_relaxed) + 1U;
}

ULONG STDMETHODCALLTYPE EndpointNotificationClient::Release() {
    const auto remaining = references_.fetch_sub(1, std::memory_order_acq_rel) - 1U;
    if (remaining == 0U) delete this;
    return remaining;
}

void EndpointNotificationClient::Publish(EndpointEventKind kind,
                                         LPCWSTR endpointId,
                                         EDataFlow flow,
                                         ERole role,
                                         DWORD state,
                                         const PROPERTYKEY* key) noexcept {
    if (sink_ == nullptr) return;
    EndpointEvent event{};
    event.kind = kind;
    event.flow = flow;
    event.role = role;
    event.state = state;
    if (key != nullptr) event.propertyKey = *key;
    if (endpointId != nullptr) {
        std::size_t length = 0;
        while (length + 1U < std::size(event.endpointId) && endpointId[length] != L'\0') {
            ++length;
        }
        for (std::size_t i = 0; i < length; ++i) event.endpointId[i] = endpointId[i];
        event.endpointId[length] = L'\0';
    }
    sink_(context_, event);  // Sink contract: bounded, nonblocking queue write only.
}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::OnDeviceStateChanged(
    LPCWSTR endpointId, DWORD newState) {
    Publish(EndpointEventKind::StateChanged, endpointId, eAll, eConsole, newState);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::OnDeviceAdded(LPCWSTR endpointId) {
    Publish(EndpointEventKind::Added, endpointId);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::OnDeviceRemoved(LPCWSTR endpointId) {
    Publish(EndpointEventKind::Removed, endpointId);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::OnDefaultDeviceChanged(
    EDataFlow flow, ERole role, LPCWSTR endpointId) {
    Publish(EndpointEventKind::DefaultChanged, endpointId, flow, role);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE EndpointNotificationClient::OnPropertyValueChanged(
    LPCWSTR endpointId, const PROPERTYKEY key) {
    Publish(EndpointEventKind::PropertyChanged, endpointId, eAll, eConsole, 0, &key);
    return S_OK;
}

EndpointWatcher::~EndpointWatcher() {
    (void)Stop();
}

HRESULT EndpointWatcher::Start(EndpointEventSink sink, void* context) noexcept {
    if (enumerator_ != nullptr || client_ != nullptr) return HRESULT_FROM_WIN32(ERROR_ALREADY_INITIALIZED);
    if (sink == nullptr) return E_INVALIDARG;

    IMMDeviceEnumerator* enumerator = nullptr;
    auto result = CoCreateInstance(__uuidof(MMDeviceEnumerator),
                                   nullptr,
                                   CLSCTX_ALL,
                                   IID_PPV_ARGS(&enumerator));
    if (FAILED(result)) return result;

    auto* client = new (std::nothrow) EndpointNotificationClient(sink, context);
    if (client == nullptr) {
        enumerator->Release();
        return E_OUTOFMEMORY;
    }

    result = enumerator->RegisterEndpointNotificationCallback(client);
    if (FAILED(result)) {
        client->Release();
        enumerator->Release();
        return result;
    }

    enumerator_ = enumerator;
    client_ = client;
    return S_OK;
}

HRESULT EndpointWatcher::Stop() noexcept {
    HRESULT result = S_OK;
    if (enumerator_ != nullptr && client_ != nullptr) {
        result = enumerator_->UnregisterEndpointNotificationCallback(client_);
    }
    if (client_ != nullptr) {
        client_->Release();
        client_ = nullptr;
    }
    if (enumerator_ != nullptr) {
        enumerator_->Release();
        enumerator_ = nullptr;
    }
    return result;
}

}  // namespace iem::windows_audio
