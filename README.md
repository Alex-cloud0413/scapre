# Scapare

macOS 菜单栏截图工具，使用 Swift、AppKit、SwiftUI、ScreenCaptureKit 和 Vision。最低系统版本 macOS 14。

## 开发

打开 `Scapare.xcodeproj`，选择共享方案 `Scapare`。

```sh
xcodebuild -project Scapare.xcodeproj -scheme Scapare -configuration Debug -destination 'platform=macOS' build
```

仅检查编译、无需签名时，可以添加 `CODE_SIGNING_ALLOWED=NO` 并通过 `-derivedDataPath` 指定临时输出目录。未签名构建不代表已通过签名、权限或 App Store 分发验证。

## 功能

区域/窗口/多屏截图、滚动长截图、取色与放大镜、13 种标注工具、可重编辑贴图和分组备份、离线 OCR/条码、五种图片导出格式，以及命令行批处理、可选手势/触发角、快捷键与外观配置。

长截图：菜单栏「滚动长截图」→ 框选内容 → 工具条长截图按钮 → 在原窗口连续滚动 →「完成并复制」或「完成并编辑」。高级功能从「更多设置」进入，默认不开启本机命令行、手势和辅助功能控件检测。

首次默认截图快捷键为 ⌘E，以设置中保存的快捷键为准。快捷键在 Scapare 内编辑时暂停。网络仅用于显式确认的 HTTPS 图片导入，截图和文字识别在本地进行。

详细功能、限制和待验收项：[功能扩展记录](docs/feature-audit-2026-10-03.md)。命令行构建与批处理：[CLI 使用](docs/cli.md)。

## 回归检查

```sh
scripts/test.sh
```

检查快捷键失败恢复、引导迁移、保存取消/失败、历史与撤销、拼接、标注脱敏、图像导出、可编辑备份、外观和本机通信。脚本直接编译生产源码，不修改真实用户设置。它不替代签名 App 的实机交互、权限和无障碍检查。

## 名称和应用身份

工程、方案、源代码目录、程序入口、可执行文件、App 文件和界面名称统一为 **Scapare**。

Bundle ID 保留 `com.gaoyiming.SnapTool`，用于继续已有 App Store Connect 记录和本地偏好设置身份。它不是面向用户的产品名称。Apple 规定，上传过构建后不能在原有 App 记录中更改 Bundle ID。

当前本机修复版为 1.1.4（构建 9），补上固定窗口底边和阴影的识别，避免在连续滚动长图中重复追加灰色条带。148 项回归检查通过，原页面实机效果需用户复测。App Store 待审版本仍为 1.1.3（构建 8），通过后自动发布。Bundle ID 继续沿用原 App Store 记录。详见[阴影修复记录](docs/window-shadow-fix-2026-10-04.md)和[已提交版本记录](docs/appstore-release-2026-10-04.md)。

## 当前文档

- `docs/feature-audit-2026-10-03.md`：本轮功能扩展、对标差异、验证及实机边界。
- `docs/cli.md`：命令行与批处理用法。

- `项目说明.md`：开发接续和备份位置。
- `docs/apple-design-audit-2026-10-03.md`：原审核结果、证据与待验证项。
- `docs/audit-fixes-2026-10-03.md`：12 项代码问题的修复记录、36 项回归检查和实机验收边界。

历史项目说明保存在改名前提交中。当前文档以代码和实际检查结果为准。

## 图标

图形沿用本地「长卷」项目的标识。App 图标为纯白底、黑色线条；菜单栏使用透明单色模板，跟随系统明暗显示。现有默认剪刀图标在首次升级时迁移为长卷，其余外观设置保留。

可复现生成方式：将 `Tools/GenerateBrandIcons.swift` 复制为临时 `main.swift`，与 `Scapare/BrandIcon.swift` 一起编译，再运行并传入 `Scapare/Assets.xcassets/AppIcon.appiconset`。
