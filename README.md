# 音枢 SonicHub

> 多音源智能音箱控制中心

SonicHub 是面向 Android 的智能音箱控制客户端。它将 Songloft、Audiobookshelf、
Subsonic/Navidrome、LXBridge 与音频直链统一为可扩展音源，并通过 Songloft 的
MIoT 插件把内容推送到智能音箱。

## 当前进度

当前版本为 `v0.6.2`，已完成统一首页、音乐曲库、有声书和多音源页面的第一版整合，并增加本机播放：

- 首页统一展示 Songloft、Audiobookshelf 和音频直链的播放上下文
- 音乐页统一管理歌单、曲库层级和歌曲操作菜单
- 有声书页支持书库、继续收听、章节定位和进度回传
- 多音源页集中展示各音源接入状态和入口
- 设备页支持默认音箱、状态刷新和投送反馈
- 设备页支持“本机播放”，可使用手机扬声器或蓝牙音频设备播放
- 全局统一加载、空状态、错误提示和重试反馈
- 固定 Android Release 签名与 GitHub Actions 构建

下载管理、睡眠定时、播放速度和 Subsonic/Navidrome/LXBridge 仍保留为后续扩展，
在对应服务端接口和设备能力具备前不会显示为虚假可用功能。

## 使用要求

- Songloft `2.9.5` 或更高版本
- 已安装并配置
  [songloft-plugin-miot](https://github.com/songloft-org/songloft-plugin-miot)
- Android 8.0 或更高版本（首版目标）
- 音箱可以访问所投送的音频 URL

## 开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

若仓库尚未生成 Android 平台目录：

```bash
flutter create --platforms=android --org com.neo --project-name sonichub .
```

Android 包名规划为 `com.neo.sonichub`，桌面名称为“音枢”。

## 架构原则

- MIoT 插件继续由用户安装在 Songloft 中，SonicHub 不复制插件源码。
- App 通过 Songloft 带认证的插件路由控制音箱。
- 每个音源实现统一适配接口，最终产生可投送的媒体项目。
- 需要 Token 或请求头的音频由后续 Songloft 代理层生成音箱可访问地址。

详细接口结论见 [docs/INTERFACE_COMPATIBILITY.md](docs/INTERFACE_COMPATIBILITY.md)，
版本计划见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 许可与声明

SonicHub 是独立的互操作客户端，与 Songloft、MIoT、小米及相关商标持有人无
官方隶属或背书关系。本项目不包含 MIoT 插件实现及任何第三方账号协议代码。
