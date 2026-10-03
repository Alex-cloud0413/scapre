# Scapare 1.1.3（8）审核提交记录

修复浏览器连续滚动截图在固定侧栏、导航、局部动画及中文字体小数像素位移下的衔接失败。用户本机复测确认后，本次替换此前等待审核的 1.1.2（7）。

## 提交结果

- 2026-10-04 03:08（Asia/Shanghai）正式提交审核，App Store Connect 详情页确认 macOS 1.1.3、构建 1.1.3（8）的状态为「等待审核」。通过后自动发布；提交不代表已经获批或上架。
- 新提交 ID：`8ad77892-3100-490f-be79-2fabc466d4b9`。
- 构建 ID：`d1986822-e083-4a88-8a67-be6680643fa2`；页面上传时间为 2026-10-04 03:05。
- App ID：`6777382263`；Bundle ID 保留 `com.gaoyiming.SnapTool`；安装名、可执行文件及用户界面名称均为 Scapare。
- 已撤回旧提交中的 1.1.2（7），将待提交版本改为 1.1.3，选择并保存构建 8 后重新提交。
- 沿用简体中文名称 Scapare、现有商店描述和截屏、隐私信息及自动发布设置。构建选择区确认使用纯白底长卷图标。审核备注补充本次连续滚动修复及跳过所有重叠内容时的恢复方式。
- 审核进度：[App Store Connect](https://appstoreconnect.apple.com/apps/6777382263/distribution/reviewsubmissions/details/8ad77892-3100-490f-be79-2fabc466d4b9)。

## 源码与验证

- 上传构建对应源码提交：`857b3bbe04fb28a846db27d595492ed2c80eeaec`，已推送至 GitHub 的 `main` 与 `codex/scrolling-mixed-content` 分支。
- 143 项回归检查通过。用户在安装的 1.1.3（8）上自行实测后确认可以提交；本轮未由代理操作浏览器滚动进行实测。
- App Store 归档、上传和分发包导出均成功；归档签名检查通过，包含 Apple silicon 和 Intel 架构。
- 导出分发摘要确认 Apple Distribution 签名，App Sandbox 保留，未包含 `get-task-allow` 调试权限。
- 分发包 SHA-256：`deb72d6c593fb83f223273d1613c1891e467543551cdfc1d38567a22c1df2876`。

## 本地恢复材料

归档、分发包、导出设置、上传日志、审核状态截图和发布凭据保存在 `Scapare-Backups/AppStore/1.1.3-build8/`。包含账号信息的 UI 证据只保存在本机，不提交公开仓库。

## 本次新增审核备注

Version 1.1.3 (build 8) replaces the previously submitted 1.1.2 (build 7). It improves continuous scrolling capture on webpages that combine moving text with fixed sidebars, navigation, or local animations. Scrolling capture consumes continuous screen frames and does not require the user to pause after each scroll. If scrolling skips all overlapping content, it preserves the existing result and asks the user to scroll back to restore overlap.
