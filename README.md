# 音枢 SonicHub

> 多音源智能音箱控制中心

音枢 SonicHub 是一个面向 Android 的多音源播放与智能音箱控制客户端。它把 Songloft 音乐、Audiobookshelf 有声书和音频直链统一到一个播放上下文中，既可以投送到兼容的智能音箱，也可以直接使用手机扬声器或蓝牙设备播放。

## 项目定位

当前开发版本为 **v0.6.8+18**，在 v0.6.7+17 基础上修复真机有声书播放与章节切换问题：

- 首页统一展示 Songloft、Audiobookshelf 和音频直链的播放上下文
- 音乐页统一管理歌单、曲库层级和歌曲操作菜单
- 有声书页支持书库、继续收听、章节定位和进度回传
- 多音源页集中展示各音源接入状态和入口
- 设备页支持默认音箱、状态刷新和投送反馈
- 设备页支持“本机播放”，可使用手机扬声器或蓝牙音频设备播放
- 全局统一加载、空状态、错误提示和重试反馈
- 固定 Android Release 签名与 GitHub Actions 构建

- 本机播放支持音乐、有声书和音频直链，并可使用手机扬声器或蓝牙设备
- 本机有声书支持音轨内偏移、精确续播和进度拖动
- 智能音箱明确区分章节切换与不支持的音轨内跳转
- 重启后优先恢复有声书或直链播放上下文
- 发布流程使用固定 Android 签名，并通过 GitHub Actions 完成分析、测试、Release APK 构建和签名验证

下载管理、睡眠定时、播放速度以及更多第三方音源仍属于后续扩展，未接入前不会显示为虚假可用功能。

## 使用要求

- Android 8.0 或更高版本；
- Songloft 2.9.5 或更高版本；
- 已在 Songloft 中安装并配置 [songloft-plugin-miot](https://github.com/songloft-org/songloft-plugin-miot)；
- 音箱能够访问所投送的音频地址；
- 使用 Audiobookshelf 时，需要准备服务器地址和 API Key。

## 安装与配置

1. 从 [Releases](https://github.com/NeoHeee/SonicHub/releases) 下载 APK；
2. 安装后进入设置，填写 Songloft 服务地址和账号信息；
3. 在 Songloft 中确认 MIoT 插件已经安装并正常运行；
4. 在“设备”页面选择本机播放或默认智能音箱；
5. 如需播放有声书，在“有声书”页面配置 Audiobookshelf；
6. 使用音频直链时，确认手机或音箱可以访问对应 URL。

账号凭据和 Audiobookshelf API Key 仅用于客户端连接，并通过安全存储保存。请勿在公开 Issue、截图或日志中分享 API Key、Token 和内网地址。

## 开发

环境要求：Flutter stable、Dart SDK 3.4 或更高版本。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

如果仓库尚未生成 Android 平台目录：

```bash
flutter create --platforms=android --org com.neo --project-name sonichub .
```

Android 包名为 `com.neo.sonichub`，应用名称为“音枢”。

## 设计原则

- **统一播放上下文**：音乐、有声书和直链使用一致的播放目标和控制反馈；
- **服务端能力复用**：MIoT 控制由 Songloft 插件提供，客户端不复制插件实现；
- **渐进式接入**：先保证真实可用的登录、播放和设备控制，再扩展下载、定时等能力；
- **安全优先**：连接凭据使用安全存储，服务端 API Key 不写入源码和构建产物；
- **可验证发布**：每个 Android Release 均通过自动分析、测试、签名校验和制品上传。

接口兼容性说明见 [docs/INTERFACE_COMPATIBILITY.md](docs/INTERFACE_COMPATIBILITY.md)，版本计划见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 许可与声明

SonicHub 是独立的互操作客户端，与 Songloft、MIoT、小米及相关商标持有人无官方隶属或背书关系。本项目不包含 MIoT 插件实现，也不包含任何第三方账号协议代码。
