import 'package:flutter_test/flutter_test.dart';
import 'package:mota/data/models/ai_model.dart';
import 'package:mota/data/models/download_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载源派生规则 + 默认源偏好 契约测试
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hfUrl =
      'https://hf-mirror.com/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q8_0.gguf';
  const hfProj =
      'https://hf-mirror.com/ggml-org/gemma-3-4b-it-GGUF/resolve/main/mmproj-model-f16.gguf';
  const msUrl =
      'https://modelscope.cn/models/TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF/resolve/master/mixtral-8x7b-instruct-v0.1.Q4_K_M.gguf';

  AiModel hfModel() => const AiModel(
        id: 'hf-1',
        name: 'Gemma3-1B',
        author: 'Google',
        params: '1B',
        sizeInGB: 1.0,
        quant: 'Q8_0',
        tags: [],
        colorIndex: 0,
        vendor: 'Google',
        domain: '文本',
        vertical: '通用',
        license: '',
        githubStars: 0,
        downloadUrl: hfUrl,
        projectorUrl: hfProj,
      );

  AiModel msModel() => const AiModel(
        id: 'ms-1',
        name: 'Mixtral',
        author: 'TheBloke',
        params: '8x7B',
        sizeInGB: 25,
        quant: 'Q4_K_M',
        tags: [],
        colorIndex: 0,
        vendor: 'Mistral',
        domain: '文本',
        vertical: '通用',
        license: '',
        githubStars: 0,
        downloadUrl: msUrl,
      );

  group('可用源列表', () {
    test('HF 模型暴露 官方+镜像+手动上传，不含魔搭', () {
      final sources = hfModel().availableSources;
      expect(sources, contains(DownloadSource.hfOfficial));
      expect(sources, contains(DownloadSource.hfMirror));
      expect(sources, contains(DownloadSource.localImport));
      expect(sources, isNot(contains(DownloadSource.modelScope)));
    });

    test('魔搭模型暴露 魔搭+手动上传，不含 HF', () {
      final sources = msModel().availableSources;
      expect(sources, contains(DownloadSource.modelScope));
      expect(sources, contains(DownloadSource.localImport));
      expect(sources, isNot(contains(DownloadSource.hfOfficial)));
      expect(sources, isNot(contains(DownloadSource.hfMirror)));
    });

    test('无下载地址时仅暴露手动上传', () {
      const model = AiModel(
        id: 'x',
        name: 'X',
        author: '',
        params: '',
        sizeInGB: 0,
        quant: '',
        tags: [],
        colorIndex: 0,
        vendor: '',
        domain: '',
        vertical: '',
        license: '',
        githubStars: 0,
      );
      expect(model.availableSources, <DownloadSource>[DownloadSource.localImport]);
    });
  });

  group('URL 派生', () {
    test('hfOfficial 换 host 为 huggingface.co，路径保持不变', () {
      final url = hfModel().urlFor(DownloadSource.hfOfficial)!;
      expect(Uri.parse(url).host, 'huggingface.co');
      expect(Uri.parse(url).path, Uri.parse(hfUrl).path);
    });

    test('hfMirror 保持 hf-mirror.com', () {
      final url = hfModel().urlFor(DownloadSource.hfMirror)!;
      expect(Uri.parse(url).host, 'hf-mirror.com');
      expect(Uri.parse(url).path, Uri.parse(hfUrl).path);
    });

    test('魔搭源原样返回', () {
      expect(msModel().urlFor(DownloadSource.modelScope), msUrl);
    });

    test('投影器 host 随主源同步切换', () {
      expect(
        Uri.parse(hfModel().projectorUrlFor(DownloadSource.hfOfficial)!).host,
        'huggingface.co',
      );
      expect(
        Uri.parse(hfModel().projectorUrlFor(DownloadSource.hfMirror)!).host,
        'hf-mirror.com',
      );
    });

    test('手动上传无 URL；不适用源返回 null', () {
      expect(hfModel().urlFor(DownloadSource.localImport), isNull);
      expect(hfModel().projectorUrlFor(DownloadSource.localImport), isNull);
      expect(hfModel().urlFor(DownloadSource.modelScope), isNull);
      expect(msModel().urlFor(DownloadSource.hfOfficial), isNull);
    });

    test('Uri 替换不误伤 path 中含 hf-mirror 字样', () {
      const tricky =
          'https://hf-mirror.com/org/path-hf-mirror-demo/resolve/main/hf-mirror.gguf?x=hf-mirror';
      final url = resolveUrl(tricky, DownloadSource.hfOfficial)!;
      final uri = Uri.parse(url);
      expect(uri.host, 'huggingface.co');
      expect(uri.path, Uri.parse(tricky).path);
      expect(uri.query, Uri.parse(tricky).query);
    });
  });

  group('默认源偏好', () {
    test('保存后读取往返；手动上传不作为默认', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadDefaultSource(), isNull);

      await saveDefaultSource(DownloadSource.hfMirror);
      expect(await loadDefaultSource(), DownloadSource.hfMirror);

      await saveDefaultSource(DownloadSource.localImport);
      // localImport 不应写入，仍是上次的 hfMirror
      expect(await loadDefaultSource(), DownloadSource.hfMirror);
    });
  });
}
