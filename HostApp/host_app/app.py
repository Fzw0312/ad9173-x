import sys
from pathlib import Path
from typing import List

import matplotlib
import numpy as np
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QDoubleSpinBox,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .models import (
    AMPLITUDE_UNITS,
    FREQUENCY_UNITS,
    SAMPLE_RATE_UNITS,
    ChannelSettings,
    NetworkSettings,
    WaveformSettings,
    build_config_payload,
)
from .udp_client import UdpWaveformClient
from .waveform import WaveformGenerator, WaveformResult, estimate_time_axis_unit


matplotlib.rcParams["font.sans-serif"] = [
    "Microsoft YaHei UI",
    "Microsoft YaHei",
    "SimHei",
    "Noto Sans CJK SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False


class ChannelPanel(QGroupBox):
    def __init__(self, title: str, defaults: ChannelSettings):
        super().__init__(title)
        self._amplitude_unit = defaults.amplitude_unit
        self._frequency_unit = defaults.frequency_unit

        self.enable = QCheckBox("启用")
        self.enable.setChecked(defaults.enabled)

        self.amplitude = QDoubleSpinBox()
        self.amplitude.setRange(0.0, 1_000_000.0)
        self.amplitude.setDecimals(6)
        self.amplitude.setValue(defaults.amplitude)
        self.amplitude.setSuffix(" ")
        self.amplitude_unit = QComboBox()
        self.amplitude_unit.addItems(AMPLITUDE_UNITS.keys())
        self.amplitude_unit.setCurrentText(defaults.amplitude_unit)

        self.frequency = QDoubleSpinBox()
        self.frequency.setRange(0.0, 1.0e15)
        self.frequency.setDecimals(6)
        self.frequency.setValue(defaults.frequency)
        self.frequency.setSuffix(" ")
        self.frequency_unit = QComboBox()
        self.frequency_unit.addItems(FREQUENCY_UNITS.keys())
        self.frequency_unit.setCurrentText(defaults.frequency_unit)

        amp_row = QHBoxLayout()
        amp_row.addWidget(self.amplitude, 2)
        amp_row.addWidget(self.amplitude_unit, 1)
        freq_row = QHBoxLayout()
        freq_row.addWidget(self.frequency, 2)
        freq_row.addWidget(self.frequency_unit, 1)

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)
        form.addRow("", self.enable)
        form.addRow("输出幅度", amp_row)
        form.addRow("输出频率", freq_row)
        self.setLayout(form)

    def connect_changed(self, callback) -> None:
        self.enable.toggled.connect(lambda _checked: callback())
        self.amplitude.valueChanged.connect(lambda _value: callback())
        self.frequency.valueChanged.connect(lambda _value: callback())
        self.amplitude_unit.currentTextChanged.connect(self._convert_amplitude_unit)
        self.frequency_unit.currentTextChanged.connect(self._convert_frequency_unit)
        self.amplitude_unit.currentTextChanged.connect(lambda _text: callback())
        self.frequency_unit.currentTextChanged.connect(lambda _text: callback())

    def settings(self) -> ChannelSettings:
        return ChannelSettings(
            enabled=self.enable.isChecked(),
            amplitude=self.amplitude.value(),
            amplitude_unit=self.amplitude_unit.currentText(),
            frequency=self.frequency.value(),
            frequency_unit=self.frequency_unit.currentText(),
        )

    def _convert_amplitude_unit(self, new_unit: str) -> None:
        volts = self.amplitude.value() * AMPLITUDE_UNITS[self._amplitude_unit]
        self.amplitude.blockSignals(True)
        self.amplitude.setValue(volts / AMPLITUDE_UNITS[new_unit])
        self.amplitude.blockSignals(False)
        self._amplitude_unit = new_unit

    def _convert_frequency_unit(self, new_unit: str) -> None:
        hz = self.frequency.value() * FREQUENCY_UNITS[self._frequency_unit]
        self.frequency.blockSignals(True)
        self.frequency.setValue(hz / FREQUENCY_UNITS[new_unit])
        self.frequency.blockSignals(False)
        self._frequency_unit = new_unit


