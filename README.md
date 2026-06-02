# KU5P AD9173 DAC UDP Project

这是从 `D:\FPGA\ku5P\ad9173&ad6688` 搬移并瘦身后的 AD9173 工程。当前工作目标是 DAC 输出，不启用 AD6688/ADC 采集链路。

## 目录

- `Prj/`：Vivado RTL、约束、仿真和构建脚本。
- `HostApp/`：Python 上位机，支持 DDS 配置和 MATLAB/NumPy 生成波形后通过 UDP 下发。
- `docs/UDP_PROTOCOL.md`：当前 FPGA/HostApp 使用的 UDP 协议。
- `archive/`：搬移前旧工程内容，以及本次清理移出的 ADC HostApp 文件。

## 当前功能

- AD9173 JESD DAC 输出初始化保留。
- DDS 模式 FTW 已提升到 48 bit。
- UDP `K5WG/K5DC` 可配置 DAC0..DAC3 的 FTW 和幅度。
- UDP DATA/COMMIT 可写入 FPGA waveform RAM，并切换到 RAM 波形循环播放。
- HostApp GUI 只保留 DAC 双通道控制、预览、保存 BIN、发送 DDS 配置和发送波形。

## 运行上位机

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\run_host_app.py
```

依赖：

```powershell
pip install PyQt5 numpy matplotlib
```

MATLAB 生成波形可选；没有 MATLAB Engine 时 HostApp 会自动回退到 NumPy。

## 仿真与构建

协议和波形 RAM 相关仿真在 `Prj/sim` 下。轻量 DAC-only 构建脚本：

```powershell
cd D:\FPGA\ku5P\ad9173-x\Prj
$env:KU5P_BUILD_STAGE="synth"
vivado -mode batch -source .\scripts\build_dac_udp.tcl
```

生成 bitstream 时把 `KU5P_BUILD_STAGE` 改为 `bit` 或直接删除该环境变量。默认输出目录：

```text
D:\FPGA\ku5P\ad9173-x\build\vivado\ad9173_dac_udp\ku5p_vivado
```

烧录脚本：

```powershell
vivado -mode batch -source .\scripts\hw_program_only.tcl
```

旧目录内容没有删除，已归档到：

```text
D:\FPGA\ku5P\ad9173-x\archive\ad9173_x_legacy_20260602_123807
```
