# Scapare 1.1.2 (7) 审核提交记录

本次沿用本地「长卷」项目的三个黑色线条标识，使用纯白底 App 图标及透明菜单栏模板。图标覆盖 macOS 的 16、32、128、256、512 pt，以及各自的 1x/2x 尺寸。菜单栏图标在旧版默认剪刀设置上执行一次升级迁移；其他外观设置与主动选择的替代图标继续保留。

## 验证

- 120 项回归检查通过，包括既有截图、标注、贴图、连续滚动、完成并复制，以及图标默认值和设置迁移。
- Release 通用构建和 App Store 归档成功，覆盖 Apple silicon 和 Intel。
- 安装名、应用名、菜单名为 Scapare；Bundle ID 为 `com.gaoyiming.SnapTool`。
- 全部 10 个图标 PNG 的背景为 RGB (255, 255, 255)，像素完全不透明。
- 构建 6 已上传，但菜单栏迁移尚未完成，已由构建 7 替代；审核应只选构建 7。
- Chrome 浏览器控制连接超时后，使用本机 App Store Connect 软件完成元数据核对和提交。

## App Store Connect 已保存并提交

- 2026-10-03 23:39（Asia/Shanghai）重新提交审核，页面确认状态为「等待审核」。审核通过后自动发布。
- macOS 版本为 `1.1.2`，选中的构建为 `1.1.2 (7)`；构建 ID 为 `9cf7f15e-38f4-4c4d-b57b-0d7c01cbf56b`。
- App ID 为 `6777382263`，沿用原审核提交 `8416f6ea-ea26-4e0c-acb8-2bb4ce1b9ab4`，保持原 Bundle ID。
- 商店配置的本地化只有简体中文。名称已保存为 `Scapare`，副标题为「长截图、标注与离线文字识别」，描述和推广文本更新为当前功能。关键词移除第三方产品名，补充长截图与滚动截图。
- 替换包含 Scapre 名称、旧图标及联系人信息的旧截图，新截图为 `docs/store-assets/Scapare-1.1.2-capture-1280x800.png`。
- 隐私标签保持「未收集数据」；旧政策中的自动收集与上传描述已按实际数据流更正，当前隐私政策为仓库根目录 `PRIVACY.md`，商店链接已保存为 `https://github.com/Alex-cloud0413/scapre/blob/main/PRIVACY.md`。
- 已填写下方审核备注，说明安装名称一致、原 Bundle ID 保留、菜单栏入口和长截图操作方式。沿用已有审核联系人，无需登录，未修改定价或销售范围。
- 提交审核不代表已经获批或已上架。当前审核进度：[App Store Connect](https://appstoreconnect.apple.com/apps/6777382263/distribution/reviewsubmissions/details/8416f6ea-ea26-4e0c-acb8-2bb4ce1b9ab4)。

## 商店文案候选

产品名称：Scapare

更新说明：

支持连续滚动长截图与完成后直接复制。提供区域、屏幕、窗口和延时截图，常用标注、离线文字识别及桌面贴图。优化工具栏提示、贴图管理与外观设置，并统一 App 与菜单栏的长卷图标。

## App Review Notes 候选

The product name is Scapare. The installed application is Scapare.app, and the About and Quit menu items use Scapare. The original bundle identifier, com.gaoyiming.SnapTool, is preserved to maintain the existing App Store application identity. This resolves the installed-name mismatch described in the previous Guideline 2.3.8 rejection.

The app runs in the macOS menu bar. Click the LongJuan mark to open the capture menu. On first launch, configure a screenshot shortcut and grant the macOS screen capture permission when requested. For scrolling capture, select a region, choose the scrolling capture action, scroll the target application, and choose Complete and Copy or Complete and Edit. No account or login is required. Screenshot processing and OCR run on the Mac.

## 图标来源和可复现方式

来源为用户本地 LongShot 工程的 `AppIcon-LongJuan-v2.png`。先使用内置 image_gen 检查白底变体，提示要求保留三个标记，仅移除暖白纹理并换成 #FFFFFF。最终生产资产通过 `BrandIcon.swift` 和 `Tools/GenerateBrandIcons.swift` 的固定路径与颜色绘制，确保纯白底及菜单栏与 App 图形一致。

```sh
cp Tools/GenerateBrandIcons.swift /tmp/scapare-icon-main.swift
mkdir -p /tmp/scapare-icon-generator
cp /tmp/scapare-icon-main.swift /tmp/scapare-icon-generator/main.swift
swiftc Scapare/BrandIcon.swift /tmp/scapare-icon-generator/main.swift -o /tmp/scapare-icon-generator/generate
/tmp/scapare-icon-generator/generate Scapare/Assets.xcassets/AppIcon.appiconset
```
