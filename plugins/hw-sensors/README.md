# 硬件传感器（hw-sensors）

在 WinIsland 灵动岛上实时监控 **CPU、GPU、内存、显存、网卡速度与电源/电池** 状态，支持浅色 / 深色主题自适应、多显卡监控与胶囊形态高度自定义。  
全程使用免管理员通道与可靠开源组件，后续新硬件只需升级底层传感器库即可适配。

[**项目开源主页**](https://github.com/Starry-AXQG/WinLandPlugins-Dev)

---

## 显示形态

### 1. 胶囊形态（紧凑态）
- 默认显示**网卡上传 / 下载速度**，采用胶囊专用紧凑格式（最多 1 位小数，≥ 10 不保留小数，如 `1.1KB/s`、`11KB/s`），同框清晰不滚动。
- 支持在设置中切换为任意硬件的多个子项，或**跨硬件自由组合**（如 `CPU 占用 + CPU 功耗`、`CPU 占用 + 内存占用`）。
- 支持**预分配固定网格容器**（默认开启）：
  - **单行模式**：全局 2 列等宽网格，容器内硬件描述左对齐、数值右对齐，消除位数变化引起的左右抖动。
  - **双行模式**：全局 2×2 四格网格，一屏最多同显 4 项。
  - **超限自动滚动**：勾选数量超出网格容量（单行 > 2 项 / 双行 > 4 项）时自动匀速循环滚动，且每个滚动槽位仍保持固定宽度不抽动。

<center>

![胶囊-light](docs/capsule-light.png)
![胶囊-dark](docs/capsule-dark.png)

</center>

### 2. 卡片形态（悬停展开）
采用无顶部冗余标题的 **3×2 仪表盘网格**，四周留白舒适，实时展示 6 大核心板块：

![卡片-light](docs/card-light.png)

| 板块 | 显示内容 | 视觉反馈 |
| --- | --- | --- |
| **CPU** | 占用率 / 功耗 / 温度 | 蓝色进度条，温度 ≥ 85°C 变暖红警示 |
| **内存** | 占用率 / 功耗 / 温度 | 青色进度条，占用 ≥ 92% 变暖红警示 |
| **网卡** | 上传 `↑` / 下载 `↓` | 固定 3 位有效数字长度（如 `0.12 KB/s`、`12.1 KB/s`、`123 KB/s`） |
| **GPU** | 占用率 / 功耗 / 温度（设置中指定的主显卡） | 天蓝进度条，温度 ≥ 85°C 变暖红警示 |
| **显存** | 占用率 / 功耗 / 温度 | 靛紫进度条，占用 ≥ 92% 变暖红警示 |
| **电源** | 电池电量 / 整机总功耗 | 充电时显示 `⚡`，无电池显示交流供电 |

### 3. 聚光大卡片（点击岛体展开）
点击灵动岛弹出完整仪表盘（带 `● ONLINE` 状态与滚动容器）：
- **CPU 与内存**：处理器型号、已用 / 总物理内存容量及各项实时指标。
- **多显卡监控**：自动展示机器上的**全部显卡**（如独显 + 核显），标注「主卡」徽章，完整呈现 D3D 占用率、核心负载对照、温度、热点温度、功耗以及显存占用 / 容量 / 显存温度。
- **网卡与电源/电池**：当前活动网卡名称与实时速率；整机功耗说明；电池电量、充放电功率、预计充满时间、损耗程度、设计/满充容量与电压。

<center>

![大卡片](docs/spotlight-light.png)

</center>

---

## 数据来源

灵动岛宿主运行于普通用户权限，本插件全程走**免管理员、免驱动安装通道**：

| 指标 | 数据源与算法说明 |
| --- | --- |
| CPU 名称 / 占用率 | LibreHardwareMonitor（WMI 性能计数器） |
| CPU 封装功耗 | Windows PDH `\Energy Meter(*)\Power`（RAPL 能耗计数器） |
| CPU 温度 | Windows PDH `\Thermal Zone Information(*)\High Precision Temperature`（ACPI 热区） |
| 内存占用 / 容量 | LibreHardwareMonitor 物理内存组（`/ram`） |
| 多 GPU 占用率 | LibreHardwareMonitor WDDM `D3D *` 引擎负载最大值（与 Windows 任务管理器算法对齐，无 D3D 传感器时回退 `GPU Core`） |
| 多 GPU 温度 / 热点 / 功耗 / 显存 | LibreHardwareMonitor（NVAPI / ADL / Intel 接口，核显温度自动回退至 `GPU VR SoC`） |
| 网卡上传 / 下载速率 | `.NET NetworkInterface` 字节增量（自动过滤虚拟隧道与重复 WFP/QoS 过滤驱动） |
| 电池容量 / 损耗 / 电压 / 充放功率 | LibreHardwareMonitor 电池组 + `kernel32 GetSystemPowerStatus` |

> **关于台式机 CPU 温度**：普通权限下插件用主板 ACPI 热区作为免驱动兜底，但部分台式机主板 BIOS 不暴露 ACPI 热区。可在插件设置页底部的「台式机 CPU 温度与驱动状态」卡片中**一键安装微软签名的开源驱动 PawnIO**，再以管理员身份重启 WinIsland（或在 WinIsland「通用」设置开启「管理员权限自启动」），即可直接读取精确 CPU 结温（AMD `Tctl/Tdie` / Intel `CPU Package`）。不需要时可随时在设置页**一键卸载 PawnIO** 恢复原状。

**整机总功耗计算方式**：
- **电池供电时**：直接采用电池放电功率（实测值）。
- **交流供电时**：`CPU 功耗 + 全部 GPU 功耗 + 固定基线`（估算值）。基线默认 `8W`，可在设置中按机型微调。

---

## 设置内容

<center>

![设置](docs/settings.png)

</center>

路径：灵动岛设置 → 插件 → **硬件传感器**

- **总开关**：在灵动岛上显示。
- **胶囊形态显示内容**：
  - **硬件类型下拉菜单 + 子项多选框**：支持按类别挑选或跨硬件自由叠加，提供「恢复默认（网速）」与「清空已选」。
  - **为每个显示实例预分配网格容器**：默认开启，固定单行 2 格 / 双行 4 格容器消除数字抖动；关闭后恢复自适应流式排版。
  - **隐藏硬件类型描述文本**：隐藏 `CPU` / `GPU` / `内存` 等文字标签（保留网速 `↑` / `↓` 箭头）。
  - **允许双行显示**：开启后单屏最多固定展示 4 项（建议将字号调小至 `10 ~ 11`）。
  - **胶囊字号**：`8 ~ 18`（步长 `0.5`，默认 `13`），统一作用于胶囊内全部内容。
  - **胶囊左边距 / 右边距**：`0 ~ 30 px`（步长 `1`，默认 `10`），实时微调横向留白。
- **硬件选择**：
  - **主显卡**：选择胶囊与悬停卡片展示的显卡（默认优先独显；聚光大卡片始终展示全部显卡）。
  - **监控网卡**：默认自动汇总活动物理网卡，也可手动指定具体网卡。
- **参数与诊断**：
  - **整机功耗基线**：`0 ~ 200 W`（默认 `8 W`）。
  - **采样间隔**：`500 ~ 30000 ms`（默认 `1000 ms`）。
  - **立即刷新 / 检测数据源**：实时输出所有传感器当前读数，便于排查。

---

## 项目结构

```text
hw-sensors/
├── HwSensors.csproj             # 插件工程文件（net10.0-windows10.0.26100.0，引用 luolan.winland.Core 2.4.0 与 LibreHardwareMonitorLib）
├── global.json                  # 钉住 .NET 10 SDK 版本，确保与宿主运行时投影版本一致
├── plugin.json                  # 插件清单（id、版本、入口 DLL、min_host_version 等元数据）
├── HwSensorsPlugin.cs           # 插件入口（IslandPluginBase）：管理生命周期、设置监听、常驻内容与聚光卡注册
├── HwSensorsView.cs             # 岛上主视图（IMorphView）：胶囊形态（固定网格 / 跑马灯）+ 3×2 卡片形态 + 逐帧过渡动画
├── HwSensorsSpotlightView.cs    # 点击展开的聚光大卡片：多 GPU、CPU、内存、网卡、电源与电池全量仪表盘
├── HwSensorsSettingsPage.cs     # 插件设置页：胶囊显示项组合、网格/双行/字号/边距、显卡与网卡选择、参数与诊断
├── Sensors/
│   ├── SensorService.cs         # 后台独立采样线程：整合 LHM、PDH、NetworkInterface 与系统电源状态
│   ├── SensorSnapshot.cs        # 采样数据模型（SensorSnapshot、GpuSnapshot、SensorOptions、GpuChoice、NicChoice）
│   ├── PdhSet.cs                # 免管理员 Windows PDH 封装（RAPL CPU 封装功耗 + ACPI 热区温度）
│   ├── PawnIoHelper.cs          # 管理员权限与 PawnIO 驱动状态检测，提供官方安装包一键安装与一键卸载
│   └── SpeedFormatter.cs        # 网速格式化工具（卡片 3 位有效数字规则 + 胶囊紧凑格式规则）
├── deploy.ps1                   # 本地一键编译、停宿主、部署到 WinIsland 插件目录脚本
├── logo.png                     # 插件图标
└── README.md                    # 说明文档
```

---

## 安装与开发构建

- **安装**：将打包好的 `.lwp` 文件拖入灵动岛，或在灵动岛「设置 → 插件管理」中安装（要求 **WinIsland ≥ 2.4.0**）。
- **本地构建**：进入 `hw-sensors` 目录后运行（需安装 .NET 10 SDK）：
  ```powershell
  dotnet build -c Release -p:SkipDeploy=true
  ```

---

## 兼容性

- **台式机**：无电池时聚光卡自动隐藏电池明细区，电源板块显示交流供电与整机估算功耗。
- **多显卡笔记本 / 台式机**：自动识别全部 NVIDIA / AMD / Intel 显卡，聚光卡全量展示，悬停卡片可自由切换主卡。
- **数据不可读兜底**：当某项硬件传感器（如内存功耗/温度）在当前主板未暴露时自动显示 `——`，不影响其余指标正常刷新。

---

## 许可

MIT License。底层硬件传感器读取基于 [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)（MPL-2.0）。
