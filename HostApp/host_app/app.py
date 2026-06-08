import json
import math
import shutil
import subprocess
import sys
from fractions import Fraction
from pathlib import Path
from typing import List

import matplotlib
import numpy as np
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from PyQt5.QtCore import QProcess, QProcessEnvironment, Qt, QTimer
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
    QTableWidget,
    QTableWidgetItem,
    QAbstractItemView,
    QSizePolicy,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .models import (
    AMPLITUDE_UNITS,
    DIGITAL_SYMBOL_COUNT,
    FREQUENCY_UNITS,
    MAX_WAVEFORM_SAMPLES,
    MODULATION_TYPES,
    OUTPUT_MODES,
    OUTPUT_PATHS,
    SAMPLE_RATE_UNITS,
    ChannelSettings,
    ModulationSettings,
    NetworkSettings,
    RfSettings,
    WaveformSettings,
    build_config_payload,
)
from .udp_client import (
    PE43711_STEP_DB,
    UdpRuntimeConfigStreamer,
    UdpWaveformClient,
    build_dac_dds_config_payload,
    calculate_rf_output_control,
)
from .lf_calibration import LfCalibrationTable
from .rf_calibration import RfCalibrationTable
from .waveform import WaveformGenerator, WaveformResult, estimate_time_axis_unit


