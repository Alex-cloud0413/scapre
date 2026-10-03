# Scapare 本机命令行

先启动 Scapare，在「更多设置 → 高级功能」启用本机命令行。默认关闭。程序使用仅当前用户可连接的 Unix socket；不开放 TCP 端口。App 不接收任意文件路径或执行脚本：CLI 读取输入文件、发送图片数据，再将返回结果写到指定位置。

## 构建和使用

在项目目录运行：

```sh
scripts/build-cli.sh /private/tmp/scapare-cli/scapare
/private/tmp/scapare-cli/scapare --help
/private/tmp/scapare-cli/scapare status
```

这些命令不会安装系统级工具。可以自行把生成的 `scapare` 放进自己的 PATH。

```sh
# 主屏幕原始像素坐标，原点在左上角；此命令会实际截图。
scapare capture --region 100,100,1200,800 --delay 2 --output capture.png

# 原图坐标内先打码，再裁剪、旋转、加边框/圆角，最后编码。
scapare process input.png --mosaic 20,30,240,80 --rotate 90 --output edited.png
scapare process input.png --blur 10,20,100,50 --round 24 --border 2 --shadow --output rounded.png

# 输出目录应已存在；同一批次不能生成重名文件。
scapare process a.png b.png --output-dir ./results --grayscale --format jpg
scapare ocr a.png b.png
scapare barcode code.png

scapare pin a.png b.png --group 设计参考
scapare paste
scapare list
scapare hide --group 设计参考
scapare show --group 设计参考
scapare export --group 设计参考 --output pins.json
scapare import pins.json
```

不覆盖已有文件；确需覆盖时加 `--overwrite`。一个输入失败时会继续处理其余输入，最后以非零状态退出。错误写入标准错误；识别文字和状态写入标准输出。导出格式为 PNG、JPEG、TIFF、BMP、GIF，GIF 输出是当前帧。

区域格式 `x,y,width,height`，宽高为正数，必须完全落在原图内。旋转为 90 度的整数倍，范围 −360 至 360。`--mosaic`、`--blur` 可以重复。单个输入不超过 100 MB，图片最多 60 MP、单边不超过 30,000 像素；本机消息最多 140 MB（含 JSON/Base64 开销）。较大的可编辑备份请通过 App 的导入/导出使用。

「可编辑贴图备份」包含原图及可修改的标注；其中的原图可能保留打码区域。分享脱敏内容应导出已经合成的图片。

## 连接与权限

CLI 优先连接原 Bundle ID 对应容器内的 socket，再尝试开发运行位置。若运行多个版本，用「高级功能 → 复制命令行连接路径」，通过 `--socket /完整路径/socket` 指定。

截图仍需要 macOS 屏幕录制权限。文字识别和图像处理在本地完成；CLI 不代替或绕过权限授权。App 关闭后命令行连接不可用。套接字路径过长会明确报错，不改用公共监听端口。

## 检查

```sh
scripts/test.sh
scripts/build-cli.sh /private/tmp/scapare-cli/scapare
python3 Tests/CLIIntegrationTests.py /private/tmp/scapare-cli/scapare
```

第一组直接检查生产图像算法、备份和本机通信。第二组用本机合成服务验证真实 CLI 的参数、消息格式、批处理、错误退出和文件防覆盖。都不截图、不读真实剪贴板。受限执行环境可能禁止本机 socket，此时必须在允许本机通信的开发环境运行，不能将连接失败记为通过。
