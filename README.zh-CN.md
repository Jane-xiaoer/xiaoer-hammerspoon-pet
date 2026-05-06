# Xiaoer Hammerspoon Pet

[English](README.md) | **中文**

<p align="center">
  <img src="assets/xiaoer-ear-install-icon-512.png" alt="小耳桌宠安装图标" width="160" />
</p>

一个运行在 macOS Hammerspoon 里的桌面小人。当前版本来自一套水彩风小女孩素材，已经接入番茄钟、待办、吃饭、喝水、睡觉、拖动跑步和完成庆祝动画。

## 宣传视频

[![观看小耳防沉迷桌宠宣传视频](assets/xiaoer-pet-demo-poster.jpg)](https://github.com/Jane-xiaoer/xiaoer-hammerspoon-pet/releases/download/v0.1.3/xiaoer-anti-addiction-desktop-pet-demo.mp4)

点击观看：[小耳防沉迷桌宠宣传视频](https://github.com/Jane-xiaoer/xiaoer-hammerspoon-pet/releases/download/v0.1.3/xiaoer-anti-addiction-desktop-pet-demo.mp4)。

## 功能

- 桌面常驻小人，可拖动位置。
- `Control + Option + P` 打开透明水彩风控制面板。
- 45 分钟番茄钟：专注中播放 `working`，结束后跳到屏幕中间播放 `failed`，直到点掉。
- 每天 `12:30`、`18:00` 提醒吃饭，播放 `eating`。
- 每天 `22:30` 提醒睡觉，播放 `sleeping`。
- 每 1 小时提醒喝水，播放 `drinking`。
- 自定义提醒文字包含吃饭、喝水、睡觉关键词时，会自动切对应动画。
- 当天所有待办完成后播放 `jumping` 庆祝。
- 拖动桌宠时，向右播放 `running-right`，向左播放 `running-left`。

## 当前动画映射

| 场景 | mood / state | 动画目录 |
|---|---|---|
| 日常轮播 | `idle` | `idle`, `review`, `waving`, `running`, `rowing`, `waiting` |
| 专注工作 | `focus` | `working` |
| 完成普通待办 | `break` | `waving` |
| 当天全部待办完成 | `jumping` | `jumping` |
| 吃饭提醒 | `hungry` | `eating` |
| 喝水提醒 | `thirsty` | `drinking` |
| 睡觉提醒 | `sleepy` | `sleeping` |
| 专注结束休息提醒 | `failed` | `failed` |
| 拖动向右 | drag override | `running-right` |
| 拖动向左 | drag override | `running-left` |

## 安装

### 友好安装版

1. 先安装 [Hammerspoon](https://www.hammerspoon.org/)。
2. 在本仓库的 [Releases](https://github.com/Jane-xiaoer/xiaoer-hammerspoon-pet/releases) 下载 `XiaoerPet.dmg`。
3. 打开 DMG。
4. 双击：

```text
Install Xiaoer Pet.command
```

安装器会把桌宠复制到 `~/.hammerspoon/pai`，自动生成本地配置，询问“桌宠怎么称呼你”，并打开或重载 Hammerspoon。这个名字会显示在面板标题和移动时的鼓励文字里。

如果你想走 ZIP 方式，也可以点击 **Code → Download ZIP**，解压后双击同一个 `Install Xiaoer Pet.command`。

仓库里也放了一个可爱的“小耳”安装图标：

```text
assets/xiaoer-ear-install-icon.png
assets/xiaoer-ear-install-icon.icns
```

`.command` 安装器第一次运行时，会尝试把这个图标设置到自己身上。GitHub ZIP 下载不一定在首次运行前保留 Finder 自定义图标，所以图标源文件也一起放在仓库里。

### 构建 DMG

如果你想本地生成一个方便分发的 DMG：

```bash
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
```

生成位置：

```text
dist/XiaoerPet.dmg
```

DMG 里会包含：

```text
Install Xiaoer Pet.command
Switch Pet.command
pets/xiaoer/
pets/_template/
README.md
README.zh-CN.md
```

### 终端安装

1. 安装 [Hammerspoon](https://www.hammerspoon.org/)。
2. 克隆本仓库：

```bash
git clone https://github.com/Jane-xiaoer/xiaoer-hammerspoon-pet.git
cd xiaoer-hammerspoon-pet
chmod +x scripts/install.sh
./scripts/install.sh
```

3. 如果你已有自己的 `~/.hammerspoon/init.lua`，确认里面包含：

```lua
require("pai").start()
```

4. 重启 Hammerspoon。

## 自定义成你自己的角色

动画素材都在：

```text
pai/assets/companion/balloons/
```

每个状态一个目录，里面是按顺序播放的 PNG 帧：

```text
idle/00.png
idle/01.png
...
working/00.png
working/01.png
...
```

替换方法：

1. 从下面任一 pet 源头下载或生成你喜欢的角色素材。
2. 把同一个动作拆成连续 PNG 帧。
3. 放进对应状态目录，保持 `00.png`, `01.png`, `02.png` 这样的命名。
4. 重启 Hammerspoon。

推荐 pet 源头：

- [codexpet.xyz](https://codexpet.xyz/)
- [codex-pets.net](https://codex-pets.net/)
- [gitpets.com](https://gitpets.com/)

## 切换 Pet

安装之后，双击：

```text
Switch Pet.command
```

选择一个 pet 文件夹。切换器会把这个文件夹复制到：

```text
~/.hammerspoon/pai/pets/
```

然后自动更新：

```text
~/.hammerspoon/pai/local_config.json
```

让 `companion_animation_root` 指向你选择的 pet。

所以 DMG 不会限制自定义。DMG 只是分发外壳；真正安装后的 pet 文件会放在 `~/.hammerspoon/pai/pets/` 里。

如果要做自己的角色，可以复制 `pets/_template`，改名，把每个状态目录填入 PNG 帧，然后用 `Switch Pet.command` 选择它。

## 状态目录建议

| 目录 | 建议动作 |
|---|---|
| `idle` | 站着、眨眼、轻微晃动 |
| `review` | 看东西、思考、检查 |
| `waving` | 挥手、开心 |
| `waiting` | 等待、发呆 |
| `running` | 日常轮播里的小跑 |
| `rowing` | 日常轮播里的划船机运动 |
| `running-right` | 被鼠标拖着向右跑 |
| `running-left` | 被鼠标拖着向左跑 |
| `working` | 认真工作、敲键盘 |
| `eating` | 吃饭提醒、摇铃 |
| `drinking` | 喝水提醒、举杯 |
| `sleeping` | 睡觉提醒、打哈欠 |
| `failed` | 番茄钟结束、提醒休息 |
| `jumping` | 完成全部待办后的庆祝 |

## 配置

安装脚本会生成：

```text
~/.hammerspoon/pai/local_config.json
```

这里可以改尺寸、提醒时间和动画映射。示例文件在：

```text
pai/local_config.example.json
```

常用配置：

```json
{
  "companion_width": 210,
  "companion_height": 288,
  "companion_panel_width": 299,
  "companion_panel_height": 469,
  "companion_idle_animation_cycle_seconds": 600
}
```

## 注意

- 本仓库不包含个人 API key、语音助手配置或本地状态文件。
- `local_config.json` 和 `companion_state.json` 不应提交到 GitHub。
- 这是 Hammerspoon Lua 脚本，不是独立 macOS App。

## License

[MIT](LICENSE)

---

## 📱 关注作者 / Follow Me

如果这个仓库对你有帮助，欢迎关注我。后面我会持续更新更多 AI Skill、桌面自动化、Hammerspoon 工具和创意项目。

If this repo helped you, follow me for more AI skills, desktop automation, Hammerspoon tools, and creative projects.

- X (Twitter): [@xiaoerzhan](https://x.com/xiaoerzhan)
- 微信公众号 / WeChat Official Account: 扫码关注 / Scan to follow

<p align="center">
  <img src="assets/follow-wechat-qrcode.jpg" alt="Jane WeChat Official Account QR code" width="300" />
</p>

<p align="center"><strong>中文：</strong>欢迎关注我的公众号，一起研究 AI Skill、桌面自动化、Hammerspoon 工具和创意实验。</p>

<p align="center"><strong>English:</strong> Follow my WeChat Official Account for more AI skills, desktop automation, Hammerspoon tools, and creative experiments.</p>
