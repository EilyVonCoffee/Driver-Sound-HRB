package io.iemdriver.iem_driver

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.iemdriver.audio.AudioRouteMonitor
import io.iemdriver.audio.RouteSnapshot
import io.iemdriver.audio.SystemEqBand
import io.iemdriver.audio.SystemOutputEq

class MainActivity : FlutterActivity() {
    private var routeMonitor: AudioRouteMonitor? = null
    private var routeEvents: EventChannel.EventSink? = null
    private var testToneFrequencyHz = 1000f
    private var testAudioActive = false
    private val systemOutputEq = SystemOutputEq()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ROUTE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    routeEvents = events
                    startRouteMonitor()
                    requestBluetoothIdentityPermissionIfNeeded()
                }

                override fun onCancel(arguments: Any?) {
                    routeMonitor?.stop()
                    routeMonitor = null
                    routeEvents = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startTestTone" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val frequency = (arguments?.get("frequencyHz") as? Number)
                            ?.toFloat() ?: testToneFrequencyHz
                        val pinkNoise = arguments?.get("pinkNoise") as? Boolean ?: false
                        testToneFrequencyHz = frequency
                        testAudioActive = nativeStartTestTone(frequency, pinkNoise)
                        if (!testAudioActive) {
                            result.error(
                                "audio_output_unavailable",
                                "Could not open an audio output stream.",
                                null,
                            )
                        } else {
                            routeMonitor?.refresh()
                            result.success(true)
                        }
                    }

                    "stopTestAudio" -> {
                        nativeStopTestAudio()
                        testAudioActive = false
                        routeMonitor?.refresh()
                        result.success(true)
                    }

                    "isTestAudioActive" -> {
                        testAudioActive = testAudioActive && nativeIsAudioActive()
                        result.success(testAudioActive)
                    }

                    "setTestFrequency" -> {
                        val arguments = call.arguments as? Map<*, *>
                        testToneFrequencyHz = (arguments?.get("frequencyHz") as? Number)
                            ?.toFloat() ?: testToneFrequencyHz
                        result.success(
                            !testAudioActive || nativeSetTestFrequency(testToneFrequencyHz),
                        )
                    }

                    "configureEq" -> {
                        val configuration = call.arguments as? Map<*, *>
                        if (configuration == null) {
                            result.error("invalid_eq", "EQ configuration is missing.", null)
                        } else {
                            result.success(submitEqConfiguration(configuration))
                        }
                    }

                    "getSystemEqStatus" -> result.success(systemEqStatusMap())
                    "disableSystemEq" -> {
                        systemOutputEq.close()
                        result.success(true)
                    }

                    "readSpectrum" -> result.success(nativeReadSpectrum().toList())
                    else -> result.notImplemented()
                }
            }
    }

    private fun startRouteMonitor() {
        routeMonitor?.stop()
        routeMonitor = AudioRouteMonitor(
            applicationContext,
            onSnapshot = ::publishSnapshot,
            readActiveOutputId = {
                nativeCurrentDeviceId().takeIf { it >= 0 }
            },
        ).also(AudioRouteMonitor::start)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BLUETOOTH_PERMISSION_REQUEST &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && routeEvents != null
        ) {
            startRouteMonitor()
        }
    }

    private fun publishSnapshot(snapshot: RouteSnapshot) {
        val usbByName = snapshot.usbAudioDevices.associateBy { it.name.lowercase() }
        val outputs = snapshot.availableOutputs.map { endpoint ->
            val usbIdentity = usbByName[endpoint.name.lowercase()]
            mapOf(
                "id" to endpoint.id.toString(),
                "kind" to endpoint.kind.name.lowercase(),
                "name" to endpoint.name,
                "bluetoothMac" to endpoint.bluetoothMac,
                "vendorId" to usbIdentity?.vendorId,
                "productId" to usbIdentity?.productId,
                "active" to (snapshot.activeOutputId == endpoint.id),
            )
        }
        routeEvents?.success(
            mapOf(
                "availableOutputs" to outputs,
                "activeOutputId" to snapshot.activeOutputId?.toString(),
            ),
        )
    }

    private fun requestBluetoothIdentityPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), BLUETOOTH_PERMISSION_REQUEST)
        }
    }

    private fun submitEqConfiguration(configuration: Map<*, *>): Boolean {
        val bands = configuration["bands"] as? List<*> ?: return false
        if (bands.size != 10) return false
        val parsedBands = bands.map { value ->
            val band = value as? Map<*, *> ?: return false
            val frequency = (band["frequencyHz"] as? Number)?.toFloat() ?: return false
            val gain = (band["gainDb"] as? Number)?.toFloat() ?: return false
            SystemEqBand(
                enabled = band["enabled"] == true,
                frequencyHz = frequency,
                gainDb = gain,
            )
        }
        return runCatching { systemOutputEq.apply(parsedBands).available }
            .getOrDefault(false)
    }

    private fun systemEqStatusMap(): Map<String, Any> {
        val status = systemOutputEq.status
        return mapOf(
            "backend" to status.backend,
            "available" to status.available,
            "message" to status.message,
        )
    }

    override fun onDestroy() {
        nativeStopTestAudio()
        testAudioActive = false
        routeMonitor?.stop()
        routeMonitor = null
        systemOutputEq.close()
        super.onDestroy()
    }

    private external fun nativeStartTestTone(frequencyHz: Float, pinkNoise: Boolean): Boolean
    private external fun nativeStopTestAudio()
    private external fun nativeSetTestFrequency(frequencyHz: Float): Boolean
    private external fun nativeReadSpectrum(): FloatArray
    private external fun nativeCurrentDeviceId(): Int
    private external fun nativeIsAudioActive(): Boolean

    private companion object {
        const val ROUTE_CHANNEL = "iem_driver/audio_routes"
        const val ENGINE_CHANNEL = "iem_driver/audio_engine"
        const val BLUETOOTH_PERMISSION_REQUEST = 4201

        init {
            System.loadLibrary("iem_android_audio")
        }
    }
}
