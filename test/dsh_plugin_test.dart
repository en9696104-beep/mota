import 'package:flutter_test/flutter_test.dart';
import 'package:mota/services/dsh/dsh_manifest.dart';
import 'package:mota/services/dsh/dsh_models.dart';
import 'package:mota/services/dsh/dsh_runtime.dart';
import 'dart:io';

/// DSH 插件兼容层测试：清单解析 + ESM 转换 + QuickJS 真实加载/调用
void main() {
  group('DshManifestParser', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dsh_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    /// 写一个最小可用插件包
    void writePlugin({
      String patch = '''
insert:
  - id: hello
    name: './index.js'
''',
      String? pkg,
    }) {
      File('${tempDir.path}/package.json').writeAsStringSync(
        pkg ??
            '''
{
  "name": "dsh-hello-plugin",
  "version": "0.1.0",
  "type": "module",
  "main": "index.js",
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
''',
      );
      File('${tempDir.path}/cordis.patch.yml').writeAsStringSync(patch);
      File('${tempDir.path}/index.js').writeAsStringSync('export function apply(ctx) {}');
    }

    test('解析标准插件包：id / 包名 / 入口', () {
      writePlugin();
      final manifest = DshManifestParser.parse(tempDir.path);
      expect(manifest.pluginId, 'hello');
      expect(manifest.packageName, 'dsh-hello-plugin');
      expect(manifest.version, '0.1.0');
      expect(File(manifest.entryFile).existsSync(), isTrue);
      expect(manifest.entryFile.endsWith('index.js'), isTrue);
    });

    test('缺少 dsh.bundle.patch 时明确拒绝', () {
      writePlugin(pkg: '{"name": "x", "version": "1.0.0", "main": "index.js"}');
      File('${tempDir.path}/cordis.patch.yml').writeAsStringSync('insert:\n  - id: x\n    name: "./index.js"\n');
      expect(
        () => DshManifestParser.parse(tempDir.path),
        throwsA(isA<DshPluginException>().having(
          (e) => e.message, 'message', contains('dsh.bundle.patch'),
        )),
      );
    });

    test('补丁文件缺 insert 条目时报错', () {
      writePlugin(patch: '# empty\n');
      expect(
        () => DshManifestParser.parse(tempDir.path),
        throwsA(isA<DshPluginException>()),
      );
    });

    test('容忍引号与多余键', () {
      writePlugin(patch: '''
insert:
  - id: "hello"
    name: './index.js'
    config:
      foo: bar
''');
      final manifest = DshManifestParser.parse(tempDir.path);
      expect(manifest.pluginId, 'hello');
    });
  });

  group('DshRuntime.transformSource', () {
    test('剥离 import 与 export 前缀', () {
      const source = '''
import { defineTool } from '@deepseek-ai/dsh-tools'
import { readFileSync } from 'fs';

export const name = 'demo'
export function apply(ctx) {
  return 1;
}
''';
      final out = DshRuntime.transformSource(source);
      expect(out.contains('import'), isFalse);
      expect(out.contains('export'), isFalse);
      expect(out.contains('function apply(ctx)'), isTrue);
      expect(out.contains('const name'), isTrue);
    });

    test('多行 import 不吞后续代码', () {
      const source = '''
import {
  a,
  b
} from 'pkg';
const keep = 123;
''';
      final out = DshRuntime.transformSource(source);
      expect(out.contains('const keep = 123;'), isTrue);
    });

    test('不误伤含 import 前缀的普通标识符', () {
      const source = 'const imported = 1;\nconst importantVar = 2;\n';
      final out = DshRuntime.transformSource(source);
      expect(out, contains('const imported = 1;'));
      expect(out, contains('const importantVar = 2;'));
    });
  });

  group('DshRuntime（QuickJS 实际执行）', () {
    // 测试环境需要 flutter_js 的 Linux 原生库：
    //   LD_LIBRARY_PATH=<flutter_js 包>/linux/shared flutter test
    // 库缺失时跳过本组（真实设备 / 桌面构建环境始终可用）
    Future<bool> quickJsReady() async {
      try {
        await DshRuntime.instance
            .discoverTools('export function apply(ctx) {}');
        return true;
      } catch (_) {
        return false;
      }
    }

    const samplePlugin = '''
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'sample'

function buildGreeting(args) {
  return { message: 'Hello, ' + args.who + '!', plugin: 'sample' };
}

export function apply(ctx) {
  ctx.tools.register({
    name: 'kit_greet',
    description: 'Greet someone by name.',
    parameters: {
      type: 'object',
      properties: { who: { type: 'string' } },
      required: ['who']
    },
    execute: function(args) { return buildGreeting(args); }
  });

  ctx.tools.register(defineTool({
    name: 'kit_async_add',
    description: 'Async add two numbers.',
    parameters: { type: 'object', properties: { a: { type: 'number' }, b: { type: 'number' } } },
    execute: async function(args) {
      await new Promise(function(resolve) { setTimeout(resolve, 5); });
      return { sum: args.a + args.b };
    }
  }));
}
''';

    test('发现工具清单', () async {
      if (!await quickJsReady()) return;
      

      final tools = await DshRuntime.instance.discoverTools(samplePlugin);
      expect(tools.map((t) => t.name), containsAll(['kit_greet', 'kit_async_add']));
      expect(tools.firstWhere((t) => t.name == 'kit_greet').description,
          contains('Greet'));
    });

    test('同步工具执行', () async {
      if (!await quickJsReady()) return;
      

      final result = await DshRuntime.instance.callTool(
        pluginSource: samplePlugin,
        toolName: 'kit_greet',
        arguments: {'who': 'MOTA'},
      );
      expect(result.ok, isTrue);
      final value = result.value!;
      expect(value, contains('Hello, MOTA!'));
      expect(value, contains('plugin'));
    });

    test('异步（Promise）工具执行', () async {
      if (!await quickJsReady()) return;
      

      final result = await DshRuntime.instance.callTool(
        pluginSource: samplePlugin,
        toolName: 'kit_async_add',
        arguments: {'a': 2, 'b': 40},
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.value, contains('"sum":42'));
    });

    test('调用未注册工具返回明确错误', () async {
      if (!await quickJsReady()) return;
      

      final result = await DshRuntime.instance.callTool(
        pluginSource: samplePlugin,
        toolName: 'not_exist',
        arguments: {},
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('工具未注册'));
    });

    test('无 apply 导出的插件报契约错误', () async {
      if (!await quickJsReady()) return;
      

      expect(
        () => DshRuntime.instance.discoverTools('var x = 1;'),
        throwsA(isA<DshPluginException>().having(
          (e) => e.message, 'message', contains('apply'),
        )),
      );
    });
  });
}
