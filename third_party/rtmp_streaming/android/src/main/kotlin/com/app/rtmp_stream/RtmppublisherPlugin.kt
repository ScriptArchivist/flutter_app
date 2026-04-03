package com.app.rtmp_stream

import android.app.Activity
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.platform.PlatformViewRegistry

interface PermissionStuff {
    fun adddListener(listener: PluginRegistry.RequestPermissionsResultListener)
}

class RtmppublisherPlugin : FlutterPlugin, ActivityAware {

    private val tag = "RtmppublisherPlugin"

    private var methodCallHandler: MethodCallHandlerImplNew? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.v(tag, "onAttachedToEngine $flutterPluginBinding")
        this.flutterPluginBinding = flutterPluginBinding
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.v(tag, "onDetachedFromEngine $binding")
        flutterPluginBinding = null
    }

    private fun maybeStartListening(
        activity: Activity,
        messenger: BinaryMessenger,
        permissionsRegistry: PermissionStuff,
        platformViewRegistry: PlatformViewRegistry
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return
        }

        if (methodCallHandler != null) {
            Log.v(tag, "maybeStartListening skipped: handler already exists")
            return
        }

        methodCallHandler = MethodCallHandlerImplNew(
            activity,
            messenger,
            CameraPermissions(),
            permissionsRegistry,
            platformViewRegistry
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.v(tag, "onAttachedToActivity $binding")
        flutterPluginBinding?.apply {
            maybeStartListening(
                binding.activity,
                binaryMessenger,
                object : PermissionStuff {
                    override fun adddListener(listener: PluginRegistry.RequestPermissionsResultListener) {
                        binding.addRequestPermissionsResultListener(listener)
                    }
                },
                platformViewRegistry
            )
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.v(tag, "onDetachedFromActivityForConfigChanges")
        // Ничего не останавливаем здесь.
        // Иначе камера/handler умирают во время пересоздания Activity.
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.v(tag, "onReattachedToActivityForConfigChanges $binding")
        // Если handler уже есть — просто оставляем его.
        // Если нет — создаём заново.
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        Log.v(tag, "onDetachedFromActivity")
        methodCallHandler?.stopListening()
        methodCallHandler = null
    }
}
