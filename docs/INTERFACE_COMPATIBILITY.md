# Songloft / MIoT 接口兼容清单

检查基线：

- Songloft Swagger：`2.11.0`
- MIoT 插件：`2026.7.30`
- MIoT 最低宿主版本：`2.9.5`

## 访问方式

插件路由通过以下前缀向已认证客户端公开：

```text
{songloftBaseUrl}/api/v1/jsplugin/miot
```

请求携带：

```http
Authorization: Bearer <Songloft access token>
Content-Type: application/json
```

反向代理使用子路径时，用户应把子路径包含在 `songloftBaseUrl` 中。

## 第一轮已接入接口

| 能力 | 方法与插件子路径 | 结论 |
|---|---|---|
| Songloft 健康检查 | `GET /api/v1/health` | 可用 |
| Songloft 登录 | `POST /api/v1/auth/login` | 可用 |
| 获取音箱 | `GET /mina/devices` | 可用 |
| 投送 URL | `POST /mina/play-url` | 可用 |
| 暂停 | `POST /mina/pause` | 可用 |
| 恢复 | `POST /mina/resume` | 可用 |
| 停止 | `POST /mina/stop` | 可用 |
| 音量 | `POST /mina/volume` | 可用 |
| 设备状态 | `GET /mina/status` | 可用 |

控制请求统一需要 `account_id` 与 `device_id`。URL 投送另需 `url`，音量控制
另需 `volume`（0–100）。

## 第二轮待接入

| 能力 | 路径/方向 | 处理建议 |
|---|---|---|
| 实时播放状态 | `/status/ws` | 使用 WebSocket，断线后退化到 1–2 秒 HTTP 轮询 |
| Songloft 曲库搜索 | `/api/v1/songs/*` | 依据 Swagger 建立分页搜索适配 |
| 播放队列 | MIoT playlist handlers | 完整核对请求模型后接入 |
| Token 刷新 | `/api/v1/auth/refresh` | 安全存储 refresh token，401 自动刷新一次 |
| 局域网/公网切换 | 双地址探测 | 并发健康检查，优先局域网 |

## 已知限制

1. 音箱必须能直接访问所投送的 URL；`localhost`、NAS 内部容器地址和需要自定义
   Header 的地址通常不能直接播放。
2. MIoT 状态接口有约 4 秒设备查询缓存，客户端无需高频请求小米云。
3. 设备上报可能短暂返回 `unknown`，客户端应保留最后状态而非清空当前媒体。
4. MIoT 插件更新频繁，SonicHub 应记录兼容基线并持续运行契约测试。
5. 上游 README 的附加使用声明与许可证表述并不完全一致，因此 SonicHub 仅调用
   公开互操作接口，不复制上游插件源码或品牌素材。
