import 'package:get/get.dart';

import '../data/models/ai_model.dart';
import '../services/download_service.dart';
import '../services/model_repository.dart';
import 'my_models_controller.dart';

/// 体积分档（与筛选面板一致）
enum SizeBucket {
  under1('0~1G'),
  from1to5('1~5G'),
  from5to10('5~10G'),
  from10to15('10~15G'),
  over15('>15G');

  const SizeBucket(this.label);

  final String label;

  /// 判断体积是否落入该档
  bool matches(double sizeInGB) {
    switch (this) {
      case SizeBucket.under1:
        return sizeInGB < 1;
      case SizeBucket.from1to5:
        return sizeInGB >= 1 && sizeInGB < 5;
      case SizeBucket.from5to10:
        return sizeInGB >= 5 && sizeInGB < 10;
      case SizeBucket.from10to15:
        return sizeInGB >= 10 && sizeInGB < 15;
      case SizeBucket.over15:
        return sizeInGB >= 15;
    }
  }
}

/// 商店列表排序方式
enum SortMode {
  hot('按热度'),
  size('按大小'),
  name('按名称');

  const SortMode(this.label);

  final String label;
}

/// 「模型商店」页状态：多维度筛选（数据来自 ModelRepository）
class StoreController extends GetxController {
  /// 筛选后的模型列表
  final models = <AiModel>[].obs;

  /// 当前排序方式（默认按热度 = GitHub 星数降序）
  final sortBy = SortMode.hot.obs;

  /// 下载进度：模型 id -> 0.0 ~ 1.0（key 存在即正在下载）
  final progress = <String, double>{}.obs;

  /// 筛选面板是否展开
  final panelExpanded = false.obs;

  // ---- 各维度多选状态（维度之间 AND，维度内部 OR）----
  final selectedSizes = <SizeBucket>[].obs;
  final selectedVendors = <String>[].obs;
  final selectedDomains = <String>[].obs;
  final selectedVerticals = <String>[].obs;
  final selectedLicenses = <String>[].obs;
  final selectedFormats = <ModelFormat>[].obs;

  MyModelsController get _myModels => Get.find<MyModelsController>();

  @override
  void onInit() {
    super.onInit();
    // 目录就绪后重新应用过滤（main 中已 await 加载，正常情况下立即可用）
    ever(ModelRepository.to.loaded, (_) => _applyFilter());
    _applyFilter();
  }

  // ---------- 动态维度选项（从目录生成） ----------

  List<String> get vendorOptions {
    final set = <String>{};
    for (final m in ModelRepository.to.models) {
      if (m.vendor.isNotEmpty) set.add(m.vendor);
    }
    final list = set.toList()..sort();
    return list;
  }

  static const domainOptions = <String>['文本', '多模态', '全模态', '音乐', '图像', '视频'];

  List<String> get verticalOptions {
    final set = <String>{};
    for (final m in ModelRepository.to.models) {
      if (m.vertical.isNotEmpty) set.add(m.vertical);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get licenseOptions {
    final set = <String>{};
    for (final m in ModelRepository.to.models) {
      if (m.license.isNotEmpty) set.add(m.license);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// 已激活的筛选条件总数
  int get activeFilterCount =>
      selectedSizes.length +
      selectedVendors.length +
      selectedDomains.length +
      selectedVerticals.length +
      selectedLicenses.length +
      selectedFormats.length;

  void togglePanel() => panelExpanded.value = !panelExpanded.value;

  /// 切换排序方式
  void setSortBy(SortMode mode) {
    if (sortBy.value == mode) return;
    sortBy.value = mode;
    _applyFilter();
  }

  // ---------- 多选切换 ----------

  void toggleSize(SizeBucket bucket) {
    selectedSizes.contains(bucket)
        ? selectedSizes.remove(bucket)
        : selectedSizes.add(bucket);
    _applyFilter();
  }

  void toggleVendor(String vendor) {
    selectedVendors.contains(vendor)
        ? selectedVendors.remove(vendor)
        : selectedVendors.add(vendor);
    _applyFilter();
  }

  void toggleDomain(String domain) {
    selectedDomains.contains(domain)
        ? selectedDomains.remove(domain)
        : selectedDomains.add(domain);
    _applyFilter();
  }

  void toggleVertical(String vertical) {
    selectedVerticals.contains(vertical)
        ? selectedVerticals.remove(vertical)
        : selectedVerticals.add(vertical);
    _applyFilter();
  }

  void toggleLicense(String license) {
    selectedLicenses.contains(license)
        ? selectedLicenses.remove(license)
        : selectedLicenses.add(license);
    _applyFilter();
  }

  void toggleFormat(ModelFormat format) {
    selectedFormats.contains(format)
        ? selectedFormats.remove(format)
        : selectedFormats.add(format);
    _applyFilter();
  }

  /// 清空全部筛选
  void clearFilters() {
    selectedSizes.clear();
    selectedVendors.clear();
    selectedDomains.clear();
    selectedVerticals.clear();
    selectedLicenses.clear();
    selectedFormats.clear();
    _applyFilter();
  }

  // ---------- 下载 ----------

  bool isDownloaded(String id) => _myModels.isDownloaded(id);

  bool isDownloading(String id) => progress.containsKey(id);

  double progressOf(String id) => progress[id] ?? 0;

  /// 开始真实下载（dio → .tmp → rename 原子完成）
  void startDownload(AiModel model) async {
    if (isDownloaded(model.id) || isDownloading(model.id)) return;
    final url = model.downloadUrl;
    if (url == null || url.isEmpty) {
      Get.snackbar(
        '无法下载',
        '${model.name} 暂未提供下载地址',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    progress[model.id] = 0.0;
    try {
      final ok = await DownloadService.instance.download(
        id: model.id,
        url: url,
        projectorUrl: model.projectorUrl,
        onProgress: (p) => progress[model.id] = p,
      );
      if (ok) {
        await _myModels.addModel(model);
        Get.snackbar(
          '下载完成',
          '${model.name} 已保存到本地',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        '下载失败',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      progress.remove(model.id);
    }
  }

  /// 取消下载
  void cancelDownload(String id) => DownloadService.instance.cancel(id);

  // ---------- 过滤逻辑：维度间 AND，维度内 OR ----------

  void _applyFilter() {
    final all = ModelRepository.to.models.toList()..sort(_compare);
    models.assignAll(all.where(_matchAll).toList());
  }

  int _compare(AiModel a, AiModel b) {
    switch (sortBy.value) {
      case SortMode.hot:
        return b.githubStars.compareTo(a.githubStars);
      case SortMode.size:
        return a.sizeInGB.compareTo(b.sizeInGB);
      case SortMode.name:
        return a.name.compareTo(b.name);
    }
  }

  bool _matchAll(AiModel m) {
    if (selectedSizes.isNotEmpty &&
        !selectedSizes.any((b) => b.matches(m.sizeInGB))) {
      return false;
    }
    if (selectedVendors.isNotEmpty &&
        !selectedVendors.contains(m.vendor)) {
      return false;
    }
    if (selectedDomains.isNotEmpty &&
        !selectedDomains.contains(m.domain)) {
      return false;
    }
    if (selectedVerticals.isNotEmpty &&
        !selectedVerticals.contains(m.vertical)) {
      return false;
    }
    if (selectedLicenses.isNotEmpty &&
        !selectedLicenses.contains(m.license)) {
      return false;
    }
    if (selectedFormats.isNotEmpty &&
        !selectedFormats.contains(m.format)) {
      return false;
    }
    return true;
  }
}
