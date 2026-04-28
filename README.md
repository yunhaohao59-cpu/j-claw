# J-Claw

> 跨平台桌面 AI 助手 — 双击安装，填 Key 即用（其实应该还会报错，但我敲下这几行字时已经昏昏欲睡）。



J-Claw 将 [OpenClaw](https://github.com/nicepkg/openclaw) 封装为面向普通用户的桌面应用。不需要命令行、不需要装 Node.js、不需要任何技术背景（理论上是的）——**真正的开箱即用**。

---

## 开发说明

本项目（J-Claw）由 **DeepSeek V4 Pro** 辅助开发。需求分析、架构设计、代码实现、构建脚本、项目文档等均由 AI 在作者指导下完成。

| 项目 | 说明 |
|:---|:---|
| **作者** | 世一帅 |
| **AI 开发工具** | DeepSeek V4 Pro |
| **上游项目** | OpenClaw（MIT 协议） |
| **许可协议** | MIT |

---

## 用户使用流程

```
双击安装包 → 安装完成 → 打开 J-Claw
    → 选择模型提供商（DeepSeek / OpenAI / 自定义）
    → 填入 API Key
    → 自动启动内嵌 Gateway
    → 开始对话
```

---

## 技术架构

```
┌─────────────────────────────────────────┐
│              JavaFX GUI 层               │
│  主界面 / 聊天面板 / 设置面板 / 向导      │
├─────────────────────────────────────────┤
│              Gateway 通信层               │
│  WebSocket ↔ ws://127.0.0.1:18789       │
├─────────────────────────────────────────┤
│              Gateway 管理                 │
│  子进程管理 / 健康检查 / 自动重启         │
├─────────────────────────────────────────┤
│              内嵌运行时                   │
│  Node.js v24 + OpenClaw v2026.4.26      │
└─────────────────────────────────────────┘
```

| 层次 | 技术选择 |
|:---|:---|
| JDK | JDK 25 LTS（虚拟线程、jlink、jpackage） |
| UI | JavaFX 25 (FXML + CSS) |
| HTTP/WebSocket | `java.net.http`（JDK 内置） |
| JSON | 自研轻量解析器 |
| 并发 | 虚拟线程 (Project Loom) |
| Gateway | 内嵌 Node.js + OpenClaw |

---

## 功能

- [x] JavaFX 桌面主界面（暗色主题）
- [x] 流式 AI 对话（实时逐字显示）
- [x] 内嵌 Gateway 管理（启动/停止/健康检查/自动重启）
- [x] WebSocket 通信与设备认证
- [x] 图形化设置面板（提供商/模型/API Key）
- [x] 连接状态指示与自动重连
- [x] 配置兼容 `~/.openclaw/openclaw.json`
- [x] 跨平台构建（Linux / Windows / macOS）
- [ ] 首次启动向导
- [ ] Markdown 渲染
- [ ] 系统托盘

---

## 快速开始（dist目录下有打包好的）

### 前置条件（我记得这些玩意能用到的都让ai打包了的，可能开发需要吧）

- JDK 25+
- JavaFX 25 SDK
- Node.js v24+（可选，可使用内嵌运行时）

### 构建

```bash
# 安装运行时依赖（下载 Node.js + OpenClaw）
./setup-runtime.sh

# 编译并打包
./build.sh compile
./build.sh jar
./build.sh app-image
```

### 运行

```bash
# 从构建目录运行
dist/J-Claw/bin/J-Claw

# 或直接运行 jar
java --module-path /path/to/javafx/lib \
     --add-modules javafx.base,javafx.controls,javafx.fxml,javafx.graphics \
     -jar dist/J-Claw.jar
```

---

## 项目结构

```
j-claw/
├── src/com/jclaw/
│   ├── ui/                    # JavaFX 界面
│   │   ├── JClawApp.java      # Application 入口
│   │   ├── MainController.java # 主界面控制器
│   │   └── SettingsController.java # 设置面板
│   ├── config/                # 配置管理
│   │   ├── ConfigManager.java  # openclaw.json 读写
│   │   └── OpenClawConfig.java # 配置数据模型
│   ├── gateway/               # Gateway 通信
│   │   ├── ClawWebSocket.java  # WebSocket 客户端
│   │   ├── GatewayProcess.java # 子进程管理
│   │   ├── EmbeddedRuntime.java # 内嵌路径解析
│   │   ├── DeviceIdentity.java # 设备身份
│   │   └── DeviceAuthSigner.java # 认证签名
│   ├── chat/                  # 聊天模型
│   │   ├── ChatModel.java
│   │   └── ChatMessage.java
│   └── util/                  # 工具
│       ├── JsonReader.java     # JSON 解析
│       └── JsonWriter.java     # JSON 序列化
├── runtime/                   # 内嵌运行时（由 setup-runtime.sh 生成）
│   ├── node/                  # Node.js 二进制
│   └── openclaw/              # OpenClaw + node_modules
├── config/                    # 启动配置模板
├── build.sh                   # 构建脚本
├── setup-runtime.sh           # 运行时安装脚本
├── LICENSE                    # MIT 许可证
└── README.md
```

---

## 致谢

- [OpenClaw](https://github.com/nicepkg/openclaw) — 上游 AI 助理平台（MIT 协议）
- [DeepSeek](https://deepseek.com/) — AI 开发工具支持
