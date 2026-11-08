package cc.chenx.flclash.plugins

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.getSystemService

// Not the default-network callback: under the VPN the app's default network is
// the tunnel, which survives a Wi-Fi ↔ mobile switch unchanged.
internal class NetworkChangeWatcher(
    context: Context,
    private val onChanged: () -> Unit,
) {
    private val connectivity = context.getSystemService<ConnectivityManager>()
    private val handler = Handler(Looper.getMainLooper())
    private val transports = mutableMapOf<Network, Int>()
    private var primary: Network? = null
    private var seenCurrent = false

    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .build()

    private val bestCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = choose(network)

        override fun onLost(network: Network) {
            if (network == primary) primary = null
        }
    }

    private val allCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            transports[network] = rank(caps)
            choose(transports.minByOrNull { it.value }?.key)
        }

        override fun onLost(network: Network) {
            transports.remove(network)
            choose(transports.minByOrNull { it.value }?.key)
        }
    }

    private var registered: ConnectivityManager.NetworkCallback? = null

    fun start() {
        if (registered != null) return
        val manager = connectivity ?: return
        try {
            registered = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.registerBestMatchingNetworkCallback(request, bestCallback, handler)
                bestCallback
            } else {
                manager.registerNetworkCallback(request, allCallback, handler)
                allCallback
            }
        } catch (_: RuntimeException) {
            registered = null
        }
    }

    fun stop() {
        val callback = registered ?: return
        registered = null
        try {
            connectivity?.unregisterNetworkCallback(callback)
        } catch (_: RuntimeException) {
        }
        transports.clear()
        primary = null
        seenCurrent = false
    }

    private fun choose(network: Network?) {
        if (network == null || network == primary) return
        primary = network
        if (seenCurrent) onChanged()
        seenCurrent = true
    }

    private fun rank(caps: NetworkCapabilities): Int = when {
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
        else -> 20
    }
}
