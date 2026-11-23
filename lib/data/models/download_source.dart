import 'package:shared_preferences/shared_preferences.dart';

/// 模型下载源。
///
/// HF 官方与 HF 镜像是两个独立选项：两者 URL 路径完全一致，仅 host 不同
/// （`huggingface.co` ↔ `hf-mirror.com`），可安全互换实现国内加速。
/// 魔搭（modelscope.cn）路径结构不同（`/models/.../resolve/master/`），
/// 无法与 HF 互相反推，因此只暴露同族源，避免拼出 404 链接。
enum DownloadSource {
  hfOfficial('HF 官方', 'huggingface.co'),
  hfMirror('HF 镜像', 'hf-mirror.com · 国内加速'),
  modelScope('魔搭 ModelScope', 'modelscope.cn'),
  localImport('手动上传', '从本地文件导入');

  const DownloadSource(this.label, this.hint);

  /// 展示名称（中文原文即 i18n key）
  final String label;

  /// 副标题提示
  final String hint;

  /// 是否为需要联网下载的远程源（手动上传除外）
  bool get isRemote => this != DownloadSource.localImport;

  static DownloadSource? fromName(String? name) {
    if (name == null) return null;
    for (final s in DownloadSource.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// 已知 host 常量
const String _hfOfficialHost = 'huggingface.co';
const String _hfMirrorHost = 'hf-mirror.com';
const String _modelScopeHost = 'modelscope.cn';

/// URL 所属源族
enum _UrlFamily { huggingFace, modelScope, unknown }

_UrlFamily _familyOf(String? url) {
  if (url == null || url.isEmpty) return _UrlFamily.unknown;
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return _UrlFamily.unknown;
  if (host == _hfMirrorHost ||
      host == _hfOfficialHost ||
      host.endsWith('.$_hfOfficialHost') ||
      host.endsWith('.$_hfMirrorHost')) {
    return _UrlFamily.huggingFace;
  }
  if (host == _modelScopeHost || host.endsWith('.$_modelScopeHost')) {
    return _UrlFamily.modelScope;
  }
  return _UrlFamily.unknown;
}

/// 给定主下载 URL，返回该模型可用的下载源列表。
///
/// - HF 族：官方 / 镜像 / 手动上传
/// - 魔搭族：魔搭 / 手动上传
/// - 无 URL 或未知域：仅手动上传
/// 始终包含 [DownloadSource.localImport]，保证用户总有退路。
List<DownloadSource> availableSourcesFor(String? url) {
  switch (_familyOf(url)) {
    case _UrlFamily.huggingFace:
      return const <DownloadSource>[
        DownloadSource.hfOfficial,
        DownloadSource.hfMirror,
        DownloadSource.localImport,
      ];
    case _UrlFamily.modelScope:
      return const <DownloadSource>[
        DownloadSource.modelScope,
        DownloadSource.localImport,
      ];
    case _UrlFamily.unknown:
      return const <DownloadSource>[DownloadSource.localImport];
  }
}

/// 将 [url] 解析为指定源 [source] 的实际下载地址。
///
/// - 同族 URL 用 [Uri.replace] 仅替换 host，保留 path/query/fragment
/// - `localImport` 或不适用（如 HF 源用于魔搭模型）返回 null
String? resolveUrl(String? url, DownloadSource source) {
  if (source == DownloadSource.localImport) return null;
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final family = _familyOf(url);
  switch (source) {
    case DownloadSource.hfOfficial:
      if (family != _UrlFamily.huggingFace) return null;
      return uri.replace(host: _hfOfficialHost).toString();
    case DownloadSource.hfMirror:
      if (family != _UrlFamily.huggingFace) return null;
      return uri.replace(host: _hfMirrorHost).toString();
    case DownloadSource.modelScope:
      // 魔搭 URL 原样返回（其 host 可能带 www 等子域，保留原样最安全）
      if (family != _UrlFamily.modelScope) return null;
      return url;
    case DownloadSource.localImport:
      return null;
  }
}

/// 默认下载源偏好键
const String defaultDownloadSourceKey = 'default_download_source_v1';

/// 读取用户保存的默认下载源；无偏好或值非法返回 null
Future<DownloadSource?> loadDefaultSource() async {
  final prefs = await SharedPreferences.getInstance();
  return DownloadSource.fromName(prefs.getString(defaultDownloadSourceKey));
}

/// 保存默认下载源（仅远程源，手动上传不作为默认）
Future<void> saveDefaultSource(DownloadSource source) async {
  if (!source.isRemote) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(defaultDownloadSourceKey, source.name);
}
