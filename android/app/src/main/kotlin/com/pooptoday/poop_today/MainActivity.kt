package com.pooptoday.poop_today

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "poop_today/reminder_settings")
            .setMethodCallHandler { call, result ->
                val power = getSystemService(POWER_SERVICE) as PowerManager
                when (call.method) {
                    "backgroundAllowed" -> result.success(power.isIgnoringBatteryOptimizations(packageName))
                    "openBackgroundSettings", "openBannerSettings" -> {
                        val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))
                        val intent = when {
                            call.method == "openBannerSettings" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            call.method == "openBackgroundSettings" && !power.isIgnoringBatteryOptimizations(packageName) ->
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"))
                            else -> appSettings
                        }
                        try {
                            startActivity(intent)
                            result.success(null)
                        } catch (_: ActivityNotFoundException) {
                            try {
                                startActivity(appSettings)
                                result.success(null)
                            } catch (_: ActivityNotFoundException) {
                                result.error("settings_unavailable", "无法打开系统应用设置", null)
                            }
                        } catch (_: SecurityException) {
                            result.error("settings_denied", "系统拒绝打开设置", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
