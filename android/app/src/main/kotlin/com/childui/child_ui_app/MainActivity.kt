package com.childui.child_ui_app

import android.app.backup.BackupManager
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "child_ui_app/platform"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        try {
                            if (multicastLock?.isHeld == true) {
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            val wifi = applicationContext
                                .applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            if (wifi == null) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            multicastLock = wifi.createMulticastLock("child_ui_discovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST", e.message, null)
                        }
                    }
                    "releaseMulticastLock" -> {
                        try {
                            multicastLock?.let { lock ->
                                if (lock.isHeld) {
                                    lock.release()
                                }
                            }
                            multicastLock = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST", e.message, null)
                        }
                    }
                    "requestBackupNow" -> {
                        try {
                            BackupManager(applicationContext).dataChanged()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BACKUP_ERROR", e.message, null)
                        }
                    }
                    "openWifiSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WIFI_SETTINGS_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
