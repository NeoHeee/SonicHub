# 音枢 SonicHub

> 多音源智能音箱控制中心

SonicHub 是面向 Android 的智能音箱控制客户端。它将 Songloft、Audiobookshelf、
Subsonic/Navidrome、LXBridge 与音频直链统一为可扩展音源，并通过 Songloft 的
MIoT 插件把内容推送到智能音箱。

## 当前进度

项目处于 `v0.1.0` 第一轮核心链路验证阶段，已经具备：

- Songloft 服务地址和管理员账号配置
- Songloft 健康检查与 Token 登录
- MIoT 音箱设备列表
- HTTP/HTTPS 音频直链投送
- 播放、暂停、停止和音量控制
- Android Keystore 加密保存连接凭据
- GitHub Actions 自动分析、测试和构建 APK

第一轮暂不包含 Songloft 曲库搜索、Audiobookshelf、Navidrome 和 LXBridge，
这些功能将在核心投送链路经真实设备验证后逐步加入。

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
