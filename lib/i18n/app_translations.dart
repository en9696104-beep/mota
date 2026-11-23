import 'package:get/get.dart';

/// 应用翻译表。
///
/// 设计约定：**翻译 key 直接使用中文原文**。
/// - `zh_CN` 留空映射 → `.tr` 找不到条目时回退返回 key 本身（即中文），零开销；
/// - `en_US` 提供「中文原文 → English」映射，未登记的字符串同样回退中文。
/// 这样中文用户界面与升级前完全一致，英文按条目渐进覆盖。
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => <String, Map<String, String>>{
        'zh_CN': <String, String>{},
        'en_US': _en,
      };

  static const Map<String, String> _en = <String, String>{
    // ---- 底部导航 ----
    '我的模型': 'My Models',
    '模型商店': 'Model Store',
    '历史对话': 'History',
    '工作': 'Work',

    // ---- 商店页 ----
    'GGUF 格式 · 下载后完全离线运行':
        'GGUF models · Fully offline after download',
    '全部 @n 个模型': '@n models',
    '筛选出 @n 个模型': '@n models matched',
    '没有符合筛选条件的模型': 'No models match the filters',
    '商店暂无数据': 'Store data unavailable',
    '清空筛选条件': 'Clear filters',
    '按热度': 'Popular',
    '按大小': 'Size',
    '按名称': 'Name',

    // ---- 下载源选择 ----
    '选择下载源': 'Choose download source',
    '同一模型可选不同来源，HF 镜像国内访问更快':
        'Same model, different sources. HF mirror is faster in China',
    'HF 官方': 'HuggingFace',
    'HF 镜像': 'HF Mirror',
    'hf-mirror.com · 国内加速': 'hf-mirror.com · Faster in China',
    '魔搭 ModelScope': 'ModelScope',
    '手动上传': 'Import locally',
    '从本地文件导入': 'Import from a local file',
    '设为默认下载源': 'Set as default source',
    '选择文件': 'Choose file',
    '开始下载': 'Download',
    '无法下载': 'Cannot download',
    '@name 在该来源暂未提供下载地址':
        'No download URL for @name from this source',
    '下载失败': 'Download failed',
    '@name 已加入我的模型': '@name added to My Models',
    '下载完成': 'Download complete',
    '@name 已保存到本地': '@name saved locally',

    // ---- 筛选面板 ----
    '多维度筛选': 'Filters',
    '未筛选': 'Off',
    '@count 个条件': '@count active',
    '清空': 'Clear',
    '架构': 'Format',
    '大小': 'Size',
    '领域': 'Domain',
    '垂直': 'Vertical',
    '厂商': 'Vendor',
    '协议': 'License',
    '能力': 'Capabilities',

    // 领域值（来自商店数据）
    '文本': 'Text',
    '多模态': 'Multimodal',
    '全模态': 'Omni',
    '图像': 'Vision',
    '视频': 'Video',

    // 垂直值（来自商店数据）
    '通用': 'General',
    '数学': 'Math',
    '代码': 'Code',
    '医疗': 'Medical',
    '检索': 'Retrieval',
    '语音识别': 'Speech Recognition',
    '金融': 'Finance',
    '法律': 'Legal',

    // 能力值（ModelCapability.label）
    '对话': 'Chat',
    '视觉': 'Vision',
    'OCR': 'OCR',
    '语音合成': 'Speech Synthesis',
    '向量': 'Embedding',
    '重排': 'Rerank',
    '安全审核': 'Safety',
    '推理': 'Reasoning',

    // ---- 我的模型 ----
    '导入成功': 'Imported',
    '@name（@f）已加入我的模型': '@name (@f) added to My Models',
    '导入失败': 'Import failed',
    '该架构引擎正在适配中，敬请期待':
        'Inference for this format is coming soon',
    'GGUF 模型可直接对话；其他架构可正常管理文件':
        'GGUF models can chat directly; other formats are manageable files',
    '删除模型': 'Delete Model',
    '确定要删除该模型文件以释放空间吗？\n\n@name（@size）将从本机移除，如需使用需重新下载。':
        'Delete this model to free up space?\n\n@name (@size) will be removed from this device and must be re-downloaded to use again.',
    '取消': 'Cancel',
    '删除': 'Delete',
    '@params · @quant · 已就绪': '@params · @quant · Ready',
    '开始对话': 'Start Chat',
    '打开': 'Open',
    '下载': 'Download',

    // ---- 历史 ----
    '@n 条记录': '@n sessions',
    '暂无对话记录': 'No conversations yet',
    '在「我的模型」中开始一次对话，记录会出现在这里':
        'Start a chat from My Models and it will show up here',

    // ---- 设置页 ----
    '设置': 'Settings',
    '关于': 'About',
    '当前版本': 'Version',
    '检查更新': 'Check for Updates',
    '从远端版本配置检查是否有新版本': 'Check the remote config for new releases',
    '检查更新失败': 'Update check failed',
    '网络异常或更新配置无效，请稍后重试':
        'Network error or invalid update config. Try again later.',
    '已是最新版本': 'Already up to date',
    '当前版本 v@v': 'Current version v@v',
    '发现新版本 v@v': 'New version v@v available',
    '更新内容': "What's new",
    '（未提供更新说明）': '(No release notes)',
    '暂不更新': 'Later',
    '立即更新': 'Update Now',
    '打开失败': 'Could not open',
    '下载地址无效': 'Invalid download URL',
    '未找到可处理该链接的应用': 'No app can handle this link',
    '语言': 'Language',
    '跟随系统': 'Follow System',
    '中文': 'Chinese',
    'English': 'English',
    '选择界面语言': 'Choose the interface language',
    '界面语言跟随系统设置（当前：@l）': 'Interface follows system (current: @l)',
    'JS 脚本': 'JS Scripts',
    '脚本管理': 'Script Manager',
    '在 QuickJS 沙箱中编写并运行 JavaScript':
        'Write & run JavaScript in a QuickJS sandbox',
    '模型在对话中输出 javascript 代码块时会自动在沙箱中执行，结果反馈给模型继续推理；也可以在这里手动管理脚本。沙箱限制：5 秒超时、64MB 内存，无网络与文件访问。':
        'JavaScript code blocks produced by models run automatically in the sandbox and results feed back into the conversation; scripts can also be managed here. Sandbox limits: 5s timeout, 64MB memory, no network or file access.',
    '商店数据': 'Store Data',
    '数据来源': 'Data Source',
    '模型数量': 'Models',
    '@n 个': '@n',
    '商店数据启动时自动从远端同步，失败时使用本地缓存，断网时使用 App 内置数据，全程无需手动操作。':
        'Store data syncs from the remote source at startup; falls back to local cache on failure and to bundled data offline. Fully automatic.',
    '本地 API 服务': 'Local API Server',
    '开启本地 API': 'Enable Local API',
    'OpenAI 兼容接口，需先在 App 内加载模型':
        'OpenAI-compatible endpoint; load a model in-app first',
    '允许局域网访问': 'Allow LAN Access',
    '同一 Wi-Fi 下的设备可直接调用本机 API':
        'Devices on the same Wi-Fi can call this API directly',
    '局域网地址 · @p 端口': 'LAN address · port @p',
    '仅本机访问 · @p 端口': 'Localhost only · port @p',
    'MCP 服务器端点 · 供 Claude Desktop 等 MCP 客户端连接':
        'MCP server endpoint · for Claude Desktop and other MCP clients',
    '开启后，第三方工具（Cherry Studio、LobeChat 等）将 Base URL 设为上述地址、模型任选即可调用本机算力；Claude Desktop 等 MCP 客户端可连接 /mcp 端点使用 MOTA 工具。':
        'Point third-party tools (Cherry Studio, LobeChat, etc.) at the Base URL above and pick any model to use local compute; MCP clients such as Claude Desktop can connect to /mcp to use MOTA tools.',
    '已复制': 'Copied',
    'MCP 客户端': 'MCP Client',
    '@n 个工具可用': '@n tools available',
    '尚未连接任何 MCP 服务器\n连接后，本地模型即可调用外部工具':
        'No MCP server connected yet\nConnect one to give local models external tools',
    '添加服务器': 'Add Server',
    '添加 MCP 服务器': 'Add MCP Server',
    '输入 MCP 服务器的 Streamable HTTP 端点地址':
        'Enter the Streamable HTTP endpoint of the MCP server',
    '连接': 'Connect',
    '连接成功': 'Connected',
    '发现 @n 个工具': 'Found @n tools',
    '连接失败': 'Connection failed',
    '请检查地址与网络': 'Check the URL and network',
    '@n 个工具': '@n tools',
    '未连接': 'Not connected',
    '重新连接': 'Reconnect',
    '移除': 'Remove',
    '复制地址': 'Copy URL',
    '启动失败': 'Start failed',

    // ---- Work 工作台 ----
    '工作台': 'Workbench',
    '添加设备': 'Add Device',
    '设备网格': 'Devices',
    '本机 · @p · 被控节点': 'This device · @p · controlled node',
    '他人请求本机时的权限档位': 'Permission tier granted to remote requests',
    '@t（授权引导见设备详情）': '@t (grant guide in device details)',
    '本机配对码': 'Pairing Code',
    '刷新配对码（旧码立即作废）': 'Refresh code (invalidates the old one)',
    '对方在 MOTA 工作台添加设备时，输入此配对码即可配对本机':
        'Enter this code when adding this device from another MOTA workbench',
    '本地 API 服务未开启：被控端点不可用。请到 设置 → 本地 API 服务 开启（建议同时允许局域网访问）':
        'Local API is off: the controlled endpoint is unavailable. Enable it in Settings → Local API Server (LAN access recommended).',
    '添加': 'Add',
    '还没有配对任何设备': 'No paired devices yet',
    '在另一台设备的 MOTA 中开启工作台，\n输入其 IP 与端口即可发起配对':
        'Open the workbench on another MOTA device,\nthen pair using its IP and port',
    '未知档位': 'Unknown tier',
    '发起调度': 'Dispatch Task',
    '解绑设备': 'Unpair Device',
    '申请对端权限档位': 'Request peer tier',
    '输入对端 MOTA 的地址（对端需开启局域网访问）':
        "Enter the peer MOTA address (peer must allow LAN access)",
    '备注名': 'Alias',
    '如：书房 PC': 'e.g. Study PC',
    '端点地址': 'Endpoint',
    '平台': 'Platform',
    '发起配对': 'Pair',
    '请在对端设备的 MOTA → 工作台中查看本机配对码（6 位数字）并输入：':
        "Enter the 6-digit pairing code shown on the peer's MOTA workbench:",
  };
}
