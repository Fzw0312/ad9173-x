# KU5P AD9173 UDP Protocol v1

当前工程只保留 PC 到 FPGA 的 AD9173 DAC 控制和波形发送协议。所有多字节整数均为 little-endian。

## K5WG UDP 帧头

HostApp 发出的每个 UDP datagram 都以 28 字节 `K5WG` 帧头开始。

| 字段 | 字节数 | 说明 |
| --- | ---: | --- |
| magic | 4 | `K5WG` |
| version | 1 | `1` |
| frame_type | 1 | `1=HELLO`, `2=CONFIG`, `3=DATA`, `4=COMMIT` |
| header_len | 2 | 固定为 `28` |
| sequence | 4 | 主机侧递增序号 |
| flags | 4 | 预留 |
| payload_len | 4 | payload 字节数 |
| payload_crc32 | 4 | payload 的 CRC32 |
| reserved | 4 | 预留 |

FPGA RTL 当前识别目标 IP `192.168.1.10` 或广播地址，UDP 目标端口为 `5005`。

## CONFIG

HostApp 会发送两个 `frame_type=2` 的 CONFIG 帧：

1. UTF-8 JSON 配置，便于 PC 侧记录和以后扩展。当前 FPGA RTL 会忽略此 JSON。
2. FPGA 直接解析的 `K5DC` 二进制配置，用于 NCO-only、JESD 单音和 RAM 波形播放的运行时控制。

`K5DC` payload 总长为 52 字节：

| 偏移 | 字段 | 字节数 | 说明 |
| ---: | --- | ---: | --- |
| `0x00` | magic | 4 | `K5DC` |
| `0x04` | version | 1 | `1` |
| `0x05` | flags | 1 | bit0 复位 DDS 相位；bit1 选择 AD9173 NCO-only；bit2 表示 RAM 波形配置 |
| `0x06` | channel_mask | 2 | DAC0..DAC3 使能位 |
| `0x08` | sample_rate_hz | 4 | FTW 计算使用的采样率 |
| `0x0c` | ftw[4] | 24 | DAC0..DAC3 的 48 位 DDS FTW，每个 `u48` little-endian |
| `0x24` | scale[4] | 8 | DAC0..DAC3 幅度，unsigned Q1.15 |
| `0x2c` | reserved | 4 | 预留 |
| `0x30` | relay_atten_mask | 1 | 4-bit relay attenuation mask: bit0/D9=5 dB, bit1/C11=10 dB, bit2/E11=15 dB, bit3/D11=20 dB |
| `0x31` | output_path_sel | 1 | B9 output path select, 1=RF path, 0=LF path |
| `0x32` | rf_reserved | 2 | 预留 |

HostApp 的 FTW 计算方式：

```text
ftw = round(frequency_hz / sample_rate_hz * 2^48)
```

GUI 只有 CH1/CH2 两个通道时，HostApp 普通 JESD/DDS 输出会把 CH1 映射到内部 DAC0、CH2 映射到内部 DAC2；内部 DAC1/DAC3 静音。RAM 任意波是例外：RF 通路时 CH0 RAM 进内部 DAC0，LF 通路时 CH0 RAM 进内部 DAC1。

JSON 配置中的 `output_mode` 当前支持：

| 值 | 说明 |
| --- | --- |
| `nco_only` | 保持 VIO 校准流程，HostApp 通过 Vivado VIO 写 AD9173 片内 NCO 幅度、FTW、继电器衰减 mask 和输出通路。 |
| `jesd_tone` | UDP `K5DC` 配置 PL DDS 单音，经 JESD 样点输出。 |
| `ram_waveform` | HostApp 发送 `K5DC`、DATA、COMMIT，RTL 切换到 waveform RAM 循环播放。 |

JSON 配置中的 `modulation` 字段只作为 Host 侧记录和调试元数据。AM、FM、PM、ASK、FSK、PSK 波形由 HostApp 预计算为 DATA 帧里的 `int16` 样点；FPGA 不在实时逻辑中计算调制公式，因此不会额外消耗大规模 DSP/LUT 资源。

## DATA

`frame_type=3` 的 DATA 帧用于写 FPGA 内部 waveform RAM。payload 前 20 字节为 chunk 头：

| 字段 | 字节数 | 说明 |
| --- | ---: | --- |
| channel_mask | 2 | 当前固定为 `0x0003` |
| sample_format | 2 | `1=int16_le_interleaved_ch0_ch1` |
| sample_offset | 4 | 本 chunk 的第一个 sample pair 下标 |
| sample_count | 4 | 本 chunk 的 sample pair 数 |
| total_samples | 4 | 整个波形的 sample pair 数 |
| reserved | 4 | 预留 |

剩余 payload 为交织的 signed int16：

```text
ch0[0], ch1[0], ch0[1], ch1[1], ...
```

当前 FPGA waveform RAM 地址宽度为 15，因此最多接收 32768 个 CH0/CH1 sample pair。GUI 的样本点数上限也限制为 32768。

ASK/FSK/PSK 在 HostApp 中按固定 4 个等长码元铺满整段 RAM；码型输入取 4 bit，不再由符号率四舍五入决定码元个数。有效码元率为 `sample_rate_hz * 4 / sample_count`。

## COMMIT

`frame_type=4` 的 COMMIT 帧表示 DATA 发送完成。RTL 看到 COMMIT 后切换到 waveform RAM 播放模式；COMMIT payload 可为 JSON，当前 RTL 不解析其中字段。

## FPGA 侧行为

- 收到有效 `K5DC` CONFIG 后更新 48 位 DDS FTW、幅度、继电器衰减 mask 和 B9 输出选通。flags bit1=1 时通过 AD9173 runtime SPI 切到片内 NCO-only；flags bit2=1 时保持 RAM 播放状态，避免重复/延迟 CONFIG 把输出退回默认 DDS 正弦。
- 收到 DATA 后按 `sample_offset` 写入 waveform RAM。
- 收到 COMMIT 后从 DDS 输出切换到 RAM 波形循环播放。
- RF 通路时 CH0 RAM 波形输出到内部 DAC0；LF 通路时 CH0 RAM 波形输出到内部 DAC1；CH1 RAM 波形保留在内部 DAC2，内部 DAC3 静音。
- VIO apply 会把 AD9173 runtime 控制权切回 VIO 参数，用于保护原有幅度/频率校准流程；UDP `K5DC` apply 会切到 UDP 参数源。
