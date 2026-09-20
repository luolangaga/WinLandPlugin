# WinLandPlugin · WinIsland 社区插件市场

WinIsland（Windows 11 灵动岛）的社区插件仓库。

WinIsland 的「设置 → 插件市场」只请求本仓库根目录的 **[index.json](./index.json)**：插件列表、版本、图标
（内嵌 PNG）全在这一个文件里，整个列表**只发一次请求**；只有点「安装」时才下载对应的 `.lwp` 并校验 SHA-256。

清单由 GitHub Action 自动生成，**请勿手改 `index.json` 和下面的表格**。

## 插件清单

<!-- PLUGINS:START -->
| 图标 | 插件（Id） | 版本 | 作者 | 说明 |
| :---: | :--- | :---: | :--- | :--- |
| ![](plugins/hw-monitor/logo.png) | **硬件监控**<br/>`hw-monitor` | 1.0.0 | WinIsland | 常驻硬件信息：小岛显示 CPU/GPU/网络/帧率，大岛显示前台窗口 FPS、CPU、GPU 与上下传速度 |
<!-- PLUGINS:END -->

## 目录结构

```
WinLandPlugin/
├── index.json                  ← 自动生成：客户端唯一数据源（含 sha256 / 体积 / 内嵌图标）
├── README.md                   ← 本文件（插件表格也由 Action 更新）
├── CONTRIBUTING.md             ← 投稿规范
├── tools/
│   ├── build-index.ps1         ← 扫描 plugins/ 生成 index.json + README 表格
│   └── submit-plugin.ps1       ← 作者本地打包 + 校验（一条命令产出待提交目录）
└── plugins/
    └── hw-monitor/             ← 一个插件一个目录，目录名 = 插件 id
        ├── plugin.json         ← 清单（元数据来源，必须与包内那份一致）
        ├── hw-monitor.lwp      ← 插件包（zip 格式，扩展名 .lwp）
        ├── logo.png            ← 可选，建议 240×240 透明 PNG
        └── README.md           ← 可选，详情页展示的说明
```

## 装插件

1. 打开 WinIsland → 设置 → **插件市场**，列表来自本仓库的 `index.json`；
2. 点「安装」→ 客户端下载 `.lwp`、校验 SHA-256、安装并启用；
3. 「详情」里有完整说明、许可证、主页与包哈希；启用/禁用/删除在「插件管理」。

## 投稿插件

见 **[CONTRIBUTING.md](./CONTRIBUTING.md)**。最简流程：

1. 按 WinIsland 插件开发指南（`PLUGIN.md`，SDK 2.0）写好插件并打包成 `.lwp`；
2. `pwsh tools/submit-plugin.ps1 -SourceDir <构建输出目录> -Logo logo.png` 生成 `plugins/<id>/`；
3. Fork 本仓库 → 分支 `add-plugin-<id>` → 提交该目录 → 开 PR。

PR 合并后 Action 会自动重建 `index.json` 与本文件的插件表格，客户端刷新即可看到。

## index.json 格式（schema 1）

| 字段 | 说明 |
|------|------|
| `schema` | 清单格式版本，当前为 `1` |
| `repo` / `updated` / `count` | 仓库名 / 生成时间 / 插件数量 |
| `plugins[]` | 插件条目数组，见下表 |

单条插件：

| 字段 | 说明 |
|------|------|
| `id` | 插件 Id，与目录名、`plugin.json` 一致 |
| `name` / `version` / `description` / `author` | 展示信息 |
| `icon_glyph` | 没有 logo 时的 Segoe 图标字形 |
| `homepage` / `license` / `tags` | 主页 / 许可证 / 标签 |
| `api_version` / `min_host_version` | 兼容性要求，客户端据此禁用不兼容的插件 |
| `package` | 包在仓库内的相对路径 |
| `package_size` / `sha256` | 包大小与哈希，下载后强制校验 |
| `readme` | 说明文件相对路径（详情页按需拉取，列表阶段不请求） |
| `logo` | 原图路径（供浏览器查看） |
| `logo_data` | `data:image/png;base64,…` 缩略图标，随清单一次下发，避免逐插件请求 |
| `updated_at` | 该插件目录最后一次提交时间 |

## 许可

本仓库自身的脚本与文档为 MIT；每个插件的许可见其 `plugin.json` 的 `license` 字段。
