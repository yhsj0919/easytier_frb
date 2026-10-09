package xyz.yhsj.easytier_frb

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import java.net.InetAddress

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

        try {
            vpnInterface = createVpnInterface(args)
        } catch (error: Exception) {
            triggerCallback(
                "vpn_service_error",
                mapOf("configId" to configId, "message" to (error.message ?: "VPN 创建失败")),
            )
            stopSelf()
            return START_NOT_STICKY
        }
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

        val networkCidr = "${networkAddress(ipParts[0], ipParts[1].toInt())}/${ipParts[1]}"

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
            val prefix = routeParts[1].toInt()
            builder.addRoute(networkAddress(routeParts[0], prefix), prefix)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        return builder.establish()
            ?: throw IllegalStateException("Failed to establish VpnService")
    }

    /** 按掩码清除主机位，兼容 /16、/24、/32 等网段。 */
    private fun networkAddress(address: String, prefix: Int): String {
        val bytes = InetAddress.getByName(address).address
        require(prefix in 0..bytes.size * 8) { "无效的路由掩码：$prefix" }
        for (index in bytes.indices) {
            val bits = (prefix - index * 8).coerceIn(0, 8)
            val mask = (0xff shl (8 - bits)) and 0xff
            bytes[index] = (bytes[index].toInt() and mask).toByte()
        }
        return InetAddress.getByAddress(bytes).hostAddress!!
    }
}


