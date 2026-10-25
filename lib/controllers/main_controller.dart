import 'package:get/get.dart';

/// 底部导航 Tab 状态
class MainController extends GetxController {
  /// 当前 Tab 索引：0 我的模型 / 1 模型商店 / 2 历史对话 / 3 Work 工作台
  final tabIndex = 0.obs;

  void changeTab(int index) => tabIndex.value = index;
}
