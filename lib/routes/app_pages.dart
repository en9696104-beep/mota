import 'package:get/get.dart';

import '../controllers/chat_controller.dart';
import '../controllers/history_controller.dart';
import '../controllers/main_controller.dart';
import '../controllers/mcp_controller.dart';
import '../controllers/my_models_controller.dart';
import '../controllers/scripts_controller.dart';
import '../controllers/store_controller.dart';
import '../screens/chat_page.dart';
import '../screens/dsh_plugins_page.dart';
import '../screens/main_screen.dart';
import '../screens/memory_page.dart';
import '../screens/script_editor_page.dart';
import '../screens/scripts_page.dart';
import '../screens/settings_page.dart';
import 'app_routes.dart';

/// JS 脚本页公共依赖
class ScriptsBinding implements Bindings {
  const ScriptsBinding();

  @override
  void dependencies() {
    Get.lazyPut<ScriptsController>(() => ScriptsController());
  }
}

/// 主页面三个 Tab 的公共依赖
class MainBinding implements Bindings {
  const MainBinding();

  @override
  void dependencies() {
    Get.lazyPut<MainController>(() => MainController());
    Get.lazyPut<MyModelsController>(() => MyModelsController());
    Get.lazyPut<StoreController>(() => StoreController());
    Get.lazyPut<HistoryController>(() => HistoryController());
    Get.lazyPut<McpController>(() => McpController());
  }
}

/// 全局路由表
class AppPages {
  AppPages._();

  static final List<GetPage> pages = <GetPage>[
    GetPage(
      name: AppRoutes.main,
      page: () => const MainScreen(),
      binding: const MainBinding(),
    ),
    GetPage(
      name: AppRoutes.chat,
      page: () => const ChatPage(),
      binding: BindingsBuilder(() {
        Get.lazyPut<ChatController>(() => ChatController());
      }),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
    GetPage(
      name: AppRoutes.settings,
      page: () => const SettingsPage(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
    GetPage(
      name: AppRoutes.scripts,
      page: () => const ScriptsPage(),
      binding: const ScriptsBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
    GetPage(
      name: AppRoutes.scriptEditor,
      page: () => const ScriptEditorPage(),
      binding: const ScriptsBinding(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
    GetPage(
      name: AppRoutes.memory,
      page: () => const MemoryPage(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
    GetPage(
      name: AppRoutes.dshPlugins,
      page: () => const DshPluginsPage(),
      transition: Transition.rightToLeft,
      transitionDuration: const Duration(milliseconds: 220),
    ),
  ];
}
