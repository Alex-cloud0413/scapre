# Scapare 1.2.2（17）直接分发

用户确认固定侧栏修复版在本机可用，并授权推送 GitHub、更新可直接安装的 DMG，暂不提交 App Store。

## 已完成

- 源码构建提交：`1492aec20f4205446c7dfd3b827e84e48994648a`。
- GitHub `main` 与 `codex/adaptive-fixed-regions` 已更新至该提交，使用普通快进推送。
- 514 项回归通过，Release 通用归档包含 Apple Silicon 与 Intel 架构，最低 macOS 14。
- 签名 DMG 候选已创建，含 Scapare.app、Applications 安装链接和中文安装说明，磁盘映像校验通过。

## 公证状态

候选包尚未公证，暂不作为正式分发包。Apple 公证上传被自动审批拒绝，理由是需要针对这个具体版本明确授权将二进制包发送给 Apple；已请求用户确认。公证属于 Developer ID 直接分发，不是 App Store 上传或审核。

正式分发前还需验证 Apple 公证票据、Gatekeeper，并从 DMG 复制 App 添加下载隔离标记后核对安装检查结果。

本次未上传 App Store，未提交 App Store 审核。
