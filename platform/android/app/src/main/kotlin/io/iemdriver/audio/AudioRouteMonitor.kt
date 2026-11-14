package io.iemdriver.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean

enum class RouteKind { USB, BLUETOOTH, JACK, OTHER }

data class AudioEndpoint(
    val id: Int,
    val kind: RouteKind,
    val name: String,
    val address: String?,
    val bluetoothMac: String?,
)

data class UsbAudioIdentity(
    val deviceId: Int,
    val name: String,
    val vendorId: Int,
    val productId: Int,
)

data class RouteSnapshot(
    val availableOutputs: List<AudioEndpoint>,
    val activeOutputId: Int?,
    val usbAudioDevices: List<UsbAudioIdentity>,
)

/** Event-driven output route watcher. `onSnapshot` is always delivered on the main thread. */
class AudioRouteMonitor(
    context: Context,
    private val onSnapshot: (RouteSnapshot) -> Unit,
    private val readActiveOutputId: () -> Int? = { null },
) {
    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val usbManager = appContext.getSystemService(Context.USB_SERVICE) as UsbManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
    private var worker: HandlerThread? = null
    private var workerHandler: Handler? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            publishLatest()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            publishLatest()
        }
    }

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val thread = HandlerThread("iem-audio-route").apply { start() }
        worker = thread
        workerHandler = Handler(thread.looper)
        audioManager.registerAudioDeviceCallback(deviceCallback, workerHandler)
        workerHandler?.post(::publishLatest)
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        worker?.quitSafely()
        worker = null
        workerHandler = null
    }

    fun refresh() {
        workerHandler?.post(::publishLatest)
    }

    private fun publishLatest() {
        if (!running.get()) return
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.isSink }
            .mapNotNull(::toEndpoint)
        val usbAudio = usbManager.deviceList.values
            .filter(::hasAudioInterface)
            .map(::toUsbIdentity)
        val snapshot = RouteSnapshot(
            availableOutputs = outputs,
            activeOutputId = runCatching(readActiveOutputId).getOrNull(),
            usbAudioDevices = usbAudio,
        )
        mainHandler.post {
            if (running.get()) onSnapshot(snapshot)
        }
    }

    private fun toEndpoint(device: AudioDeviceInfo): AudioEndpoint? {
        val kind = when (device.type) {
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET -> RouteKind.USB

            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER -> RouteKind.BLUETOOTH

            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_LINE_ANALOG -> RouteKind.JACK

            else -> RouteKind.OTHER
        }
        val address = try {
            device.address.takeIf(String::isNotBlank)
        } catch (_: SecurityException) {
            null
        }
        val canReadBluetooth = appContext.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        val mac = if (kind == RouteKind.BLUETOOTH && canReadBluetooth &&
            address != null && MAC_ADDRESS.matches(address)
        ) address else null

        return AudioEndpoint(
            id = device.id,
            kind = kind,
            name = device.productName?.toString()?.takeIf(String::isNotBlank) ?: "Audio output",
            address = address,
            bluetoothMac = mac,
        )
    }

    private fun hasAudioInterface(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_AUDIO) return true
        return (0 until device.interfaceCount).any { index ->
            device.getInterface(index).interfaceClass == UsbConstants.USB_CLASS_AUDIO
        }
    }

    private fun toUsbIdentity(device: UsbDevice) = UsbAudioIdentity(
        deviceId = device.deviceId,
        name = device.productName?.takeIf(String::isNotBlank) ?: "USB audio device",
        vendorId = device.vendorId,
        productId = device.productId,
    )

    private companion object {
        val MAC_ADDRESS = Regex("(?i)^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")
    }
}
