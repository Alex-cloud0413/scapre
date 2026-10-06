# Scapare 1.1.8（13）功能引导

新增首次启动和随时可重开的原生功能引导。沿用原 Bundle ID `com.gaoyiming.SnapTool`，保留用户的快捷键、贴图和偏好设置。

## 用户入口

- 首次启动显示「欢迎使用 Scapare」，关闭或点「开始使用」后记录已看过。
- 菜单栏「功能引导…」或「设置… → 查看功能引导…」可随时打开。已有窗口会被带到前台，不重复创建。
- 七个主题：快速开始、截图与取色、滚动长截图、标注与保存、桌面贴图、文字与条码识别、更多功能。
- 每个主题说明功能入口、操作步骤和必要提示；显示当前截图快捷键，并提供「截图设置…」入口。Esc 可关闭引导。
- 重新查看引导不重置任何设置，也不启用权限、登录启动、手势或命令行服务。

## 验证

- `scripts/test.sh`：258 项检查通过。新增检查覆盖七个主题的完整内容、主题列表和正文的可见面积、首次关闭标记及重新查看时偏好设置不变。
- Release 通用架构归档成功，支持 arm64 / x86_64，macOS 14 起。
- CUA 操作实际 AppKit 预览窗口：切换到长截图主题；进入设置；通过「查看功能引导…」返回；关闭后再次打开。浅色和深色原生窗口的选中项及正文可读；正式图标资产也已在预览验证。
- 独立截图审核指出离屏 `cacheDisplay` 测试图的选中项颜色异常，原生激活窗口未复现，不能将该离屏图用作颜色验收依据。原生控件采用系统 sourceList 样式，正文使用 regular、步骤标题 semibold。
- 首次启动状态与偏好保留通过隔离 UserDefaults 验证；没有重置真实用户设置来模拟全新安装。本轮未重新执行截图和长截图的手动实测。

## 本地分发

Developer ID 签名并通过 Apple 公证；App 内已装订公证票据。`stapler validate`、`codesign --verify --deep --strict`、`spctl --assess` 和 `syspolicy_check distribution` 通过。DMG 校验通过；模拟从 DMG 复制 App 并添加下载隔离标记后，分发检查仍通过。

- DMG：`Scapare-1.1.8-13.dmg`，932527 字节。
- SHA-256：`161a05bc50f506803bfbe7b70412ee1660ace4c26bfd5b5465aeee83b7f9b829`。
- DMG 内容仅为公证后的 `Scapare.app`、指向 `/Applications` 的安装链接和中文安装说明。
- 恢复材料：`/Users/gaoyiming/Desktop/Scapare-Backups/DirectDistribution/1.1.8-build13/`。

本轮不推送 GitHub、不替换 App Store 已提交的 1.1.7（12）。后续发布应从本版本归档构建新的 App Store 安装包，不能直接上传 Developer ID 的 App。
