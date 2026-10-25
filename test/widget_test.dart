// 冒烟测试：模型架构枚举的扩展名解析（多架构支持的底层契约）
//
// 注意：不在此做整 App pumpWidget 冒烟——main() 会执行
// StorageService / ModelRepository / sqflite 等原生初始化，
// 需要平台通道环境；单元级契约测试见 test/ 下其他文件。

import 'package:flutter_test/flutter_test.dart';
import 'package:mota/data/models/ai_model.dart';

void main() {
  group('ModelFormat.fromExtension', () {
    test('四类受支持扩展名映射到对应架构', () {
      expect(ModelFormat.fromExtension('.mnn'), ModelFormat.mnn);
      expect(ModelFormat.fromExtension('.litertlm'), ModelFormat.litert);
      expect(ModelFormat.fromExtension('.mlmodel'), ModelFormat.apple);
      expect(ModelFormat.fromExtension('.gguf'), ModelFormat.gguf);
    });

    test('别名扩展名同样识别', () {
      expect(ModelFormat.fromExtension('.tflite'), ModelFormat.litert);
      expect(ModelFormat.fromExtension('.mlpackage'), ModelFormat.apple);
    });

    test('大小写不敏感，未知扩展名回退 GGUF', () {
      expect(ModelFormat.fromExtension('.MNN'), ModelFormat.mnn);
      expect(ModelFormat.fromExtension('.bin'), ModelFormat.gguf);
      expect(ModelFormat.fromExtension(''), ModelFormat.gguf);
    });
  });

  group('AiModel format 字段', () {
    test('fromJson 按 name / label 双匹配解析', () {
      final byName =
          AiModel.fromJson({'id': 'x', 'name': 'x', 'format': 'litert'});
      expect(byName.format, ModelFormat.litert);

      // 展示标签值同样兼容（如商店数据写 "LiteRT"）
      final byLabel =
          AiModel.fromJson({'id': 'y', 'name': 'y', 'format': 'LiteRT'});
      expect(byLabel.format, ModelFormat.litert);
    });

    test('format 缺省或非法时回退 GGUF（默认架构）', () {
      final missing = AiModel.fromJson({'id': 'z', 'name': 'z'});
      expect(missing.format, ModelFormat.gguf);

      final invalid =
          AiModel.fromJson({'id': 'w', 'name': 'w', 'format': 'onnx'});
      expect(invalid.format, ModelFormat.gguf);
    });
  });
}
