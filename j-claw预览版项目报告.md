# J-Claw 预览版项目报告

> **版本**: v0.4.0-e (预览版)
> **日期**: 2026 年 4 月 29 日
> **许可**: MIT

---

## 一、项目概述

### 1.1 项目定位

J-Claw 是一个**跨平台桌面 AI 助手应用**，将 OpenClaw（Node.js/TypeScript 实现的个人 AI 助理平台）封装为面向普通用户的、真正"开箱即用"的桌面应用。用户只需双击安装包 → 填写 API Key → 即可开始与 AI 对话，零技术门槛。

### 1.2 核心竞争力

| 维度 | 说明 |
|:---|:---|
| **零技术门槛** | 不需要命令行、不需要装 Node.js、不需要 npm |
| **打包一切依赖** | JRE + Node.js + OpenClaw 全部内嵌于安装包 |
| **图形化向导** | 首次启动时通过 GUI 引导完成 API 配置 |
| **配置兼容** | 仍然使用 `~/.openclaw/openclaw.json`，CLI 老用户可直接迁移 |
| **跨平台** | 通过 jlink + jpackage 产出 `.deb`、`.msi`、`.dmg` 原生安装包 |

### 1.3 用户使用流程

```
1. 双击安装包 → 系统安装器安装
2. 桌面出现 "J-Claw" 图标 → 双击打开
3. 弹出"欢迎向导"：
   ├── 步骤1: 选择模型提供商（DeepSeek / OpenAI / 自定义）
   ├── 步骤2: 填入 API Key
   ├── 步骤3: 确认配置 → 自动写入 ~/.openclaw/openclaw.json
   └── 步骤4: 自动启动内嵌 Gateway
4. 进入聊天界面 → 开始对话
```

---

## 二、技术架构

### 2.1 整体分层

```
┌─────────────────────────────────────────────────┐
│                 JavaFX GUI 层                     │
│  JClawApp → MainController / SettingsController  │
│  · FXML 布局  · CSS 样式  · 事件绑定             │
├─────────────────────────────────────────────────┤
│                 业务逻辑层                        │
│  ChatModel / ChatMessage                         │
│  ConfigManager / OpenClawConfig                  │
├─────────────────────────────────────────────────┤
│               Gateway 通信层                      │
│  ClawWebSocket (ws://127.0.0.1:18789)            │
│  GatewayProcess (子进程管理)                      │
│  EmbeddedRuntime (内嵌 Node.js 路径解析)          │
│  DeviceAuthSigner / DeviceIdentity                │
├─────────────────────────────────────────────────┤
│                   工具层                          │
│  JsonReader / JsonWriter (自研轻量 JSON 解析)     │
├─────────────────────────────────────────────────┤
│                 外部依赖                          │
│  JDK 25 (java.net.http, 虚拟线程)                │
│  JavaFX 25 (FXML + CSS)                          │
│  内嵌 Node.js + OpenClaw                          │
└─────────────────────────────────────────────────┘
```

### 2.2 运行时架构

```
┌──────────────────────────────────────────────────┐
│                  J-Claw 进程                       │
│  ┌────────────────────────────────────────────┐   │
│  │  JavaFX Application Thread                 │   │
│  │  · UI 渲染  · 事件处理                      │   │
│  ├────────────────────────────────────────────┤   │
│  │  虚拟线程 (Virtual Threads)                 │   │
│  │  · WebSocket 心跳  · Gateway 健康检查       │   │
│  │  · 消息接收处理   · 自动重连                │   │
│  └──────────────┬─────────────────────────────┘   │
│                 │ spawn                            │
│  ┌──────────────┴─────────────────────────────┐   │
│  │  GatewayProcess (子进程)                    │   │
│  │  · openclaw gateway run --port 18789       │   │
│  │  · 异常退出自动重启 (最多 3 次)             │   │
│  │  · 每 5s 健康检查                           │   │
│  └──────────────┬─────────────────────────────┘   │
│                 │                                  │
│  ┌──────────────┴─────────────────────────────┐   │
│  │  内嵌 Node.js 运行时                        │   │
│  │  runtime/node/bin/node                      │   │
│  │  runtime/openclaw/openclaw.mjs              │   │
│  │  runtime/openclaw/node_modules/             │   │
│  └────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### 2.3 WebSocket 通信协议

```
Client (J-Claw)                          Gateway Server
     │                                        │
     ├── connect ────────────────────────────→│
     │   ws://127.0.0.1:18789                │
     │                                        │
     ├── handshake (device auth / token) ────→│
     │   { type: "auth", ... }               │
     │                                        │
     ├── chat.send ──────────────────────────→│
     │   { sessionKey, message,              │
     │     idempotencyKey }                  │
     │                                        │
     │←─ agent event (stream) ───────────────┤
     │   { event: "agent",                   │
     │     payload: { stream: "assistant",   │
     │       data: { text: "..." } } }        │
     │                                        │
     │←─ agent event (lifecycle: end) ───────┤
     │                                        │
     │─ health ping ─────────────────────────→│
     │←─ health pong ────────────────────────┤
