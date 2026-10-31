import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/main_controller.dart';
import '../work/screens/work_page.dart';
import 'history_page.dart';
import 'my_models_page.dart';
import 'store_page.dart';

/// 根页面：底部导航栏 + 四个 Tab
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  static const List<Widget> _pages = <Widget>[
    MyModelsPage(),
    StorePage(),
    HistoryPage(),
    WorkPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MainController>();
    return Scaffold(
      // IndexedStack 保持各 Tab 页面状态
      body: Obx(
        () => IndexedStack(
          index: controller.tabIndex.value,
          children: _pages,
        ),
      ),
      bottomNavigationBar: Obx(
        () => BottomNavigationBar(
          currentIndex: controller.tabIndex.value,
          onTap: controller.changeTab,
          // 4 个 Tab 默认 shifting 会隐藏未选中标签，固定为 fixed
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11.5,
          unselectedFontSize: 11,
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: const Icon(Icons.memory_outlined),
              activeIcon: const Icon(Icons.memory),
              label: '我的模型'.tr,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.storefront_outlined),
              activeIcon: const Icon(Icons.storefront),
              label: '模型商店'.tr,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.chat_bubble_outline),
              activeIcon: const Icon(Icons.chat_bubble),
              label: '历史对话'.tr,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.hub_outlined),
              activeIcon: const Icon(Icons.hub),
              label: '工作'.tr,
            ),
          ],
        ),
      ),
    );
  }
}
