# Scapare 审核问题修复记录

日期：2026-10-03。对应 [原审核报告](apple-design-audit-2026-10-03.md)「优先修复的确定问题」中的 12 项。

本轮已完成 12 项问题的代码修复，36 项自动回归检查、Debug 编译和 Release 双架构归档通过。**运行界面仍未取得：原生 App 控制连接返回 `timeoutReached`，因此这不是完成实机验收或可以直接送审的结论。**

## 已实现的修复

| 原问题 | 当前行为 | 主要实现 |
| --- | --- | --- |
| F1–F12 无法录制 | 明确接受全部 12 个功能键；Esc 取消并保留旧键；无修饰字母和仅修饰键不接受 | `InteractionState.swift`、`ShortcutRecorder.swift` |
| 快捷键注册失败仍保存 | 检查系统注册结果；新注册成功后才替换旧注册、保存设置。冲突显示错误；启动失败时保留菜单栏截图入口 | `GlobalHotKey.swift`、`AppDelegate.swift` |
| 保存取消/失败丢失编辑 | 保存面板出现时暂时隐藏编辑器。成功后退出；取消或写入失败返回原选区和标注。失败可重新选择位置；贴图保存共用该流程 | `CaptureController.swift`、`ImageFileSaver.swift` |
| 历史切换清空编辑 | 六条历史分别保存各显示器的选区、标注和撤销状态；往返恢复。显示当前位置、历史边界及显示器配置不兼容提示 | `InteractionState.swift`、`CaptureController.swift` |
| 引导和登录启动状态混淆 | 引导完成独立保存；更改快捷键不再完成引导。设置页始终提供登录启动开关，读取系统状态，展示待系统批准或失败原因；关闭只清理一次 | `SettingsManager.swift`、`SetupWindow.swift` |
| 选区把手不可见 | 绘制八个把手，命中区域与显示位置一致；提供缩放方向光标 | `EditorView.swift` |
| 文字把手命中错位 | 显示与命中共用右下角矩形；先检查把手，再处理文字本体移动 | `EditorView.swift`、`InteractionState.swift` |
| OCR 没有可靠状态 | 立即打开带进度的窗口；区分识别中、有结果、无文字、失败；空/失败不能复制占位内容，可重试；关闭取消待处理任务，过期结果不再更新窗口 | `OCRResultWindow.swift`、`OCRService.swift` |
| 所有捕获错误都提示权限 | 只将 ScreenCaptureKit 的用户拒绝错误归为权限问题；其他捕获错误显示原因并提供重试 | `ScreenshotEngine.swift`、`Permission.swift` |
| 颜色和工具状态难以辨认 | 颜色改用带名称和色值的原生选择器；工具有选择状态、边框及辅助功能标签；使用系统语义颜色；快捷键录制控件支持键盘启动和焦点环 | `EditorToolbar.swift`、`ShortcutRecorder.swift` |
| 缺少撤销/重做及标准快捷键 | 每次编辑保存可逆快照；支持 ⌘Z / ⇧⌘Z、⌘C、⌘S、⌘A、⇧⌘O、⇧⌘P；接入 AppKit 响应链，提供右键菜单与快捷键提示；文字输入使用独立撤销栈 | `EditorView.swift`、`InteractionState.swift` |
| 尺寸标签与 PNG 不符 | 尺寸显示明确的 px 单位，标签和输出使用相同像素裁剪规则；有标注时按原图像素合成，避免绘制焦点改变分辨率 | `InteractionState.swift`、`ScreenshotRenderer.swift` |

OCR 文本窗口同时补上宽度追踪与最小窗口尺寸；设置窗口关闭路径去掉递归调用。图标未改动。

## 已验证的范围

运行 `scripts/test.sh`，直接编译生产源码和 `Tests/RegressionTests.swift`，共 **36 项检查通过**。原始结果保存在 [regression-results-2026-10-03.txt](regression-results-2026-10-03.txt)。

- 快捷键：12 个功能键的输入校验；注入注册失败，验证旧注册和持久化值保持；成功才提交新值。
- 设置：用独立临时偏好域验证新用户初始化、修改快捷键后继续引导、已完成状态及旧设置迁移，不改动用户的真实设置。
- 编辑：撤销/重做、历史往返、每张图独立撤销、历史边界及六条容量上限。
- 保存：注入取消与写入失败；验证重试后在临时目录原子写入相同数据。未把注入测试当作真实保存面板操作。
- OCR/错误：空白与失败状态不能复制；无效图片实际进入 OCR 错误路径；相同错误码在不同错误域下正确区分。
- 图像：1×/2× 裁剪、文字把手几何、离屏实际标注合成位置、背景保留和最终 PNG 像素尺寸。

构建结果：

| 检查 | 结果 |
| --- | --- |
| Debug（arm64） | `BUILD SUCCEEDED` |
| Release Archive | `ARCHIVE SUCCEEDED`；`x86_64 arm64` |
| 名称 | App 包、CFBundleName、CFBundleDisplayName、可执行文件均为 Scapare |
| 应用身份 / 版本 | `com.gaoyiming.SnapTool` / `1.0 (2)`；保持原应用身份 |
| 最低系统 | macOS 14.0 |
| 图标 SHA-256 | `8c73bb025061c38571fd37f0ae2a21341d58de10a182234a59bcf4dabac2d2e4`，未变化 |
| 差异格式检查 | 通过 |

两次构建均使用 `CODE_SIGNING_ALLOWED=NO`。日志中的本机 Simulator 服务不可用信息和未依赖 AppIntents 的元数据提示没有阻止 macOS 构建；未声称已通过签名、权限或商店验证。机器可读结果见 [audit-fixes-verification-2026-10-03.json](audit-fixes-verification-2026-10-03.json)。

## 实机验收仍待完成

1. 用签名候选 App 测屏幕录制允许/拒绝、登录启动启用/取消/待批准，以及旧安装和偏好的迁移。
2. 标注后取消保存；真实写入失败后重试；两张历史分别编辑并往返，再撤销/重做。
3. 检查 F1–F12、冲突快捷键、Esc、文字输入时标准编辑命令；包括全局截图快捷键与 App 内快捷键重叠的情况。
4. 在屏幕四角拖动八个把手、移动/缩放多行文字；对照 1×、2×、混合显示器上的标签和 PNG。
5. OCR 检查有字、空白、大图、失败、重试和中途关闭；检查长文、最小窗口和文字编辑。
6. 深浅色、增加对比度、Tab/VoiceOver、工具条溢出、多屏/Spaces、实际取色与长时内存仍需运行界面证据。原报告中的这些假设没有被批量宣告为已修复。

App Store Connect 的名称和各语言素材仍需在线同步 Scapare，并核实构建号 2 是否可用。本轮没有替换 `/Applications/SnapTool.app`、公开推送 GitHub、上传或提交审核。
