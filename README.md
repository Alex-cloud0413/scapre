# Scapare

macOS 菜单栏截图工具，使用 Swift、AppKit、SwiftUI、ScreenCaptureKit 和 Vision。最低系统版本 macOS 14。

## 开发

打开 `Scapare.xcodeproj`，选择共享方案 `Scapare`。

```sh
xcodebuild -project Scapare.xcodeproj -scheme Scapare -configuration Debug -destination 'platform=macOS' build
```

仅检查编译、无需签名时，可以添加 `CODE_SIGNING_ALLOWED=NO` 并通过 `-derivedDataPath` 指定临时输出目录。未签名构建不代表已通过签名、权限或 App Store 分发验证。

## 功能

区域截图与选区调整；矩形、椭圆、箭头、画笔、文字标注；PNG 保存与复制；浮动贴图；离线中英文 OCR；最近六次屏幕截图历史；自定义截图快捷键。首次默认快捷键为 ⌘E，以设置中保存的快捷键为准。

## 名称和应用身份

工程、方案、源代码目录、程序入口、可执行文件、App 文件和界面名称统一为 **Scapare**。

Bundle ID 保留 `com.gaoyiming.SnapTool`，用于继续已有 App Store Connect 记录和本地偏好设置身份。它不是面向用户的产品名称。Apple 规定，上传过构建后不能在原有 App 记录中更改 Bundle ID。

版本号为 1.0，构建号已递增为 2（用户提供的拒审记录是 1.0 (1)）。上传前仍需核对 App Store Connect 最新已使用的构建号，必要时继续递增。改名不会自动修改远端商店名称：商店原名 Scapre 也需在所有语言中统一为 Scapare。

## 当前文档

- `项目说明.md`：开发接续和备份位置。
- `docs/apple-design-audit-2026-10-03.md`：本轮审核结果、证据与待验证项。

历史项目说明保存在改名前提交中。当前文档以代码和实际检查结果为准。
