# Scapare 1.1.2 商店截图

`Scapare-1.1.2-capture-1280x800.png` 展示发布源码 `7839fb58e259b76d0978134e26c0e50e9b9347d6` 的 `EditorView`、`EditorToolbar` 和标注绘制。背景是专门编写的公开示例文档，不含用户截图或联系信息。图片通过生产视图的 AppKit 显示缓存生成，没有重绘或仿造工具栏。

`RenderStore.swift` 是只生成发布素材的入口，不属于 App 构建。将 Scapare 目录中除 `ScapareApp.swift` 外的 Swift 源码与此入口一起编译运行，输出文件位于 `/private/tmp/scapare-store-assets/Scapare-1.1.2-capture-1280x800.png`。需要创建输出目录并允许本机 AppKit 图形运行。

该截图替换原商店截图，后者包含 Scapre 旧名称、旧图标及 App Store Connect 联系字段。