class InteractiveCanvas(FigureCanvas):
    def __init__(self, title: str, color: str):
        self.title = title
        self.color = color
        self.ui_font_size = 13
        self.recommended_xlim = None
        self.recommended_ylim = None
        self._drag_start = None
        self.figure = Figure(figsize=(6.0, 3.1), dpi=100, facecolor="#101722")
        super().__init__(self.figure)
        self.axes = self.figure.add_subplot(111)
        self.mpl_connect("scroll_event", self._on_scroll)
        self.mpl_connect("button_press_event", self._on_button_press)
        self.mpl_connect("button_release_event", self._on_button_release)
        self.mpl_connect("motion_notify_event", self._on_motion)

    def _style_axes(self) -> None:
        self.axes.tick_params(colors="#aab6c5", labelsize=max(8, self.ui_font_size - 2))
        for spine in self.axes.spines.values():
            spine.set_color("#2a3545")
        self.axes.grid(True, color="#253244", linewidth=0.6, alpha=0.8)

    def _save_recommended_view(self) -> None:
        self.recommended_xlim = self.axes.get_xlim()
        self.recommended_ylim = self.axes.get_ylim()

    def reset_recommended_view(self) -> None:
        if self.recommended_xlim is not None:
            self.axes.set_xlim(self.recommended_xlim)
        if self.recommended_ylim is not None:
            self.axes.set_ylim(self.recommended_ylim)
        self.draw_idle()

    def set_ui_font_size(self, font_size: int) -> None:
        self.ui_font_size = int(font_size)
        if self.axes.has_data():
            self.draw_idle()

    def _modifier_axes(self) -> str:
        modifiers = QApplication.keyboardModifiers()
        axes = ""
        if modifiers & Qt.ShiftModifier:
            axes += "x"
        if modifiers & Qt.ControlModifier:
            axes += "y"
        return axes

    def _on_scroll(self, event) -> None:
        if event.inaxes != self.axes or event.xdata is None or event.ydata is None:
            return
        scale = 0.82 if event.button == "up" else 1.22
        mode = self._modifier_axes() or "xy"
        if "x" in mode:
            self._scale_axis("x", event.xdata, scale)
        if "y" in mode:
            self._scale_axis("y", event.ydata, scale)
        self.draw_idle()

    def _scale_axis(self, axis: str, center: float, scale: float) -> None:
        getter = self.axes.get_xlim if axis == "x" else self.axes.get_ylim
        setter = self.axes.set_xlim if axis == "x" else self.axes.set_ylim
        low, high = getter()
        new_low = center - (center - low) * scale
        new_high = center + (high - center) * scale
        if abs(new_high - new_low) > 1e-18:
            setter(new_low, new_high)

    def _on_button_press(self, event) -> None:
        if event.inaxes != self.axes or event.button != 1 or event.xdata is None or event.ydata is None:
            return
        self._drag_start = {
            "xdata": event.xdata,
            "ydata": event.ydata,
            "xlim": self.axes.get_xlim(),
            "ylim": self.axes.get_ylim(),
        }

    def _on_button_release(self, _event) -> None:
        self._drag_start = None

    def _on_motion(self, event) -> None:
        if self._drag_start is None or event.inaxes != self.axes or event.xdata is None or event.ydata is None:
            return
        dx = event.xdata - self._drag_start["xdata"]
        dy = event.ydata - self._drag_start["ydata"]
        x0, x1 = self._drag_start["xlim"]
        y0, y1 = self._drag_start["ylim"]
        self.axes.set_xlim(x0 - dx, x1 - dx)
        self.axes.set_ylim(y0 - dy, y1 - dy)
        self.draw_idle()


