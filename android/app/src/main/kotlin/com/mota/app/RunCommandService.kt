package com.mota.app

import rikka.shizuku.Shizuku

/**
 * Shizuku UserService（对应「Shizuku 权限」档）
 *
 * 由 Shizuku 服务器以 shell(uid 2000) 权限拉起本进程，向控制端提供
 * adb 级命令执行。进程与主进程隔离（:shell 后缀），崩溃不影响 UI。
 */
class RunCommandService : android.app.Service() {

    override fun onBind(intent: android.content.Intent?): android.os.IBinder {
        return object : IRunCommand.Stub() {
            override fun runCommand(cmd: String): String {
                return try {
                    val process = ProcessBuilder("/bin/sh", "-c", cmd)
                        .redirectErrorStream(true)
                        .start()
                    val output = process.inputStream.bufferedReader().use { it.readText() }
                    val exit = process.waitFor()
                    if (output.isEmpty()) "(exit=$exit, 无输出)" else output
                } catch (e: Exception) {
                    "命令执行异常: ${e.message}"
                }
            }
        }
    }
}

/**
 * Shizuku UserService 绑定管理（主进程侧）
 *
 * 生命周期：pingBinder 存活 + 已授权 → bindUserService（异步）→ asInterface。
 * 解绑/进程死亡时清空引用，下次 ensureBound 重建。
 */
object ShizukuShell {

    @Volatile
    private var service: IRunCommand? = null

    private val connection = object : android.content.ServiceConnection {
        override fun onServiceConnected(name: android.content.ComponentName?, binder: android.os.IBinder?) {
            service = IRunCommand.Stub.asInterface(binder)
        }

        override fun onServiceDisconnected(name: android.content.ComponentName?) {
            service = null
        }
    }

    /** 服务是否可用（Shizuku 存活 + 已授权 + UserService 已连接） */
    fun isAvailable(): Boolean {
        return try {
            Shizuku.pingBinder() &&
                Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED &&
                service != null
        } catch (e: Exception) {
            false
        }
    }

    /** 确保 UserService 已绑定（异步；isAvailable 变 true 即就绪） */
    fun ensureBound(context: android.content.Context) {
        if (service != null) return
        try {
            if (!Shizuku.pingBinder()) return
            if (Shizuku.checkSelfPermission() != android.content.pm.PackageManager.PERMISSION_GRANTED) return
            val args = Shizuku.UserServiceArgs(
                android.content.ComponentName(context.packageName, RunCommandService::class.java.name)
            )
                .daemon(false)
                .debuggable(false)
                .version(1)
                .processNameSuffix("shell")
            Shizuku.bindUserService(args, connection)
        } catch (_: Exception) {
            // 绑定失败：isAvailable 保持 false，UI 引导重试
        }
    }

    /** 执行命令；服务未就绪返回 null */
    fun exec(cmd: String): String? {
        val svc = service ?: return null
        return try {
            svc.runCommand(cmd)
        } catch (e: Exception) {
            "命令执行异常: ${e.message}"
        }
    }
}
