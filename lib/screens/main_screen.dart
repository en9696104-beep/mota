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
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.memory_outlined),
              activeIcon: Icon(Icons.memory),
              label: '我的模型',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              activeIcon: Icon(Icons.storefront),
              label: '模型商店',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: '历史对话',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_outlined),
              activeIcon: Icon(Icons.hub),
              label: 'Work',
            ),
          ],
        ),
      ),
    );
  }
}
