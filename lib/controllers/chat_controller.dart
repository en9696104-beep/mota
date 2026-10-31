import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../data/models/ai_model.dart';
import '../data/models/chat_turn.dart';
import '../services/chat_history_db.dart';
import '../services/cooperation_pipeline.dart';
import '../services/js_code_parser.dart';
import '../services/js_sandbox.dart';
import '../services/llama_service.dart';
import '../services/mcp/mcp_protocol.dart';
import '../services/mcp/tool_prompt.dart';
import '../services/model_repository.dart';
import '../services/tts_player.dart';
import '../services/voice_recorder.dart';
import '../theme/app_theme.dart';
import 'chat_settings_controller.dart';
import 'main_controller.dart';
import 'mcp_controller.dart';
import 'store_controller.dart';

/// 对话消息角色
enum ChatRole { user, assistant }

/// 一条对话消息（text 可变：流式 token 实时追加）
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.time,
    this.imagePaths = const <String>[],
  });

  final ChatRole role;
  String text;
  final DateTime time;

  /// 消息附带的本地图片路径（用户上传，OCR 管线用）
  final List<String> imagePaths;
}

/// 对话页状态：接入 llama.cpp 本地流式推理
class ChatController extends GetxController {
  final messages = <ChatMessage>[].obs;
  final input = ''.obs;
  final modelName = '本地模型'.obs;

  /// 模型加载中（loadModel 是耗时操作）
  final isLoadingModel = false.obs;

  /// 参数变更触发热重载中（卸载旧模型 → 按新参数重新加载）
  final isReloading = false.obs;

  /// 模型就绪，可以对话
  final modelReady = false.obs;

  /// 正在生成回复
  final isGenerating = false.obs;

  String? _modelId;
  String? _modelPath;
  String? _chatTemplate;
  StreamSubscription<String>? _subscription;

  /// 当前轮次的用户输入与助手回复（流式结束后持久化到数据库）
  String? _pendingUserText;
  ChatMessage? _currentReply;
  bool _persisted = false;

  /// 工具循环中：用户主动停止标志 / 当前轮次完成信号
  bool _stopRequested = false;
  Completer<void>? _roundCompleter;

  /// 待发送的图片路径（输入框旁的图片按钮选择）
  final pendingImages = <String>[].obs;

  /// 语音输入录音中
  final isRecording = false.obs;

  /// 语音识别转写中
  final isTranscribing = false.obs;

  /// 当前模型 id（供 UI 解析品牌图标等；合作系统主模型切换后同步更新）
  String? get modelId => _modelId;

  /// TTS 朗读中
  final isSpeaking = false.obs;

  /// 当前模型是否支持图片输入（桌面端引擎 + 模型具备 vision 能力）
  final supportsImageInput = false.obs;

  @override
  void onInit() {
    super.onInit();
    final arguments = Get.arguments as Map<String, dynamic>?;
    if (arguments != null) {
      modelName.value = arguments['modelName'] as String? ?? modelName.value;
      _modelId = arguments['modelId'] as String?;
      _modelPath = arguments['modelPath'] as String?;
    }
    // 合作系统开启且配置了主对话模型：以管线主模型为准
    _applyCooperationPrimaryModel();
    _resolveTemplate();
    // 商店数据异步加载完成后刷新图片输入能力
    if (Get.isRegistered<StoreController>()) {
      ever(Get.find<StoreController>().models, (_) => _refreshImageSupport());
    }
    // 合作开关 / OCR 角色变更时同步刷新
    if (Get.isRegistered<CooperationService>()) {
      ever(Get.find<CooperationService>().config, (_) => _refreshImageSupport());
    }
    _refreshImageSupport();
    // 从历史对话点入：恢复该模型的往期上下文
    if (arguments?['sessionId'] != null) {
      _restoreHistoryFromDb();
    }
    _loadModelIfNeeded();
  }