```

消息帧格式：
- **请求帧**: `{ type: "req", id, method, params }`
- **响应帧**: `{ type: "res", id, ok, payload }`
- **事件帧**: `{ type: "event", event, payload }`

---

## 三、技术栈

| 层次 | 技术选择 | 说明 |
|:---|:---|:---|
| **JDK** | JDK 25 LTS | 虚拟线程、jlink、jpackage |
| **UI 框架** | JavaFX 25 (FXML) | 硬件加速渲染、CSS 可定制 |
| **HTTP/WebSocket** | `java.net.http` | JDK 内置，零外部依赖 |
| **JSON** | 自研轻量解析 (JsonReader/JsonWriter) | 减少 jar 体积，约 500 行代码 |
| **并发** | 虚拟线程 (Project Loom) | JDK 25 原生支持 |
| **Gateway 运行时** | 内嵌 Node.js v24.15.0 + OpenClaw | 打包进 `runtime/` |
| **构建** | bash 脚本 + jlink + jpackage | 支持 Linux/Windows/macOS 交叉构建 |
| **CSS** | JavaFX CSS (dark.css) | 暗色主题 |

---

## 四、功能清单

### 4.1 已实现功能

| 功能模块 | 状态 | 核心文件 |
|:---|:---|:---|
| **JavaFX 主界面** | ✅ 完成 | [JClawApp.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/ui/JClawApp.java)、[MainController.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/ui/MainController.java) |
| **聊天界面** | ✅ 完成 | 消息气泡显示、流式输出、Markdown 准备中 |
| **Gateway 子进程管理** | ✅ 完成 | [GatewayProcess.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/gateway/GatewayProcess.java) — 启动/停止/健康检查/自动重启 |
| **WebSocket 通信** | ✅ 完成 | [ClawWebSocket.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/gateway/ClawWebSocket.java) — 连接/认证/心跳/RPC |
| **流式消息显示** | ✅ 完成 | 实时逐 token 渲染，Token 计数 |
| **配置管理** | ✅ 完成 | [ConfigManager.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/config/ConfigManager.java) — 读写 `openclaw.json` |
| **设置面板** | ✅ 完成 | [SettingsController.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/ui/SettingsController.java) — 提供商/模型/API Key/端口 |
| **内嵌运行时** | ✅ 完成 | [EmbeddedRuntime.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/gateway/EmbeddedRuntime.java) — Node.js + OpenClaw 路径解析 |
| **设备身份认证** | ✅ 完成 | [DeviceIdentity.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/gateway/DeviceIdentity.java)、[DeviceAuthSigner.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/gateway/DeviceAuthSigner.java) — Ed25519 签名 |
| **连接状态指示** | ✅ 完成 | 状态灯（绿/红）、连接文本、端口检测 |
| **自动重连** | ✅ 完成 | 断线后 3 秒自动重连 |
| **运行时安装脚本** | ✅ 完成 | [setup-runtime.sh](file:///home/umace/工作文档/学期文档/j-claw/setup-runtime.sh) — 自动下载 Node.js 和 OpenClaw |
| **跨平台构建** | ✅ 完成 | [build.sh](file:///home/umace/工作文档/学期文档/j-claw/build.sh) — 支持 jlink + jpackage + 便携版 |
| **CLI 测试工具** | ✅ 完成 | [Launcher.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/Launcher.java)、[ChatTest.java](file:///home/umace/工作文档/学期文档/j-claw/src/com/jclaw/ChatTest.java) |

### 4.2 待完成功能

| 功能模块 | 优先级 | 说明 |
|:---|:---|:---|
| **首次启动向导** | 高 | 图形化引导配置 API Key，替代 CLI onboard |
| **Markdown 渲染** | 高 | 代码块语法高亮、表格、链接 |
| **会话列表** | 中 | 左侧会话列表、新建/切换/删除会话 |
| **系统托盘** | 中 | 最小化到托盘、右键菜单 |
| **自动更新检查** | 低 | 检查 GitHub Release、提示下载 |

---

## 五、源代码结构

```
src/com/jclaw/
├── Launcher.java              # CLI 启动器 (v0.2.0, 第二阶段遗留)
├── ChatTest.java              # WebSocket 功能测试
├── config/
│   ├── ConfigManager.java     # 配置文件读写管理 (openclaw.json)
│   └── OpenClawConfig.java    # 配置数据模型 (Java records)
├── gateway/
│   ├── ClawWebSocket.java     # WebSocket 客户端 (连接/认证/RPC/心跳)
│   ├── ClawCli.java           # openclaw CLI 命令封装
│   ├── GatewayProcess.java    # Gateway 子进程生命周期管理
│   ├── EmbeddedRuntime.java   # 内嵌 Node.js/OpenClaw 路径解析与启动
│   ├── DeviceIdentity.java    # Ed25519 设备身份创建与签名
│   └── DeviceAuthSigner.java  # 设备认证签名器
├── chat/
│   ├── ChatModel.java         # 聊天会话模型 (消息列表/监听器)
│   └── ChatMessage.java       # 单条消息模型 (角色/内容/流式)
├── ui/
│   ├── JClawApp.java          # JavaFX Application 入口
│   ├── MainController.java    # 主界面控制器 (聊天/连接/发送)
│   └── SettingsController.java # 设置面板控制器
└── util/
    ├── JsonReader.java        # 轻量 JSON 解析器 (含注释支持)
    └── JsonWriter.java        # 轻量 JSON 序列化器
