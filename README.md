# DSH Desktop

> 面向 macOS（优先）的 DeepSeek Harness 桌面客户端。桌面壳本身也是一个 DSH 插件——**desktop-as-plugin**。

<p align="center"><sub>社区维护的项目，并非 DeepSeek 官方产品。</sub></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-优先-4D6BFE?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/Windows-未验证-9CA3AF?style=flat-square" alt="Windows unverified">
  <img src="https://img.shields.io/badge/version-0.1.0-2EA44F?style=flat-square" alt="version">
</p>

DSH Desktop 把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 Host 服务、插件系统和本地 Web UI 装进原生 Electron 窗口。官方 Harness 以固定版本依赖（`@deepseek-ai/*` `0.1.0-rc.6`）原样运行；Desktop 负责窗口、托盘、工作 profile 切换和打包发布，并通过官方插件机制与 Harness 组合。

## 核心理念

整个桌面应用遵循「一切皆插件」的规则：桌面壳不是写死的外壳，而是一个名为 `desktop-shell` 的 Host 插件，经 `cordis.patch.yml` 拼进 profile 的 patch 栈（插在 `@deepseek-ai/dsh-web-app` 之后），由 Electron 主进程 in-process `boot()` 同一个 Host Cordis root——不 spawn 独立的 `dsh web` 子进程。第三方插件照常按 DSH 规则安装，桌面能力经 `ctx.desktopRuntime` / `ctx.desktopProfiles` 注入，插件不接触 Electron API。

## 特性

- 原生窗口 + 系统托盘（Open / Quit）
- 单实例锁：重复启动自动唤起已有窗口
- 托盘「Profiles」子菜单：列出并切换 DSH profile（选择后 `app.relaunch()`）
- 默认 `desktop` profile 自动初始化（`dsh-base` + `dsh-web-app`）
- `desktopProfiles` Host 服务：供插件只读发现 / 切换 profile
- 兼容模式：loopback web server（`127.0.0.1`）+ `?dsh-desktop-mode=compatibility`
- electron-builder 打包：macOS DMG + ZIP（Windows NSIS + portable 已配置、尚未验证）
- 与 CLI 版 DSH 共享 `~/.dsh`（会话 / 存储 / 凭据 / profile 全共享）

## 架构

| 文件 | 职责 |
| --- | --- |
| `src/main.cjs` | Electron 入口（CommonJS）：单实例锁 → 注入 `desktopRuntime` → `bootHost()` → 挂载窗口 |
| `src/runtime.cjs` | Electron 运行时：BrowserWindow / Tray / 退出 |
| `src/host.js` | 与 Electron 无关的 boot：准备 profile → heal 模块 fallback → 在 `dsh-web-app` 后拼入桌面层 → `boot()` |
| `src/module-resolution.js` | Electron 主进程的 profile-relative 解析钩子（主进程拿不到 Node 内部 ESM loader） |
| `src/index.js` | `desktop-shell` Host 插件：读 `webServer.port`、调度原生窗口 |
| `src/profiles.js` | 只读 profile 发现（`$DSH_HOME/profiles/*`） |
| `src/profile-service.js` | `desktopProfiles` 服务的公开 contract |
| `cordis.patch.yml` | 桌面 Host 操作层：insert `desktop-shell`（compatibility 模式） |

## 下载与安装

### 从源码运行（开发者）

需要 Node.js ≥ 20 与 pnpm；普通用户使用打包产物则无需安装 Node / pnpm。

```sh
git clone https://github.com/Siq5005/dsh-desktop.git
cd dsh-desktop
pnpm install
env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron .   # GUI（macOS）
# 或经 npm launcher：
node scripts/bin.mjs
```

首次启动会创建 `~/.dsh/profiles/desktop`（若不存在），随后在 loopback 端口启动官方 DSH Web UI 并载入原生窗口。

### 打包为安装包

```sh
pnpm install
./node_modules/.bin/electron-builder --mac dir      # 先出未打包 .app 冒烟
./node_modules/.bin/electron-builder --mac dmg zip  # 出 DMG + ZIP
```