class WaveformCanvas(InteractiveCanvas):
    def __init__(self, channel_index: int, title: str, color: str):
        self.channel_index = channel_index
        super().__init__(title, color)
        self.figure.tight_layout(pad=2.0)

    def draw_waveform(self, result: WaveformResult) -> None:
        self.axes.clear()
        self.axes.set_facecolor("#101722")
        x, unit = estimate_time_axis_unit(result.time_s)
        max_points = min(result.volts.shape[0], 1600)
        step = max(1, result.volts.shape[0] // max_points)
        y = result.volts[:, self.channel_index]
        self.axes.plot(x[::step], y[::step], color=self.color, linewidth=1.4)
        self.axes.set_title(self.title, color="#f4f8ff", fontsize=self.ui_font_size + 1, pad=8)
        self.axes.set_xlabel(f"Time ({unit})", color="#aab6c5", fontsize=self.ui_font_size - 1)
        self.axes.set_ylabel("Amplitude (V)", color="#aab6c5", fontsize=self.ui_font_size - 1)
        self._style_axes()
        self.axes.relim()
        self.axes.autoscale_view()
        self._save_recommended_view()
        self.figure.tight_layout(pad=2.0)
        self.draw_idle()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("KU5P AD9173 DAC 双通道上位机")
        self.resize(1120, 720)
        self._sample_rate_unit = "MSPS"
        self.last_result: WaveformResult | None = None
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(180)
        self.preview_timer.timeout.connect(self.update_preview)

        self.ch1 = ChannelPanel("CH1 DAC 输出", ChannelSettings())
        self.ch2 = ChannelPanel("CH2 DAC 输出", ChannelSettings(amplitude=350.0, frequency=30.0))
        self.canvas_ch1 = WaveformCanvas(0, "CH1 预计输出波形", "#3ddc97")
        self.canvas_ch2 = WaveformCanvas(1, "CH2 预计输出波形", "#55a7ff")
        self.log = QTextEdit()
        self.log.setReadOnly(True)

        self._build_controls()
        self._build_layout()
        self._connect_signals()
        self.update_preview()

    def _build_controls(self) -> None:
        self.ip_edit = QLineEdit("192.168.1.10")
        self.local_ip_edit = QLineEdit("")
        self.local_ip_edit.setPlaceholderText("e.g. 169.254.36.237")
        self.port_spin = QSpinBox()
        self.port_spin.setRange(1, 65535)
        self.port_spin.setValue(5005)
        self.local_port_spin = QSpinBox()
        self.local_port_spin.setRange(0, 65535)
        self.local_port_spin.setValue(0)
        self.max_datagram_spin = QSpinBox()
        self.max_datagram_spin.setRange(256, 9000)
        self.max_datagram_spin.setValue(1200)

        self.sample_rate = QDoubleSpinBox()
        self.sample_rate.setRange(0.001, 1.0e12)
        self.sample_rate.setDecimals(6)
        self.sample_rate.setValue(983.04)
        self.sample_rate_unit = QComboBox()
        self.sample_rate_unit.addItems(SAMPLE_RATE_UNITS.keys())
        self.sample_rate_unit.setCurrentText("MSPS")

        self.sample_count = QSpinBox()
        self.sample_count.setRange(256, 4096)
        self.sample_count.setSingleStep(256)
        self.sample_count.setValue(4096)
        self.full_scale = QDoubleSpinBox()
        self.full_scale.setRange(0.001, 1000.0)
        self.full_scale.setDecimals(6)
        self.full_scale.setValue(1.0)
        self.full_scale.setSuffix(" Vpk")
        self.ui_font_size = QSpinBox()
        self.ui_font_size.setRange(10, 22)
        self.ui_font_size.setValue(13)
        self.ui_font_size.setSuffix(" px")

        self.use_matlab = QCheckBox("使用 MATLAB 生成")
        self.use_matlab.setToolTip("需要 MATLAB Engine for Python；不可用时自动回退到 NumPy")

        self.preview_button = QPushButton("刷新预览")
        self.save_button = QPushButton("保存 BIN")
        self.hello_button = QPushButton("UDP 测试")
        self.config_button = QPushButton("发送 DDS 配置")
        self.send_button = QPushButton("生成并发送波形")
        self.reset_ch1_button = QPushButton("复位 CH1 视图")
        self.reset_ch2_button = QPushButton("复位 CH2 视图")
        self.status = QLabel("Ready")
        self.status.setObjectName("status")

    def _build_layout(self) -> None:
        root = QWidget()
        root_layout = QGridLayout(root)
        root_layout.setContentsMargins(18, 18, 18, 18)
        root_layout.setHorizontalSpacing(16)
        root_layout.setVerticalSpacing(16)

        left = QVBoxLayout()
        left.addWidget(self._network_group())
        left.addWidget(self._waveform_group())
        left.addWidget(self.ch1)
        left.addWidget(self.ch2)
        left.addStretch(1)
        left_widget = QWidget()
        left_widget.setLayout(left)
        left_scroll = QScrollArea()
        left_scroll.setWidgetResizable(True)
        left_scroll.setFrameShape(QScrollArea.NoFrame)
        left_scroll.setMinimumWidth(350)
        left_scroll.setMaximumWidth(470)
        left_scroll.setWidget(left_widget)

        right = QVBoxLayout()
        title = QLabel("波形预览")
        title.setObjectName("sectionTitle")
        right.addWidget(title)
        plot_grid = QGridLayout()
        plot_grid.setHorizontalSpacing(12)
        plot_grid.setVerticalSpacing(12)
        plot_grid.addWidget(self._plot_panel(self.canvas_ch1, self.reset_ch1_button), 0, 0)
        plot_grid.addWidget(self._plot_panel(self.canvas_ch2, self.reset_ch2_button), 0, 1)
        plot_grid.setColumnStretch(0, 1)
        plot_grid.setColumnStretch(1, 1)
        right.addLayout(plot_grid, 7)
        right.addWidget(QLabel("运行日志"))
        right.addWidget(self.log, 2)
        right.addWidget(self.status)

        root_layout.addWidget(left_scroll, 0, 0)
        root_layout.addLayout(right, 0, 1)
        root_layout.setColumnStretch(0, 0)
        root_layout.setColumnStretch(1, 1)
        self.setCentralWidget(root)

    def _plot_panel(self, canvas: InteractiveCanvas, reset_button: QPushButton) -> QWidget:
        panel = QWidget()
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        layout.addWidget(canvas, 1)
        layout.addWidget(reset_button)
        return panel

    def _network_group(self) -> QGroupBox:
        group = QGroupBox("UDP 链路")
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)
        form.addRow("板卡 IP", self.ip_edit)
        form.addRow("本机绑定 IP", self.local_ip_edit)
        form.addRow("目标端口", self.port_spin)
        form.addRow("本地端口", self.local_port_spin)
        form.addRow("单包上限", self.max_datagram_spin)
        row = QHBoxLayout()
        row.addWidget(self.hello_button)
        row.addWidget(self.config_button)
        form.addRow("", row)
        group.setLayout(form)
        return group

    def _waveform_group(self) -> QGroupBox:
        group = QGroupBox("DAC 波形参数")
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)
        sr_row = QHBoxLayout()
        sr_row.addWidget(self.sample_rate, 2)
        sr_row.addWidget(self.sample_rate_unit, 1)
        form.addRow("采样率", sr_row)
        form.addRow("样本点数", self.sample_count)
        form.addRow("DAC 满幅", self.full_scale)
        form.addRow("界面字号", self.ui_font_size)
        form.addRow("", self.use_matlab)
        buttons = QHBoxLayout()
        buttons.addWidget(self.preview_button)
        buttons.addWidget(self.save_button)
        buttons.addWidget(self.send_button)
        form.addRow("", buttons)
        group.setLayout(form)
        return group

    def _connect_signals(self) -> None:
        self.ch1.connect_changed(self.queue_preview)
        self.ch2.connect_changed(self.queue_preview)
        self.sample_rate.valueChanged.connect(lambda _value: self.queue_preview())
        self.sample_rate_unit.currentTextChanged.connect(self._convert_sample_rate_unit)
        self.sample_count.valueChanged.connect(lambda _value: self.queue_preview())
        self.full_scale.valueChanged.connect(lambda _value: self.queue_preview())
        self.ui_font_size.valueChanged.connect(self.apply_user_font_size)
        self.preview_button.clicked.connect(self.update_preview)
        self.save_button.clicked.connect(self.save_binary)
        self.hello_button.clicked.connect(self.send_hello)
        self.config_button.clicked.connect(self.send_config)
        self.send_button.clicked.connect(self.send_waveform)
        self.reset_ch1_button.clicked.connect(lambda: self.reset_plot_view(self.canvas_ch1, "CH1"))
        self.reset_ch2_button.clicked.connect(lambda: self.reset_plot_view(self.canvas_ch2, "CH2"))

    def queue_preview(self) -> None:
        self.preview_timer.start()

    def _convert_sample_rate_unit(self, new_unit: str) -> None:
        sample_rate_hz = self.sample_rate.value() * SAMPLE_RATE_UNITS[self._sample_rate_unit]
        self.sample_rate.blockSignals(True)
        self.sample_rate.setValue(sample_rate_hz / SAMPLE_RATE_UNITS[new_unit])
        self.sample_rate.blockSignals(False)
        self._sample_rate_unit = new_unit
        self.queue_preview()

    def channel_settings(self) -> List[ChannelSettings]:
        return [self.ch1.settings(), self.ch2.settings()]

    def waveform_settings(self) -> WaveformSettings:
        return WaveformSettings(
            sample_rate=self.sample_rate.value(),
            sample_rate_unit=self.sample_rate_unit.currentText(),
            sample_count=self.sample_count.value(),
            dac_full_scale_vpk=self.full_scale.value(),
        )

    def network_settings(self) -> NetworkSettings:
        return NetworkSettings(
            target_ip=self.ip_edit.text().strip(),
            target_port=self.port_spin.value(),
            local_port=self.local_port_spin.value(),
            max_datagram_bytes=self.max_datagram_spin.value(),
            local_ip=self.local_ip_edit.text().strip(),
        )

    def generate_waveform(self, allow_matlab: bool) -> WaveformResult:
        generator = WaveformGenerator(
            matlab_enabled=allow_matlab and self.use_matlab.isChecked(),
            matlab_dir=Path(__file__).resolve().parents[1] / "matlab",
        )
        return generator.generate(self.waveform_settings(), self.channel_settings())

    def update_preview(self) -> None:
        result = self.generate_waveform(allow_matlab=False)
        self.last_result = result
        self.canvas_ch1.draw_waveform(result)
        self.canvas_ch2.draw_waveform(result)
        peak = np.max(np.abs(result.volts), axis=0)
        text = f"预览完成: CH1 {peak[0]:.4g} Vpk, CH2 {peak[1]:.4g} Vpk, {result.codes.shape[0]} 点"
        if result.warnings:
            text += " | " + "；".join(result.warnings)
        self.status.setText(text)

    def build_config(self, result: WaveformResult) -> dict:
        return build_config_payload(self.waveform_settings(), self.channel_settings(), result.source)

    def send_hello(self) -> None:
        try:
            frames = UdpWaveformClient(self.network_settings()).send_hello()
            self.append_log(f"UDP 测试包已发送: {frames} 帧")
        except Exception as exc:
            self.append_log(f"UDP 测试失败: {exc}")

    def send_config(self) -> None:
        try:
            result = self.last_result or self.generate_waveform(allow_matlab=False)
            frames = UdpWaveformClient(self.network_settings()).send_config(self.build_config(result))
            self.append_log(f"DDS 配置已发送: {frames} 帧，FTW 为 48 bit")
        except Exception as exc:
            self.append_log(f"DDS 配置发送失败: {exc}")

    def send_waveform(self) -> None:
        try:
            result = self.generate_waveform(allow_matlab=True)
            self.last_result = result
            self.canvas_ch1.draw_waveform(result)
            self.canvas_ch2.draw_waveform(result)
            config = self.build_config(result)

            def progress(done: int, total: int) -> None:
                if done == total or done % 100 == 0:
                    self.status.setText(f"正在发送 DATA 帧 {done}/{total}")
                    QApplication.processEvents()

            frames = UdpWaveformClient(self.network_settings()).send_waveform(config, result.codes, progress)
            warning_text = "；".join(result.warnings)
            suffix = f"，警告: {warning_text}" if warning_text else ""
            self.append_log(f"波形已发送: {frames} 帧，来源 {result.source}{suffix}")
            self.status.setText("发送完成")
        except Exception as exc:
            self.append_log(f"波形发送失败: {exc}")
            self.status.setText("发送失败")

    def save_binary(self) -> None:
        try:
            result = self.last_result or self.generate_waveform(allow_matlab=False)
            path, _ = QFileDialog.getSaveFileName(
                self,
                "保存 DAC 波形 BIN",
                "waveform_ch01_i16.bin",
                "Binary (*.bin)",
            )
            if not path:
                return
            result.codes.astype("<i2", copy=False).tofile(path)
            self.append_log(f"BIN 已保存: {path}")
        except Exception as exc:
            self.append_log(f"保存失败: {exc}")

    def append_log(self, message: str) -> None:
        self.log.append(message)

    def reset_plot_view(self, canvas: InteractiveCanvas, name: str) -> None:
        canvas.reset_recommended_view()
        self.status.setText(f"{name} 已复位到推荐视野")

    def apply_user_font_size(self, _value: int | None = None) -> None:
        font_size = self.ui_font_size.value()
        app = QApplication.instance()
        if app is not None:
            apply_style(app, font_size)
        self.canvas_ch1.set_ui_font_size(font_size)
        self.canvas_ch2.set_ui_font_size(font_size)
        if self.last_result is not None:
            self.canvas_ch1.draw_waveform(self.last_result)
            self.canvas_ch2.draw_waveform(self.last_result)