```

**总计**: 17 个 Java 源文件，约 3500 行代码（不含自动生成的配置 record）。

---

## 六、架构设计深度分析

### 6.1 OpenClaw 核心架构理解

项目团队对 OpenClaw v2026.4.26 进行了深入的源码逆向分析，产出了两份重要的设计参考文档：

- **[AGENT_ARCHITECTURE.md](file:///home/umace/工作文档/学期文档/j-claw/AGENT_ARCHITECTURE.md)** — Agent 运行时架构深度分析，涵盖：
  - System Prompt 动态组合系统（25+ 模块）
  - Cache Boundary 机制（稳定前缀 vs 动态后缀分离，提升 LLM 缓存命中率）
  - Memory 系统架构（会话级记忆索引、Transcript 归档、向量搜索）
  - Compaction 上下文压缩机制（自动/手动触发、失败处理）
  - 上下文文件注入（agents.md、soul.md、identity.md 等）
  - Prompt 注入防护（Unicode 控制字符清理、路径转义）

- **[COMPETITIVE_ANALYSIS.md](file:///home/umace/工作文档/学期文档/j-claw/COMPETITIVE_ANALYSIS.md)** — OpenClaw 源码竞品分析，涵盖：
  - 整体架构分层（CLI → Gateway → Plugin → Infrastructure）
  - Gateway 通信协议详解
  - 插件系统分析（频道/模型提供商/语音/工具）
  - 配置系统逆向

### 6.2 关键设计决策

| 决策 | 理由 |
|:---|:---|
| **不改 OpenClaw 代码** | J-Claw 作为外壳，OpenClaw 保持原样，易于跟随上游更新 |
| **JDK 内置库优先** | `java.net.http` 处理 WebSocket，避免引入 OkHttp 等外部依赖 |
| **自研 JSON 解析** | 替代 Jackson/Gson，减少 jar 体积约 2-3 MB |
| **虚拟线程** | JDK 25 原生支持，Gateway 健康检查、消息处理均跑在虚拟线程上 |
| **FXML 布局** | 声明式 UI，Controller 与 View 分离 |
| **配置兼容** | 使用与 OpenClaw CLI 完全相同的 `~/.openclaw/openclaw.json` |

---

## 七、构建与打包

### 7.1 构建流程

```
build.sh
├── compile         → javac 编译所有源文件到 build/
├── jar             → 打包为 J-Claw.jar
├── jlink           → 提取 JDK 最小运行时模块
├── app-image       → jpackage 生成原生应用镜像
├── cross           → 交叉构建 Windows/macOS 便携版
│   ├── cross-win   → J-Claw.bat + jre/
│   ├── cross-mac   → J-Claw.command + jre/
│   └── cross-linux → j-claw 启动脚本
└── create-launcher → 生成启动脚本
```

### 7.2 安装包体积估算

| 组件 | 大小 |
|:---|:---|
| 精简 JRE (含 JavaFX) | ~45 MB |
| Node.js 运行时 | ~35 MB |
| OpenClaw + node_modules | ~30 MB |
| J-Claw.jar | ~5 MB |
| **合计** | **~115 MB** |

### 7.3 支持的平台

| 平台 | 架构 | 格式 |
|:---|:---|:---|
| Linux | x86_64 / aarch64 / armv7l | .deb / .rpm / AppImage |
| Windows | x64 | .msi / .exe |
| macOS | x64 / aarch64 | .dmg / .pkg |

---

## 八、开发路线回顾

| 阶段 | 内容 | 状态 |
|:---|:---|:---|
| Phase 1 | 项目骨架 + 配置管理 + JSON 解析 | ✅ 完成 |
| Phase 2 | Gateway 子进程管理 + WebSocket 通信 | ✅ 完成 |
| Phase 3 | JavaFX 主界面 + 聊天面板 | ✅ 完成 |
| Phase 4 | 首次启动向导 | ⏳ 待开发 |
| Phase 5 | 系统托盘 + 状态栏 + 设置面板 | ✅ 完成 (设置面板) / ⏳ (系统托盘) |
| Phase 6 | jlink + jpackage 打包脚本 | ✅ 完成 |
| Phase 7 | 内嵌 Node.js + OpenClaw | ✅ 完成 |

---

## 九、后续展望

| 阶段 | 内容 |
|:---|:---|
| **短期** | 首次启动向导、Markdown 渲染、会话管理完善 |
| **中期** | 发布第一个正式版 v1.0.0，支持主流桌面平台 |
| **远期 1** | Kotlin Multiplatform + Compose 重构，统一移动端与桌面端 |
| **远期 2** | Android App（远程连接 Gateway） |
| **远期 3** | HarmonyOS ArkUI 适配 |

---

## 十、总结

J-Claw 预览版 (v0.4.0-e) 已经完成了**核心骨架的全部搭建**：

- ✅ 完整的三层架构（UI 层 → 通信层 → Gateway 管理）
- ✅ 基于 JDK 25 虚拟线程的高效并发模型
- ✅ 与 OpenClaw Gateway 的稳定 WebSocket 通信
- ✅ 内嵌 Node.js 运行时 + OpenClaw 的完整管理
- ✅ 图形化设置面板
- ✅ 跨平台构建脚本（Linux / Windows / macOS）
- ⏳ 待完善：首次启动向导、Markdown 渲染、系统托盘

项目代码风格清晰，架构设计合理，充分体现了"打包一切、零门槛使用"的核心理念。自研的轻量 JSON 解析器和 JDK 内置库优先的策略有效控制了安装包体积。作为预览版，J-Claw 已经具备基本可用性，完成首次启动向导后即可发布第一个正式版。
