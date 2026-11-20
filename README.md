# MOTA

本地大模型（GGUF）应用：在设备端离线运行开源模型，并提供模型商店、API 模型接入、多模型协作与技能扩展。支持 **Android** 与 **Linux 桌面**。

> 当前版本 **v3.1.3** · 许可证 **Apache License 2.0**（SPDX: `Apache-2.0`）

## 源码仓库

- 极狐 GitLab（主仓）：**https://jihulab.com/mota-project/mota**
- GitHub（镜像）：**https://github.com/en9696104-beep/mota**

两个仓库内容同步，均为 `main` 分支、保留完整提交历史：

```bash
git clone https://jihulab.com/mota-project/mota.git
# 或
git clone https://github.com/en9696104-beep/mota.git
```

仓库根目录的 `update.json` 与 `assets/store_data.json` 为纯静态 JSON，作为「检查更新」与「商店数据」的远端数据源（多源回退、无需自建后端）。App 内置三个源、按序回退：

- `https://jihulab.com/mota-project/mota/-/raw/main/update.json` — 极狐，国内最快（主源）
- `https://cdn.jsdelivr.net/gh/en9696104-beep/mota@main/update.json` — jsDelivr CDN（海外兜底）
- `https://raw.githubusercontent.com/en9696104-beep/mota/main/update.json` — GitHub Raw（兜底）

`store_data.json` 路径相同（在以上地址末尾接 `assets/store_data.json`）。字段：`update.json` 为 `version` / `download_url` / `release_notes`，`store_data.json` 为模型元数据数组。

## 主要能力

- **本地推理**：加载 GGUF 量化模型，数据不出设备
- **模型商店**：浏览/筛选 100+ 开源模型元数据（作者、参数规模、量化、开源协议），权重由用户自行下载
- **API 模型**：导入兼容 OpenAI 格式的接口配置，可接云端或自建服务
- **多模型协作**：群聊、合作系统角色分工
- **扩展能力**：Ask 人机问答、Work 工作台、记忆、JS 脚本、MCP 客户端
- **检查更新**：多源版本配置，远端商店数据可热更新

## 构建

需要 Flutter SDK（Dart 3）。

```bash
flutter pub get
flutter build apk --release      # Android
flutter build linux --release    # Linux x64
flutter test                     # 单元测试 / Widget 测试
```

Android 产物需满足 16KB 页对齐（本项目已验证所有 ELF64 动态库兼容）。Linux 产物位于 `build/linux/x64/release/bundle/`。

## 许可证与版权

本项目采用 **Apache License 2.0**：

- 完整条款：[LICENSE](LICENSE)（与 apache.org 官方全文逐字节一致）
- 归属声明与第三方素材说明：[NOTICE](NOTICE)

> Copyright 2026 The MOTA Project Authors

选择 Apache 2.0 而不是 MIT，主要因为它对**版权与专利**的保护更完整：

| 条款 | 作用 |
|---|---|
| 第 2、3 条 | 明确授予版权与**专利许可**，附带专利诉讼终止（报复）条款 |
| 第 4 条 | 再分发必须**保留版权声明、NOTICE 与变更说明**，署名不会被抹掉 |
| 第 6 条 | **商标不授权**——第三方模型名称/标识不受本项目许可证覆盖 |
| 第 7、8 条 | 无担保与责任限制，适合分发可运行的二进制 |

**再分发时请做到**：

1. 保留 `LICENSE` 与 `NOTICE` 原文；
2. 修改过的文件注明变更；
3. 分发 APK / Linux 包等二进制时，随附 `LICENSE` 与 `NOTICE` 副本（仓库根目录提供 `*-licenses.zip` 便于随包附带）；
4. 第三方依赖、模型权重、图标与商标各自遵循其原许可证，本项目不授予其任何权利。

如需把版权人改为个人或组织名义，修改 `NOTICE` 与本文件中的版权行即可。

## 第三方

`pubspec.yaml` 列出全部 Dart/Flutter 依赖，各包许可证随包分发；模型权重与图标相关声明见 [NOTICE](NOTICE)。本项目不内置也不分发任何模型权重。