matplotlib.rcParams["font.sans-serif"] = [
    "Microsoft YaHei UI",
    "Microsoft YaHei",
    "SimHei",
    "Noto Sans CJK SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False


LF_SWEEP_MIN_HZ = 1e-3
LF_SWEEP_MAX_HZ = 10_000_000.0
RF_SWEEP_MIN_HZ = 10_000_000.0
RF_SWEEP_MAX_HZ = 2_000_000_000.0
AD9173_RUNTIME_NCO_HZ = 1_474_561_031.9672773
RF_MAIN_NCO_SHIFT_HZ = 300_000_000.0
JESD_MAIN_NCO_SHIFT_HZ = 450_000_000.0
JESD_MAIN_NCO_IF_HZ = 450_000_000.0
RAM_MAIN_NCO_SHIFT_HZ = 200_000_000.0
RAM_MAIN_NCO_IF_HZ = 200_000_000.0
SWEEP_MAX_POINTS = 20_000
UDP_BROADCAST_TARGETS = {"255.255.255.255", "<broadcast>"}
FPGA_UDP_ACCEPTED_TARGETS = {"192.168.1.10", *UDP_BROADCAST_TARGETS}


def _windows_ipv4_entries() -> list[dict]:
    if sys.platform != "win32":
        return []
    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        (
            "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
            "$OutputEncoding=[System.Text.Encoding]::UTF8; "
            "$ErrorActionPreference='SilentlyContinue'; "
            "Get-NetIPAddress -AddressFamily IPv4 | "
            "Where-Object { $_.AddressState -eq 'Preferred' -and $_.PrefixLength -lt 32 "
            "-and $_.IPAddress -notmatch '^127\\.' } | "
            "Select-Object InterfaceAlias,InterfaceIndex,IPAddress,PrefixLength | ConvertTo-Json -Compress"
        ),
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=2.0,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except Exception:
        return []
    if completed.returncode != 0 or not completed.stdout.strip():
        return []
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return []
    entries = payload if isinstance(payload, list) else [payload]
    return [entry for entry in entries if isinstance(entry, dict)]


def _udp_local_ip_score(entry: dict) -> int:
    ip = str(entry.get("IPAddress", "")).strip()
    alias = str(entry.get("InterfaceAlias", "")).lower()
    score = 0
    if ip.startswith("192.168.1."):
        score += 70
    if ip.startswith("169.254."):
        score += 50
    if "ethernet" in alias or "以太网" in alias:
        score += 80
    elif "local area" in alias and "*" not in alias:
        score += 20
    if "*" in alias or "wi-fi direct" in alias or "virtual" in alias:
        score -= 35
    if "wi-fi" in alias or "wifi" in alias or "wlan" in alias or "wireless" in alias:
        score -= 50
    return score


def _default_udp_local_ip() -> str:
    return _select_udp_local_ip(_windows_ipv4_entries())


def _select_udp_local_ip(entries: list[dict]) -> str:
    candidates: list[tuple[int, str, str]] = []
    for entry in entries:
        ip = str(entry.get("IPAddress", "")).strip()
        if not ip or ip.startswith("127."):
            continue
        candidates.append((_udp_local_ip_score(entry), str(entry.get("InterfaceIndex", "")), ip))
    if not candidates:
        return ""
    candidates.sort(reverse=True)
    return candidates[0][2]


def _udp_local_ip_entry(ip: str, entries: list[dict] | None = None) -> dict | None:
    ip = str(ip).strip()
    if not ip:
        return None
    for entry in _windows_ipv4_entries() if entries is None else entries:
        if str(entry.get("IPAddress", "")).strip() == ip:
            return entry
    return None


def _should_replace_udp_local_ip(
    current_ip: str,
    preferred_ip: str,
    entries: list[dict] | None = None,
) -> bool:
    if not preferred_ip:
        return False
    if not current_ip:
        return True
    if current_ip == preferred_ip:
        return False
    current_entry = _udp_local_ip_entry(current_ip, entries)
    if current_entry is None:
        return True
    current_alias = str(current_entry.get("InterfaceAlias", "")).lower()
    if "*" in current_alias or "wi-fi direct" in current_alias or "virtual" in current_alias:
        return True
    if "wi-fi" in current_alias or "wifi" in current_alias or "wlan" in current_alias or "wireless" in current_alias:
        return True
    if current_ip.startswith("169.254.") and preferred_ip.startswith(("169.254.", "192.168.1.")):
        preferred_entry = _udp_local_ip_entry(preferred_ip, entries) or {}
        return _udp_local_ip_score(current_entry) < _udp_local_ip_score(preferred_entry)
    return False


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
    FIXED_WIDTH_PX = 900
    FIXED_HEIGHT_PX = 430
    DPI = 100

    def __init__(self, title: str, color: str):
        self.title = title
        self.color = color
        self.ui_font_size = 13
        self.recommended_xlim = None
        self.recommended_ylim = None
        self._drag_start = None
        self.figure = Figure(
            figsize=(self.FIXED_WIDTH_PX / self.DPI, self.FIXED_HEIGHT_PX / self.DPI),
            dpi=self.DPI,
            facecolor="#101722",
        )
        super().__init__(self.figure)
        self.setMinimumSize(720, 360)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
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

    def draw_waveform(
        self,
        result: WaveformResult,
        preview_frequency_hz: float | None = None,
        zoom_high_frequency: bool = False,
    ) -> None:
        self.axes.clear()
        self.axes.set_facecolor("#101722")
        x, unit = estimate_time_axis_unit(result.time_s)
        y = result.volts[:, self.channel_index]
        plot_x, plot_y = self._display_envelope(x, y, max_columns=50000)
        self.axes.plot(plot_x, plot_y, color=self.color, linewidth=1.0)
        self.axes.set_title(self.title, color="#f4f8ff", fontsize=self.ui_font_size + 1, pad=8)
        self.axes.set_xlabel(f"Time ({unit})", color="#aab6c5", fontsize=self.ui_font_size - 1)
        self.axes.set_ylabel("Amplitude (V)", color="#aab6c5", fontsize=self.ui_font_size - 1)
        self._style_axes()
        self.axes.relim()
        self.axes.autoscale_view()
        if zoom_high_frequency:
            self._apply_high_resolution_view(x, result.time_s, preview_frequency_hz)
        self._save_recommended_view()
        self.figure.tight_layout(pad=2.0)
        self.draw_idle()

    def _apply_high_resolution_view(
        self,
        x: np.ndarray,
        time_s: np.ndarray,
        preview_frequency_hz: float | None,
    ) -> None:
        sample_count = int(time_s.size)
        if sample_count < 4 or preview_frequency_hz is None or preview_frequency_hz <= 0.0:
            return
        dt = float(time_s[1] - time_s[0])
        if dt <= 0.0 or not np.isfinite(dt):
            return
        sample_rate_hz = 1.0 / dt
        total_cycles = abs(float(preview_frequency_hz)) * sample_count / sample_rate_hz
        if total_cycles < 80.0:
            return
        samples_per_cycle = sample_rate_hz / abs(float(preview_frequency_hz))
        visible_samples = int(round(samples_per_cycle * 18.0))
        visible_samples = max(96, min(2400, visible_samples, sample_count))
        self.axes.set_xlim(float(x[0]), float(x[visible_samples - 1]))

    @staticmethod
    def _display_envelope(x: np.ndarray, y: np.ndarray, max_columns: int) -> tuple[np.ndarray, np.ndarray]:
        sample_count = int(y.shape[0])
        if sample_count <= max_columns:
            return x, y

        bucket_count = max(1, min(int(max_columns), sample_count))
        edges = np.linspace(0, sample_count, bucket_count + 1, dtype=np.int64)
        plot_x = np.empty(bucket_count * 3, dtype=np.float64)
        plot_y = np.empty(bucket_count * 3, dtype=np.float64)
        for index in range(bucket_count):
            start = int(edges[index])
            stop = max(start + 1, int(edges[index + 1]))
            segment = y[start:stop]
            center = x[(start + stop - 1) // 2]
            base = index * 3
            plot_x[base:base + 3] = center
            plot_y[base] = float(np.min(segment))
            plot_y[base + 1] = float(np.max(segment))
            plot_y[base + 2] = np.nan
        return plot_x, plot_y


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("KU5P AD9173 DAC HostApp")
        self.resize(1480, 760)
        self._sample_rate_unit = "MSPS"
        self.last_result: WaveformResult | None = None
        self.loaded_waveform_path: Path | None = None
        self.program_process: QProcess | None = None
        self.vio_process: QProcess | None = None
        self.vio_ready = False
        self.vio_pending_commands: list[tuple[str, str, bool]] = []
        self.vio_startup_quiet = False
        self.rf_calibration = RfCalibrationTable.load_latest(Path(__file__).resolve().parents[2])
        self.lf_calibration = LfCalibrationTable.load_latest(Path(__file__).resolve().parents[2])
        self.preview_timer = QTimer(self)
        self.preview_timer.setSingleShot(True)
        self.preview_timer.setInterval(180)
        self.preview_timer.timeout.connect(self.update_preview)
        self.sweep_timer = QTimer(self)
        self.sweep_timer.setSingleShot(False)
        self.sweep_timer.timeout.connect(self.on_sweep_timer)
        self.sweep_points: list[tuple[str, float]] = []
        self.sweep_index = 0
        self.sweep_running = False
        self.sweep_waiting_for_vio = False
        self.sweep_point_pending = False
        self.sweep_udp_streamer: UdpRuntimeConfigStreamer | None = None

        self.ch1 = ChannelPanel("CH1 DAC 输出", ChannelSettings())
        self.ch2 = ChannelPanel("CH2 DAC 输出", ChannelSettings(amplitude=350.0, frequency=30.0))
        self.canvas_current = WaveformCanvas(0, "当前输出预览", "#3ddc97")
        self.log = QTextEdit()
        self.log.setReadOnly(True)

        self._build_controls()
        self._build_layout()
        self._connect_signals()
        self.update_preview()

    def _build_controls(self) -> None:
        self.ip_edit = QLineEdit("255.255.255.255")
        self.local_ip_edit = QLineEdit(_default_udp_local_ip())
        self.local_ip_edit.setPlaceholderText("auto Ethernet IP, e.g. 169.254.36.237")
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
        self._rf_amplitude_unit = "V"

        self.output_mode = QComboBox()
        for mode_key, mode_label in OUTPUT_MODES.items():
            self.output_mode.addItem(mode_label, mode_key)
        nco_index = self.output_mode.findData("nco_only")
        self.output_mode.setCurrentIndex(nco_index if nco_index >= 0 else 0)
        self.output_mode.setEnabled(True)
        self.output_mode.setToolTip("DDS单音输出走 VIO 配置片内 NCO；任意波形输出使用 UDP DATA/COMMIT")
        self.modulation_type = QComboBox()
        for mod_key, mod_label in MODULATION_TYPES.items():
            self.modulation_type.addItem(mod_label, mod_key)
        self.modulation_type.setCurrentIndex(0)
        self.mod_frequency = QDoubleSpinBox()
        self.mod_frequency.setRange(0.0, 1.0e12)
        self.mod_frequency.setDecimals(6)
        self.mod_frequency.setSingleStep(1.0)
        self.mod_frequency.setValue(120.0)
        self.mod_frequency.setSuffix(" ")
        self.mod_frequency_unit = QComboBox()
        self.mod_frequency_unit.addItems(FREQUENCY_UNITS.keys())
        self.mod_frequency_unit.setCurrentText("kHz")
        self._mod_frequency_unit = "kHz"
        self.am_depth_percent = QDoubleSpinBox()
        self.am_depth_percent.setRange(0.0, 100.0)
        self.am_depth_percent.setDecimals(2)
        self.am_depth_percent.setSingleStep(1.0)
        self.am_depth_percent.setValue(50.0)
        self.am_depth_percent.setSuffix(" %")
        self.fm_deviation = QDoubleSpinBox()
        self.fm_deviation.setRange(0.0, 1.0e12)
        self.fm_deviation.setDecimals(6)
        self.fm_deviation.setSingleStep(0.1)
        self.fm_deviation.setValue(5.0)
        self.fm_deviation.setSuffix(" ")
        self.fm_deviation_unit = QComboBox()
        self.fm_deviation_unit.addItems(FREQUENCY_UNITS.keys())
        self.fm_deviation_unit.setCurrentText("MHz")
        self._fm_deviation_unit = "MHz"
        self.pm_deviation_deg = QDoubleSpinBox()
        self.pm_deviation_deg.setRange(0.0, 180.0)
        self.pm_deviation_deg.setDecimals(2)
        self.pm_deviation_deg.setSingleStep(1.0)
        self.pm_deviation_deg.setValue(90.0)
        self.pm_deviation_deg.setSuffix(" deg")
        self.symbol_rate = QDoubleSpinBox()
        self.symbol_rate.setRange(0.0, 1.0e12)
        self.symbol_rate.setDecimals(6)
        self.symbol_rate.setSingleStep(1.0)
        self.symbol_rate.setValue(120.0)
        self.symbol_rate.setSuffix(" ")
        self.symbol_rate_unit = QComboBox()
        self.symbol_rate_unit.addItems(FREQUENCY_UNITS.keys())
        self.symbol_rate_unit.setCurrentText("kHz")
        self._symbol_rate_unit = "kHz"
        self.ask_low_percent = QDoubleSpinBox()
        self.ask_low_percent.setRange(0.0, 100.0)
        self.ask_low_percent.setDecimals(2)
        self.ask_low_percent.setSingleStep(1.0)
        self.ask_low_percent.setValue(10.0)
        self.ask_low_percent.setSuffix(" %")
        self.fsk_deviation = QDoubleSpinBox()
        self.fsk_deviation.setRange(0.0, 1.0e12)
        self.fsk_deviation.setDecimals(6)
        self.fsk_deviation.setSingleStep(0.1)
        self.fsk_deviation.setValue(5.0)
        self.fsk_deviation.setSuffix(" ")
        self.fsk_deviation_unit = QComboBox()
        self.fsk_deviation_unit.addItems(FREQUENCY_UNITS.keys())
        self.fsk_deviation_unit.setCurrentText("MHz")
        self._fsk_deviation_unit = "MHz"
        self.psk_order = QComboBox()
        self.psk_order.addItem("BPSK", 2)
        self.psk_order.addItem("QPSK", 4)
        self.data_pattern = QLineEdit("1011")
        self.data_pattern.setMaxLength(DIGITAL_SYMBOL_COUNT)
        self.data_pattern.setPlaceholderText("4-symbol pattern, e.g. 1011")
        self.sawtooth_rise_percent = QDoubleSpinBox()
        self.sawtooth_rise_percent.setRange(1.0, 99.0)
        self.sawtooth_rise_percent.setDecimals(2)
        self.sawtooth_rise_percent.setSingleStep(1.0)
        self.sawtooth_rise_percent.setValue(50.0)
        self.sawtooth_rise_percent.setSuffix(" %")
        self.square_duty_percent = QDoubleSpinBox()
        self.square_duty_percent.setRange(0.1, 99.9)
        self.square_duty_percent.setDecimals(2)
        self.square_duty_percent.setSingleStep(1.0)
        self.square_duty_percent.setValue(50.0)
        self.square_duty_percent.setSuffix(" %")
        self.harmonic_spec = QLineEdit("1:1,2:0.30,3:0.15")
        self.harmonic_spec.setPlaceholderText("order:gain[:phase_deg], e.g. 1:1,2:0.3,3:0.15")
        self.harmonic_table = QTableWidget(6, 3)
        self.harmonic_table.setHorizontalHeaderLabels(["阶数", "幅度", "相位deg"])
        self.harmonic_table.verticalHeader().setVisible(False)
        self.harmonic_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.harmonic_table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.harmonic_table.setMinimumHeight(170)
        self.harmonic_table.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        self.harmonic_add_button = QPushButton("添加谐波")
        self.harmonic_remove_button = QPushButton("删除选中")
        self.harmonic_reset_button = QPushButton("复位")
        harmonic_defaults = [(order, 1.0 / order, 0.0) for order in range(1, 7)]
        for row in range(self.harmonic_table.rowCount()):
            order = harmonic_defaults[row][0] if row < len(harmonic_defaults) else row + 1
            gain = harmonic_defaults[row][1] if row < len(harmonic_defaults) else 0.0
            phase = harmonic_defaults[row][2] if row < len(harmonic_defaults) else 0.0
            for column, value in enumerate((order, gain, phase)):
                item = QTableWidgetItem(f"{value:g}")
                self.harmonic_table.setItem(row, column, item)
        self.harmonic_table.resizeColumnsToContents()

        self.output_path = QComboBox()
        for path_key, path_label in OUTPUT_PATHS.items():
            self.output_path.addItem(path_label, path_key)
        self.output_path.setCurrentIndex(0)
        self.rf_target_frequency = QDoubleSpinBox()
        self.rf_target_frequency.setRange(RF_SWEEP_MIN_HZ / 1e6, RF_SWEEP_MAX_HZ / 1e6)
        self.rf_target_frequency.setDecimals(6)
        self.rf_target_frequency.setSingleStep(1.0)
        self.rf_target_frequency.setValue(20.0)
        self.rf_target_frequency.setSuffix(" ")
        self.rf_target_frequency_unit = QComboBox()
        self.rf_target_frequency_unit.addItems(("mHz", "Hz", "kHz", "MHz", "GHz"))
        self.rf_target_frequency_unit.setCurrentText("MHz")
        self._rf_frequency_unit = "MHz"
        self.rf_target_amplitude = QDoubleSpinBox()
        self.rf_target_amplitude.setRange(0.01, 3.0)
        self.rf_target_amplitude.setDecimals(4)
        self.rf_target_amplitude.setSingleStep(0.01)
        self.rf_target_amplitude.setValue(1.0)
        self.rf_target_amplitude.setSuffix(" ")
        self.rf_target_amplitude_unit = QComboBox()
        self.rf_target_amplitude_unit.addItems(("V", "mV"))
        self.rf_target_amplitude_unit.setCurrentText("V")
        self.pe43711_atten_db = QDoubleSpinBox()
        self.pe43711_atten_db.setRange(0.0, 31.75)
        self.pe43711_atten_db.setDecimals(2)
        self.pe43711_atten_db.setSingleStep(0.25)
        self.pe43711_atten_db.setValue(16.0)
        self.pe43711_atten_db.setSuffix(" dB")
        self.pe43711_code = QSpinBox()
        self.pe43711_code.setRange(0, 127)
        self.pe43711_code.setValue(64)
        self.pe43711_code.setPrefix("0x")
        self.pe43711_code.setDisplayIntegerBase(16)
        self.rf_atten_preview = QLabel("PE43711: 16.00 dB, code 0x40")

        self.sample_count = QSpinBox()
        self.sample_count.setRange(256, MAX_WAVEFORM_SAMPLES)
        self.sample_count.setSingleStep(256)
        self.sample_count.setValue(MAX_WAVEFORM_SAMPLES)
        self.full_scale = QDoubleSpinBox()
        self.full_scale.setRange(0.001, 1000.0)
        self.full_scale.setDecimals(6)
        self.full_scale.setValue(1.0)
        self.full_scale.setSuffix(" Vpk")
        self.main_nco_frequency = QLineEdit("0 MHz")
        self.main_nco_frequency.setReadOnly(True)
        self.main_nco_frequency.setToolTip("RF > 300 MHz 时，RTL 只启用 AD9173 main NCO，channel NCO 置零")
        self.ui_font_size = QSpinBox()
        self.ui_font_size.setRange(10, 22)
        self.ui_font_size.setValue(13)
        self.ui_font_size.setSuffix(" px")

        self.use_matlab = QCheckBox("使用 MATLAB 生成")
        self.use_matlab.setToolTip("需要 MATLAB Engine for Python；不可用时自动回退到 NumPy")

        self.preview_button = QPushButton("刷新预览")
        self.load_button = QPushButton("加载 BIN")
        self.text_wave_button = QPushButton("生成汉字 BIN")
        self.save_button = QPushButton("保存 BIN")
        self.hello_button = QPushButton("UDP 测试")
        self.config_button = QPushButton("发送 DDS 配置")
        self.vio_nco_button = QPushButton("VIO 写入")
        self.vio_status_button = QPushButton("VIO 状态")
        self.send_button = QPushButton("发送波形")
        self.sweep_path = QComboBox()
        self.sweep_path.addItem("LF 1mHz-10MHz", "lf")
        self.sweep_path.addItem("RF 10MHz-2GHz", "rf")
        self.sweep_path.addItem("LF+RF 分段", "segmented")
        self.sweep_mode = QComboBox()
        self.sweep_mode.addItem("线性扫频", "linear")
        self.sweep_mode.addItem("对数扫频", "log")
        self.sweep_start = QDoubleSpinBox()
        self.sweep_start.setRange(1e-12, 1.0e12)
        self.sweep_start.setDecimals(6)
        self.sweep_start.setValue(1.0)
        self.sweep_start.setSuffix(" ")
        self.sweep_start_unit = QComboBox()
        self.sweep_start_unit.addItems(FREQUENCY_UNITS.keys())
        self.sweep_start_unit.setCurrentText("mHz")
        self._sweep_start_unit = "mHz"
        self.sweep_stop = QDoubleSpinBox()
        self.sweep_stop.setRange(1e-12, 1.0e12)
        self.sweep_stop.setDecimals(6)
        self.sweep_stop.setValue(10.0)
        self.sweep_stop.setSuffix(" ")
        self.sweep_stop_unit = QComboBox()
        self.sweep_stop_unit.addItems(FREQUENCY_UNITS.keys())
        self.sweep_stop_unit.setCurrentText("MHz")
        self._sweep_stop_unit = "MHz"
        self.sweep_step = QDoubleSpinBox()
        self.sweep_step.setRange(1e-12, 1.0e12)
        self.sweep_step.setDecimals(6)
        self.sweep_step.setValue(1.0)
        self.sweep_step.setSuffix(" ")
        self.sweep_step_unit = QComboBox()
        self.sweep_step_unit.addItems(FREQUENCY_UNITS.keys())
        self.sweep_step_unit.setCurrentText("MHz")
        self._sweep_step_unit = "MHz"
        self.sweep_log_ratio = QDoubleSpinBox()
        self.sweep_log_ratio.setRange(1.000001, 10.0)
        self.sweep_log_ratio.setDecimals(6)
        self.sweep_log_ratio.setSingleStep(0.01)
        self.sweep_log_ratio.setValue(1.1)
        self.sweep_log_ratio.setSuffix(" x")
        self.sweep_dwell_ms = QSpinBox()
        self.sweep_dwell_ms.setRange(5, 600_000)
        self.sweep_dwell_ms.setSingleStep(5)
        self.sweep_dwell_ms.setValue(15)
        self.sweep_dwell_ms.setSuffix(" ms")
        self.sweep_repeat = QCheckBox("循环扫频")
        self.sweep_repeat.setChecked(True)
        self.sweep_amplitude = QDoubleSpinBox()
        self.sweep_amplitude.setRange(0.001, 3.0)
        self.sweep_amplitude.setDecimals(4)
        self.sweep_amplitude.setSingleStep(0.01)
        self.sweep_amplitude.setValue(1.0)
        self.sweep_amplitude.setSuffix(" ")
        self.sweep_amplitude_unit = QComboBox()
        self.sweep_amplitude_unit.addItems(("Vpp", "mVpp"))
        self.sweep_amplitude_unit.setCurrentText("Vpp")
        self.sweep_start_button = QPushButton("开始扫频")
        self.sweep_stop_button = QPushButton("停止")
        self.sweep_step_button = QPushButton("单步")
        self.sweep_reset_button = QPushButton("复位范围")
        self.sweep_status = QLabel("未启动")
        self.bit_path_edit = QLineEdit(str(self.default_bit_path()))
        self.bit_browse_button = QPushButton("选择 bit")
        self.program_bit_button = QPushButton("烧入 bit")
        self.reset_ch1_button = QPushButton("复位当前输出视图")
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
        left.addWidget(self._program_group())
        left.addWidget(self._arbitrary_group())
        left.addWidget(self._nco_sweep_group())
        left.addWidget(self.ch1)
        left.addWidget(self.ch2)
        left.addStretch(1)
        left_widget = QWidget()
        left_widget.setLayout(left)
        left_scroll = QScrollArea()
        left_scroll.setWidgetResizable(True)
        left_scroll.setFrameShape(QScrollArea.NoFrame)
        left_widget.setMinimumWidth(410)
        left_scroll.setMinimumWidth(430)
        left_scroll.setMaximumWidth(560)
        left_scroll.setWidget(left_widget)

        right = QVBoxLayout()
        title = QLabel("参数与预览")
        title.setObjectName("sectionTitle")
        right.addWidget(title)
        plot_grid = QGridLayout()
        plot_grid.setHorizontalSpacing(12)
        plot_grid.setVerticalSpacing(12)
        plot_grid.addWidget(self._waveform_group(), 0, 0, Qt.AlignTop)
        plot_grid.addWidget(self._plot_panel(self.canvas_current, self.reset_ch1_button), 0, 1)
        plot_grid.setColumnStretch(0, 0)
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
        panel.setMinimumWidth(760)
        panel.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        panel.setMinimumHeight(canvas.FIXED_HEIGHT_PX + 46)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        layout.addWidget(canvas)
        reset_button.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
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
        row.addWidget(self.vio_nco_button)
        row.addWidget(self.vio_status_button)
        form.addRow("", row)
        group.setLayout(form)
        return group

    def _program_group(self) -> QGroupBox:
        group = QGroupBox("FPGA 烧录")
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)
        bit_row = QHBoxLayout()
        bit_row.addWidget(self.bit_path_edit, 1)
        bit_row.addWidget(self.bit_browse_button)
        form.addRow("bit 文件", bit_row)
        form.addRow("", self.program_bit_button)
        group.setLayout(form)
        return group

    def _row_widget(self, layout: QHBoxLayout) -> QWidget:
        widget = QWidget()
        widget.setLayout(layout)
        return widget

    def _add_modulation_param_row(self, key: str, label: str, field: QWidget) -> None:
        label_widget = QLabel(label)
        label_widget.setAlignment(Qt.AlignRight | Qt.AlignTop)
        self.modulation_param_rows[key] = (label_widget, field)
        self.modulation_param_order.append(key)

    def _set_modulation_param_rows(self, visible_keys: set[str]) -> None:
        while self.modulation_params_form.rowCount():
            self.modulation_params_form.takeRow(0)
        for key in self.modulation_param_order:
            widgets = self.modulation_param_rows[key]
            visible = key in visible_keys
            for widget in widgets:
                widget.setVisible(visible)
            if visible:
                self.modulation_params_form.addRow(*widgets)

    def _arbitrary_group(self) -> QGroupBox:
        group = QGroupBox("任意波形 / 调制")
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)

        rf_freq_row = QHBoxLayout()
        rf_freq_row.addWidget(self.rf_target_frequency, 2)
        rf_freq_row.addWidget(self.rf_target_frequency_unit, 1)
        rf_amp_row = QHBoxLayout()
        rf_amp_row.addWidget(self.rf_target_amplitude, 2)
        rf_amp_row.addWidget(self.rf_target_amplitude_unit, 1)
        pe_row = QHBoxLayout()
        pe_row.addWidget(self.pe43711_atten_db, 2)
        pe_row.addWidget(self.pe43711_code, 1)

        self.modulation_params = QWidget()
        self.modulation_params.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Maximum)
        self.modulation_params_form = QFormLayout()
        self.modulation_params_form.setContentsMargins(0, 0, 0, 0)
        self.modulation_params_form.setVerticalSpacing(6)
        self.modulation_params_form.setFormAlignment(Qt.AlignTop)
        self.modulation_params_form.setLabelAlignment(Qt.AlignRight | Qt.AlignTop)
        self.modulation_param_rows: dict[str, tuple[QWidget, QWidget]] = {}
        self.modulation_param_order: list[str] = []

        mod_freq_row = QHBoxLayout()
        mod_freq_row.setContentsMargins(0, 0, 0, 0)
        mod_freq_row.addWidget(self.mod_frequency, 2)
        mod_freq_row.addWidget(self.mod_frequency_unit, 1)
        self._add_modulation_param_row("mod_frequency", "调制频率", self._row_widget(mod_freq_row))

        fm_dev_row = QHBoxLayout()
        fm_dev_row.setContentsMargins(0, 0, 0, 0)
        fm_dev_row.addWidget(self.fm_deviation, 2)
        fm_dev_row.addWidget(self.fm_deviation_unit, 1)
        self._add_modulation_param_row("fm_deviation", "FM 频偏", self._row_widget(fm_dev_row))

        symbol_rate_row = QHBoxLayout()
        symbol_rate_row.setContentsMargins(0, 0, 0, 0)
        symbol_rate_row.addWidget(self.symbol_rate, 2)
        symbol_rate_row.addWidget(self.symbol_rate_unit, 1)
        self._add_modulation_param_row("symbol_rate", "符号率", self._row_widget(symbol_rate_row))

        fsk_dev_row = QHBoxLayout()
        fsk_dev_row.setContentsMargins(0, 0, 0, 0)
        fsk_dev_row.addWidget(self.fsk_deviation, 2)
        fsk_dev_row.addWidget(self.fsk_deviation_unit, 1)
        self._add_modulation_param_row("fsk_deviation", "4FSK 频偏", self._row_widget(fsk_dev_row))

        self._add_modulation_param_row("am_depth", "AM 深度", self.am_depth_percent)
        self._add_modulation_param_row("pm_deviation", "PM 相偏", self.pm_deviation_deg)
        self._add_modulation_param_row("ask_low", "4ASK 低电平", self.ask_low_percent)
        self._add_modulation_param_row("psk_order", "4PSK 阶数", self.psk_order)
        self._add_modulation_param_row("data_pattern", "码型", self.data_pattern)
        self._add_modulation_param_row("sawtooth_rise", "上升占比", self.sawtooth_rise_percent)
        self._add_modulation_param_row("square_duty", "占空比", self.square_duty_percent)
        harmonic_widget = QWidget()
        harmonic_widget.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Maximum)
        harmonic_layout = QVBoxLayout(harmonic_widget)
        harmonic_layout.setContentsMargins(0, 0, 0, 0)
        harmonic_layout.setSpacing(6)
        harmonic_layout.addWidget(self.harmonic_table)
        harmonic_button_row = QHBoxLayout()
        harmonic_button_row.setContentsMargins(0, 0, 0, 0)
        harmonic_button_row.addWidget(self.harmonic_add_button)
        harmonic_button_row.addWidget(self.harmonic_remove_button)
        harmonic_button_row.addWidget(self.harmonic_reset_button)
        harmonic_layout.addLayout(harmonic_button_row)
        self._add_modulation_param_row("harmonic_table", "谐波", harmonic_widget)
        self.modulation_params.setLayout(self.modulation_params_form)

        form.addRow("输出模式", self.output_mode)
        form.addRow("输出通路", self.output_path)
        self.target_frequency_label = QLabel("RF 目标频率")
        self.target_amplitude_label = QLabel("RF 目标幅度")
        form.addRow(self.target_frequency_label, rf_freq_row)
        form.addRow(self.target_amplitude_label, rf_amp_row)
        form.addRow("调制类型", self.modulation_type)
        form.addRow(self.modulation_params)
        form.addRow("PE43711", pe_row)
        form.addRow("RF 衰减预览", self.rf_atten_preview)
        form.addRow("", self.use_matlab)
        form.addRow("", self.send_button)
        group.setLayout(form)
        return group

    def _nco_sweep_group(self) -> QGroupBox:
        group = QGroupBox("DDS 扫频 (SPI/UDP)")
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)

        start_row = QHBoxLayout()
        start_row.addWidget(self.sweep_start, 2)
        start_row.addWidget(self.sweep_start_unit, 1)
        stop_row = QHBoxLayout()
        stop_row.addWidget(self.sweep_stop, 2)
        stop_row.addWidget(self.sweep_stop_unit, 1)
        step_row = QHBoxLayout()
        step_row.addWidget(self.sweep_step, 2)
        step_row.addWidget(self.sweep_step_unit, 1)
        amp_row = QHBoxLayout()
        amp_row.addWidget(self.sweep_amplitude, 2)
        amp_row.addWidget(self.sweep_amplitude_unit, 1)
        button_row = QHBoxLayout()
        button_row.addWidget(self.sweep_start_button)
        button_row.addWidget(self.sweep_stop_button)
        button_row.addWidget(self.sweep_step_button)
        button_row.addWidget(self.sweep_reset_button)

        self.sweep_step_row_widget = self._row_widget(step_row)
        form.addRow("通路", self.sweep_path)
        form.addRow("方式", self.sweep_mode)
        form.addRow("起点", self._row_widget(start_row))
        form.addRow("终点", self._row_widget(stop_row))
        self.sweep_step_label = QLabel("线性步进")
        self.sweep_log_ratio_label = QLabel("对数倍率")
        form.addRow(self.sweep_step_label, self.sweep_step_row_widget)
        form.addRow(self.sweep_log_ratio_label, self.sweep_log_ratio)
        form.addRow("驻留", self.sweep_dwell_ms)
        form.addRow("", self.sweep_repeat)
        form.addRow("幅度", self._row_widget(amp_row))
        form.addRow("", self._row_widget(button_row))
        form.addRow("状态", self.sweep_status)
        group.setLayout(form)
        return group

    def _waveform_group(self) -> QGroupBox:
        group = QGroupBox("DAC 波形参数")
        group.setMinimumWidth(330)
        group.setMaximumWidth(370)
        group.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Maximum)
        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight)
        sr_row = QHBoxLayout()
        sr_row.addWidget(self.sample_rate, 2)
        sr_row.addWidget(self.sample_rate_unit, 1)
        form.addRow("采样率", sr_row)
        form.addRow("样本点数", self.sample_count)
        form.addRow("DAC 满幅", self.full_scale)
        form.addRow("Main NCO", self.main_nco_frequency)
        form.addRow("界面字号", self.ui_font_size)
        for button in (self.preview_button, self.load_button, self.text_wave_button, self.save_button):
            button.setMinimumHeight(36)
            button.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        button_grid = QGridLayout()
        button_grid.setHorizontalSpacing(8)
        button_grid.setVerticalSpacing(8)
        button_grid.addWidget(self.preview_button, 0, 0)
        button_grid.addWidget(self.load_button, 0, 1)
        button_grid.addWidget(self.text_wave_button, 1, 0)
        button_grid.addWidget(self.save_button, 1, 1)
        form.addRow("", button_grid)
        group.setLayout(form)
        return group

    def _connect_signals(self) -> None:
        self.ch1.connect_changed(self.queue_preview)
        self.ch2.connect_changed(self.queue_preview)
        self.sample_rate.valueChanged.connect(lambda _value: self.on_waveform_timing_changed())
        self.sample_rate_unit.currentTextChanged.connect(self._convert_sample_rate_unit)
        self.output_mode.currentIndexChanged.connect(self.on_output_mode_changed)
        self.modulation_type.currentIndexChanged.connect(self.on_modulation_type_changed)
        self.mod_frequency.valueChanged.connect(lambda _value: self.queue_preview())
        self.mod_frequency_unit.currentTextChanged.connect(self.on_mod_frequency_unit_changed)
        self.am_depth_percent.valueChanged.connect(lambda _value: self.queue_preview())
        self.fm_deviation.valueChanged.connect(lambda _value: self.queue_preview())
        self.fm_deviation_unit.currentTextChanged.connect(self.on_fm_deviation_unit_changed)
        self.pm_deviation_deg.valueChanged.connect(lambda _value: self.queue_preview())
        self.symbol_rate.valueChanged.connect(lambda _value: self.queue_preview())
        self.symbol_rate_unit.currentTextChanged.connect(self.on_symbol_rate_unit_changed)
        self.ask_low_percent.valueChanged.connect(lambda _value: self.queue_preview())
        self.fsk_deviation.valueChanged.connect(lambda _value: self.queue_preview())
        self.fsk_deviation_unit.currentTextChanged.connect(self.on_fsk_deviation_unit_changed)
        self.psk_order.currentIndexChanged.connect(lambda _index: self.queue_preview())
        self.data_pattern.textChanged.connect(lambda _text: self.queue_preview())
        self.sawtooth_rise_percent.valueChanged.connect(lambda _value: self.queue_preview())
        self.square_duty_percent.valueChanged.connect(lambda _value: self.queue_preview())
        self.harmonic_table.itemChanged.connect(lambda _item: self.on_harmonic_table_changed())
        self.harmonic_add_button.clicked.connect(self.add_harmonic_row)
        self.harmonic_remove_button.clicked.connect(self.remove_selected_harmonic_row)
        self.harmonic_reset_button.clicked.connect(self.reset_harmonics)
        self.output_path.currentIndexChanged.connect(self.on_output_path_changed)
        self.rf_target_frequency.valueChanged.connect(self.on_rf_target_frequency_changed)
        self.rf_target_frequency_unit.currentTextChanged.connect(self.on_rf_target_frequency_unit_changed)
        self.rf_target_amplitude.valueChanged.connect(self.on_rf_target_amplitude_changed)
        self.rf_target_amplitude_unit.currentTextChanged.connect(self.on_rf_target_amplitude_unit_changed)
        self.pe43711_atten_db.valueChanged.connect(self.on_pe43711_atten_changed)
        self.pe43711_code.valueChanged.connect(self.on_pe43711_code_changed)
        self.sample_count.valueChanged.connect(lambda _value: self.on_waveform_timing_changed())
        self.full_scale.valueChanged.connect(lambda _value: self.queue_preview())
        self.ui_font_size.valueChanged.connect(self.apply_user_font_size)
        self.preview_button.clicked.connect(self.update_preview)
        self.load_button.clicked.connect(self.load_binary)
        self.text_wave_button.clicked.connect(self.generate_text_binary)
        self.save_button.clicked.connect(self.save_binary)
        self.hello_button.clicked.connect(self.send_hello)
        self.config_button.clicked.connect(self.send_config)
        self.vio_nco_button.clicked.connect(self.send_vio_nco_config)
        self.vio_status_button.clicked.connect(self.read_vio_status)
        self.send_button.clicked.connect(self.send_waveform)
        self.sweep_path.currentIndexChanged.connect(self.on_sweep_path_changed)
        self.sweep_mode.currentIndexChanged.connect(self.on_sweep_mode_changed)
        self.sweep_start_unit.currentTextChanged.connect(self.on_sweep_start_unit_changed)
        self.sweep_stop_unit.currentTextChanged.connect(self.on_sweep_stop_unit_changed)
        self.sweep_step_unit.currentTextChanged.connect(self.on_sweep_step_unit_changed)
        self.sweep_start_button.clicked.connect(self.start_nco_sweep)
        self.sweep_stop_button.clicked.connect(self.stop_nco_sweep)
        self.sweep_step_button.clicked.connect(self.single_step_nco_sweep)
        self.sweep_reset_button.clicked.connect(self.reset_sweep_range)
        self.bit_browse_button.clicked.connect(self.choose_bit_file)
        self.program_bit_button.clicked.connect(self.program_bitstream)
        self.reset_ch1_button.clicked.connect(lambda: self.reset_plot_view(self.canvas_current, "当前输出"))
        self.reset_ch2_button.setVisible(False)
        self.on_output_mode_changed()
        self.update_output_path_controls()
        self.update_sweep_controls()
        self.on_rf_target_frequency_changed(self.rf_target_frequency.value())

    def queue_preview(self) -> None:
        self.preview_timer.start()

    def on_waveform_timing_changed(self) -> None:
        self.update_effective_symbol_rate_display()
        self.queue_preview()

    def update_output_path_controls(self) -> None:
        is_lf = self.output_path_key() == "lf"
        self.target_frequency_label.setText("LF/DAC1 目标频率" if is_lf else "RF 目标频率")
        self.target_amplitude_label.setText("LF/DAC1 目标幅度" if is_lf else "RF 目标幅度")
        current_hz = self.rf_target_frequency.value() * FREQUENCY_UNITS[self._rf_frequency_unit]
        self.rf_target_frequency.blockSignals(True)
        self.rf_target_frequency_unit.blockSignals(True)
        if is_lf:
            current_hz = max(1e-3, min(current_hz, 10_000_000.0))
            unit = self._rf_frequency_unit
            if unit not in FREQUENCY_UNITS:
                unit = "MHz"
            self.rf_target_frequency_unit.setCurrentText(unit)
            self._rf_frequency_unit = unit
            self.rf_target_frequency.setRange(1e-3 / FREQUENCY_UNITS[unit], 10_000_000.0 / FREQUENCY_UNITS[unit])
            self.rf_target_frequency.setValue(current_hz / FREQUENCY_UNITS[unit])
        else:
            current_hz = max(RF_SWEEP_MIN_HZ, min(current_hz, RF_SWEEP_MAX_HZ))
            unit = self._rf_frequency_unit
            if unit not in FREQUENCY_UNITS:
                unit = "MHz"
            self.rf_target_frequency_unit.setCurrentText(unit)
            self._rf_frequency_unit = unit
            self.rf_target_frequency.setRange(
                RF_SWEEP_MIN_HZ / FREQUENCY_UNITS[unit],
                RF_SWEEP_MAX_HZ / FREQUENCY_UNITS[unit],
            )
            self.rf_target_frequency.setValue(current_hz / FREQUENCY_UNITS[unit])
        self.rf_target_frequency_unit.blockSignals(False)
        self.rf_target_frequency.blockSignals(False)
        self.update_main_nco_display()

    def update_effective_symbol_rate_display(self) -> None:
        sample_rate_hz = self.waveform_settings().sample_rate_hz()
        sample_count = max(int(self.sample_count.value()), 1)
        symbol_rate_hz = sample_rate_hz * DIGITAL_SYMBOL_COUNT / sample_count
        unit = self.symbol_rate_unit.currentText()
        self.symbol_rate.blockSignals(True)
        self.symbol_rate.setValue(symbol_rate_hz / FREQUENCY_UNITS[unit])
        self.symbol_rate.blockSignals(False)

    def _convert_sample_rate_unit(self, new_unit: str) -> None:
        sample_rate_hz = self.sample_rate.value() * SAMPLE_RATE_UNITS[self._sample_rate_unit]
        self.sample_rate.blockSignals(True)
        self.sample_rate.setValue(sample_rate_hz / SAMPLE_RATE_UNITS[new_unit])
        self.sample_rate.blockSignals(False)
        self._sample_rate_unit = new_unit
        self.on_waveform_timing_changed()

    def active_output_channel_index(self) -> int:
        return 0

    def sync_target_to_output_channel(self) -> None:
        target_panel = self.ch2 if self.output_path_key() == "lf" else self.ch1
        target_panel.enable.blockSignals(True)
        target_panel.enable.setChecked(True)
        target_panel.enable.blockSignals(False)
        target_panel.frequency.blockSignals(True)
        target_panel.frequency.setValue(self.rf_target_frequency.value())
        target_panel.frequency.blockSignals(False)
        target_panel.frequency_unit.blockSignals(True)
        target_panel.frequency_unit.setCurrentText(self.rf_target_frequency_unit.currentText())
        target_panel.frequency_unit.blockSignals(False)
        target_panel._frequency_unit = self.rf_target_frequency_unit.currentText()
        target_panel.amplitude.blockSignals(True)
        target_panel.amplitude.setValue(self.rf_settings().target_amplitude_vpk)
        target_panel.amplitude.blockSignals(False)
        target_panel.amplitude_unit.blockSignals(True)
        target_panel.amplitude_unit.setCurrentText("V")
        target_panel.amplitude_unit.blockSignals(False)
        target_panel._amplitude_unit = "V"

    def channel_settings(self) -> List[ChannelSettings]:
        ch1 = self.ch1.settings()
        ch2 = self.ch2.settings()
        target_channel = ch1
        target_channel.enabled = True
        target_channel.frequency = self.rf_target_frequency.value()
        target_channel.frequency_unit = self.rf_target_frequency_unit.currentText()
        target_channel.amplitude = self.rf_settings().target_amplitude_vpk
        target_channel.amplitude_unit = "V"
        if self.output_path_key() == "lf":
            ch2.enabled = False
            ch2.frequency = target_channel.frequency
            ch2.frequency_unit = target_channel.frequency_unit
            ch2.amplitude = 0.0
            ch2.amplitude_unit = "V"
        else:
            ch2.enabled = False
            ch2.amplitude = 0.0
            ch2.amplitude_unit = "V"
        return [ch1, ch2]

    def waveform_channel_settings_for_mode(self, output_mode: str) -> List[ChannelSettings]:
        channels = self.channel_settings()
        if output_mode == "ram_waveform" and channels and self.output_path_key() == "rf":
            target_hz = self.rf_target_frequency_hz()
            if_hz, main_hz = self.ram_rf_plan_for(output_mode, self.output_path_key(), target_hz)
            channels[0].frequency = if_hz
            channels[0].frequency_unit = "Hz"
        return channels

    def output_mode_key(self) -> str:
        return str(self.output_mode.currentData() or "jesd_tone")

    def output_path_key(self) -> str:
        return str(self.output_path.currentData() or "rf")

    def rf_settings(self) -> RfSettings:
        code = max(0, min(int(self.pe43711_code.value()), 127))
        atten_db = code * PE43711_STEP_DB
        return RfSettings(
            output_path=self.output_path_key(),
            target_amplitude_vpk=self.rf_target_amplitude_vpp() / 2.0,
            pe43711_atten_db=atten_db,
            pe43711_code=code,
        )

    def rf_target_amplitude_vpp(self) -> float:
        unit_scale = 1e-3 if self.rf_target_amplitude_unit.currentText() == "mV" else 1.0
        return self.rf_target_amplitude.value() * unit_scale

    def rf_target_frequency_hz(self) -> float:
        return self.rf_target_frequency.value() * FREQUENCY_UNITS[self.rf_target_frequency_unit.currentText()]

    def payload_nyquist_hz(self) -> float:
        return 0.5 * self.waveform_settings().sample_rate_hz()

    def predistortion_safe_hz(self) -> float:
        return 0.5 * self.payload_nyquist_hz()

    def main_nco_if_hz_for(self, requested_if_hz: float) -> float:
        nyquist_hz = self.payload_nyquist_hz()
        margin_hz = max(1.0, nyquist_hz - 1.0)
        return max(1.0, min(float(requested_if_hz), margin_hz))

    def rf_main_nco_hz_for(self, path_key: str, frequency_hz: float) -> float:
        if path_key != "rf":
            return 0.0
        frequency_hz = float(frequency_hz)
        return frequency_hz if frequency_hz > RF_MAIN_NCO_SHIFT_HZ else 0.0

    def active_main_nco_hz_for(self, output_mode: str, path_key: str, frequency_hz: float) -> float:
        if path_key != "rf":
            return 0.0
        if output_mode == "nco_only":
            return self.rf_main_nco_hz_for(path_key, frequency_hz)
        if output_mode == "jesd_tone":
            _if_hz, main_hz = self.jesd_rf_plan_for(output_mode, path_key, frequency_hz)
            return main_hz
        if output_mode == "ram_waveform":
            _if_hz, main_hz = self.ram_rf_plan_for(output_mode, path_key, frequency_hz)
            return main_hz
        return 0.0

    def jesd_rf_plan_for(self, output_mode: str, path_key: str, frequency_hz: float) -> tuple[float, float]:
        if output_mode != "jesd_tone" or path_key != "rf":
            return float(frequency_hz), 0.0
        frequency_hz = float(frequency_hz)
        if frequency_hz <= self.payload_nyquist_hz():
            return frequency_hz, 0.0
        if_hz = self.main_nco_if_hz_for(min(JESD_MAIN_NCO_IF_HZ, max(1.0, frequency_hz)))
        return if_hz, frequency_hz - if_hz

    def ram_rf_plan_for(self, output_mode: str, path_key: str, frequency_hz: float) -> tuple[float, float]:
        if output_mode != "ram_waveform" or path_key != "rf":
            return float(frequency_hz), 0.0
        frequency_hz = float(frequency_hz)
        if frequency_hz <= RAM_MAIN_NCO_SHIFT_HZ:
            return self.coherent_ram_frequency_hz(frequency_hz), 0.0
        requested_if_hz = self.main_nco_if_hz_for(min(RAM_MAIN_NCO_IF_HZ, max(1.0, frequency_hz)))
        if_hz = self.coherent_ram_frequency_hz(requested_if_hz)
        main_hz = frequency_hz - if_hz
        if main_hz <= 0.0:
            return frequency_hz, 0.0
        return if_hz, main_hz

    def coherent_ram_frequency_hz(self, requested_hz: float) -> float:
        settings = self.waveform_settings()
        sample_rate_hz = settings.sample_rate_hz()
        sample_count = max(int(settings.sample_count), 1)
        bin_hz = sample_rate_hz / sample_count
        max_cycles = max(sample_count // 2, 1)
        cycles = int(round(max(0.0, float(requested_hz)) / max(bin_hz, 1e-12)))
        cycles = max(1, min(cycles, max_cycles))
        return cycles * bin_hz

    def update_main_nco_display(self) -> None:
        freq_hz = self.rf_target_frequency_hz()
        main_hz = self.active_main_nco_hz_for(self.output_mode_key(), self.output_path_key(), freq_hz)
        self.main_nco_frequency.setText(self.format_frequency_hz(main_hz))

    def active_output_channel(self) -> ChannelSettings:
        channels = self.channel_settings()
        index = min(self.active_output_channel_index(), len(channels) - 1)
        return channels[index]

    def preview_frequency_hz(self) -> float:
        return self.active_output_channel().frequency_hz()

    def waveform_preview_frequency_hz(self) -> float:
        if self.output_mode_key() == "ram_waveform" and self.output_path_key() == "rf":
            if_hz, _main_hz = self.ram_rf_plan_for(
                "ram_waveform",
                "rf",
                self.rf_target_frequency_hz(),
            )
            return if_hz
        return self.preview_frequency_hz()

    def display_preview_frequency_hz(self) -> float:
        if self.modulation_settings_for_mode(self.output_mode_key()).modulation_type == "sine":
            return self.rf_target_frequency_hz()
        return self.waveform_preview_frequency_hz()

    def should_zoom_high_frequency_preview(self) -> bool:
        modulation = self.modulation_settings_for_mode(self.output_mode_key())
        return modulation.modulation_type not in {"ask", "fsk", "psk"}

    def modulation_settings(self) -> ModulationSettings:
        return self.modulation_settings_for_mode(self.output_mode_key())

    @staticmethod
    def parse_table_number(text: str) -> float:
        text = str(text).strip()
        if "/" in text:
            return float(Fraction(text))
        return float(text)

    def harmonic_spec_from_table(self) -> str:
        entries: list[str] = []
        for row in range(self.harmonic_table.rowCount()):
            try:
                order_item = self.harmonic_table.item(row, 0)
                gain_item = self.harmonic_table.item(row, 1)
                phase_item = self.harmonic_table.item(row, 2)
                order = int(self.parse_table_number(order_item.text())) if order_item and order_item.text().strip() else 0
                gain = self.parse_table_number(gain_item.text()) if gain_item and gain_item.text().strip() else 0.0
                phase = self.parse_table_number(phase_item.text()) if phase_item and phase_item.text().strip() else 0.0
            except (ValueError, ZeroDivisionError):
                continue
            if order <= 0 or abs(gain) <= 1e-12:
                continue
            entries.append(f"{order}:{gain:.9g}:{phase:.9g}")
        return ",".join(entries) or "1:1:0"

    def set_harmonic_row(self, row: int, order: int, gain: float, phase: float) -> None:
        for column, value in enumerate((order, gain, phase)):
            self.harmonic_table.setItem(row, column, QTableWidgetItem(f"{value:g}"))

    def add_harmonic_row(self) -> None:
        row = self.harmonic_table.rowCount()
        self.harmonic_table.insertRow(row)
        self.set_harmonic_row(row, row + 1, 0.0, 0.0)
        self.harmonic_table.selectRow(row)
        self.on_harmonic_table_changed()

    def remove_selected_harmonic_row(self) -> None:
        row = self.harmonic_table.currentRow()
        if row < 0:
            return
        self.harmonic_table.removeRow(row)
        self.on_harmonic_table_changed()

    def reset_harmonics(self) -> None:
        defaults = [(order, 1.0 / order, 0.0) for order in range(1, 7)]
        self.harmonic_table.blockSignals(True)
        self.harmonic_table.setRowCount(6)
        for row in range(self.harmonic_table.rowCount()):
            order = defaults[row][0] if row < len(defaults) else row + 1
            gain = defaults[row][1] if row < len(defaults) else 0.0
            phase = defaults[row][2] if row < len(defaults) else 0.0
            self.set_harmonic_row(row, order, gain, phase)
        self.harmonic_table.blockSignals(False)
        self.harmonic_table.resizeColumnsToContents()
        self.on_harmonic_table_changed()

    def on_harmonic_table_changed(self) -> None:
        self.harmonic_spec.setText(self.harmonic_spec_from_table())
        self.queue_preview()

    def modulation_settings_for_mode(self, output_mode: str) -> ModulationSettings:
        modulation_type = self.modulation_type.currentData()
        if output_mode != "ram_waveform":
            modulation_type = "sine"
        harmonic_spec = self.harmonic_spec_from_table()
        return ModulationSettings(
            modulation_type=str(modulation_type or "sine"),
            loop_coherent=(output_mode == "ram_waveform"),
            mod_frequency=self.mod_frequency.value(),
            mod_frequency_unit=self.mod_frequency_unit.currentText(),
            am_depth_percent=self.am_depth_percent.value(),
            fm_deviation=self.fm_deviation.value(),
            fm_deviation_unit=self.fm_deviation_unit.currentText(),
            pm_deviation_deg=self.pm_deviation_deg.value(),
            symbol_rate=self.symbol_rate.value(),
            symbol_rate_unit=self.symbol_rate_unit.currentText(),
            ask_low_percent=self.ask_low_percent.value(),
            fsk_deviation=self.fsk_deviation.value(),
            fsk_deviation_unit=self.fsk_deviation_unit.currentText(),
            psk_order=int(self.psk_order.currentData() or 2),
            data_pattern=self.data_pattern.text(),
            harmonic_spec=harmonic_spec,
            sawtooth_rise_percent=self.sawtooth_rise_percent.value(),
            square_duty_percent=self.square_duty_percent.value(),
        )

    def _convert_frequency_spinbox(self, spinbox: QDoubleSpinBox, old_unit: str, new_unit: str) -> None:
        value_hz = spinbox.value() * FREQUENCY_UNITS[old_unit]
        spinbox.blockSignals(True)
        spinbox.setValue(value_hz / FREQUENCY_UNITS[new_unit])
        spinbox.blockSignals(False)
        self.queue_preview()

    def on_mod_frequency_unit_changed(self, new_unit: str) -> None:
        self._convert_frequency_spinbox(self.mod_frequency, self._mod_frequency_unit, new_unit)
        self._mod_frequency_unit = new_unit

    def on_fm_deviation_unit_changed(self, new_unit: str) -> None:
        self._convert_frequency_spinbox(self.fm_deviation, self._fm_deviation_unit, new_unit)
        self._fm_deviation_unit = new_unit

    def on_symbol_rate_unit_changed(self, new_unit: str) -> None:
        self._convert_frequency_spinbox(self.symbol_rate, self._symbol_rate_unit, new_unit)
        self._symbol_rate_unit = new_unit
        self.update_effective_symbol_rate_display()

    def on_fsk_deviation_unit_changed(self, new_unit: str) -> None:
        self._convert_frequency_spinbox(self.fsk_deviation, self._fsk_deviation_unit, new_unit)
        self._fsk_deviation_unit = new_unit

    def on_modulation_type_changed(self, _index: int | None = None) -> None:
        self.update_modulation_controls()
        self.queue_preview()

    def update_modulation_controls(self) -> None:
        ram_mode = self.output_mode_key() == "ram_waveform"
        mod_type = str(self.modulation_type.currentData() or "sine")
        analog_mod = ram_mode and mod_type in ("am", "fm", "pm")
        digital_mod = ram_mode and mod_type in ("ask", "fsk", "psk")
        if digital_mod:
            self.update_effective_symbol_rate_display()
        visible_rows: dict[str, set[str]] = {
            "sine": set(),
            "sawtooth": {"sawtooth_rise"},
            "square": {"square_duty"},
            "harmonic": {"harmonic_table"},
            "am": {"mod_frequency", "am_depth"},
            "fm": {"mod_frequency", "fm_deviation"},
            "pm": {"mod_frequency", "pm_deviation"},
            "ask": {"symbol_rate", "ask_low", "data_pattern"},
            "fsk": {"symbol_rate", "fsk_deviation", "data_pattern"},
            "psk": {"symbol_rate", "psk_order", "data_pattern"},
        }
        self.modulation_type.setEnabled(ram_mode)
        self.modulation_params.setVisible(ram_mode and mod_type != "sine")
        self._set_modulation_param_rows(visible_rows.get(mod_type, set()) if ram_mode else set())
        self.mod_frequency.setEnabled(analog_mod)
        self.mod_frequency_unit.setEnabled(analog_mod)
        self.am_depth_percent.setEnabled(ram_mode and mod_type == "am")
        self.fm_deviation.setEnabled(ram_mode and mod_type == "fm")
        self.fm_deviation_unit.setEnabled(ram_mode and mod_type == "fm")
        self.pm_deviation_deg.setEnabled(ram_mode and mod_type == "pm")
        self.symbol_rate.setEnabled(False)
        self.symbol_rate_unit.setEnabled(digital_mod)
        self.ask_low_percent.setEnabled(ram_mode and mod_type == "ask")
        self.fsk_deviation.setEnabled(ram_mode and mod_type == "fsk")
        self.fsk_deviation_unit.setEnabled(ram_mode and mod_type == "fsk")
        self.psk_order.setEnabled(ram_mode and mod_type == "psk")
        self.data_pattern.setEnabled(digital_mod)
        self.sawtooth_rise_percent.setEnabled(ram_mode and mod_type == "sawtooth")
        self.square_duty_percent.setEnabled(ram_mode and mod_type == "square")
        self.harmonic_table.setEnabled(ram_mode and mod_type == "harmonic")

    def on_pe43711_atten_changed(self, value: float) -> None:
        code = max(0, min(127, int(round(float(value) / PE43711_STEP_DB))))
        self.pe43711_code.blockSignals(True)
        self.pe43711_code.setValue(code)
        self.pe43711_code.blockSignals(False)
        self.queue_preview()

    def on_pe43711_code_changed(self, value: int) -> None:
        atten_db = max(0, min(int(value), 127)) * PE43711_STEP_DB
        self.pe43711_atten_db.blockSignals(True)
        self.pe43711_atten_db.setValue(atten_db)
        self.pe43711_atten_db.blockSignals(False)
        self.queue_preview()

    def on_rf_target_frequency_changed(self, value: float) -> None:
        self.sync_target_to_output_channel()
        self.update_main_nco_display()
        self.queue_preview()

    def on_rf_target_frequency_unit_changed(self, new_unit: str) -> None:
        current_hz = self.rf_target_frequency.value() * FREQUENCY_UNITS[self._rf_frequency_unit]
        self.rf_target_frequency.blockSignals(True)
        self.rf_target_frequency.setValue(current_hz / FREQUENCY_UNITS[new_unit])
        self.rf_target_frequency.blockSignals(False)
        self._rf_frequency_unit = new_unit
        self.update_output_path_controls()
        self.on_rf_target_frequency_changed(self.rf_target_frequency.value())

    def on_output_path_changed(self, _index: int | None = None) -> None:
        self.update_output_path_controls()
        self.on_rf_target_frequency_changed(self.rf_target_frequency.value())
        self.queue_preview()

    def on_rf_target_amplitude_changed(self, _value: float) -> None:
        self.sync_target_to_output_channel()
        self.queue_preview()

    def on_rf_target_amplitude_unit_changed(self, new_unit: str) -> None:
        old_scale = 1e-3 if self._rf_amplitude_unit == "mV" else 1.0
        new_scale = 1e-3 if new_unit == "mV" else 1.0
        amplitude_v = self.rf_target_amplitude.value() * old_scale
        self.rf_target_amplitude.blockSignals(True)
        if new_unit == "mV":
            self.rf_target_amplitude.setRange(10.0, 3000.0)
            self.rf_target_amplitude.setSingleStep(10.0)
            self.rf_target_amplitude.setDecimals(2)
        else:
            self.rf_target_amplitude.setRange(0.01, 3.0)
            self.rf_target_amplitude.setSingleStep(0.01)
            self.rf_target_amplitude.setDecimals(4)
        self.rf_target_amplitude.setValue(amplitude_v / new_scale)
        self.rf_target_amplitude.blockSignals(False)
        self._rf_amplitude_unit = new_unit
        self.sync_target_to_output_channel()
        self.queue_preview()

    def on_output_mode_changed(self, _index: int | None = None) -> None:
        mode = self.output_mode_key()
        nco_only = mode == "nco_only"
        ram_mode = mode == "ram_waveform"
        self.send_button.setEnabled(nco_only or ram_mode)
        self.use_matlab.setEnabled(ram_mode)
        self.update_modulation_controls()
        if ram_mode:
            self.status.setText("任意波形输出：通过 UDP DATA/COMMIT 写入 waveform RAM")
        elif nco_only:
            self.status.setText("DDS单音输出：通过 VIO 配置 AD9173 片内 NCO")
        else:
            self.status.setText("JESD 单音模式：DDS 配置驱动 PL 生成 JESD 样点")
        self.queue_preview()

    def sweep_path_key(self) -> str:
        return str(self.sweep_path.currentData() or "lf")

    def sweep_mode_key(self) -> str:
        return str(self.sweep_mode.currentData() or "linear")

    def on_sweep_path_changed(self, _index: int | None = None) -> None:
        self.reset_sweep_range()

    def on_sweep_mode_changed(self, _index: int | None = None) -> None:
        self.update_sweep_controls()

    def _convert_sweep_frequency_spinbox(
        self,
        spinbox: QDoubleSpinBox,
        old_unit: str,
        new_unit: str,
    ) -> None:
        value_hz = spinbox.value() * FREQUENCY_UNITS[old_unit]
        spinbox.blockSignals(True)
        spinbox.setValue(value_hz / FREQUENCY_UNITS[new_unit])
        spinbox.blockSignals(False)

    def on_sweep_start_unit_changed(self, new_unit: str) -> None:
        self._convert_sweep_frequency_spinbox(self.sweep_start, self._sweep_start_unit, new_unit)
        self._sweep_start_unit = new_unit

    def on_sweep_stop_unit_changed(self, new_unit: str) -> None:
        self._convert_sweep_frequency_spinbox(self.sweep_stop, self._sweep_stop_unit, new_unit)
        self._sweep_stop_unit = new_unit

    def on_sweep_step_unit_changed(self, new_unit: str) -> None:
        self._convert_sweep_frequency_spinbox(self.sweep_step, self._sweep_step_unit, new_unit)
        self._sweep_step_unit = new_unit

    def _set_sweep_value(self, spinbox: QDoubleSpinBox, unit_box: QComboBox, hz: float, unit: str) -> str:
        unit_box.blockSignals(True)
        spinbox.blockSignals(True)
        unit_box.setCurrentText(unit)
        spinbox.setValue(float(hz) / FREQUENCY_UNITS[unit])
        spinbox.blockSignals(False)
        unit_box.blockSignals(False)
        return unit

    def reset_sweep_range(self) -> None:
        path_key = self.sweep_path_key()
        if path_key == "rf":
            self._sweep_start_unit = self._set_sweep_value(
                self.sweep_start,
                self.sweep_start_unit,
                RF_SWEEP_MIN_HZ,
                "MHz",
            )
            self._sweep_stop_unit = self._set_sweep_value(
                self.sweep_stop,
                self.sweep_stop_unit,
                RF_SWEEP_MAX_HZ,
                "GHz",
            )
            self._sweep_step_unit = self._set_sweep_value(
                self.sweep_step,
                self.sweep_step_unit,
                10_000_000.0,
                "MHz",
            )
        else:
            stop_hz = RF_SWEEP_MAX_HZ if path_key == "segmented" else LF_SWEEP_MAX_HZ
            stop_unit = "GHz" if path_key == "segmented" else "MHz"
            step_hz = 1_000_000.0 if path_key == "segmented" else 100_000.0
            self._sweep_start_unit = self._set_sweep_value(
                self.sweep_start,
                self.sweep_start_unit,
                LF_SWEEP_MIN_HZ,
                "mHz",
            )
            self._sweep_stop_unit = self._set_sweep_value(
                self.sweep_stop,
                self.sweep_stop_unit,
                stop_hz,
                stop_unit,
            )
            self._sweep_step_unit = self._set_sweep_value(
                self.sweep_step,
                self.sweep_step_unit,
                step_hz,
                "kHz" if path_key == "lf" else "MHz",
            )
        self.sweep_index = 0
        self.sweep_points = []
        self.update_sweep_controls()

    def update_sweep_controls(self) -> None:
        if not hasattr(self, "sweep_start_button"):
            return
        running = self.sweep_running or self.sweep_waiting_for_vio
        log_mode = self.sweep_mode_key() == "log"
        if hasattr(self, "sweep_step_label"):
            self.sweep_step_label.setVisible(not log_mode)
            self.sweep_step_row_widget.setVisible(not log_mode)
            self.sweep_log_ratio_label.setVisible(log_mode)
            self.sweep_log_ratio.setVisible(log_mode)
        for widget in (
            self.sweep_path,
            self.sweep_mode,
            self.sweep_start,
            self.sweep_start_unit,
            self.sweep_stop,
            self.sweep_stop_unit,
            self.sweep_step,
            self.sweep_step_unit,
            self.sweep_log_ratio,
            self.sweep_dwell_ms,
            self.sweep_repeat,
            self.sweep_amplitude,
            self.sweep_amplitude_unit,
        ):
            widget.setEnabled(not running)
        self.sweep_start_button.setEnabled(not running)
        self.sweep_step_button.setEnabled(not running)
        self.sweep_reset_button.setEnabled(not running)
        self.sweep_stop_button.setEnabled(running)

    def sweep_frequency_bounds(self, path_key: str) -> list[tuple[str, float, float]]:
        if path_key == "lf":
            return [("lf", LF_SWEEP_MIN_HZ, LF_SWEEP_MAX_HZ)]
        if path_key == "rf":
            return [("rf", RF_SWEEP_MIN_HZ, RF_SWEEP_MAX_HZ)]
        return [
            ("lf", LF_SWEEP_MIN_HZ, LF_SWEEP_MAX_HZ),
            ("rf", RF_SWEEP_MIN_HZ, RF_SWEEP_MAX_HZ),
        ]

    def sweep_amplitude_vpk(self) -> float:
        unit_scale = 1e-3 if self.sweep_amplitude_unit.currentText() == "mVpp" else 1.0
        return 0.5 * self.sweep_amplitude.value() * unit_scale

    @staticmethod
    def format_frequency_hz(freq_hz: float) -> str:
        freq_hz = float(freq_hz)
        for unit, scale in (("GHz", 1e9), ("MHz", 1e6), ("kHz", 1e3), ("Hz", 1.0)):
            if abs(freq_hz) >= scale:
                return f"{freq_hz / scale:.6g} {unit}"
        return f"{freq_hz / 1e-3:.6g} mHz"

    def _linear_frequency_points(self, start_hz: float, stop_hz: float, step_hz: float) -> list[float]:
        if step_hz <= 0.0:
            raise ValueError("线性步进必须大于 0")
        if stop_hz < start_hz:
            raise ValueError("扫频终点必须大于或等于起点")
        estimate = int(math.floor((stop_hz - start_hz) / step_hz)) + 1
        if estimate > SWEEP_MAX_POINTS:
            raise ValueError(f"扫频点数约 {estimate}，超过上限 {SWEEP_MAX_POINTS}，请增大步进")
        points = [start_hz + index * step_hz for index in range(max(estimate, 1))]
        if not points or points[-1] < stop_hz:
            if len(points) >= SWEEP_MAX_POINTS:
                raise ValueError(f"扫频点数超过上限 {SWEEP_MAX_POINTS}，请增大步进")
            points.append(stop_hz)
        return [min(point, stop_hz) for point in points]

    def _log_frequency_points(self, start_hz: float, stop_hz: float, ratio: float) -> list[float]:
        if start_hz <= 0.0 or stop_hz <= 0.0:
            raise ValueError("对数扫频起点和终点必须大于 0")
        if ratio <= 1.0:
            raise ValueError("对数倍率必须大于 1")
        if stop_hz < start_hz:
            raise ValueError("扫频终点必须大于或等于起点")
        points: list[float] = []
        freq_hz = start_hz
        while freq_hz <= stop_hz:
            if len(points) >= SWEEP_MAX_POINTS:
                raise ValueError(f"扫频点数超过上限 {SWEEP_MAX_POINTS}，请增大倍率")
            points.append(freq_hz)
            next_hz = freq_hz * ratio
            if next_hz <= freq_hz:
                break
            freq_hz = next_hz
        if not points or points[-1] < stop_hz:
            if len(points) >= SWEEP_MAX_POINTS:
                raise ValueError(f"扫频点数超过上限 {SWEEP_MAX_POINTS}，请增大倍率")
            points.append(stop_hz)
        return points

    def build_sweep_points(self) -> list[tuple[str, float]]:
        start_hz = self.sweep_start.value() * FREQUENCY_UNITS[self.sweep_start_unit.currentText()]
        stop_hz = self.sweep_stop.value() * FREQUENCY_UNITS[self.sweep_stop_unit.currentText()]
        if stop_hz < start_hz:
            raise ValueError("扫频终点必须大于或等于起点")
        step_hz = self.sweep_step.value() * FREQUENCY_UNITS[self.sweep_step_unit.currentText()]
        ratio = self.sweep_log_ratio.value()
        mode_key = self.sweep_mode_key()
        points: list[tuple[str, float]] = []
        for path_key, low_hz, high_hz in self.sweep_frequency_bounds(self.sweep_path_key()):
            segment_start = max(start_hz, low_hz)
            segment_stop = min(stop_hz, high_hz)
            if segment_stop < segment_start:
                continue
            if mode_key == "log":
                segment_points = self._log_frequency_points(segment_start, segment_stop, ratio)
            else:
                segment_points = self._linear_frequency_points(segment_start, segment_stop, step_hz)
            for freq_hz in segment_points:
                points.append((path_key, freq_hz))
        if not points:
            raise ValueError("当前起止频率不在所选通路范围内")
        if len(points) > SWEEP_MAX_POINTS:
            raise ValueError(f"扫频点数 {len(points)} 超过上限 {SWEEP_MAX_POINTS}")
        return points

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

    def prepare_udp_network_settings(self, purpose: str) -> NetworkSettings:
        entries = _windows_ipv4_entries()
        preferred_ip = _select_udp_local_ip(entries)
        current_ip = self.local_ip_edit.text().strip()
        if _should_replace_udp_local_ip(current_ip, preferred_ip, entries):
            self.local_ip_edit.setText(preferred_ip)
            current_ip = preferred_ip
            self.append_log(f"UDP local bind auto-selected: {preferred_ip}")

        settings = self.network_settings()
        target_key = settings.target_ip.strip().lower()
        if target_key not in FPGA_UDP_ACCEPTED_TARGETS:
            self.ip_edit.setText("255.255.255.255")
            self.append_log(
                "UDP target auto-selected: 255.255.255.255 broadcast "
                f"(FPGA RTL does not accept {settings.target_ip})"
            )
            settings = self.network_settings()
            target_key = settings.target_ip.strip().lower()
        elif target_key == "192.168.1.10" and settings.local_ip.startswith("169.254."):
            self.ip_edit.setText("255.255.255.255")
            self.append_log(
                "UDP target auto-selected: 255.255.255.255 broadcast "
                f"(local bind {settings.local_ip} is link-local, not 192.168.1.x)"
            )
            settings = self.network_settings()
            target_key = settings.target_ip.strip().lower()
        if target_key in UDP_BROADCAST_TARGETS and not settings.local_ip:
            self.append_log(
                "UDP warning: broadcast target without a local bind may leave through the wrong NIC"
            )

        local_text = settings.local_ip or "OS auto"
        entry = _udp_local_ip_entry(settings.local_ip, entries)
        if entry is not None:
            alias = str(entry.get("InterfaceAlias", "")).strip()
            if alias:
                local_text = f"{local_text} ({alias})"
        self.append_log(
            f"{purpose}: UDP local={local_text} -> "
            f"{settings.target_ip}:{settings.target_port}, "
            f"local_port={settings.local_port}, max_datagram={settings.max_datagram_bytes}"
        )
        return settings

    def repo_root(self) -> Path:
        return Path(__file__).resolve().parents[2]

    def default_bit_path(self) -> Path:
        return (
            self.repo_root()
            / "build"
            / "vivado"
            / "ad9173_dac_only"
            / "ku5p_vivado"
            / "ku5p_dac_only_top.bit"
        )

    def choose_bit_file(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择 FPGA bit 文件",
            str(Path(self.bit_path_edit.text()).parent),
            "Bitstream (*.bit);;All files (*)",
        )
        if path:
            self.bit_path_edit.setText(path)

    def set_program_controls_enabled(self, enabled: bool) -> None:
        self.program_bit_button.setEnabled(enabled)
        self.bit_browse_button.setEnabled(enabled)
        self.bit_path_edit.setEnabled(enabled)

    def vivado_command(self) -> tuple[str, List[str], str]:
        candidates = [
            shutil.which("vivado.bat"),
            r"D:\Xilinx\Vivado\2020.2\bin\vivado.bat",
            shutil.which("vivado"),
            r"D:\Xilinx\Vivado\2020.2\bin\vivado",
        ]
        for candidate in candidates:
            if candidate and Path(candidate).exists():
                vivado_path = str(Path(candidate))
                if vivado_path.lower().endswith((".bat", ".cmd")):
                    return "cmd.exe", ["/d", "/c", vivado_path], vivado_path
                return vivado_path, [], vivado_path
        return "vivado", [], "vivado"

    def program_bitstream(self) -> None:
        if self.program_process is not None:
            self.append_log("FPGA bit programming is already running")
            return

        bit_path = Path(self.bit_path_edit.text().strip()).expanduser()
        if not bit_path.exists():
            self.append_log(f"bit file not found: {bit_path}")
            self.status.setText("bit file not found")
            return

        script_path = self.repo_root() / "Prj" / "scripts" / "hw_program_only.tcl"
        if not script_path.exists():
            self.append_log(f"Vivado programming script not found: {script_path}")
            self.status.setText("program script not found")
            return

        process = QProcess(self)
        program, prefix_args, vivado_label = self.vivado_command()
        process.setProgram(program)
        process.setArguments(prefix_args + ["-mode", "batch", "-source", str(script_path)])
        process.setWorkingDirectory(str(self.repo_root()))
        process.setProcessChannelMode(QProcess.MergedChannels)
        env = QProcessEnvironment.systemEnvironment()
        env.insert("KU5P_HW_BIT", str(bit_path))
        process.setProcessEnvironment(env)
        process.readyReadStandardOutput.connect(self.on_program_output)
        process.readyReadStandardError.connect(self.on_program_output)
        process.finished.connect(self.on_program_finished)
        process.errorOccurred.connect(self.on_program_error)

        self.program_process = process
        self.set_program_controls_enabled(False)
        self.status.setText("正在烧入 FPGA bit...")
        self.append_log(f"Programming FPGA bit: {bit_path}")
        self.append_log(f"Vivado launcher: {vivado_label}")
        process.start()

    def on_program_output(self) -> None:
        process = self.program_process
        if process is None:
            return
        data = bytes(process.readAllStandardOutput()) + bytes(process.readAllStandardError())
        text = data.decode("utf-8", errors="replace")
        for line in text.splitlines():
            if line.strip():
                self.append_log(line.rstrip())

    def on_program_finished(self, exit_code: int, _exit_status) -> None:
        self.on_program_output()
        success = exit_code == 0
        if success:
            self.append_log("FPGA bit programming completed")
            self.status.setText("FPGA bit 烧入完成")
        else:
            self.append_log(f"FPGA bit programming failed: exit_code={exit_code}")
            self.status.setText("FPGA bit 烧入失败")
        if self.program_process is not None:
            self.program_process.deleteLater()
            self.program_process = None
        self.set_program_controls_enabled(True)

    def on_program_error(self, error) -> None:
        error_names = {
            QProcess.FailedToStart: "FailedToStart",
            QProcess.Crashed: "Crashed",
            QProcess.Timedout: "Timedout",
            QProcess.WriteError: "WriteError",
            QProcess.ReadError: "ReadError",
            QProcess.UnknownError: "UnknownError",
        }
        error_name = error_names.get(error, str(error))
        process_error = self.program_process.errorString() if self.program_process is not None else ""
        self.append_log(f"FPGA bit programming process error: {error_name} {process_error}".strip())
        self.status.setText("FPGA bit 烧入进程错误")
        if self.program_process is not None:
            self.program_process.deleteLater()
            self.program_process = None
        self.set_program_controls_enabled(True)

    def set_vio_controls_enabled(self, enabled: bool) -> None:
        self.vio_nco_button.setEnabled(enabled)
        self.vio_status_button.setEnabled(enabled)
        self.update_sweep_controls()

    def vio_script_path(self) -> Path:
        return self.repo_root() / "Prj" / "scripts" / "hw_runtime_vio_server.tcl"

    def ensure_vio_session(self, quiet: bool = False) -> bool:
        if self.vio_process is not None:
            return True

        script_path = self.vio_script_path()
        if not script_path.exists():
            self.append_log(f"VIO script not found: {script_path}")
            self.status.setText("VIO script not found")
            return False

        process = QProcess(self)
        program, prefix_args, vivado_label = self.vivado_command()
        process.setProgram(program)
        process.setArguments(prefix_args + ["-mode", "tcl", "-source", str(script_path)])
        process.setWorkingDirectory(str(self.repo_root()))
        process.setProcessChannelMode(QProcess.MergedChannels)
        process.readyReadStandardOutput.connect(self.on_vio_output)
        process.readyReadStandardError.connect(self.on_vio_output)
        process.finished.connect(self.on_vio_finished)
        process.errorOccurred.connect(self.on_vio_error)

        self.vio_process = process
        self.vio_ready = False
        self.vio_startup_quiet = quiet
        self.set_vio_controls_enabled(False)
        self.status.setText("正在连接常驻 VIO...")
        if not quiet:
            self.append_log("Starting persistent Vivado VIO session")
            self.append_log(f"Vivado launcher: {vivado_label}")
            self.append_log(f"VIO server script: {script_path}")
        process.start()
        return True

    def send_vio_command(
        self,
        command: str,
        description: str,
        log_command: bool = True,
        quiet: bool = False,
    ) -> bool:
        if not self.ensure_vio_session(quiet=quiet):
            return False
        if not self.vio_ready:
            if not quiet:
                self.append_log(f"VIO not ready; queued command: {description}")
            self.status.setText("VIO 正在连接，命令已排队")
            self.vio_pending_commands.append((command, description, log_command))
            return True
        self.write_vio_command(command, description, log_command=log_command)
        return True

    def write_vio_command(
        self,
        command: str,
        description: str = "VIO command",
        log_command: bool = True,
    ) -> None:
        process = self.vio_process
        if process is None:
            return
        if process.state() != QProcess.Running:
            self.append_log(f"VIO process is not running; drop command: {description}")
            self.status.setText("VIO 进程未运行")
            return
        if log_command:
            self.append_log(f"VIO command sent: {description}: {command}")
        written = process.write((command + "\n").encode("utf-8"))
        flushed = process.waitForBytesWritten(1000)
        if written < 0 or not flushed:
            self.append_log(f"VIO command write failed or timed out: {description}")
            self.status.setText("VIO 命令写入失败")

    def read_vio_status(self) -> None:
        self.send_vio_command("ku5p_vio_status", "读取VIO状态")

    def send_vio_nco_config(self, quiet_success: bool = False) -> None:
        try:
            channels = self.channel_settings()
            if not channels or not channels[0].enabled:
                raise ValueError("CH1 未启用")
            path_key = self.output_path_key()
            frequency_hz = channels[0].frequency_hz()
            target_vpk = self.rf_settings().target_amplitude_vpk
            command, config, ftws, scales, pe_code, path_sel = self.build_vio_nco_command(
                path_key,
                frequency_hz,
                target_vpk,
                fast=quiet_success,
            )
            if quiet_success:
                self.append_log(self.format_dds_success_log(config, ftws, scales, pe_code, path_sel))
            else:
                self.append_log(
                    "VIO NCO config: "
                    f"CH1 amp=0x{scales[0]:04X} ftw=0x{ftws[0]:012X}, "
                    f"CH2 amp=0x{scales[2]:04X} ftw=0x{ftws[2]:012X}, "
                    f"PE43711=0x{pe_code:02X}, path_sel={path_sel}, "
                    f"freq={self.format_frequency_hz(frequency_hz)}"
                )
                rf_cal = config.get("rf", {}).get("calibration", {})
                if rf_cal.get("enabled"):
                    self.append_log(
                        "RF calibration applied: "
                        f"raw={float(rf_cal.get('raw_vpp', 0.0)):.4g} Vpp, "
                        f"expected={float(rf_cal.get('expected_vpp', 0.0)):.4g} Vpp, "
                        f"amp=0x{int(rf_cal.get('amp_code', 0)):04X}, "
                        f"PE=0x{int(rf_cal.get('pe43711_code', 0)):02X}"
                    )
                lf_cal = config.get("rf", {}).get("lf_calibration", {})
                if lf_cal.get("enabled"):
                    self.append_log(
                        "LF calibration applied: "
                        f"raw={float(lf_cal.get('raw_vpp', 0.0)):.4g} Vpp, "
                        f"expected={float(lf_cal.get('expected_vpp', 0.0)):.4g} Vpp, "
                        f"amp=0x{int(lf_cal.get('amp_code', 0)):04X}"
                    )
            if not self.send_vio_command(command, "VIO 发送 NCO", log_command=not quiet_success, quiet=quiet_success):
                return
            self.status.setText("DDS配置成功")
        except Exception as exc:
            self.append_log(f"DDS配置失败：{exc}")
            self.status.setText("DDS配置失败")

    def format_dds_success_log(
        self,
        config: dict,
        ftws: list[int],
        scales: list[int],
        pe_code: int,
        path_sel: int,
    ) -> str:
        rf = config.get("rf", {})
        channels = config.get("channels") or [{}]
        frequency_hz = float(rf.get("target_frequency_hz", channels[0].get("frequency_hz", 0.0)))
        target_vpk = float(rf.get("target_amplitude_vpk", 0.0))
        return (
            "DDS配置成功：配置信息："
            f"模式=DDS单音输出，"
            f"通路={rf.get('output_path_label', self.output_path.currentText())}，"
            f"频率={self.format_frequency_hz(frequency_hz)}，"
            f"幅度={target_vpk:.4g} Vpk，"
            f"CH1幅度码=0x{scales[0]:04X}，"
            f"CH1 FTW=0x{ftws[0]:012X}，"
            f"CH2幅度码=0x{scales[2]:04X}，"
            f"CH2 FTW=0x{ftws[2]:012X}，"
            f"PE43711=0x{pe_code:02X}，"
            f"path_sel={path_sel}"
        )

    def close_sweep_udp_streamer(self) -> None:
        if self.sweep_udp_streamer is None:
            return
        try:
            self.sweep_udp_streamer.close()
        finally:
            self.sweep_udp_streamer = None

    def start_nco_sweep(self) -> None:
        try:
            self.sweep_points = self.build_sweep_points()
            self.sweep_index = 0
            self.sweep_point_pending = False
            first_path, first_hz = self.sweep_points[0]
            last_path, last_hz = self.sweep_points[-1]
            self.append_log(
                "DDS sweep prepared: "
                f"{len(self.sweep_points)} points, "
                f"{first_path.upper()} {self.format_frequency_hz(first_hz)} -> "
                f"{last_path.upper()} {self.format_frequency_hz(last_hz)}, "
                f"interval={self.sweep_dwell_ms.value()} ms"
            )
            self.sweep_running = False
            self.sweep_waiting_for_vio = False
            self.close_sweep_udp_streamer()
            network = self.prepare_udp_network_settings("DDS sweep")
            self.sweep_udp_streamer = UdpRuntimeConfigStreamer(network)
            self.update_sweep_controls()
            self._begin_ready_sweep()
            self.status.setText("DDS sweep started")
        except Exception as exc:
            self.sweep_waiting_for_vio = False
            self.sweep_running = False
            self.close_sweep_udp_streamer()
            self.update_sweep_controls()
            self.append_log(f"DDS sweep start failed: {exc}")
            self.status.setText("DDS sweep start failed")

    def _begin_ready_sweep(self) -> None:
        if not self.sweep_points:
            return
        self.sweep_waiting_for_vio = False
        self.sweep_running = True
        self.sweep_timer.setInterval(self.sweep_dwell_ms.value())
        self.update_sweep_controls()
        self.sweep_status.setText("DDS running")
        self.on_sweep_timer()
        if self.sweep_running:
            self.sweep_timer.start()

    def stop_nco_sweep(self) -> None:
        self.sweep_timer.stop()
        was_active = self.sweep_running or self.sweep_waiting_for_vio
        self.sweep_running = False
        self.sweep_waiting_for_vio = False
        self.sweep_point_pending = False
        self.close_sweep_udp_streamer()
        self.update_sweep_controls()
        if was_active:
            self.append_log("DDS sweep stopped")
        self.sweep_status.setText("Stopped")
        self.status.setText("DDS sweep stopped")

    def single_step_nco_sweep(self) -> None:
        try:
            if not self.sweep_points or self.sweep_index >= len(self.sweep_points):
                self.sweep_points = self.build_sweep_points()
                self.sweep_index = 0
            self.send_next_sweep_point(queue_if_needed=True)
        except Exception as exc:
            self.append_log(f"DDS single step failed: {exc}")
            self.status.setText("DDS single step failed")

    def on_sweep_timer(self) -> None:
        if not self.sweep_running:
            return
        try:
            if self.sweep_index >= len(self.sweep_points):
                if self.sweep_repeat.isChecked():
                    self.sweep_index = 0
                else:
                    self.stop_nco_sweep()
                    self.sweep_status.setText("Done")
                    self.status.setText("DDS sweep done")
                    return
            if not self.send_next_sweep_point():
                self.stop_nco_sweep()
                self.sweep_status.setText("Done")
                self.status.setText("DDS sweep done")
        except Exception as exc:
            self.append_log(f"DDS sweep send failed: {exc}")
            self.status.setText("DDS sweep send failed")
            self.stop_nco_sweep()

    def send_next_sweep_point(self, queue_if_needed: bool = False) -> bool:
        if self.sweep_index >= len(self.sweep_points):
            return False
        path_key, freq_hz = self.sweep_points[self.sweep_index]
        point_number = self.sweep_index + 1
        _command, config, _ftws, scales, pe_code, path_sel = self.build_vio_nco_command(
            path_key,
            freq_hz,
            self.sweep_amplitude_vpk(),
            fast=True,
        )
        if self.sweep_udp_streamer is None:
            network = self.prepare_udp_network_settings("DDS sweep")
            self.sweep_udp_streamer = UdpRuntimeConfigStreamer(network)
        self.sweep_udp_streamer.send_dac_config(config)
        self.sweep_point_pending = False
        self.sweep_status.setText(
            f"{point_number}/{len(self.sweep_points)} "
            f"{path_key.upper()} {self.format_frequency_hz(freq_hz)} "
            f"amp=0x{scales[0] if path_sel == 0 else scales[2]:04X} "
            f"PE=0x{pe_code:02X}"
        )
        self.status.setText(self.sweep_status.text())
        self.sweep_index += 1
        return True

    def build_vio_sweep_command(self, points: list[tuple[str, float]]) -> tuple[str, str]:
        if not points:
            raise ValueError("扫频点为空")
        start_path, start_hz = points[0]
        stop_path, stop_hz = points[-1]
        paths_in_sweep = {path for path, _freq in points}
        segmented = self.sweep_path_key() == "segmented" and paths_in_sweep == {"lf", "rf"}
        if start_path != stop_path and not segmented:
            raise ValueError("非分段扫频不能跨通路")
        target_vpk = self.sweep_amplitude_vpk()
        if segmented:
            lf_start_hz = next(freq for path, freq in points if path == "lf")
            rf_start_hz = next(freq for path, freq in points if path == "rf")
            _lf_command, _lf_config, lf_ftws, lf_scales, _lf_pe_code, _lf_path_sel = (
                self.build_vio_nco_command("lf", lf_start_hz, target_vpk)
            )
            _rf_command, _rf_config, rf_ftws, rf_scales, pe_code, _rf_path_sel = (
                self.build_vio_nco_command("rf", rf_start_hz, target_vpk)
            )
            ftws = [rf_ftws[0], 0, lf_ftws[2], 0]
            scales = [rf_scales[0], 0, lf_scales[2], 0]
            path_sel = 1
            segment_ftw = rf_ftws[0]
        else:
            start_command, _start_config, ftws, scales, pe_code, path_sel = self.build_vio_nco_command(
                start_path,
                start_hz,
                target_vpk,
            )
            del start_command
            segment_ftw = 0
        stop_ftw = self.build_vio_nco_command(stop_path, stop_hz, target_vpk)[2][2 if stop_path == "lf" else 0]
        linear_step_hz = self.sweep_step.value() * FREQUENCY_UNITS[self.sweep_step_unit.currentText()]
        step_ftw = max(1, int(round(linear_step_hz / AD9173_RUNTIME_NCO_HZ * (1 << 48))))
        if self.sweep_mode_key() == "log":
            ratio = max(1.000001, self.sweep_log_ratio.value())
            log_shift = max(1, min(15, int(round(-math.log(ratio - 1.0, 2)))))
        else:
            log_shift = 8
        interval_cycles = max(1, min(0xFFFFFFFF, int(round(self.sweep_dwell_ms.value() * 200_000.0))))
        control = 0x01
        if self.sweep_mode_key() == "log":
            control |= 0x02
        if self.sweep_repeat.isChecked():
            control |= 0x04
        if segmented:
            control |= 0x08
        command = " ".join([
            "ku5p_vio_sweep",
            f"{scales[0]:04x}",
            f"{ftws[0]:012x}",
            f"{scales[2]:04x}",
            f"{ftws[2]:012x}",
            f"{pe_code:02x}",
            str(path_sel),
            f"{stop_ftw:012x}",
            f"{step_ftw:012x}",
            f"{interval_cycles:08x}",
            f"{log_shift:04x}",
            f"{control:02x}",
            f"{segment_ftw:012x}",
        ])
        summary = (
            f"start_ftw=0x{(ftws[2] if path_sel else ftws[0]):012X}, "
            f"stop_ftw=0x{stop_ftw:012X}, step_ftw=0x{step_ftw:012X}, "
            f"control=0x{control:02X}"
        )
        return command, summary

    def send_vio_sweep_stop(self, log_command: bool = True) -> None:
        command = " ".join([
            "ku5p_vio_sweep",
            "0000",
            "000000000000",
            "0000",
            "000000000000",
            f"{self.pe43711_code.value() & 0x7F:02x}",
            "0",
            "000000000000",
            "000000000001",
            "00000001",
            "0008",
            "00",
            "000000000000",
        ])
        self.send_vio_command(command, "停止硬件 DDS 扫频", log_command=log_command)

    def on_vio_output(self) -> None:
        process = self.vio_process
        if process is None:
            return
        data = bytes(process.readAllStandardOutput()) + bytes(process.readAllStandardError())
        text = data.decode("utf-8", errors="replace")
        for line in text.splitlines():
            stripped = line.strip()
            if stripped:
                is_fast_apply_line = (
                    stripped.startswith("K5VIO_CMD ku5p_vio_apply_fast")
                    or stripped.startswith("FAST_APPLY")
                )
                if stripped.startswith("FAST_APPLY"):
                    self.sweep_point_pending = False
                quiet_startup = self.vio_startup_quiet and not self.vio_ready
                should_log = not is_fast_apply_line
                if quiet_startup and "ERROR:" not in line and "CRITICAL WARNING:" not in line:
                    should_log = False
                if should_log:
                    self.append_log(line.rstrip())
                if "ERROR:" in line or "CRITICAL WARNING:" in line:
                    self.status.setText("VIO 返回错误，请查看日志")
                if "K5VIO_READY" in line:
                    self.vio_ready = True
                    self.set_vio_controls_enabled(True)
                    self.status.setText("常驻 VIO 已连接")
                    pending = self.vio_pending_commands
                    self.vio_pending_commands = []
                    for command, description, log_command in pending:
                        self.write_vio_command(command, description, log_command=log_command)
                    self.vio_startup_quiet = False
                    if self.sweep_waiting_for_vio:
                        self._begin_ready_sweep()

    def on_vio_finished(self, exit_code: int, _exit_status) -> None:
        self.on_vio_output()
        self.append_log(f"Persistent VIO session exited: exit_code={exit_code}")
        self.status.setText("常驻 VIO 已退出")
        if self.vio_process is not None:
            self.vio_process.deleteLater()
            self.vio_process = None
        self.vio_ready = False
        self.vio_pending_commands = []
        if self.sweep_running or self.sweep_waiting_for_vio:
            self.stop_nco_sweep()
        self.set_vio_controls_enabled(True)

    def on_vio_error(self, error) -> None:
        error_names = {
            QProcess.FailedToStart: "FailedToStart",
            QProcess.Crashed: "Crashed",
            QProcess.Timedout: "Timedout",
            QProcess.WriteError: "WriteError",
            QProcess.ReadError: "ReadError",
            QProcess.UnknownError: "UnknownError",
        }
        error_name = error_names.get(error, str(error))
        process_error = self.vio_process.errorString() if self.vio_process is not None else ""
        self.append_log(f"VIO process error: {error_name} {process_error}".strip())
        self.status.setText("VIO 进程错误")
        if self.vio_process is not None:
            self.vio_process.deleteLater()
            self.vio_process = None
        self.vio_ready = False
        self.vio_pending_commands = []
        if self.sweep_running or self.sweep_waiting_for_vio:
            self.stop_nco_sweep()
        self.set_vio_controls_enabled(True)

    def generate_waveform(self, allow_matlab: bool) -> WaveformResult:
        output_mode = self.output_mode_key()
        generator = WaveformGenerator(
            matlab_enabled=allow_matlab and self.use_matlab.isChecked(),
            matlab_dir=Path(__file__).resolve().parents[1] / "matlab",
        )
        result = generator.generate(
            self.waveform_settings(),
            self.waveform_channel_settings_for_mode(output_mode),
            self.modulation_settings_for_mode(output_mode),
        )
        return self.apply_rf_ram_quadrature_if_needed(result, output_mode)

    def apply_rf_ram_quadrature_if_needed(self, result: WaveformResult, output_mode: str) -> WaveformResult:
        if output_mode != "ram_waveform" or self.output_path_key() != "rf":
            return result
        _if_hz, main_hz = self.ram_rf_plan_for(output_mode, "rf", self.rf_target_frequency_hz())
        modulation = self.modulation_settings_for_mode(output_mode)
        if modulation.modulation_type != "sine":
            result.warnings.append("RF RAM main-NCO shift uses real data for non-sine waveforms")
            return result

        settings = self.waveform_settings()
        sample_rate_hz = settings.sample_rate_hz()
        time_s = np.arange(int(settings.sample_count), dtype=np.float64) / max(sample_rate_hz, 1.0)
        phase = 2.0 * np.pi * float(_if_hz) * time_s
        amplitude_v = float(self.active_output_channel().amplitude_volts())

        volts = np.array(result.volts, copy=True)
        if volts.ndim != 2 or volts.shape[1] != 2:
            return result
        if main_hz <= 0.0 and abs(float(_if_hz)) <= self.predistortion_safe_hz():
            volts[:, 0] = WaveformGenerator._generate_predistorted_sine(phase, amplitude_v)
            result.warnings.append("RF RAM direct sine uses H2 predistortion with H2 inside payload Nyquist")
        else:
            volts[:, 0] = amplitude_v * np.sin(phase)
            if main_hz > 0.0:
                volts[:, 1] = amplitude_v * np.sin(phase + (0.5 * np.pi))
                result.warnings.append("RF RAM main-NCO shift sends clean quadrature IF data; predistortion disabled")
            else:
                result.warnings.append("RF RAM direct sine disables H2 predistortion because H2 would alias")
        codes = WaveformGenerator._volts_to_codes(volts, settings.dac_full_scale_vpk)
        result.volts = volts
        result.codes = codes
        return result

    def preview_result_for_display(self, result: WaveformResult) -> WaveformResult:
        ideal_result = self.ideal_sine_preview_result(result)
        if ideal_result is not None:
            return ideal_result

        freq_hz = self.waveform_preview_frequency_hz()
        if freq_hz <= 0.0:
            return result
        sample_rate_hz = self.waveform_settings().sample_rate_hz()
        sample_count = max(int(self.sample_count.value()), 1)
        visible_cycles = freq_hz * sample_count / max(sample_rate_hz, 1.0)
        if visible_cycles >= 1.25:
            return result
        display_count = min(max(sample_count, 4096), 32768)
        display_sample_rate_hz = freq_hz * display_count / 2.0
        if display_sample_rate_hz >= 1e9:
            display_rate = display_sample_rate_hz / 1e9
            display_unit = "GSPS"
        elif display_sample_rate_hz >= 1e6:
            display_rate = display_sample_rate_hz / 1e6
            display_unit = "MSPS"
        else:
            display_rate = display_sample_rate_hz / 1e3
            display_unit = "kSPS"
        display_settings = WaveformSettings(
            sample_rate=display_rate,
            sample_rate_unit=display_unit,
            sample_count=display_count,
            dac_full_scale_vpk=self.full_scale.value(),
        )
        generator = WaveformGenerator(matlab_enabled=False)
        display_result = generator.generate(
            display_settings,
            self.waveform_channel_settings_for_mode(self.output_mode_key()),
            self.modulation_settings_for_mode(self.output_mode_key()),
        )
        display_result.source = f"{result.source} preview"
        display_result.warnings = list(result.warnings)
        return display_result

    def ideal_sine_preview_result(self, result: WaveformResult) -> WaveformResult | None:
        modulation = self.modulation_settings_for_mode(self.output_mode_key())
        if modulation.modulation_type != "sine":
            return None
        target_hz = self.rf_target_frequency_hz()
        if target_hz <= 0.0:
            return None
        sample_rate_hz = self.waveform_settings().sample_rate_hz()
        samples_per_cycle = sample_rate_hz / abs(float(target_hz))
        total_cycles = abs(float(target_hz)) * max(int(self.sample_count.value()), 1) / max(sample_rate_hz, 1.0)
        if samples_per_cycle >= 32.0 and total_cycles >= 1.25:
            return None

        display_count = 4096
        visible_cycles = 10.0
        display_sample_rate_hz = abs(float(target_hz)) * display_count / visible_cycles
        time_s = np.arange(display_count, dtype=np.float64) / max(display_sample_rate_hz, 1.0)
        volts = np.zeros((display_count, 2), dtype=np.float64)
        active_index = self.active_output_channel_index()
        amplitude_v = float(self.active_output_channel().amplitude_volts())
        volts[:, active_index] = amplitude_v * np.sin(2.0 * np.pi * float(target_hz) * time_s)
        codes = WaveformGenerator._volts_to_codes(volts, self.waveform_settings().dac_full_scale_vpk)
        return WaveformResult(
            time_s=time_s,
            volts=volts,
            codes=codes,
            source=f"{result.source} preview",
            warnings=list(result.warnings),
        )

    def update_preview(self) -> None:
        result = self.generate_waveform(allow_matlab=False)
        self.loaded_waveform_path = None
        self.last_result = result
        display_result = self.preview_result_for_display(result)
        self.canvas_current.channel_index = self.active_output_channel_index()
        self.canvas_current.title = "LF/DAC1 输出预览" if self.output_path_key() == "lf" else "RF/DAC0 输出预览"
        self.canvas_current.draw_waveform(
            display_result,
            preview_frequency_hz=self.display_preview_frequency_hz(),
            zoom_high_frequency=self.should_zoom_high_frequency_preview(),
        )
        self.update_main_nco_display()
        rf = self.rf_settings()
        cal_result = self.calculate_rf_calibration()
        if cal_result is not None:
            self.rf_atten_preview.setText(
                f"校准: raw {cal_result.raw_vpp:.3g} Vpp; "
                f"PE43711 {cal_result.pe43711_atten_db:.2f} dB/0x{cal_result.pe43711_code:02X}; "
                f"amp 0x{cal_result.amp_code:04X}; 预计 {cal_result.expected_vpp:.3g} Vpp"
            )
        else:
            dac_vpk, _auto_code, _auto_atten_db = calculate_rf_output_control(
                rf.target_amplitude_vpk,
                self.full_scale.value(),
            )
            if self.output_path_key() == "lf":
                self.rf_atten_preview.setText(
                    f"LF/DAC1 direct: {2.0 * rf.target_amplitude_vpk:.4g} Vpp target"
                )
            else:
                self.rf_atten_preview.setText(
                    f"PE43711: {rf.pe43711_atten_db:.2f} dB, code 0x{rf.pe43711_code:02X}; "
                    f"DAC0 {dac_vpk:.4g} Vpk"
                )
        peak = np.max(np.abs(display_result.volts), axis=0)
        path_label = "LF/DAC1" if self.output_path_key() == "lf" else "RF/DAC0"
        active_index = self.active_output_channel_index()
        aux_index = 1 - active_index
        text = (
            f"Preview ready: {path_label} {peak[active_index]:.4g} Vpk, "
            f"AUX {peak[aux_index]:.4g} Vpk, {result.codes.shape[0]} samples"
        )
        if result.warnings:
            text += " | " + "; ".join(result.warnings)
        self.status.setText(text)

    def calculate_rf_calibration(self):
        channel = self.active_output_channel()
        if not channel.enabled:
            return None
        freq_hz = self.rf_target_frequency_hz() if self.output_mode_key() == "ram_waveform" else channel.frequency_hz()
        return self.calculate_rf_calibration_at(
            self.output_path_key(),
            freq_hz,
            self.rf_settings().target_amplitude_vpk,
            self.output_mode_key(),
        )

    def calculate_lf_calibration(self):
        channel = self.active_output_channel()
        if not channel.enabled:
            return None
        return self.calculate_lf_calibration_at(
            self.output_path_key(),
            channel.frequency_hz(),
            self.rf_settings().target_amplitude_vpk,
        )

    def calculate_rf_calibration_at(
        self,
        path_key: str,
        freq_hz: float,
        target_vpk: float,
        output_mode: str | None = None,
    ):
        if self.rf_calibration is None or path_key != "rf":
            return None
        low_hz, high_hz = self.rf_calibration.data.get("frequency_range_hz", [RF_SWEEP_MIN_HZ, 200_000_000])
        if freq_hz < float(low_hz) or freq_hz > float(high_hz):
            return None
        return self.rf_calibration.calculate(freq_hz, target_vpk, output_mode)

    def calculate_lf_calibration_at(self, path_key: str, freq_hz: float, target_vpk: float):
        if self.lf_calibration is None or path_key != "lf":
            return None
        low_hz, high_hz = self.lf_calibration.data.get("frequency_range_hz", [LF_SWEEP_MIN_HZ, LF_SWEEP_MAX_HZ])
        if freq_hz < float(low_hz) or freq_hz > float(high_hz):
            return None
        return self.lf_calibration.calculate(freq_hz, target_vpk)

    def build_vio_nco_config(self, path_key: str, frequency_hz: float, target_vpk: float) -> dict:
        path_key = "lf" if path_key == "lf" else "rf"
        target_vpk = max(0.0, float(target_vpk))
        channel = ChannelSettings(
            enabled=True,
            amplitude=target_vpk,
            amplitude_unit="V",
            frequency=float(frequency_hz),
            frequency_unit="Hz",
        )
        rf = RfSettings(
            output_path=path_key,
            target_amplitude_vpk=target_vpk,
            pe43711_atten_db=self.pe43711_code.value() * PE43711_STEP_DB,
            pe43711_code=self.pe43711_code.value(),
        )
        main_nco_hz = self.rf_main_nco_hz_for(path_key, frequency_hz)
        config = build_config_payload(
            self.waveform_settings(),
            [channel],
            "vio_nco",
            "nco_only",
            rf,
            self.modulation_settings_for_mode("nco_only"),
        )
        config["rf"]["main_nco_hz"] = main_nco_hz
        config["rf"]["channel_nco_hz"] = 0.0 if main_nco_hz > 0.0 else float(frequency_hz)
        config["rf"]["main_nco_threshold_hz"] = RF_MAIN_NCO_SHIFT_HZ
        rf_cal_result = self.calculate_rf_calibration_at(path_key, frequency_hz, target_vpk)
        if rf_cal_result is not None:
            config["rf"]["calibration"] = rf_cal_result.to_payload()
            config["rf"]["pe43711_code"] = rf_cal_result.pe43711_code
            config["rf"]["pe43711_atten_db"] = rf_cal_result.pe43711_atten_db
        lf_cal_result = self.calculate_lf_calibration_at(path_key, frequency_hz, target_vpk)
        if lf_cal_result is not None:
            config["rf"]["lf_calibration"] = lf_cal_result.to_payload()
        return config

    def build_vio_nco_command(
        self,
        path_key: str,
        frequency_hz: float,
        target_vpk: float,
        fast: bool = False,
    ):
        config = self.build_vio_nco_config(path_key, frequency_hz, target_vpk)
        payload = build_dac_dds_config_payload(config)
        ftws = [int.from_bytes(payload[12 + index * 6 : 18 + index * 6], "little") for index in range(4)]
        scales = [int.from_bytes(payload[36 + index * 2 : 38 + index * 2], "little") for index in range(4)]
        pe_code = int(payload[48]) & 0x7F
        path_sel = int(payload[49]) & 0x01
        command_name = "ku5p_vio_apply_fast" if fast else "ku5p_vio_apply"
        command = " ".join([
            command_name,
            f"{scales[0]:04x}",
            f"{ftws[0]:012x}",
            f"{scales[2]:04x}",
            f"{ftws[2]:012x}",
            f"{pe_code:02x}",
            str(path_sel),
        ])
        return command, config, ftws, scales, pe_code, path_sel

    def build_config_for_mode(self, result: WaveformResult, output_mode: str) -> dict:
        target_freq_hz = self.rf_target_frequency_hz()
        config_channels = self.waveform_channel_settings_for_mode(output_mode)
        config = build_config_payload(
            self.waveform_settings(),
            config_channels,
            result.source,
            output_mode,
            self.rf_settings(),
            self.modulation_settings_for_mode(output_mode),
        )
        jesd_if_hz, jesd_main_nco_hz = self.jesd_rf_plan_for(output_mode, self.output_path_key(), target_freq_hz)
        if jesd_main_nco_hz > 0.0 and config.get("channels"):
            config["channels"][0]["frequency_hz"] = jesd_if_hz
            config["channels"][0]["frequency"] = jesd_if_hz
            config["channels"][0]["frequency_unit"] = "Hz"
        ram_if_hz, ram_main_nco_hz = self.ram_rf_plan_for(output_mode, self.output_path_key(), target_freq_hz)
        if output_mode == "ram_waveform" and config.get("channels"):
            config["channels"][0]["frequency_hz"] = ram_if_hz
            config["channels"][0]["frequency"] = ram_if_hz
            config["channels"][0]["frequency_unit"] = "Hz"
        main_nco_hz = self.active_main_nco_hz_for(output_mode, self.output_path_key(), target_freq_hz)
        config["rf"]["main_nco_hz"] = main_nco_hz
        config["rf"]["target_frequency_hz"] = target_freq_hz
        config["rf"]["ram_if_hz"] = ram_if_hz
        config["rf"]["ram_main_nco_hz"] = ram_main_nco_hz
        config["rf"]["ram_main_nco_threshold_hz"] = self.payload_nyquist_hz()
        config["rf"]["jesd_if_hz"] = jesd_if_hz
        config["rf"]["jesd_main_nco_hz"] = ram_main_nco_hz if output_mode == "ram_waveform" else jesd_main_nco_hz
        config["rf"]["jesd_main_nco_threshold_hz"] = self.payload_nyquist_hz()
        config["rf"]["channel_nco_hz"] = 0.0 if output_mode == "nco_only" and main_nco_hz > 0.0 else config["channels"][0].get("frequency_hz", target_freq_hz)
        config["rf"]["main_nco_threshold_hz"] = RF_MAIN_NCO_SHIFT_HZ
        cal_result = self.calculate_rf_calibration()
        if cal_result is not None:
            config["rf"]["calibration"] = cal_result.to_payload()
            config["rf"]["pe43711_code"] = cal_result.pe43711_code
            config["rf"]["pe43711_atten_db"] = cal_result.pe43711_atten_db
        lf_cal_result = self.calculate_lf_calibration()
        if lf_cal_result is not None:
            config["rf"]["lf_calibration"] = lf_cal_result.to_payload()
        return config

    def build_config(self, result: WaveformResult) -> dict:
        return self.build_config_for_mode(result, self.output_mode_key())

    def send_hello(self) -> None:
        try:
            network = self.prepare_udp_network_settings("UDP test")
            frames = UdpWaveformClient(network).send_hello()
            self.append_log(f"UDP test packet sent: {frames} frame(s)")
        except Exception as exc:
            self.append_log(f"UDP 测试失败: {exc}")

    def send_config(self) -> None:
        if self.output_mode_key() == "nco_only":
            self.send_vio_nco_config(quiet_success=True)
            return

        try:
            result = self.last_result or self.generate_waveform(allow_matlab=False)
            config = self.build_config(result)
            network = self.prepare_udp_network_settings("DDS config")
            frames = UdpWaveformClient(network).send_config(config)
            mode_label = config.get("output_mode_label", self.output_mode.currentText())
            rf = config.get("rf", {})
            self.append_log(
                "DDS config sent: "
                f"{frames} frame(s), mode={mode_label}, "
                f"path={rf.get('output_path_label')}, "
                f"target={float(rf.get('target_amplitude_vpk', 0.0)):.4g} Vpk, "
                f"PE43711=0x{int(rf.get('pe43711_code', 127)):02X}"
            )
        except Exception as exc:
            self.append_log(f"DDS 配置发送失败: {exc}")

    def format_ram_waveform_success_log(self, frames: int, config: dict, result: WaveformResult) -> str:
        rf = config.get("rf", {})
        waveform = config.get("waveform", {})
        modulation = config.get("modulation", {})
        channels = config.get("channels") or [{}]
        target_hz = float(rf.get("target_frequency_hz", channels[0].get("frequency_hz", 0.0)) or 0.0)
        target_vpp = 2.0 * float(rf.get("target_amplitude_vpk", 0.0) or 0.0)
        sample_rate_hz = float(waveform.get("sample_rate_hz", self.waveform_settings().sample_rate_hz()) or 0.0)
        ram_hz = float(rf.get("ram_if_hz", target_hz) or 0.0)
        shift_hz = float(rf.get("ram_main_nco_hz", 0.0) or 0.0)
        if abs(shift_hz) > 1.0:
            frequency_plan = (
                f"RAM波形 {self.format_frequency_hz(ram_hz)} + "
                f"片内搬移 {self.format_frequency_hz(shift_hz)}"
            )
        elif abs(ram_hz - target_hz) > 1.0:
            frequency_plan = f"RAM波形 {self.format_frequency_hz(ram_hz)}"
        else:
            frequency_plan = "RAM直接输出"
        warning_suffix = f"，提示={'；'.join(result.warnings)}" if result.warnings else ""
        return (
            "任意波形输出成功：配置信息："
            f"通路={rf.get('output_path_label', self.output_path.currentText())}，"
            f"目标频率={self.format_frequency_hz(target_hz)}，"
            f"目标幅度={target_vpp:.4g} Vpp，"
            f"调制={modulation.get('modulation_label', self.modulation_type.currentText())}，"
            f"样本点={result.codes.shape[0]}，"
            f"采样率={self.format_frequency_hz(sample_rate_hz).replace('Hz', 'SPS')}，"
            f"UDP帧={frames}，"
            f"数据源={result.source}，"
            f"频率规划={frequency_plan}{warning_suffix}"
        )

    def send_waveform(self) -> None:
        try:
            output_mode = self.output_mode_key()
            if output_mode == "nco_only":
                self.send_vio_nco_config(quiet_success=True)
                return
            if output_mode != "ram_waveform":
                self.append_log("发送波形仅在任意波形输出模式下可用")
                return
            using_loaded_bin = self.loaded_waveform_path is not None and self.last_result is not None
            if using_loaded_bin:
                result = self.last_result
            else:
                result = self.generate_waveform(allow_matlab=True)
                self.last_result = result
            display_result = result if using_loaded_bin else self.preview_result_for_display(result)
            self.canvas_current.channel_index = self.active_output_channel_index()
            self.canvas_current.draw_waveform(
                display_result,
                preview_frequency_hz=self.display_preview_frequency_hz(),
                zoom_high_frequency=self.should_zoom_high_frequency_preview(),
            )
            config = self.build_config(result)

            def progress(done: int, total: int) -> None:
                if done == total or done % 100 == 0:
                    self.status.setText(f"正在发送波形数据 {done}/{total}")
                    QApplication.processEvents()

            network = self.prepare_udp_network_settings("Waveform send")
            frames = UdpWaveformClient(network).send_waveform(config, result.codes, progress)
            if using_loaded_bin:
                self.append_log(f"External BIN sent: {self.loaded_waveform_path}")
            self.append_log(self.format_ram_waveform_success_log(frames, config, result))
            self.status.setText("任意波形输出发送完成")
        except Exception as exc:
            self.append_log(f"波形发送失败: {exc}")
            self.status.setText("波形发送失败")

    def load_binary(self) -> None:
        try:
            path_text, _ = QFileDialog.getOpenFileName(
                self,
                "加载 DAC 波形 BIN",
                str(Path(__file__).resolve().parents[1] / "generated_waveforms"),
                "Binary (*.bin)",
            )
            if not path_text:
                return
            self.load_binary_path(Path(path_text))
        except Exception as exc:
            self.append_log(f"加载失败: {exc}")
            self.status.setText("Load failed")

    def load_binary_path(self, path: Path) -> None:
        self.preview_timer.stop()
        raw = np.fromfile(path, dtype="<i2")
        if raw.size == 0 or raw.size % 2 != 0:
            raise ValueError("BIN must contain interleaved int16 CH0/CH1 samples")
        sample_count = raw.size // 2
        if sample_count > MAX_WAVEFORM_SAMPLES:
            raise ValueError(f"BIN has {sample_count} samples; maximum is {MAX_WAVEFORM_SAMPLES}")
        codes = raw.reshape(sample_count, 2)
        volts = codes.astype(np.float64) / 32767.0 * float(self.full_scale.value())
        sample_rate_hz = self.waveform_settings().sample_rate_hz()
        time_s = np.arange(sample_count, dtype=np.float64) / max(sample_rate_hz, 1.0)
        self.sample_count.blockSignals(True)
        self.sample_count.setValue(sample_count)
        self.sample_count.blockSignals(False)
        self.loaded_waveform_path = path
        self.last_result = WaveformResult(
            time_s=time_s,
            volts=volts,
            codes=codes.astype("<i2", copy=False),
            source=f"BIN {path.name}",
            warnings=[],
        )
        ram_index = self.output_mode.findData("ram_waveform")
        if ram_index >= 0 and self.output_mode.currentIndex() != ram_index:
            self.output_mode.blockSignals(True)
            self.output_mode.setCurrentIndex(ram_index)
            self.output_mode.blockSignals(False)
            self.send_button.setEnabled(True)
            self.use_matlab.setEnabled(True)
            self.update_modulation_controls()
            self.update_main_nco_display()
        self.canvas_current.channel_index = self.active_output_channel_index()
        self.canvas_current.draw_waveform(
            self.last_result,
            preview_frequency_hz=self.preview_frequency_hz(),
            zoom_high_frequency=self.should_zoom_high_frequency_preview(),
        )
        self.append_log(f"BIN loaded: {path} ({sample_count} sample pairs)")
        self.status.setText(f"BIN loaded: {path.name}")

    def generate_text_binary(self) -> None:
        try:
            out_dir = Path(__file__).resolve().parents[1] / "generated_waveforms"
            out_dir.mkdir(parents=True, exist_ok=True)
            path = out_dir / "hanzi_zhong_time_ch0_i16.bin"
            sample_count = int(self.sample_count.value())
            sample_count = max(1024, min(sample_count, MAX_WAVEFORM_SAMPLES))
            codes = self.make_text_waveform_codes(sample_count, 0.82)
            codes.tofile(path)
            self.load_binary_path(path)
            self.append_log(f"Hanzi waveform generated: {path}")
        except Exception as exc:
            self.append_log(f"汉字信号生成失败: {exc}")
            self.status.setText("Text waveform failed")

    @staticmethod
    def make_text_waveform_codes(sample_count: int, amplitude: float) -> np.ndarray:
        glyph = np.asarray([
            [0, 0, 1, 0, 0],
            [0, 0, 1, 0, 0],
            [1, 1, 1, 1, 1],
            [1, 0, 1, 0, 1],
            [1, 1, 1, 1, 1],
            [0, 0, 1, 0, 0],
            [0, 0, 1, 0, 0],
        ], dtype=np.float64)
        image = np.kron(glyph, np.ones((5, 5), dtype=np.float64))
        image = image[::-1, :]
        rows, cols = image.shape
        segments: list[float] = []
        for row in range(rows):
            row_values = image[row, :]
            if row % 2:
                row_values = row_values[::-1]
            segments.extend(row_values.tolist())
            segments.extend([0.0, 0.0])
        base = np.asarray(segments, dtype=np.float64)
        if base.size == 0:
            base = np.zeros(1, dtype=np.float64)
        x_old = np.linspace(0.0, 1.0, base.size, endpoint=False)
        x_new = np.linspace(0.0, 1.0, sample_count, endpoint=False)
        y = np.interp(x_new, x_old, base, period=1.0)
        window = np.hanning(17)
        window = window / np.sum(window)
        y = np.convolve(y, window, mode="same")
        y = (2.0 * y - 1.0) * float(amplitude)
        ch0 = np.rint(np.clip(y, -1.0, 1.0) * 32767.0).astype("<i2")
        ch1 = np.zeros_like(ch0)
        return np.column_stack((ch0, ch1)).astype("<i2", copy=False)

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
        self.canvas_current.set_ui_font_size(font_size)
        if self.last_result is not None:
            display_result = self.preview_result_for_display(self.last_result)
            self.canvas_current.draw_waveform(
                display_result,
                preview_frequency_hz=self.display_preview_frequency_hz(),
                zoom_high_frequency=self.should_zoom_high_frequency_preview(),
            )


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
        QTableWidget {{
            background: #0f1722;
            alternate-background-color: #111f31;
            color: #e7f0ff;
            gridline-color: #1b2a3c;
            border: 1px solid #2a3545;
            selection-background-color: #1e6fcc;
            selection-color: #ffffff;
        }}
        QHeaderView::section {{
            background: #163a63;
            color: #eaf4ff;
            border: 1px solid #2c5f95;
            padding: 4px 6px;
            font-weight: 600;
        }}
        QTableCornerButton::section {{
            background: #163a63;
            border: 1px solid #2c5f95;
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
