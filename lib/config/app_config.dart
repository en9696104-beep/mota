/// 应用级配置常量
///
/// 远端「假服务器」：多源回退（极狐 GitLab → jsDelivr CDN → GitHub Raw），
/// 全部为静态 JSON，无需自建后端。三个源指向同一个公开仓库的 main 分支，
/// 任一源可达即可拿到数据；国内以极狐最快，海外/极端情况走 CDN 兜底。
///
/// 1. store_data.json：与 assets/store_data.json 同构（模型列表数组）
/// 2. update.json：包含字段 version / download_url / release_notes
class AppConfig {
  AppConfig._();

  /// 远端商店数据源（按序回退：极狐国内直连最快，CDN / GitHub 兜底）
  static const List<String> storeDataUrls = <String>[
    'https://jihulab.com/mota-project/mota/-/raw/main/assets/store_data.json',
    'https://cdn.jsdelivr.net/gh/en9696104-beep/mota@main/assets/store_data.json',
    'https://raw.githubusercontent.com/en9696104-beep/mota/main/assets/store_data.json',
  ];

  /// 远端版本信息源（version / download_url / release_notes）
  static const List<String> updateUrls = <String>[
    'https://jihulab.com/mota-project/mota/-/raw/main/update.json',
    'https://cdn.jsdelivr.net/gh/en9696104-beep/mota@main/update.json',
    'https://raw.githubusercontent.com/en9696104-beep/mota/main/update.json',
  ];

  /// 远端源是否已配置（已替换为真实仓库地址即为 true）
  static bool get remoteConfigured => !updateUrls.first.contains('<OWNER>');

  /// 当前版本号（与 pubspec.yaml 的 version 保持同步）
  static const String currentVersion = '3.1.3';

  /// 远端商店数据本地缓存键（shared_preferences）
  static const String storeDataCacheKey = 'store_data_remote_v1';

  /// 启动时拉取远端商店数据的单源超时（失败无缝切下一源 / 本地兜底）
  static const Duration storeFetchTimeout = Duration(seconds: 8);

  /// 检查更新的单源网络超时
  static const Duration updateCheckTimeout = Duration(seconds: 8);
}