def apply_style(app: QApplication, font_size: int = 13) -> None:
    title_size = max(font_size + 7, 17)
    input_padding = max(4, round(font_size * 0.46))
    button_padding_y = max(6, round(font_size * 0.62))
    button_padding_x = max(10, round(font_size * 0.92))
    group_padding_top = max(12, round(font_size * 1.08))
    style = """
        QWidget {{
            background: #0b1018;
            color: #dbe6f3;
            font-family: "Microsoft YaHei UI", "Segoe UI", sans-serif;
            font-size: {font_size}px;
        }}
        QGroupBox {{
            border: 1px solid #233044;
            border-radius: 8px;
            margin-top: 12px;
            padding: {group_padding_top}px 12px 12px 12px;
            background: #111925;
        }}
        QGroupBox::title {{
            subcontrol-origin: margin;
            left: 12px;
            padding: 0 6px;
            color: #8fc7ff;
            font-weight: 600;
        }}
        QLabel#sectionTitle {{
            font-size: {title_size}px;
            font-weight: 700;
            color: #f4f8ff;
        }}
        QLabel#status {{
            color: #aab6c5;
            padding: 8px;
            border: 1px solid #233044;
            border-radius: 8px;
            background: #101722;
        }}
        QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox, QTextEdit {{
            background: #0f1722;
            border: 1px solid #2a3545;
            border-radius: 6px;
            padding: {input_padding}px;
            selection-background-color: #2b74c7;
        }}
        QLineEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus, QComboBox:focus {{
            border-color: #55a7ff;
        }}
        QPushButton {{
            background: #1e6fcc;
            border: 1px solid #3183df;
            border-radius: 6px;
            padding: {button_padding_y}px {button_padding_x}px;
            color: white;
            font-weight: 600;
        }}
        QPushButton:hover {{
            background: #277cdc;
        }}
        QPushButton:pressed {{
            background: #175aa6;
        }}
        QCheckBox {{
            spacing: 8px;
        }}
        QCheckBox::indicator {{
            width: 16px;
            height: 16px;
        }}
        QScrollArea {{
            border: none;
        }}
        """
    app.setStyleSheet(
        style.format(
            font_size=font_size,
            group_padding_top=group_padding_top,
            title_size=title_size,
            input_padding=input_padding,
            button_padding_y=button_padding_y,
            button_padding_x=button_padding_x,
        )
    )


def main() -> None:
    app = QApplication(sys.argv)
    apply_style(app)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())
