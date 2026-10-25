package com.mota.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Work 工作台原生能力桥（无障碍 / Shizuku / Root）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WorkNative.CHANNEL)
            .setMethodCallHandler { call, result ->
                WorkNative.handle(call, result, this)
            }
    }
}
