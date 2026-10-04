# Scapare 1.1.6（11）审核提交记录

本次发布包含连续滚动衔接、固定顶栏/侧栏，以及窗口和侧栏圆角重复修复。用户在本机验证固定侧边栏、固定顶边栏两个场景正常后，明确要求同步 GitHub 和 App Store。

## 提交结果

- 2026-10-04 14:10（Asia/Shanghai）正式提交审核。App Store Connect 详情页确认 macOS 1.1.6、构建 1.1.6（11）的状态为「等待审核」。审核通过后自动发布；尚不代表获批或已上架。
- 新提交 ID：`3ed12062-7249-4b45-8693-3512f0a30533`。
- 构建 ID：`a5d3480d-a9b4-458c-ac1f-8820a9e9aaca`；页面上传时间为 2026-10-04 14:02。
- App ID：`6777382263`；Bundle ID 保留 `com.gaoyiming.SnapTool`。
- 已撤回旧待审提交 `8ad77892-3100-490f-be79-2fabc466d4b9`，将版本从 1.1.3 改为 1.1.6，替换构建 8 为 11，保存并提交。
- 沿用 Scapare 名称、纯白底长卷图标、现有商店描述、截屏、隐私信息及自动发布设置。审核备注补充固定边栏、圆角去重、连续滚动和回滚恢复说明。
- 审核进度：[App Store Connect](https://appstoreconnect.apple.com/apps/6777382263/distribution/reviewsubmissions/details/3ed12062-7249-4b45-8693-3512f0a30533)。

## 源码与验证

- 构建源码提交：[`d792449dc2ac97dfdb91f0d4149ccd6b43692fa9`](https://github.com/Alex-cloud0413/scapre/commit/d792449dc2ac97dfdb91f0d4149ccd6b43692fa9)，已同步 GitHub `main` 与 `codex/scroll-rounded-edges`。
- 233 项完整回归检查通过；使用附件真实边缘和可控正文的 12 项重放检查通过。用户另行完成固定侧边栏、固定顶边栏实机验证。重放检查不等同于原网页视频回放，也不宣称覆盖所有网页。
- App Store 归档、上传及分发包导出成功；归档签名验证通过，包含 Apple silicon 和 Intel 架构。
- 分发摘要确认 Apple Distribution 签名、App Sandbox 保留，未包含 `get-task-allow` 调试权限。
- 分发包 SHA-256：`8ca836db53b1d22bed671cfa0c2b250a0c1231cb11936184016085577f4f7fa7`。

## 本地恢复材料

归档、分发包、导出设置、上传日志、审核备注、发布凭据及发布后 Git bundle 保存在 `Scapare-Backups/AppStore/1.1.6-build11/`。账号联系信息不提交公开仓库。

## 本次新增审核备注

Version 1.1.6 (build 11) replaces the previously submitted 1.1.3 (build 8). It improves continuous scrolling capture with fixed headers and sidebars, prevents repeated window and sidebar corners in long screenshots, and preserves completed content when scrolling back. Scrolling capture consumes continuous screen frames and does not require the user to pause after each scroll. If no reliably identifiable overlap remains, it preserves the existing result and asks the user to scroll back to restore overlap. Fixed-header and fixed-sidebar workflows have been tested on the developer's Mac.