  /// 按 id 查找商店中的当前模型（找不到返回 null）
  AiModel? _findStoreModel(String? id) {
    if (id == null || !Get.isRegistered<StoreController>()) return null;
    for (final m in Get.find<StoreController>().models) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 按当前模型的能力刷新图片输入开关
  void _refreshImageSupport() {
    if (!LlamaService.supportsMultimodal) {
      supportsImageInput.value = false;
      return;
    }
    // 合作管线配置了 OCR 角色时，图片经 OCR 模型转文字，对话模型无需视觉能力
    if (_cooperationEnabled) {
      final coop = Get.find<CooperationService>();
      if (coop.config.value.ocrModelId != null) {
        supportsImageInput.value = true;
        return;
      }
    }
    final model = _findStoreModel(_modelId);
    // 商店外的模型（本地导入）无法核对能力，放行
    supportsImageInput.value =
        model == null || model.hasCapability(ModelCapability.vision);
  }

  /// 合作系统开启时，聊天页主模型切换为管线配置的主对话模型
  void _applyCooperationPrimaryModel() {
    if (!Get.isRegistered<CooperationService>()) return;
    final coop = Get.find<CooperationService>();
    if (!coop.config.value.enabled) return;
    final primary = coop.primaryChatModel;
    if (primary == null) return;
    _modelId = primary.model.id;
    _modelPath = primary.path;
    modelName.value = primary.model.name;
  }

  /// 合作系统是否可用（已注册且开启）
  bool get _cooperationEnabled =>
      Get.isRegistered<CooperationService>() &&
      Get.find<CooperationService>().config.value.enabled;

  /// 附加一张待发送图片
  void addPendingImage(String path) {
    if (pendingImages.length >= 4) {
      Get.snackbar(
        '最多 4 张',
        '一次最多上传 4 张图片',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    pendingImages.add(path);
  }

  /// 选择本地图片（file_picker）
  Future<void> pickImages() async {
    if (!supportsImageInput.value) {
      Get.snackbar(
        '当前模型不支持图片输入',
        '请切换到具备视觉能力的模型（如 DeepSeek-OCR、Qwen2.5-VL、Gemma-3），或在合作系统中配置 OCR 模型',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );
      final paths = result?.paths.whereType<String>().where((p) => p.isNotEmpty);
      if (paths != null) {
        for (final p in paths) {
          addPendingImage(p);
        }
      }
    } catch (e) {
      Get.snackbar('选择图片失败', e.toString(), snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// 移除一张待发送图片
  void removePendingImage(String path) => pendingImages.remove(path);

  /// 语音输入：开始 / 停止录音（停止后自动 ASR 转写填入输入框）
  Future<void> toggleVoiceInput() async {
    if (isTranscribing.value) return;
    if (isRecording.value) {
      final path = await VoiceRecorderService.instance.stop();
      isRecording.value = false;
      if (path == null) return;
      isTranscribing.value = true;
      try {
        final text = await Get.find<CooperationService>().runAsr(path);
        if (text != null && text.trim().isNotEmpty) {
          input.value = text.trim();
        } else {
          Get.snackbar(
            '未识别到语音',
            '请确认已在合作系统中配置语音识别（ASR）模型',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } on UnsupportedError {
        Get.snackbar(
          '当前平台不支持语音识别',
          'ASR 需要桌面端（llamadart）推理引擎',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } catch (e) {
        Get.snackbar(
          '语音识别失败',
          e.toString(),
          snackPosition: SnackPosition.BOTTOM,
        );
      } finally {
        isTranscribing.value = false;
        // 清理临时录音文件
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      return;
    }
    final path = await VoiceRecorderService.instance.start();
    if (path == null) {
      Get.snackbar(
        '无法录音',
        '请检查麦克风权限',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    isRecording.value = true;
  }

  /// 朗读最后一条助手回复（合作系统 TTS 阶段）
  Future<void> speakLastReply() async {
    ChatMessage? last;
    for (final m in messages.reversed) {
      if (m.role == ChatRole.assistant && m.text.trim().isNotEmpty) {
        last = m;
        break;
      }
    }
    if (last == null) return;
    if (isSpeaking.value) {
      await TtsPlayerService.instance.stop();
      isSpeaking.value = false;
      return;
    }
    isSpeaking.value = true;
    try {
      final audio = await Get.find<CooperationService>().runTts(last.text);
      if (audio == null) {
        Get.snackbar(
          '未配置语音合成',
          '请先在合作系统中配置 TTS 模型',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      await TtsPlayerService.instance.play(audio);
    } on UnsupportedError {
      Get.snackbar(
        '当前平台不支持语音合成',
        'TTS 需要桌面端（llamadart）推理引擎',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      Get.snackbar('朗读失败', e.toString(), snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSpeaking.value = false;
    }
  }

  /// 从历史记录点入时，把该模型的往期轮次读出来渲染为历史气泡；
  /// send() 携带全量历史，上下文随之喂给模型
  Future<void> _restoreHistoryFromDb() async {
    final id = _modelId;
    if (id == null) return;
    final turns = await ChatHistoryDatabase.instance.turnsForModel(id);
    for (final turn in turns) {
      if (turn.userContent.isNotEmpty) {
        messages.add(
          ChatMessage(
            role: ChatRole.user,
            text: turn.userContent,
            time: turn.createdAt,
          ),
        );
      }
      if (turn.assistantContent.isNotEmpty) {
        messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            text: turn.assistantContent,
            time: turn.createdAt,
          ),
        );
      }
    }
    messages.refresh();
  }

  /// 将当前轮次写入数据库（完成 / 出错 / 手动停止时调用，幂等）
  void _persistTurnIfNeeded() {
    if (_persisted) return;
    final reply = _currentReply;
    final userText = _pendingUserText;
    final modelId = _modelId;
    if (reply == null || userText == null || modelId == null) return;
    if (reply.text.trim().isEmpty) return;
    _persisted = true;
    ChatHistoryDatabase.instance.insertTurn(
      ChatTurn(
        modelId: modelId,
        modelName: modelName.value,
        createdAt: DateTime.now(),
        userContent: userText,
        assistantContent: reply.text,
      ),
    );
  }

  /// 从商店数据中解析该模型的聊天模板（如 Qwen 系用 chatml）
  void _resolveTemplate() {
    final id = _modelId;
    if (id == null) return;
    final model = ModelRepository.to.byId(id);
    if (model != null) _chatTemplate = model.chatTemplate;
  }

  /// 模型是否有本地文件（已下载）；未下载时参数仅保存不重载
  bool get hasLocalModel => _modelPath != null && _modelPath!.isNotEmpty;

  /// 有本地路径才加载模型；未下载时保持未就绪，由 UI 引导去商店
  Future<void> _loadModelIfNeeded() async {
    final path = _modelPath;
    if (path == null || path.isEmpty) return;
    isLoadingModel.value = true;
    final ok = await _loadModelWithOomFallback(path);
    isLoadingModel.value = false;
    modelReady.value = ok;
    if (!ok) {
      if (!LlamaService.isEngineAvailable) {
        Get.snackbar(
          '当前平台不支持本地推理',
          LlamaService.engineUnavailableReason,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          '模型加载失败',
          '请尝试更小的量化版本',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  /// 带 OOM 降级的模型加载（阶段三容错核心）：
  /// 按设置参数加载失败时，若请求上下文大于 2048，判定为内存不足，
  /// 自动降级到 2048 重试并持久化修正，避免用户每次启动都闪退。
  Future<bool> _loadModelWithOomFallback(String path) async {
    final settings = ChatSettingsController.instance;
    final requested = settings.contextSize.value;
    final ok = await LlamaService.instance.loadModel(
      path,
      threads: settings.threads.value,
      contextSize: requested,
    );
    if (ok || requested <= ChatSettingsController.defaultContextSize) {
      return ok;
    }

    // 大上下文（如 4096）加载失败：疑似内存不足，降级到安全档位 2048 重试
    final downgraded = await LlamaService.instance.loadModel(
      path,
      threads: settings.threads.value,
      contextSize: ChatSettingsController.defaultContextSize,
    );
    if (downgraded) {
      await settings.downgradeContextSizeToSafe();
      Get.snackbar(
        '内存不足，已自动恢复为 2048 上下文',
        '大上下文占用内存过高，已为你切换到安全档位',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    return downgraded;
  }

  /// 参数变更后热重载模型（阶段二核心）：
  /// 中断当前生成 → LlamaService.dispose() 卸载 → 按新 contextSize/threads 重新加载
  Future<void> reloadWithNewSettings() async {
    final path = _modelPath;
    if (path == null || path.isEmpty) return;
    if (isReloading.value) return;

    // 中断当前生成，避免向已释放的底层 controller 继续写入
    _subscription?.cancel();
    _subscription = null;
    await LlamaService.instance.stop();
    // 显式卸载当前模型，再按新参数重新加载
    await LlamaService.instance.dispose();

    isReloading.value = true;
    modelReady.value = false;

    final ok = await _loadModelWithOomFallback(path);

    isReloading.value = false;
    modelReady.value = ok;
    if (!ok) {
      if (!LlamaService.isEngineAvailable) {
        Get.snackbar(
          '当前平台不支持本地推理',
          LlamaService.engineUnavailableReason,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          '模型重载失败',
          '请尝试更小的上下文或量化版本',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  /// 发送消息并流式接收回复
  ///
  /// 合作系统开启时，发送前依次执行：
  /// 1. 安全审核（配置了安全模型时）：unsafe 直接拦截
  /// 2. OCR 预处理（消息带图且配置了 OCR 模型时）：图片文字拼入消息
  Future<void> send() async {
    final text = input.value.trim();
    if (text.isEmpty && pendingImages.isEmpty) return;
    if (isGenerating.value) return;
    if (!modelReady.value) {
      if (_modelPath == null) {
        // 未下载：引导去商店，带快捷按钮
        Get.snackbar(
          '请先在商店下载模型',
          '下载后即可完全离线对话',
          snackPosition: SnackPosition.BOTTOM,
          mainButton: TextButton(
            onPressed: () {
              Get.back(); // 关闭 snackbar
              Get.find<MainController>().changeTab(1);
            },
            child: const Text(
              '去商店下载',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      } else if (!LlamaService.isEngineAvailable) {
        Get.snackbar(
          '当前平台不支持本地推理',
          LlamaService.engineUnavailableReason,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          '暂时无法对话',
          '模型正在加载中，请稍候',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return;
    }

    var finalText = text;
    final images = List<String>.from(pendingImages);

    // ---------- 合作管线预处理 ----------
    if (_cooperationEnabled) {
      final coop = Get.find<CooperationService>();
      final config = coop.config.value;

      // 1. 安全审核（输入闸门）
      if (config.securityModelId != null && finalText.isNotEmpty) {
        final check = await coop.runSecurityCheck(finalText);
        if (!check.safe) {
          Get.snackbar(
            '内容被安全模型拦截',
            check.reason.isEmpty ? '输入内容未通过安全审核' : check.reason,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 5),
          );
          return;
        }
      }

      // 2. OCR 预处理（图片 → 文字，拼入消息）
      if (images.isNotEmpty && config.ocrModelId != null) {
        final ocrTexts = <String>[];
        for (final image in images) {
          final ocr = await coop.runOcr(image);
          if (ocr != null && ocr.trim().isNotEmpty) ocrTexts.add(ocr.trim());
        }
        if (ocrTexts.isNotEmpty) {
          finalText =
              '$finalText\n\n【图片文字识别】\n${ocrTexts.join('\n\n')}';
        }
      }
    }

    messages.add(
      ChatMessage(
        role: ChatRole.user,
        text: finalText.isEmpty ? '（图片）' : finalText,
        time: DateTime.now(),
        imagePaths: images,
      ),
    );
    input.value = '';
    pendingImages.clear();

    final reply = ChatMessage(
      role: ChatRole.assistant,
      text: '',
      time: DateTime.now(),
    );
    messages.add(reply);

    // 记录当前轮次，流式结束后持久化到数据库
    _pendingUserText = finalText;
    _currentReply = reply;
    _persisted = false;

    _runGenerationWithTools(reply);
  }

  /// 多轮生成循环：生成 → 解析工具调用 → 执行 → 结果回喂 → 再生成
  /// （maxRounds 防死循环；无 MCP 工具时退化为普通单轮对话）
  Future<void> _runGenerationWithTools(ChatMessage reply) async {
    final settings = ChatSettingsController.instance;
    final mcp = Get.isRegistered<McpController>()
        ? Get.find<McpController>()
        : null;
    final tools = mcp?.allTools ?? <({McpServerEntry server, McpTool tool})>[];

    // 上下文策略：system prompt（工具指令 + JS 沙箱能力）+ 全量历史，
    // 保证任意上下文长度下行为正确
    final systemContent = [
      settings.systemPrompt.value,
      if (tools.isNotEmpty) ToolPrompt.buildToolsPrompt(tools),
      JsPrompt.instruction,
    ].where((s) => s.isNotEmpty).join('\n\n');
    final history = <LlamaTurn>[
      LlamaTurn(role: 'system', content: systemContent),
      ...messages
          .where((m) => m.text.isNotEmpty)
          .map(
            (m) => LlamaTurn(
              role: m.role == ChatRole.user ? 'user' : 'assistant',
              content: m.text,
              imagePaths: m.imagePaths,
            ),
          ),
    ];
    // 带图消息走多模态流的条件：桌面端引擎 + 当前对话模型自身具备视觉能力。
    // 纯文本对话模型（配合合作管线 OCR 角色）只接收 OCR 提取的文字。
    final chatModelHasVision =
        _findStoreModel(_modelId)?.hasCapability(ModelCapability.vision) ?? true;
    final hasImages = history.any((t) => t.imagePaths.isNotEmpty);
    final useMedia =
        hasImages && LlamaService.supportsMultimodal && chatModelHasVision;

    const maxRounds = 4;
    var display = ''; // 已定稿的展示文本（含工具调用摘要）
    isGenerating.value = true;
    _stopRequested = false;

    for (var round = 0; round < maxRounds; round++) {
      reply.text = display;
      messages.refresh();

      // 流式生成一轮（带图消息走多模态通道）
      final roundText = StringBuffer();
      final roundCompleter = Completer<void>();
      _roundCompleter = roundCompleter;
      final stream = useMedia
          ? LlamaService.instance.generateChatStreamWithMedia(
              history,
              template: _chatTemplate,
              temperature: settings.temperature.value,
            )
          : LlamaService.instance.generateChatStream(
              history,
              template: _chatTemplate,
              temperature: settings.temperature.value,
            );
      _subscription = stream.listen(
            (token) {
              roundText.write(token);
              reply.text = '$display${roundText.toString()}';
              messages.refresh();
            },
            onError: (Object error) {
              roundText.write('（生成失败：$error）');
              reply.text = '$display${roundText.toString()}';
              messages.refresh();
              if (!roundCompleter.isCompleted) roundCompleter.complete();
            },
            onDone: () {
              if (!roundCompleter.isCompleted) roundCompleter.complete();
            },
          );
      await roundCompleter.future;
      if (_stopRequested) break;

      final output = roundText.toString();
      final calls = ToolCallParser.parse(output);
      final jsBlocks = JsCodeBlockParser.parse(output);
      if (calls.isEmpty && jsBlocks.isEmpty) {
        // 纯文本回复：定稿收尾
        display = '$display$output';
        reply.text = display;
        messages.refresh();
        break;
      }

      // 有工具/代码调用：把 tool 与 javascript 代码块替换为可读摘要
      var summary = ToolCallParser.stripToolBlocks(output, calls);
      summary = JsCodeBlockParser.stripJsBlocks(summary, jsBlocks);
      display = '$display$summary\n';
      reply.text = display;
      messages.refresh();

      // 回喂历史：assistant 原始输出 + 工具/代码执行结果（标为 user，chatml 兼容性最好）
      history.add(LlamaTurn(role: 'assistant', content: output));
      for (final call in calls) {
        final matches = tools.where((t) => t.tool.name == call.name);
        final entry = matches.isEmpty ? null : matches.first;
        String result;
        if (entry == null || mcp == null) {
          result = '工具不存在：${call.name}';
        } else {
          try {
            final toolResult = await mcp.callTool(
              entry.server,
              call.name,
              call.arguments,
            );
            result = toolResult.text.isEmpty ? '（工具无返回）' : toolResult.text;
          } catch (e) {
            result = '工具执行失败：$e';
          }
        }
        history.add(
          LlamaTurn(
            role: 'user',
            content: '【工具 ${call.name} 执行结果】\n$result',
          ),
        );
      }

      // 执行 JS 代码块：气泡实时展示执行状态与结果，并回喂模型继续推理
      for (final block in jsBlocks) {
        // 先展示执行中状态，完成后同一行位置替换为结果，避免残留过时状态
        final preExec = display;
        display = '$preExec⏳ 正在执行 JavaScript 代码...\n';
        reply.text = display;
        messages.refresh();

        final result = await JsSandboxService.instance.execute(block.code);

        final report = StringBuffer('💻 JavaScript 执行结果');
        if (result.timedOut) report.write('（超时终止）');
        report.writeln('（${result.durationMs}ms）');
        if (result.hasOutput) report.writeln('console：\n${result.output}');
        final ret = result.returnValue;
        if (result.ok && ret != null && ret.isNotEmpty && ret != 'undefined') {
          report.writeln('返回值：$ret');
        }
        if (!result.ok) report.writeln('错误：${result.error}');
        display = '$preExec$report\n';
        reply.text = display;
        messages.refresh();

        // 回喂内容截断到 2000 字，防止超长输出挤占上下文
        final feedback = result.ok
            ? '【JavaScript 执行结果】\n'
                '${result.hasOutput ? "console 输出:\n${result.output}\n" : ""}'
                '${ret != null && ret.isNotEmpty && ret != 'undefined' ? '返回值: $ret' : '（无返回值）'}'
            : '【JavaScript 执行失败】\n${result.error}';
        history.add(
          LlamaTurn(
            role: 'user',
            content: feedback.length > 2000
                ? '${feedback.substring(0, 2000)}\n……（输出过长已截断）'
                : feedback,
          ),
        );
      }

      // 工具/代码执行期间用户可能已点停止：收尾退出，不再进入下一轮
      if (_stopRequested) break;
      // 继续循环：模型基于执行结果生成最终回答
    }

    _persistTurnIfNeeded();
    _finish();
  }

  /// 停止生成：保留已生成的部分内容（并落库，避免丢失）
  void stop() {
    _stopRequested = true;
    _subscription?.cancel();
    _subscription = null;
    // 唤醒等待中的生成循环，使其收尾退出
    final completer = _roundCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    LlamaService.instance.stop();
    _persistTurnIfNeeded();
    _finish();
  }

  /// 统一收尾：结束生成态，清理空的回复气泡
  void _finish() {
    _subscription?.cancel();
    _subscription = null;
    isGenerating.value = false;
    if (messages.isNotEmpty &&
        messages.last.role == ChatRole.assistant &&
        messages.last.text.trim().isEmpty) {
      messages.removeLast();
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _currentReply = null;
    _pendingUserText = null;
    VoiceRecorderService.instance.dispose();
    TtsPlayerService.instance.dispose();
    super.onClose();
  }
}
