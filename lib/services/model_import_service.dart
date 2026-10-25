import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import '../controllers/my_models_controller.dart';
import '../data/models/ai_model.dart';
import '../services/storage_service.dart';
import '../widgets/import_format_sheet.dart';

/// 自定义模型导入服务
/// - 系统文件选择器（限定 .gguf / .mnn / .litertlm / .mlmodel）
/// - 复制到应用私有目录 <documents>/models/imported_<ts>.<ext>
///   （file_picker 返回的缓存路径随时可能被系统清理，必须落到自己的目录）
/// - 架构选择面板 → 写入本地已下载列表
class ModelImportService {
  ModelImportService._();
  static final ModelImportService instance = ModelImportService._();

  /// 允许的文件后缀（小写）
  static const List<String> allowedExtensions = <String>[
    'gguf',
    'mnn',
    'litertlm',
    'mlmodel',
  ];

  /// 选择并导入一个本地模型。取消返回 null；失败抛异常由调用方提示。
  Future<AiModel?> pickAndImport() async {
    // 1. 系统文件选择器
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final sourcePath = picked.path;
    if (sourcePath == null) {
      throw Exception('无法读取所选文件，请重新选择');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('文件不存在或已被移动，请重新选择');
    }

    // 2. 复制到应用私有目录（系统清理缓存后文件依然在）
    final sizeInBytes = await source.length();
    if (sizeInBytes == 0) throw Exception('文件为空，无法导入');

    final ext = _extensionOf(sourcePath);
    final modelsDir = await StorageService.to.modelsDir();
    final importedId = 'imported_${DateTime.now().millisecondsSinceEpoch}';
    final targetPath = '${modelsDir.path}/$importedId$ext';
    await source.copy(targetPath);

    // 3. 架构选择面板（默认按后缀预推断）
    final sizeLabel = _formatSize(sizeInBytes);
    final choice = await ImportFormatSheet.show(
      fileName: picked.name,
      sizeLabel: sizeLabel,
      defaultFormat: ModelFormat.fromExtension(ext),
    );
    if (choice == null) {
      // 用户取消：清理已复制的文件，避免残留垃圾
      final target = File(targetPath);
      if (await target.exists()) await target.delete();
      return null;
    }

    // 4. 构造模型记录并写入本地已下载列表
    final model = AiModel(
      id: importedId,
      name: choice['name'] as String,
      author: '本地导入',
      params: '自定义',
      sizeInGB: sizeInBytes / (1024 * 1024 * 1024),
      quant: '本地文件',
      tags: const ['本地导入'],
      colorIndex: DateTime.now().millisecondsSinceEpoch % 6,
      vendor: '本地导入',
      domain: '文本',
      vertical: '通用',
      license: '',
      githubStars: 0,
      description: '从本地文件导入的模型（$sizeLabel）',
      format: choice['format'] as ModelFormat,
    );

    await Get.find<MyModelsController>().addImportedModel(model, targetPath);
    return model;
  }

  /// 字节数 → 可读体积文案
  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  /// 取文件后缀（含点，小写），无后缀返回空串
  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf(Platform.pathSeparator);
    if (dot <= 0 || dot < slash) return '';
    return path.substring(dot).toLowerCase();
  }
}
