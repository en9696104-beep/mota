import 'dart:async';
import 'dart:io' show File, Platform, exit, stdout;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app.dart';
import 'controllers/chat_settings_controller.dart';
import 'services/api_service.dart';
import 'services/chat_history_db.dart';
import 'services/cooperation_pipeline.dart';
import 'services/github_stars_sync.dart';
import 'services/llama_service.dart';
import 'services/locale_service.dart';
import 'services/model_repository.dart';
import 'services/storage_service.dart';
import 'work/services/work_agent_server.dart';
Future<void> main(List<String> args) async {
  // 推理自检模式（无 GUI）：桌面端运行
  //   MOTA_SELFTEST_MODEL=/path/to/model.gguf ./mota
  // 加载模型 → 流式生成 → 打印结果 → 退出码 0/1。
  // 用于发布前的端到端验证与用户排障。
  if (!kIsWeb) {
    final selfTestModel = Platform.environment['MOTA_SELFTEST_MODEL'];
    if (selfTestModel != null && selfTestModel.isNotEmpty) {
      await _runInferenceSelfTest(selfTestModel);
      return;
    }
  }

  // 启动期全局兜底：捕获未处理异常（如大上下文模型加载 OOM 等），
  // 避免直接闪退无感知；上下文 OOM 的恢复逻辑见 ChatController 的降级重载
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 本地存储（已下载模型映射）需在 UI 之前就绪
      await Get.putAsync<StorageService>(() => StorageService().init());
      // 界面语言（跟随系统 / 中文 / English；app.dart 读取初始 locale）
      await Get.putAsync<LocaleService>(() => LocaleService().init());
      // 模型目录（assets/store_data.json + 星数本地缓存）
      await Get.putAsync<ModelRepository>(() => ModelRepository().init());
      // 聊天记录数据库（sqflite；桌面端走 sqflite_common_ffi）。
      // 失败仅降级历史功能，不阻塞启动
      await ChatHistoryDatabase.instance.ensureInitialized();
      // 模型高级参数（上下文长度 / 系统提示词 / 发散度 / 线程数）
      await Get.putAsync<ChatSettingsController>(
        () => ChatSettingsController.instance.init(),
      );
      // 合作系统（多模型接力管线配置，shared_preferences 持久化）
      await Get.putAsync<CooperationService>(
        () => CooperationService().init(),
      );
      // 本地 API 服务（OpenAI 兼容，默认不启动，用户在设置页手动开启）
      Get.put<ApiService>(ApiService.instance);
      // Work 工作台被控端（配对码/档位持久化恢复；端点随 API 服务挂载）
      await WorkAgentServer.instance.init();
      runApp(const MotaApp());
      // 启动后异步刷新 GitHub 星数（失败/断网则用本地缓存，不阻塞首帧）
      GitHubStarsSyncService.sync();
    },
    (error, stack) {
      debugPrint('MOTA 启动期未捕获异常: $error\n$stack');
    },
  );
}

/// 推理引擎端到端自检（不启动 GUI）：
/// 1) 平台路由检查  2) GGUF 加载（含 GPU→CPU 降级）  3) 流式生成  4) 资源释放
Future<void> _runInferenceSelfTest(String modelPath) async {
  final sw = Stopwatch()..start();
  stdout.writeln('== MOTA 推理自检 ==');
  stdout.writeln('平台: ${Platform.operatingSystem} | '
      '引擎可用: ${LlamaService.isEngineAvailable}');
  stdout.writeln('模型: $modelPath');

  if (!File(modelPath).existsSync()) {
    stdout.writeln('自检失败: 模型文件不存在');
    exit(1);
  }

  final ok = await LlamaService.instance.loadModel(
    modelPath,
    threads: 4,
    contextSize: 1024,
  );
  stdout.writeln('加载: ${ok ? "成功" : "失败"} (${sw.elapsedMilliseconds}ms)');
  if (!ok) {
    exit(1);
  }

  final buf = StringBuffer();
  await for (final token in LlamaService.instance.generateChatStream(
    const [
      LlamaTurn(
        role: 'system',
        content: 'You are a helpful assistant. Answer briefly.',
      ),
      LlamaTurn(role: 'user', content: 'Say hello in one short sentence.'),
    ],
    temperature: 0.2,
    maxTokens: 48,
  )) {
    buf.write(token);
  }
  final reply = buf.toString().trim();
  stdout.writeln('回复 (${sw.elapsedMilliseconds}ms): ${reply.isEmpty ? "<空>" : reply}');
  stdout.writeln(reply.isNotEmpty ? '== 自检通过 ==' : '== 自检失败: 无输出 ==');

  await LlamaService.instance.dispose();
  exit(reply.isNotEmpty ? 0 : 1);
}
