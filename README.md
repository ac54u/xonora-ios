# Xonora：适用于 iOS 与 CarPlay 的 Music Assistant 播放器

Xonora 是一款高性能的 [Music Assistant](https://music-assistant.io/) 原生客户端，支持 iPhone 和 CarPlay。使用 SwiftUI 和自定义 **SendspinKit** 音频引擎构建，实现从自托管服务器到设备的无缝、同步高保真播放。

> **关于本 Fork：** 这是社区维护分支。README 已根据**仓库实际代码**核对修订，移除了上游中尚未在本分支实现的功能描述（如 Toast 通知、独立个性化设置页、完整 watchOS 配套应用、Siri 意图等），力求与实际可用功能一致。

## 自行编译（适用于 TrollStore / 巨魔）

如果你没有 Mac，或者想绕过 Apple 签名直接安装，可以使用 **GitHub Actions** 自动编译：

### 步骤

1. **Fork 此仓库** — 点击 GitHub 页面右上角的 Fork 按钮
2. **进入你 Fork 后的仓库** → 点击 **Actions** 标签页
3. **同意/启用 Actions**（如果提示）
4. **在左侧选择 "Build IPA"** → 点击右侧 **Run workflow** → 再次点击 **Run workflow**
5. **等待编译完成**（约 5-10 分钟）
6. **编译完成后**，点击出现的 **Xonora.ipa** 工件（Artifact）下载
7. **将 IPA 传输到 iPhone**（通过 AirDrop、iCloud 或任何方式）
8. **用 TrollStore 打开 IPA** → 点击安装即可

> 也可以直接在本仓库的 **[Releases](../../releases)** 页面下载已编译好的 `Xonora.ipa`。

### 前提条件

- **iOS 17.0** 设备已安装 [TrollStore 2](https://github.com/opa334/TrollStore)
- 一台 **Music Assistant 服务器**（版本 2.x，Schema 28+）
- 服务器上已启用 **Sendspin** 播放器提供程序

### 常见问题

- **编译失败？** 检查 GitHub Actions 日志，可能需要更新 Xcode 版本或修复代码问题
- **安装后闪退？** 确保 iOS 版本为 17.0，TrollStore 为最新版本
- **无法连接服务器？** 确保手机和服务器在同一网络，且 Sendspin 已启用
- **封面一直转圈？** 已修复（改用禁用系统代理的图片加载会话）；若仍不显示，多为服务器未返回封面元数据

## 版本 1.0.7 维护更新（本 Fork）

本次更新以**修复实际可用性问题**和**对齐 Music Assistant 2.9.x API** 为主：

### 播放器管理

- **真正删除播放器**：使用 `config/players/remove` 从服务器彻底移除（离线设备删除后不再重现），仅在 provider 重新上报时回退为本地隐藏
- **重命名生效**：改用 PlayerConfig 根级 `name` 字段（此前发送的 `name_override` 被服务器忽略，导致改名不生效）
- **远程播放器静音开关**：通过 `players/cmd/volume_mute` 切换
- **图标识别**：正确识别 Web（Chrome/Safari 等浏览器）与 Universal Player

### 曲库同步

- **下拉刷新触发服务器扫描**：下拉刷新会调用 `music/sync` 让服务器重新扫描音乐源，新上传到服务器音乐文件夹的歌曲会被收录
- **扫描完成自动刷新**：监听 `media_item_added` / `music_sync_completed` 等事件，后台扫描收录新歌后曲库列表自动更新

### 播放队列（服务端同步）

- **删除/清空/拖拽排序**：分别对应 `player_queues/delete_item`、`player_queues/stop`、`player_queues/move_item`（按 URI 匹配 queue_item_id，避免索引漂移）

### 当前播放界面

- **封面加载修复**：背景模糊大图与专辑封面改用带缓存、禁用系统代理的加载器，解决"一直转圈"问题
- **歌词**：改用 `metadata/get_track_lyrics`，修复此前静默失败

### CarPlay 与界面

- **CarPlay 主页真实数据**：继续收听、最近播放、推荐改为拉取真实数据并可点击播放
- **迷你播放条遮挡修复**：在"正在播放"标签页隐藏迷你条，不再遮挡播放控制
- **登录界面精简**：去除持续动画的渐变背景、移动光球与图标发光/呼吸效果，改为干净静态外观
- **图片代理**：改用规范的 `/imageproxy/{proxy_id}` 端点
- **简体中文翻译**：修正用词（您/令牌等）、补齐 CarPlay 与排序相关缺失翻译、修复因 SwiftUI 类型推断绕过本地化的字符串

## 核心功能

### 音频流

- **Sendspin 协议**：无损 PCM/FLAC 音频流，动态缓冲
- **无缝播放**：曲目之间的平滑过渡
- **硬件加速**：使用 Accelerate 框架进行 vDSP/SIMD 音频处理
- **后台音频**：支持锁屏控制的持续播放
- **远程控制**：支持锁屏、控制中心和蓝牙硬件按钮

### 音乐库与内容

- **音乐**：专辑、艺人、歌曲、播放列表，完整浏览和搜索
- **播客**：网格布局浏览剧集
- **电台**：支持网络电台
- **收藏**：红心/收藏媒体
- **添加到音乐库**：搜索并从流媒体服务添加内容
- **排序与视图**：按名称/添加日期排序；专辑与播放列表支持网格/列表切换与网格列数自定义（位于对应分类的视图菜单中）

### 播放与队列

- **多播放器切换**：选择目标播放器发送播放指令
- **远程音量与静音**：远程播放器音量调节与静音切换
- **队列管理**：滑动删除、清空、拖拽排序、"接下来播放"、上下文菜单（与服务端同步）
- **睡眠定时器**：定时或本曲结束后停止
- **歌词**：从服务器获取歌词

### CarPlay

- **标签栏**：主页、音乐库、播放队列、当前播放
- **主页**：继续收听 / 最近播放 / 推荐，点击即播
- **下钻浏览**：艺人 → 专辑 → 歌曲
- **当前播放收藏**：在 CarPlay 直接红心当前曲目
- **模板与图片缓存**：减少返回/重入时的重复加载

### 元数据与缓存

- **本地元数据缓存**：磁盘支持，实现即时音乐库加载（stale-while-revalidate）
- **图片缓存**：内存缓存，使用尺寸感知 URL；加载会话禁用系统代理以保证可用性
- **智能艺术作品**：处理本地（Plex/SMB）与 CDN（Apple Music 等）图片

### 服务器集成

- **mDNS 发现**：自动局域网扫描 Music Assistant 服务器
- **用户名/密码 + 令牌认证**：凭据通过钥匙串安全存储
- **WebSocket 协议**：与 Music Assistant API 的高效实时通信
- **事件驱动更新**：曲库变更、队列更新和播放器状态的实时同步

## 路线图

> 以下为**尚未实现**或**部分实现**的方向，欢迎贡献。

- ⏳ **播放器分组**：部分相关 API 已接入，UI 尚未完善
- ⏳ **Apple Watch 配套应用**：当前为占位界面，尚未接入 WatchConnectivity 中继
- ⏳ **Siri / 媒体意图**："嘿 Siri，播放…" 尚未实现
- ⏳ **有声书**：尚未提供专用视图
- ⏳ **个性化设置页**：外观/主页自定义/标签重排等尚未实现
- ⏳ **Toast 通知**：尚未实现
- ⏳ **iPad 适配**：当前仅在 Mac 上作为 iPad 应用测试

## 系统要求

- **iOS**：17.0 或更高
- **Music Assistant 服务器**：2.x（Schema 28）或更高
- **Sendspin**：服务器上必须启用 Sendspin 播放器提供程序

## 架构

### 设计模式

- **MVVM**：视图、视图模型和数据模型分离
- **SwiftUI**：声明式 UI 框架
- **Combine**：用于状态管理的响应式数据流

### 核心组件

- **SendspinKit**：独立的 Swift Package，实现 Sendspin 协议和音频引擎
  - WebSocket 传输层
  - 基于 AVAudioEngine 的播放
  - 硬件加速音频处理（vDSP/SIMD）
  - 多编解码器支持（PCM、FLAC、Opus）
  - 突发时钟同步
- **XonoraClient**：Music Assistant WebSocket API 客户端（连接、认证、命令、事件）
- **PlayerManager**：播放状态、远程控制、锁屏集成
- **LibraryViewModel / PlayerViewModel**：曲库与播放的视图模型
- **MetadataCache 与 ImageCache**：基于 Actor 的缓存，支持磁盘持久化
- **CarPlaySceneDelegate**：CarPlay 集成，含标签栏、缓存模板和图片缓存

## 版本历史

### 版本 1.0.7（当前）

- 真正删除播放器（`config/players/remove`）、修复重命名（根级 `name`）
- 下拉刷新触发服务器扫描（`music/sync`），扫描完成后自动刷新曲库
- 队列删除/清空/排序与服务端同步
- 当前播放封面加载修复、歌词改用 `metadata/get_track_lyrics`
- 远程播放器静音开关、Web/Universal 播放器图标识别
- CarPlay 主页真实数据、迷你播放条遮挡修复
- 登录界面精简、图片代理端点更新、简体中文翻译修正

### 版本 1.0.6

- 多播放器管理与切换
- 播客和电台支持
- 应用中统一的提供者品牌标识
- 睡眠定时器
- 增强搜索含过滤

### 版本 1.0.5

- mDNS 发现自动扫描服务器
- 硬件音量控制
- 智能艺术作品处理
- 自动重连与指数退避
- 后台音乐库解码

### 版本 1.0.4

- 音乐库 TabView 分类
- 持久化迷你播放器
- 自动播放器选择
- 搜索体验改进与队列修复

### 版本 1.0.3

- 歌曲标签、曲目管理、元数据缓存

## 许可

本项目在 1.0.4 版本之前为开源。此后所有版本均为闭源，仅供个人与 Music Assistant 配合使用。

---

**使用 Xonora 享受你的音乐！**
