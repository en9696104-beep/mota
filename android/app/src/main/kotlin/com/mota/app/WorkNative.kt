package com.mota.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import rikka.shizuku.Shizuku
import java.io.File

/**
 * Work 工作台原生能力桥（MethodChannel: com.mota.app/work_native）
 *
 * 对应移动端三档系统权限：
 * - 无障碍（[WorkAccessibilityService]）：tap / swipe / inputText / readScreen
 * - Shizuku（[ShizukuShell]）：adb 级 shell 执行
 * - Root（su）：最高权限 shell 执行
 *
 * 所有方法在权限未就绪时返回可读失败原因，不做静默降级。
 */
object WorkNative {

    const val CHANNEL = "com.mota.app/work_native"

    private const val REQ_SHIZUKU = 0x5A17 // 任意请求码

    fun handle(call: MethodCall, result: Result, context: Context) {
        when (call.method) {
            // ---- 无障碍 ----
            "accessibilityStatus" -> result.success(WorkAccessibilityService.instance != null)
            "openAccessibilitySettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "tap" -> {
                val x = (call.argument<Double>("x"))?.toFloat()
                val y = (call.argument<Double>("y"))?.toFloat()
                if (x == null || y == null) {
                    result.error("BAD_ARGS", "tap 需要 x/y", null)
                    return
                }
                val svc = WorkAccessibilityService.instance
                if (svc == null) {
                    result.error("NO_SERVICE", "无障碍服务未开启", null)
                    return
                }
                svc.tap(x, y) { ok ->
                    if (ok) result.success(true)
                    else result.error("GESTURE_FAILED", "手势分发失败", null)
                }
            }
            "swipe" -> {
                val x1 = (call.argument<Double>("x1"))?.toFloat()
                val y1 = (call.argument<Double>("y1"))?.toFloat()
                val x2 = (call.argument<Double>("x2"))?.toFloat()
                val y2 = (call.argument<Double>("y2"))?.toFloat()
                val duration = (call.argument<Number>("duration"))?.toLong() ?: 300L
                if (x1 == null || y1 == null || x2 == null || y2 == null) {
                    result.error("BAD_ARGS", "swipe 需要 x1/y1/x2/y2", null)
                    return
                }
                val svc = WorkAccessibilityService.instance
                if (svc == null) {
                    result.error("NO_SERVICE", "无障碍服务未开启", null)
                    return
                }
                svc.swipe(x1, y1, x2, y2, duration) { ok ->
                    if (ok) result.success(true)
                    else result.error("GESTURE_FAILED", "手势分发失败", null)
                }
            }
            "inputText" -> {
                val text = call.argument<String>("text")
                if (text == null) {
                    result.error("BAD_ARGS", "inputText 需要 text", null)
                    return
                }
                val svc = WorkAccessibilityService.instance
                if (svc == null) {
                    result.error("NO_SERVICE", "无障碍服务未开启", null)
                    return
                }
                result.success(svc.inputText(text))
            }
            "readScreen" -> {
                val svc = WorkAccessibilityService.instance
                if (svc == null) {
                    result.error("NO_SERVICE", "无障碍服务未开启", null)
                    return
                }
                result.success(svc.readScreen())
            }

            // ---- 设备信息 ----
            "deviceInfo" -> result.success(deviceInfo(context))

            // ---- Shizuku ----
            "shizukuStatus" -> result.success(shizukuStatus(context))
            "requestShizukuPermission" -> {
                try {
                    Shizuku.requestPermission(REQ_SHIZUKU)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("REQ_FAILED", e.message, null)
                }
            }
            "shizukuExec" -> {
                val cmd = call.argument<String>("cmd")
                if (cmd == null) {
                    result.error("BAD_ARGS", "shizukuExec 需要 cmd", null)
                    return
                }
                ShizukuShell.ensureBound(context)
                // 首次 bindUserService 是异步的：轮询等待 UserService 连接（最多 2s）
                var waited = 0
                while (!ShizukuShell.isAvailable() && waited < 2000) {
                    Thread.sleep(50)
                    waited += 50
                }
                val out = ShizukuShell.exec(cmd)
                if (out == null) {
                    result.error(
                        "SHIZUKU_NOT_READY",
                        "Shizuku 未就绪：请确认 Shizuku 应用已运行且已授权",
                        null,
                    )
                } else {
                    result.success(out)
                }
            }

            // ---- Root ----
            "rootStatus" -> result.success(rootStatus())
            "rootExec" -> {
                val cmd = call.argument<String>("cmd")
                if (cmd == null) {
                    result.error("BAD_ARGS", "rootExec 需要 cmd", null)
                    return
                }
                Thread {
                    val outcome = try {
                        val process = ProcessBuilder("su", "-c", cmd)
                            .redirectErrorStream(true)
                            .start()
                        val output = process.inputStream.bufferedReader().use { it.readText() }
                        val exit = process.waitFor()
                        "$output(exit=$exit)"
                    } catch (e: Exception) {
                        "su 执行失败（未 Root 或未授权）: ${e.message}"
                    }
                    // Result 回主线程回调（MethodChannel 契约）
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        result.success(outcome)
                    }
                }.start()
            }

            else -> result.notImplemented()
        }
    }

    private fun deviceInfo(context: Context): Map<String, Any> {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        return mapOf(
            "platform" to "android",
            "model" to Build.MODEL,
            "brand" to Build.BRAND,
            "manufacturer" to Build.MANUFACTURER,
            "device" to Build.DEVICE,
            "android_version" to Build.VERSION.RELEASE,
            "sdk_int" to Build.VERSION.SDK_INT,
            "abi" to (Build.SUPPORTED_ABIS?.firstOrNull() ?: "unknown"),
            "screen" to "${metrics.widthPixels}x${metrics.heightPixels}",
        )
    }

    private fun shizukuStatus(context: Context): Map<String, Any> {
        val alive = try {
            Shizuku.pingBinder()
        } catch (_: Exception) {
            false
        }
        val permitted = alive && try {
            Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
        if (permitted) ShizukuShell.ensureBound(context)
        return mapOf(
            "available" to alive,
            "permitted" to permitted,
            "service_ready" to ShizukuShell.isAvailable(),
            "version" to try {
                Shizuku.getVersion()
            } catch (_: Exception) {
                0
            },
        )
    }

    private fun rootStatus(): Map<String, Any> {
        val paths = listOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/su/bin/su", "/debug_ramdisk/su",
        )
        val found = paths.firstOrNull { File(it).exists() }
        return mapOf(
            "su_binary" to (found != null),
            "path" to (found ?: ""),
        )
    }
}