产物在 `release/`（`mac-arm64/DSH Desktop.app`、`.dmg`、`.zip`）。发布时把这些产物附到 GitHub Releases 即可分发。

## 使用

| 环境变量 | 作用 |
| --- | --- |
| `DSH_DESKTOP_PROFILE` | 覆盖启动 profile（默认 `desktop`） |
| `DSH_DESKTOP_HEADLESS=1` | 创建并加载窗口但不显示、不建托盘（冒烟用） |
| `DSH_HOME` | 覆盖 DSH 数据目录（默认 `~/.dsh`） |

> 注意：安装后的 app 与 CLI 版 DSH 共用 `~/.dsh`（会话 / 存储 / 凭据 / profile 全共享）；不要与官方桌面 app 同时运行同一 workspace，二者会争用 `~/.dsh/sessions` 与 `storages`。

## 给插件开发者

本仓库同时是一个合法 DSH bundle（`package.json` 声明 `dsh.bundle`），可被 `dsh plugin --profile <name> add` 安装；但 `desktop-shell` 行需要 `desktopRuntime`（由 `dsh-desktop` 启动器注入），普通 `dsh` 启动时该行保持 inactive、自动 no-op。

桌面能力通过两个 Host 服务暴露：

- `desktopRuntime`：窗口 / 托盘调度（由 Electron 启动器注入，第三方插件不应直接依赖）
- `desktopProfiles`：`{ current, list(), select(name) }` —— 只读发现与切换 profile；插件可用 `ctx.inject(['desktopProfiles'])` 读取

contract 见 `src/profile-service.js`。

## 无头验证

```sh
# 组合层冒烟：只校验 profile 组合与 desktop-shell 行挂载
DSH_HOME=/tmp/dsh-desktop-smoke node scripts/smoke-profile.mjs

# 完整 boot 冒烟：in-process boot + web server + desktop-shell 调度 + 拉取页面
DSH_HOME=/tmp/dsh-desktop-boot node scripts/smoke-boot.mjs

# Electron 无头冒烟：真实 Electron 主进程 boot（隐藏窗口）
DSH_HOME=/tmp/dsh-desktop-gui DSH_DESKTOP_HEADLESS=1 \
  env -u ELECTRON_RUN_AS_NODE ./node_modules/.bin/electron .
```

## 已知限制（当前 0.1.0）

- 未签名 / 未公证：本机构建无 Developer ID，macOS 首次打开需右键→打开，或 `xattr -dr com.apple.quarantine "DSH Desktop.app"`
- 托盘图标为占位空图标（真实图标随后续版本补齐）
- Windows 打包配置已就绪但未经真机验证
- 尚未内置自动更新、内置 pnpm、内置终端（node-pty）等高级能力

## 路线图

- Phase 1：完整多 profile 切换 + last-known-good（当前为骨架版：托盘切换 + `profile-selection/state.json` 落盘）
- Phase 2：内置 pnpm + 自动更新（打包本身已完成）
- Phase 3：内置 node-pty 终端 / advanced shell / Windows 特化

## 与官方项目的关系

本项目基于 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 构建，核心的 agent、模型、工具、会话、Web UI 与插件生态均来自官方（以 `@deepseek-ai/*` `0.1.0-rc.6` 固定版本依赖引入，不 fork 上游源码）。本项目只负责桌面封装：窗口、托盘、profile 切换与打包发布。

如需在命令行运行 Harness，或参与核心功能开发，请优先查看官方仓库。

## 致谢与参考

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) —— 上游平台与插件系统
- [anywhere-labs/deepseek-harness-desktop](https://github.com/anywhere-labs/deepseek-harness-desktop) —— desktop-as-plugin 架构的参考实现，本项目的桌面分层思路与启动方式借鉴自该项目
- [Cordis](https://github.com/cordiverse/cordis) —— 插件化基础

## License / 非官方声明

- DeepSeek 是 DeepSeek AI 的商标；DSH Desktop 是独立的社区项目，与 DeepSeek 官方没有隶属关系，也未获得其背书。
- 本项目当前未附加开源许可证；如需使用或分发，请先补充 `LICENSE` 文件。
