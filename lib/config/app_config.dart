/// 应用级配置常量
///
/// 远端「假服务器」使用 GitHub Raw 公开链接，无需自建后端。
/// 以下两个 URL 为**占位符**，替换为你自己的 GitHub 仓库 Raw 链接即可：
///
/// 1. [storeDataUrl] 指向的 JSON 需与 assets/store_data.json 同构（模型列表数组）
/// 2. [updateUrl] 指向的 JSON 需包含字段：version / download_url / release_notes
class AppConfig {
  AppConfig._();

  /// 远端商店数据（模型列表 JSON）
  ///
  /// 占位符：https://raw.githubusercontent.com/<你的用户名>/<仓库名>/<分支>/store_data.json
  static const String storeDataUrl =
      'https://raw.githubusercontent.com/OWNER/mota-config/main/store_data.json';

  /// 远端版本信息（version / download_url / release_notes）
  ///
  /// 占位符：https://raw.githubusercontent.com/<你的用户名>/<仓库名>/<分支>/update.json
  static const String updateUrl =
      'https://raw.githubusercontent.com/OWNER/mota-config/main/update.json';

  /// 当前版本号（与 pubspec.yaml 的 version 保持同步）
  static const String currentVersion = '1.0.0';

  /// 远端商店数据本地缓存键（shared_preferences）
  static const String storeDataCacheKey = 'store_data_remote_v1';

  /// 启动时拉取远端商店数据的超时（失败则无缝走本地兜底，不阻塞启动）
  static const Duration storeFetchTimeout = Duration(seconds: 10);

  /// 检查更新的网络超时
  static const Duration updateCheckTimeout = Duration(seconds: 10);
}
