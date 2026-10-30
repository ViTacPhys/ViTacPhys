# 视频提交与部署注意事项

本文用于规范 ViTacPhys 项目网页中视频资源的制作、替换、提交和上线验证，避免再次出现“本地播放器正常，但 GitHub Pages 网页黑屏”的问题。

## 1. 必须遵守的视频格式

网页视频必须满足以下要求：

| 项目 | 要求 | 说明 |
| --- | --- | --- |
| 容器 | MP4 | 文件扩展名为 `.mp4` |
| 视频编码 | H.264/AVC | MP4 内部编码标识应为 `avc1`，禁止只提供 H.265/HEVC（`hvc1`） |
| 像素格式 | `yuv420p` | 保证桌面和移动浏览器的广泛兼容性 |
| 音频编码 | AAC（如有音频） | 当前网页视频默认静音，但保留兼容音轨没有问题 |
| 流式加载 | `faststart` | `moov` 索引必须移到文件开头，以便 GitHub Pages 快速显示首帧 |
| 单文件大小 | 建议小于 95 MiB | GitHub 拒绝大于 100 MB 的普通 Git 文件，预留余量可避免推送失败 |

注意：`.mp4` 只是容器名称，不能证明内部视频编码是 H.264。H.265 视频同样可以使用 `.mp4` 扩展名，但 Chrome、Firefox、Edge 和不同操作系统对 H.265 的支持依赖硬件、系统扩展和浏览器配置，不适合作为公开网页的唯一视频格式。

## 2. 本次黑屏问题的原因与修复

本次故障发生时，`assets/videos/` 下的 83 个 MP4 视频全部使用 H.265/HEVC（`hvc1`）。GitHub Pages 的路径、MIME 类型和 Range 请求均正常，但不具备 HEVC 解码能力的浏览器无法显示画面，因此出现黑屏。

提交 `17f9aef` 已完成以下修复：

- 将 83 个视频全部转换为 H.264/AVC（`avc1`）。
- 将像素格式统一为 `yuv420p`。
- 将 MP4 的 `moov` 索引移到文件开头。
- 将视频总体积从 266.3 MiB 降至 71.5 MiB。
- 使用 FFmpeg 对 83 个文件进行完整解码验证。
- 使用 Windows Edge 对 83 个文件进行真实浏览器首帧加载验证，结果为 83/83 成功。

不要通过简单改扩展名的方式“转换”视频，例如把 `.mov` 或 H.265 文件直接重命名为 `.mp4`。这不会改变内部编码。

## 3. 替换视频前的原则

1. 保持现有文件名和目录结构，除非同时修改 `index.html` 中的引用。
2. 原始高质量素材应保存在仓库外的归档目录；GitHub Pages 仓库只保存网页发布版本。
3. 不要反复对已经压缩的 H.264 文件转码。多次有损转码会降低画质。应尽量从原始素材生成最终网页版本。
4. 替换单个视频时，只转换并提交该视频，不要无意义地重新编码全部 83 个文件。
5. 页面中的视频默认静音。即使源文件包含音频，也不要依赖自动播放声音；主流浏览器会限制有声自动播放。

## 4. 转换单个视频

本机可使用以下 FFmpeg：

```text
C:\Program Files\EVCapture\ffmpeg.exe
```

在 PowerShell 中，将原始素材转换到临时输出文件：

```powershell
& "C:\Program Files\EVCapture\ffmpeg.exe" `
  -hide_banner -y `
  -i ".\source.mp4" `
  -map 0:v:0 -map "0:a?" `
  -c:v libx264 `
  -preset medium `
  -crf 23 `
  -pix_fmt yuv420p `
  -profile:v high `
  -tag:v avc1 `
  -movflags +faststart `
  -c:a aac -b:a 128k `
  ".\output.web.mp4"
```

确认输出正常后，再用它覆盖目标文件，例如：

```powershell
Move-Item -Force `
  ".\output.web.mp4" `
  ".\assets\videos\main.mp4"
```

`CRF 23` 适合当前网页展示。需要更高画质时可使用 `CRF 20` 或 `CRF 21`，但文件会更大。不要为了缩小文件盲目降低分辨率或帧率；应先比较实际画质和文件大小。

## 5. 批量转换

仓库提供了批量转换工具：

```text
tools/convert-videos-to-web.ps1
```

运行方式：

```powershell
cd "C:\拷贝\website_VitacPhys"

powershell -ExecutionPolicy Bypass `
  -File ".\tools\convert-videos-to-web.ps1" `
  -FfmpegPath "C:\Program Files\EVCapture\ffmpeg.exe"
```

该工具会：

