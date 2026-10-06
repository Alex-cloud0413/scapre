# Scapare 1.1.7（12）：截图启动、放大镜和贴图再截图

## 用户反馈与改动

- 快捷键截图时页面明显跳动。原截图层是可成为主窗口的 NSWindow，逐屏抢键盘焦点后又强制激活 Scapare。改为非激活 NSPanel，关闭窗口动画，以不透明背景提前准备冻结画面；所有显示器准备好后，仅鼠标所在屏幕接收键盘焦点。退出时只在模态操作确实激活了 Scapare 的情况下恢复来源 App。
- 框选期间仍有方形像素窗口。原放大镜默认开启，绘制条件没有排除已有选区。改为默认关闭，并在升级时关闭一次旧默认设置；用户之后明确启用的偏好仍保留。即使手动启用，开始框选后也不再绘制放大镜。取色、像素坐标和精确框选功能保留。
- 桌面贴图不能纳入再次截图。原 ScreenCaptureKit 过滤器排除了 Scapare 的全部窗口。现在只将可见且未隐藏的贴图作为自有窗口例外纳入截图，编辑器和截屏工具仍被排除；浮动贴图也参与悬停窗口选区。不会修改贴图的隐藏、位置、透明度或原图状态。

截图面板不激活 App 后，键盘焦点独立于前台应用。全局快捷键、手势和触发角相应按实际键盘焦点暂停/恢复，防止它们打断文字标注。面板接受 Esc、框选和编辑快捷键，关闭后释放焦点。

## 验证记录

- **247 项回归检查通过**：包括原有长图拼接检查、放大镜前后真实 AppKit 栅格比较、升级偏好保留、可见/隐藏贴图窗口身份，以及非激活面板取得键盘焦点后来源 App 仍然活跃、关闭后释放焦点的窗口服务器检查。
- Release 的 arm64 与 x86_64 构建通过，Developer ID 签名与完整性检查通过；保留 App Sandbox 和原 Bundle ID，没有调试权限。
- 已安装到 `/Applications/Scapare.app` 并启动。旧安装版保存为 `Scapare-Backups/Scapare-before-1.1.7-12-2026-10-06.app`。
- 绘制证据使用合成图像，不包含用户桌面内容。原版本的原生 UI 控制连接未返回可操作的窗口，本轮没有完成真实桌面「截图→贴图→再次截图」操作链，也没有量测快捷键启动动画；这些实际手感、全屏 Space 和多显示器效果仍需用户复测。代码修复和自动检查不替代这项验收。

原安装版、源码恢复 bundle、验证日志和合成界面绘制证据保存在 `Scapare-Backups/`。本轮仅安装本机开发版，没有提交 1.1.7 到 App Store Connect。

## 平台行为依据

- [非激活面板](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)和[窗口动画行为](https://developer.apple.com/documentation/appkit/nswindow/animationbehavior-swift.property)。当前 Xcode SDK 的 NSWindow/NSPanel 头文件用于核实行为。
- [ScreenCaptureKit 应用过滤与窗口例外](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingapplications:exceptingwindows:))。SDK 的 SCStream.h 明确说明：被排除应用的例外窗口仍会显示。
