package xyz.yhsj.easytier_frb

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EasytierFrbPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var activity: Activity
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "easytier_flutter/vpn")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "easytier_flutter/vpn_events")
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    EasytierVpnService.triggerCallback = { event, data ->
                        eventSink?.success(mapOf("event" to event, "data" to data))
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    EasytierVpnService.triggerCallback = { _, _ -> }
                }
            },
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareVpn" -> {
                val intent = VpnService.prepare(activity)
                if (intent != null) {
                    activity.startActivityForResult(intent, PREPARE_VPN_REQUEST)
                    result.success(false)
                } else {
                    result.success(true)
                }
            }
            "startVpn" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                val configId = args?.get("configId") as? String
                val ipv4Addr = args?.get("ipv4Addr") as? String
                if (configId.isNullOrBlank() || ipv4Addr.isNullOrBlank()) {
                    result.error("invalid_args", "configId and ipv4Addr are required", null)
                    return
                }

                val prepareIntent = VpnService.prepare(activity)
                if (prepareIntent != null) {
                    result.error("need_prepare", "Call prepareVpn first", null)
                    return
                }

                EasytierVpnService.self?.onRevoke()

                val serviceIntent = Intent(activity, EasytierVpnService::class.java)
                serviceIntent.putExtra(EasytierVpnService.CONFIG_ID, configId)
                serviceIntent.putExtra(EasytierVpnService.IPV4_ADDR, ipv4Addr)

                val routesList = args["routes"] as? List<*>
                if (routesList != null) {
                    val routes = routesList.filterIsInstance<String>().toTypedArray()
                    serviceIntent.putExtra(EasytierVpnService.ROUTES, routes)
                }

                val mtu = args["mtu"]
                if (mtu is Int) {
                    serviceIntent.putExtra(EasytierVpnService.MTU, mtu)
                }

                val dns = args["dns"] as? String
                if (!dns.isNullOrBlank()) {
                    serviceIntent.putExtra(EasytierVpnService.DNS, dns)
                }

                activity.startService(serviceIntent)
                result.success(null)
            }
            "stopVpn" -> {
                EasytierVpnService.self?.onRevoke()
                activity.stopService(Intent(activity, EasytierVpnService::class.java))
                result.success(null)
            }
            "getDeviceName" -> {
                val name =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                        android.provider.Settings.Global.getString(
                            activity.contentResolver,
                            android.provider.Settings.Global.DEVICE_NAME,
                        )
                    } else {
                        Build.MODEL
                    }
                result.success(name ?: Build.MODEL)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    companion object {
        private const val PREPARE_VPN_REQUEST = 0x0f
    }
}