1. 查找 `assets/videos/` 下的全部 MP4 文件。
2. 将输出写入 `.web-video-staging/` 暂存目录。
3. 对每个输出执行首秒解码验证。
4. 拒绝空文件以及大于或等于 95 MiB 的文件。
5. 只有全部文件转换成功后，才替换仓库中的视频。

批量工具会重新编码目录中的所有视频。因此，仅替换少量素材时应优先使用上一节的单文件命令，避免对其他视频进行重复有损转码。

## 6. 提交前检查

### 6.1 检查视频编码

对新视频执行：

```powershell
& "C:\Program Files\EVCapture\ffmpeg.exe" `
  -hide_banner `
  -i ".\assets\videos\main.mp4"
```

输出中的视频流应包含：

```text
Video: h264
```

不应包含：

```text
Video: hevc
```

### 6.2 执行完整解码测试

```powershell
& "C:\Program Files\EVCapture\ffmpeg.exe" `
  -hide_banner -loglevel error `
  -i ".\assets\videos\main.mp4" `
  -map 0:v:0 `
  -f null NUL
```

命令正常结束且没有错误输出，表示视频可以完整解码。

### 6.3 检查文件大小

```powershell
Get-ChildItem ".\assets\videos" -Filter *.mp4 -File -Recurse |
  Sort-Object Length -Descending |
  Select-Object -First 10 FullName,
    @{Name="MiB"; Expression={[math]::Round($_.Length / 1MB, 2)}}
```

任何接近 95 MiB 的文件都应重新压缩或考虑使用专门的视频托管服务，不能直接冒险推送。

### 6.4 使用本地 HTTP 服务测试

不要只通过双击 `index.html` 的 `file://` 地址测试。应从项目目录启动本地 HTTP 服务：

```bash
python -m http.server 8000
```

然后访问：

```text
http://localhost:8000/
```

至少检查以下内容：

- 顶部 `main.mp4` 可以显示首帧、播放、暂停和拖动。
- `single`、`merged`、`separate` 和 `failure` 分区各抽查一个视频。
- 浏览器开发者工具 Console 中没有媒体解码错误。
- Network 中视频请求返回 HTTP 200 或 206，且 `Content-Type` 为 `video/mp4`。

建议至少使用 Chrome 或 Edge 测试一次；如条件允许，再使用 Firefox 和 Safari 测试。

### 6.5 检查 Git 变更范围

```bash
git status --short
git diff --check
```

确认：

- 只包含计划替换的视频和必要的说明、脚本变更。
- 没有误提交原始素材、暂存文件、编辑器缓存或测试页面。
- 视频数量与本次替换计划一致。
- `.web-video-staging/` 没有进入 Git。

## 7. 提交和推送

只暂存本次确实需要提交的文件，不建议直接使用含义不明确的 `git add .`：

```bash
git add assets/videos/main.mp4
git commit -m "Update overview video"
git push origin main
```

批量替换时可以明确暂存视频目录：

```bash
git add assets/videos
git commit -m "Update website videos"
git push origin main
```

提交信息应说明实际变化，例如：

- `Update overview video`
- `Add new robot comparison videos`
- `Transcode website videos to browser-compatible H.264`

避免使用无法说明内容的提交信息，例如 `final`、`change` 或 `update`。

## 8. GitHub Pages 部署后检查

推送成功不等于网页已经更新。GitHub Pages 需要经过构建和 CDN 刷新：

1. 打开仓库的 **Actions** 页面。
2. 等待 `pages build and deployment` 状态变成 `completed / success`。
3. 打开线上网站并使用 `Ctrl + F5` 强制刷新。
4. 检查顶部视频和各视频分区。
5. 如果刚部署后仍出现旧视频，等待最长约 10 分钟再试；GitHub Pages/CDN 和浏览器可能仍缓存旧文件。

线上地址：

```text
https://vitacphys.github.io/ViTacPhys/
```

检查单个远程视频时，可以直接访问其 URL：

```text
https://vitacphys.github.io/ViTacPhys/assets/videos/main.mp4
```

## 9. 提交前最终清单

- [ ] 文件是 MP4 容器。
- [ ] 视频编码是 H.264/AVC（`avc1`），不是 H.265/HEVC（`hvc1`）。
- [ ] 像素格式是 `yuv420p`。
- [ ] 已启用 `faststart`。
- [ ] 视频能完成全片解码。
- [ ] 单文件小于 95 MiB。
- [ ] 已通过本地 HTTP 服务在浏览器中播放。
- [ ] 文件名和目录与 `index.html` 引用一致。
- [ ] `git status` 中没有无关文件。
- [ ] GitHub Pages Actions 部署成功。
- [ ] 线上页面强制刷新后可以播放。

只要以上检查全部通过，视频就不会依赖用户设备是否安装 HEVC 扩展，能够在主流浏览器中获得稳定得多的播放兼容性。
