package io.iemdriver.audio

/**
 * Converts route notifications into profile-selection events. Supply a resolver
 * backed by user-configured fingerprints; do not persist AudioDeviceInfo.id,
 * which is only an in-session identifier.
 */
class DeviceProfileRouter(
    private val resolveProfileId: (RouteSnapshot) -> String?,
    private val onProfileChanged: (String?) -> Unit,
) {
    var activeProfileId: String? = null
        private set

    /** Call on the main/control thread from AudioRouteMonitor.onSnapshot. */
    fun accept(snapshot: RouteSnapshot) {
        val nextProfileId = resolveProfileId(snapshot)
        if (nextProfileId == activeProfileId) return
        activeProfileId = nextProfileId
        onProfileChanged(nextProfileId)
    }
}
