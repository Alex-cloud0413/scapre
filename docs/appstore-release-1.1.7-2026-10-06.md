# Scapare 1.1.7（12）发布与清理记录

本次发布改善快捷键截图时的页面跳动、移除框选期间的像素放大窗口，并将可见桌面贴图纳入再次截图。保留此前长截图的连续滚动、固定边栏与圆角去重修复。

## 发布结果

- 2026-10-06 15:50（Asia/Shanghai）正式提交审核。详情页确认 macOS 1.1.7、构建 1.1.7（12）为「等待审核」。通过后自动发布；当前尚未获批上架。
- 提交 ID：`e4fda6e4-b72a-4386-9b13-df20c8c923a1`；构建 ID：`4a375927-225a-421d-8b4f-0cd668566bc7`，上传时间 2026-10-06 15:44。
- 撤回旧待审提交 `3ed12062-7249-4b45-8693-3512f0a30533`，将版本从 1.1.6 改为 1.1.7，关联构建 12 后保存并重新提交。
- 审核进度：[App Store Connect](https://appstoreconnect.apple.com/apps/6777382263/distribution/reviewsubmissions/details/e4fda6e4-b72a-4386-9b13-df20c8c923a1)。

- App ID：`6777382263`；原 Bundle ID `com.gaoyiming.SnapTool` 保留。
- 构建源码：[`68cd888e4cdd030fbf898f060944415f904a0969`](https://github.com/Alex-cloud0413/scapre/commit/68cd888e4cdd030fbf898f060944415f904a0969)，已推送 GitHub `main` 和 `codex/capture-polish`。
- 沿用 Scapare 名称、纯白底长卷图标、现有描述、商店截屏、隐私信息和自动发布设置。审核备注说明本次截图和贴图行为改进。

## 验证与恢复材料

- 247 项回归检查通过；涵盖非激活截图面板、键盘焦点、放大镜绘制与偏好迁移、可见/隐藏贴图筛选和已有长图拼接。
- Release 归档和 App Store 上传成功，包含 arm64 与 x86_64。分发包使用 Apple Distribution 签名、保留 App Sandbox，不含调试或网络服务端权限。
- 分发包 SHA-256：`cd177f1229b7b1eea4c48d3b67464c47a50f0292bb737b7d7b130c5605631810`。
- 本机安装版为 `/Applications/Scapare.app` 1.1.7（12）。实际「截图→贴图→再次截图」操作链、启动手感、多显示器与全屏 Space 效果仍需实机验收；自动检查不等同于这些交互验收。
- 当前版本归档、安装包、导出配置、发布凭据、清理清单和完整 Git bundle 保存在 `Scapare-Backups/AppStore/1.1.7-build12/`；自动验证证据保存在 `Scapare-Backups/1.1.7-build12-verification-2026-10-06/`。

## 旧版本清理

按用户只保留 1.1.7（12）的要求，将 40 项旧程序、安装包、旧归档、构建缓存及重复备份移入废纸篓，包括旧 SnapTool、1.1 至 1.1.6 的 App 备份和旧 App Store 分发材料。清理旧 App 的系统注册，保留最新安装版的注册。

源码和完整 Git 历史、当前版本的恢复材料及用户截图数据/偏好保留。清理后检查 `/Applications`、用户应用目录、桌面、下载目录、Xcode DerivedData 和临时构建目录，找到的 Scapare App/归档均为 1.1.7（12）。废纸篓中的旧文件可恢复；本次没有清空整个废纸篓。此前发布文档中的旧备份路径属于历史记录，其文件已按本次要求清理。
