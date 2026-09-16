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
import io.flutter.plugin.common.PluginRegistry

/** Flutter 插件入口：负责系统 VPN 授权、服务启停和 TUN fd 事件转发。 */
class EasytierFrbPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var activity: Activity
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPrepareResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "easytier_flutter/vpn")
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "easytier_flutter/vpn_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
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
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareVpn" -> prepareVpn(result)
            "startVpn" -> startVpn(call, result)
            "stopVpn" -> {
                EasytierVpnService.self?.onRevoke()
                activity.stopService(Intent(activity, EasytierVpnService::class.java))
                result.success(null)
            }
            "getDeviceName" -> {
                val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
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

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingPrepareResult != null) {
            result.error("prepare_in_progress", "VPN permission is already being requested", null)
            return
        }
        pendingPrepareResult = result
        activity.startActivityForResult(intent, PREPARE_VPN_REQUEST)
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any?>
        val configId = args?.get("configId") as? String
        val ipv4Addr = args?.get("ipv4Addr") as? String
        if (configId.isNullOrBlank() || ipv4Addr.isNullOrBlank()) {
            result.error("invalid_args", "configId and ipv4Addr are required", null)
            return
        }
        if (VpnService.prepare(activity) != null) {
            result.error("need_prepare", "Call prepareVpn first", null)
            return
        }

        EasytierVpnService.self?.onRevoke()
        val serviceIntent = Intent(activity, EasytierVpnService::class.java).apply {
            putExtra(EasytierVpnService.CONFIG_ID, configId)
            putExtra(EasytierVpnService.IPV4_ADDR, ipv4Addr)
            (args["routes"] as? List<*>)?.filterIsInstance<String>()?.toTypedArray()?.let {
                putExtra(EasytierVpnService.ROUTES, it)
            }
            (args["mtu"] as? Int)?.let { putExtra(EasytierVpnService.MTU, it) }
            (args["dns"] as? String)?.takeIf { it.isNotBlank() }?.let {
                putExtra(EasytierVpnService.DNS, it)
            }
        }
        activity.startService(serviceIntent)
        result.success(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PREPARE_VPN_REQUEST) return false
        val pending = pendingPrepareResult ?: return false
        pendingPrepareResult = null
        pending.success(resultCode == Activity.RESULT_OK || VpnService.prepare(activity) == null)
        return true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() = detachFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    private fun detachFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingPrepareResult?.error(
            "activity_detached",
            "Activity detached during VPN permission request",
            null,
        )
        pendingPrepareResult = null
    }

    companion object {
        private const val PREPARE_VPN_REQUEST = 0x0f
    }
}
