package xyz.yhsj.easytier_frb

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor

/** 瘦 VpnService：仅建立 TUN 并通过 EventChannel 回传 fd，不运行 Rust。 */
class EasytierVpnService : VpnService() {
    companion object {
        var triggerCallback: (String, Map<String, Any?>) -> Unit = { _, _ -> }

        @JvmField
        var self: EasytierVpnService? = null

        const val CONFIG_ID = "CONFIG_ID"
        const val IPV4_ADDR = "IPV4_ADDR"
        const val ROUTES = "ROUTES"
        const val DNS = "DNS"
        const val MTU = "MTU"
    }

    private lateinit var vpnInterface: ParcelFileDescriptor
    private var configId: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val args = intent?.extras
        configId = args?.getString(CONFIG_ID)

        vpnInterface = createVpnInterface(args)
        triggerCallback(
            "vpn_service_start",
            mapOf(
                "fd" to vpnInterface.fd,
                "configId" to (configId ?: ""),
            ),
        )
        return START_NOT_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        self = this
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }

    override fun onRevoke() {
        disconnect()
        super.onRevoke()
    }

    private fun disconnect() {
        if (self != this) return
        if (this::vpnInterface.isInitialized) {
            triggerCallback(
                "vpn_service_stop",
                mapOf("configId" to configId),
            )
            vpnInterface.close()
        }
        self = null
    }

    private fun createVpnInterface(args: Bundle?): ParcelFileDescriptor {
        val mtu = args?.getInt(MTU) ?: 1300
        val ipv4Addr = args?.getString(IPV4_ADDR) ?: "10.0.0.1/24"
        val dns = args?.getString(DNS)

        val ipParts = ipv4Addr.split("/")
        if (ipParts.size != 2) {
            throw IllegalArgumentException("Invalid IPv4 addr: $ipv4Addr")
        }

        val octets = ipParts[0].split(".")
        if (octets.size != 4) {
            throw IllegalArgumentException("Invalid IPv4 address: ${ipParts[0]}")
        }
        val networkCidr = "${octets[0]}.${octets[1]}.${octets[2]}.0/${ipParts[1]}"

        var routes = mutableListOf(
            networkCidr,
            "224.0.0.0/4",
            "255.255.255.255/32",
        )
        args?.getStringArray(ROUTES)?.let { routes.addAll(it) }

        val builder = Builder()
            .setSession("EasyTier")
            .setBlocking(false)
            .addAddress(ipParts[0], ipParts[1].toInt())
            .setMtu(mtu)

        if (!dns.isNullOrBlank()) {
            builder.addDnsServer(dns)
        }

        for (route in routes) {
            val routeParts = route.split("/")
            if (routeParts.size != 2) {
                throw IllegalArgumentException("Invalid route: $route")
            }
            builder.addRoute(routeParts[0], routeParts[1].toInt())
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish()
            ?: throw IllegalStateException("Failed to establish VpnService")
    }
}


