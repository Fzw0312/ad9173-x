# KU5P AD9173 DAC 上位机

此上位机当前只服务 AD9173 DAC 输出，不包含 AD6688/ADC 接收界面。

## 功能

- CH1/CH2 独立设置启用、幅度和频率。
- 预览 NumPy 或 MATLAB 生成的双通道波形。
- 发送 48 位 FTW 的 DDS 配置到 FPGA。
- 发送 `int16_le_interleaved_ch0_ch1` 波形 DATA，并用 COMMIT 切换 FPGA waveform RAM 播放。
- 保存本地 `.bin` 波形文件。

## 运行

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\run_host_app.py
```

依赖：

```powershell
pip install PyQt5 numpy matplotlib
```

## MATLAB

MATLAB 生成函数：

```text
HostApp/matlab/generate_two_channel_waveform.m
```

GUI 勾选“使用 MATLAB 生成”后，发送波形时会尝试调用 MATLAB Engine for Python。若调用失败，会自动回退到 NumPy 并在日志里提示。

## UDP

默认目标：

```text
FPGA IP: 192.168.1.10
UDP port: 5005
```

协议见：

```text
HostApp/PROTOCOL.md
```

本地回环测试：

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\tools\udp_loopback.py
```

然后把 GUI 的板卡 IP 改为 `127.0.0.1`，点击“UDP 测试”“发送 DDS 配置”或“生成并发送波形”。
