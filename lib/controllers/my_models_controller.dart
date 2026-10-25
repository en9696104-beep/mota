import 'package:get/get.dart';

import '../data/models/ai_model.dart';
import '../services/download_service.dart';
import '../services/llama_service.dart';
import '../services/model_repository.dart';
import '../services/storage_service.dart';

/// 「我的模型」页状态：本地存储（shared_preferences）驱动
/// 数据来源两部分：
/// 1. 商店下载的模型（ModelRepository 解析 id → AiModel）
/// 2. 自定义导入的本地模型（StorageService.importedModels 元数据）
class MyModelsController extends GetxController {
  /// 已下载到本地的模型
  final models = <AiModel>[].obs;

  @override
  void onInit() {
    super.onInit();
    refreshFromStorage();
  }

  /// 从本地存储读取已下载模型列表（商店下载 + 自定义导入合并）
  Future<void> refreshFromStorage() async {
    final ids = StorageService.to.downloadedIds;
    final list = <AiModel>[];
    for (final id in ids) {
      // 优先从商店目录解析（携带完整元数据）
      final model = ModelRepository.to.byId(id);
      if (model != null) {
        list.add(model);
        continue;
      }
      // 商店目录中没有：按自定义导入模型还原
      final imported = StorageService.to.importedModels
          .where((m) => m['id'] == id)
          .firstOrNull;
      if (imported != null) {
        list.add(AiModel.fromJson(imported));
      }
    }
    models.assignAll(list);
  }

  /// 查询某个模型的本地 GGUF 路径，未下载返回 null
  String? pathFor(String id) => StorageService.to.pathFor(id);

  bool isDownloaded(String id) => models.any((m) => m.id == id);

  /// 下载完成后回调
  Future<void> addModel(AiModel model) async {
    if (isDownloaded(model.id)) return;
    models.add(model);
  }

  /// 记录一个自定义导入的模型（写入元数据 + 已下载列表，刷新 UI）
  Future<void> addImportedModel(AiModel model, String path) async {
    if (isDownloaded(model.id)) return;
    await StorageService.to.markDownloaded(model.id, path);
    await StorageService.to.saveImportedModel(model.toJson());
    models.add(model);
    models.refresh();
  }

  /// 删除本地模型：先物理删除文件与下载记录，成功后再刷新 UI；
  /// 任一步失败则保持原状并提示（避免出现"UI 已消失但文件还在"的不一致）
  Future<void> removeModel(String id) async {
    final model = models.firstWhereOrNull((m) => m.id == id);
    try {
      // 若该模型正被聊天页加载，先释放 llama.cpp 引擎（否则占用文件句柄）
      final path = StorageService.to.pathFor(id);
      if (path != null && LlamaService.instance.loadedPath == path) {
        await LlamaService.instance.dispose();
      }
      // File(path).delete() 物理删除模型文件 + 从已下载列表移除记录
      await DownloadService.instance.delete(id);
      // 自定义导入模型还需清理元数据（商店模型无需）
      await StorageService.to.removeImportedModel(id);
    } catch (e) {
      Get.snackbar(
        '删除失败',
        '文件可能被占用，请关闭对话页后重试',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    models.removeWhere((m) => m.id == id);
    Get.snackbar(
      '已删除',
      '${model?.name ?? '模型'} 已从本地移除，存储空间已释放',
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}
