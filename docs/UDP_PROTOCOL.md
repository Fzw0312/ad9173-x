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
2. FPGA 直接解析的 `K5DC` 二进制配置，用于 DDS 模式。

`K5DC` payload 总长为 48 字节：

| 偏移 | 字段 | 字节数 | 说明 |
| ---: | --- | ---: | --- |
| `0x00` | magic | 4 | `K5DC` |
| `0x04` | version | 1 | `1` |
| `0x05` | flags | 1 | bit0 复位 DDS 相位 |
| `0x06` | channel_mask | 2 | DAC0..DAC3 使能位 |
| `0x08` | sample_rate_hz | 4 | FTW 计算使用的采样率 |
| `0x0c` | ftw[4] | 24 | DAC0..DAC3 的 48 位 DDS FTW，每个 `u48` little-endian |
| `0x24` | scale[4] | 8 | DAC0..DAC3 幅度，unsigned Q1.15 |
| `0x2c` | reserved | 4 | 预留 |

HostApp 的 FTW 计算方式：

```text
ftw = round(frequency_hz / sample_rate_hz * 2^48)
```

GUI 只有 CH1/CH2 两个通道时，HostApp 会把 CH1/CH2 镜像到 DAC0/DAC2 和 DAC1/DAC3。

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

当前 FPGA waveform RAM 地址宽度为 12，因此最多接收 4096 个 CH0/CH1 sample pair。GUI 的样本点数上限也限制为 4096。

## COMMIT

`frame_type=4` 的 COMMIT 帧表示 DATA 发送完成。RTL 看到 COMMIT 后切换到 waveform RAM 播放模式；COMMIT payload 可为 JSON，当前 RTL 不解析其中字段。

## FPGA 侧行为

- 收到有效 `K5DC` CONFIG 后更新 48 位 DDS FTW 和幅度，默认保持 DDS 输出。
- 收到 DATA 后按 `sample_offset` 写入 waveform RAM。
- 收到 COMMIT 后从 DDS 输出切换到 RAM 波形循环播放。
- CH0/CH1 RAM 波形会镜像到 DAC2/DAC3，保持四路 DAC 数据都有确定输出。
