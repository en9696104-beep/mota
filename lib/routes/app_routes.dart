/// 路由路径集中管理
abstract class AppRoutes {
  /// 根页面（底部导航容器）
  static const String main = '/main';

  /// 以下三个为 Tab 内页面，预留直达路由（可选跳转）
  static const String myModels = '/my-models';
  static const String store = '/store';
  static const String history = '/history';

  /// 对话页
  static const String chat = '/chat';

  /// 设置页（检查更新 / 商店数据来源）
  static const String settings = '/settings';

  /// JS 脚本列表页 / 编辑运行页
  static const String scripts = '/scripts';
  static const String scriptEditor = '/scripts/editor';
}
