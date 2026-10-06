# Scapare 1.2.2（17）直接分发

用户确认固定侧栏修复版在本机可用，授权推送 GitHub、更新可直接安装的 DMG，并明确允许该版本发送至 Apple 公证服务；暂不提交 App Store。

## 版本与源码

- 归档源码提交：`1492aec20f4205446c7dfd3b827e84e48994648a`。
- GitHub `main` 与 `codex/adaptive-fixed-regions` 已包含该版本，使用普通快进推送。
- 514 项回归通过，用户确认本机测试通过。
- 支持 macOS 14 及以上，包含 Apple Silicon 与 Intel 架构。

## 分发验证

Developer ID 直接分发 App 已通过 Apple 公证，票据已附在 App 内。签名校验、票据验证、Gatekeeper 与 `syspolicy_check distribution` 均通过。

从正式 DMG 复制 App，添加下载隔离标记后，上述检查同样通过；包内程序代码在两种架构下均与本机测试版一致。公证重新导出仅改变签名数据。

- 正式 DMG：`/Users/gaoyiming/Desktop/Scapare-1.2.2-17.dmg`。
- 文件大小：1,045,644 字节。
- DMG SHA-256：`399d103a3402183e02a258aa648fb7298e676b102fab8f3b4bb25335e9f8a42d`。
- 内容仅为公证后的 `Scapare.app`、指向 `/Applications` 的安装链接和中文安装说明。
- 安装：先退出已有 Scapare，再将包内 Scapare 拖入 Applications。首次日常截图需按 macOS 提示允许屏幕录制。
- 源码、归档、App、DMG、验证日志及 receipt.json 保存于 `Scapare-Backups/DirectDistribution/1.2.2-build17/`。

本机正在使用的同版测试 App 保持不变。本次未上传 App Store，未提交 App Store 审核。
