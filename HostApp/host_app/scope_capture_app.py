from __future__ import annotations

import sys
import traceback
from pathlib import Path

import matplotlib
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.figure import Figure
from PyQt5.QtCore import QObject, QThread, Qt, pyqtSignal
from PyQt5.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QPushButton,
    QSpinBox,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from .scope_scpi import (
    DEFAULT_CAPTURE_POINTS,
    DEFAULT_MEASUREMENT_NAMES,
    DEFAULT_SCOPE_IP,
    DEFAULT_SCOPE_PORT,
    DEFAULT_SCOPE_TIMEOUT_S,
    PROFILE_SIGLENT,
    SUPPORTED_PROFILES,
    ScopeEndpoint,
    MeasurementCapture,
    WaveformCapture,
    capture_scope_waveform,
    query_scope_idn,
    query_scope_measurements,
    save_capture_outputs,
)


matplotlib.rcParams["font.sans-serif"] = [
    "Microsoft YaHei UI",
    "Microsoft YaHei",
    "SimHei",
    "Noto Sans CJK SC",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False


class ScopePlot(FigureCanvas):
    def __init__(self) -> None:
        self.figure = Figure(figsize=(8.0, 4.2), dpi=100, facecolor="#101722")
        super().__init__(self.figure)
        self.axes = self.figure.add_subplot(111)
        self._style_axes()

    def plot_capture(self, capture: WaveformCapture) -> None:
        self.axes.clear()
        self._style_axes()
        self.axes.plot(capture.time_s, capture.voltage_v, color="#48b4ff", linewidth=1.0)
        self.axes.set_title(f"{capture.channel} waveform", color="#e9eef6")
        self.axes.set_xlabel("Time (s)", color="#cbd6e2")
        self.axes.set_ylabel("Voltage (V)", color="#cbd6e2")
        self.figure.tight_layout()
        self.draw_idle()

    def _style_axes(self) -> None:
        self.axes.set_facecolor("#101722")
        self.axes.grid(True, color="#253244", linewidth=0.6, alpha=0.8)
        self.axes.tick_params(colors="#aab6c5", labelsize=9)
        for spine in self.axes.spines.values():
            spine.set_color("#2a3545")


class IdnWorker(QObject):
    finished = pyqtSignal(str)
    failed = pyqtSignal(str)

    def __init__(self, endpoint: ScopeEndpoint) -> None:
        super().__init__()
        self.endpoint = endpoint

    def run(self) -> None:
        try:
            self.finished.emit(query_scope_idn(self.endpoint))
        except Exception as exc:
            self.failed.emit(f"{exc}\n{traceback.format_exc()}")


class CaptureWorker(QObject):
    finished = pyqtSignal(object, object)
    failed = pyqtSignal(str)

    def __init__(
        self,
        endpoint: ScopeEndpoint,
        channel: str,
        profile: str,
        points: int,
        mode: str,
        output_dir: Path,
        stop_before_capture: bool,
        run_after_capture: bool,
        output_formats: tuple[str, ...],
    ) -> None:
        super().__init__()
        self.endpoint = endpoint
        self.channel = channel
        self.profile = profile
        self.points = points
        self.mode = mode
        self.output_dir = output_dir
        self.stop_before_capture = stop_before_capture
        self.run_after_capture = run_after_capture
        self.output_formats = output_formats

    def run(self) -> None:
        try:
            capture = capture_scope_waveform(
                endpoint=self.endpoint,
                channel=self.channel,
                profile=self.profile,
                points=self.points,
                mode=self.mode,
                stop_before_capture=self.stop_before_capture,
                run_after_capture=self.run_after_capture,
            )
            outputs = save_capture_outputs(capture, self.output_dir, self.output_formats)
            self.finished.emit(capture, outputs)
        except Exception as exc:
            self.failed.emit(f"{exc}\n{traceback.format_exc()}")


class MeasurementWorker(QObject):
    finished = pyqtSignal(object)
    failed = pyqtSignal(str)

    def __init__(self, endpoint: ScopeEndpoint, channel: str, profile: str) -> None:
        super().__init__()
        self.endpoint = endpoint
        self.channel = channel
        self.profile = profile

    def run(self) -> None:
        try:
            capture = query_scope_measurements(
                endpoint=self.endpoint,
                channel=self.channel,
                profile=self.profile,
                names=DEFAULT_MEASUREMENT_NAMES,
            )
            self.finished.emit(capture)
        except Exception as exc:
            self.failed.emit(f"{exc}\n{traceback.format_exc()}")


class ScopeCaptureWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Scope Capture")
        self.resize(980, 720)
        self._thread: QThread | None = None
        self._worker: QObject | None = None

        self.ip_edit = QLineEdit(DEFAULT_SCOPE_IP)
        self.port_spin = QSpinBox()
        self.port_spin.setRange(1, 65535)
        self.port_spin.setValue(DEFAULT_SCOPE_PORT)
        self.timeout_spin = QSpinBox()
        self.timeout_spin.setRange(1, 120)
        self.timeout_spin.setValue(int(DEFAULT_SCOPE_TIMEOUT_S))
        self.channel_combo = QComboBox()
        self.channel_combo.addItems(["CHAN1", "CHAN2", "CHAN3", "CHAN4"])
        self.profile_combo = QComboBox()
        self.profile_combo.addItems(SUPPORTED_PROFILES)
        self.profile_combo.setCurrentText(PROFILE_SIGLENT)
        self.mode_combo = QComboBox()
        self.mode_combo.addItems(["NORM", "RAW", "MAX"])
        self.points_spin = QSpinBox()
        self.points_spin.setRange(1, 100_000)
        self.points_spin.setValue(DEFAULT_CAPTURE_POINTS)
        self.output_edit = QLineEdit(str(Path(__file__).resolve().parents[1] / "captures"))
        self.stop_check = QCheckBox("Stop before capture")
        self.run_after_check = QCheckBox("Run after capture")
        self.csv_check = QCheckBox("CSV")
        self.csv_check.setChecked(True)
        self.npz_check = QCheckBox("NPZ")
        self.png_check = QCheckBox("PNG")

        self.idn_button = QPushButton("Test")
        self.measure_button = QPushButton("Measure")
        self.capture_button = QPushButton("Capture")
        self.output_button = QPushButton("Browse")
        self.status_label = QLabel("Ready")
        self.status_label.setWordWrap(True)
        self.summary_label = QLabel("No capture yet")
        self.summary_label.setWordWrap(True)
        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.plot = ScopePlot()

        self._build_ui()
        self._connect_signals()
        self._apply_style()

    def _build_ui(self) -> None:
        network_box = QGroupBox("Network")
        network_form = QFormLayout()
        network_form.addRow("IP", self.ip_edit)
        network_form.addRow("Port", self.port_spin)
        network_form.addRow("Timeout/s", self.timeout_spin)
        network_box.setLayout(network_form)

        capture_box = QGroupBox("Capture")
        capture_form = QFormLayout()
        capture_form.addRow("Channel", self.channel_combo)
        capture_form.addRow("Profile", self.profile_combo)
        capture_form.addRow("Mode", self.mode_combo)
        capture_form.addRow("Points", self.points_spin)
        capture_form.addRow("", self.stop_check)
        capture_form.addRow("", self.run_after_check)
        capture_box.setLayout(capture_form)

        format_row = QHBoxLayout()
        format_row.addWidget(self.csv_check)
        format_row.addWidget(self.npz_check)
        format_row.addWidget(self.png_check)
        format_row.addStretch(1)
        output_row = QHBoxLayout()
        output_row.addWidget(self.output_edit, 1)
        output_row.addWidget(self.output_button)
        output_box = QGroupBox("Output")
        output_form = QFormLayout()
        output_form.addRow("Directory", output_row)
        output_form.addRow("Formats", format_row)
        output_box.setLayout(output_form)

        button_row = QHBoxLayout()
        button_row.addWidget(self.idn_button)
        button_row.addWidget(self.measure_button)
        button_row.addWidget(self.capture_button)
        button_row.addStretch(1)

        left = QVBoxLayout()
        left.addWidget(network_box)
        left.addWidget(capture_box)
        left.addWidget(output_box)
        left.addLayout(button_row)
        left.addWidget(self.status_label)
        left.addWidget(self.summary_label)
        left.addWidget(self.log_text, 1)

        left_widget = QWidget()
        left_widget.setLayout(left)
        left_widget.setFixedWidth(330)

        content = QHBoxLayout()
        content.addWidget(left_widget)
        content.addWidget(self.plot, 1)

        root = QWidget()
        root.setLayout(content)
        self.setCentralWidget(root)

    def _connect_signals(self) -> None:
        self.idn_button.clicked.connect(self.test_connection)
        self.measure_button.clicked.connect(self.measure)
        self.capture_button.clicked.connect(self.capture)
        self.output_button.clicked.connect(self.choose_output_dir)

    def _apply_style(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget {
                background: #0d131d;
                color: #e9eef6;
                font-size: 13px;
            }
            QGroupBox {
                border: 1px solid #273242;
                border-radius: 6px;
                margin-top: 12px;
                padding: 10px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 8px;
                padding: 0 4px;
                color: #9fb1c7;
            }
            QLineEdit, QSpinBox, QComboBox, QTextEdit {
                background: #121b29;
                border: 1px solid #2b384a;
                border-radius: 4px;
                color: #e9eef6;
                padding: 5px;
            }
            QPushButton {
                background: #1e6ea7;
                border: 1px solid #2e8acb;
                border-radius: 4px;
                color: #ffffff;
                padding: 7px 10px;
            }
            QPushButton:disabled {
                background: #243040;
                border-color: #303c4d;
                color: #8793a2;
            }
            QLabel {
                color: #d4deeb;
            }
            """
        )

    def endpoint(self) -> ScopeEndpoint:
        return ScopeEndpoint(
            host=self.ip_edit.text().strip(),
            port=int(self.port_spin.value()),
            timeout=float(self.timeout_spin.value()),
        )

    def choose_output_dir(self) -> None:
        selected = QFileDialog.getExistingDirectory(self, "Select output directory", self.output_edit.text())
        if selected:
            self.output_edit.setText(selected)

    def test_connection(self) -> None:
        self._start_worker(IdnWorker(self.endpoint()), "Connecting...")

    def capture(self) -> None:
        worker = CaptureWorker(
            endpoint=self.endpoint(),
            channel=self.channel_combo.currentText(),
            profile=self.profile_combo.currentText(),
            points=int(self.points_spin.value()),
            mode=self.mode_combo.currentText(),
            output_dir=Path(self.output_edit.text().strip()),
            stop_before_capture=self.stop_check.isChecked(),
            run_after_capture=self.run_after_check.isChecked(),
            output_formats=self.selected_output_formats(),
        )
        self._start_worker(worker, "Capturing...")

    def measure(self) -> None:
        worker = MeasurementWorker(
            endpoint=self.endpoint(),
            channel=self.channel_combo.currentText(),
            profile=self.profile_combo.currentText(),
        )
        self._start_worker(worker, "Measuring...")

    def selected_output_formats(self) -> tuple[str, ...]:
        formats: list[str] = []
        if self.csv_check.isChecked():
            formats.append("csv")
        if self.npz_check.isChecked():
            formats.append("npz")
        if self.png_check.isChecked():
            formats.append("png")
        if not formats:
            self.csv_check.setChecked(True)
            formats.append("csv")
        return tuple(formats)

    def _start_worker(self, worker: QObject, busy_text: str) -> None:
        if self._thread is not None:
            return
        self._thread = QThread(self)
        self._worker = worker
        worker.moveToThread(self._thread)
        self._thread.started.connect(worker.run)
        if isinstance(worker, IdnWorker):
            worker.finished.connect(self._on_idn_finished)
        if isinstance(worker, CaptureWorker):
            worker.finished.connect(self._on_capture_finished)
        if isinstance(worker, MeasurementWorker):
            worker.finished.connect(self._on_measurement_finished)
        worker.failed.connect(self._on_worker_failed)
        worker.finished.connect(worker.deleteLater)
        worker.failed.connect(worker.deleteLater)
        worker.finished.connect(lambda *_args: self._request_thread_finish())
        worker.failed.connect(lambda *_args: self._request_thread_finish())
        self._thread.finished.connect(self._on_thread_finished)
        self._thread.finished.connect(self._thread.deleteLater)
        self.idn_button.setEnabled(False)
        self.measure_button.setEnabled(False)
        self.capture_button.setEnabled(False)
        self.status_label.setText(busy_text)
        self._thread.start()

    def _request_thread_finish(self) -> None:
        if self._thread is not None:
            self._thread.quit()

    def _on_thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self.idn_button.setEnabled(True)
        self.measure_button.setEnabled(True)
        self.capture_button.setEnabled(True)

    def _on_idn_finished(self, idn: str) -> None:
        self.status_label.setText("Connected")
        self._log(f"*IDN? {idn}")

    def _on_capture_finished(self, capture: WaveformCapture, outputs: dict[str, Path]) -> None:
        self.plot.plot_capture(capture)
        self.status_label.setText("Capture complete")
        self.summary_label.setText(
            f"{capture.channel}: {capture.points} points, "
            f"sample rate {capture.sample_rate_hz:.6g} Hz, "
            f"Vpp {capture.v_pp:.6g} V"
        )
        self._log(f"*IDN? {capture.idn}")
        self._log(f"profile={capture.profile}")
        for name, path in outputs.items():
            self._log(f"{name}: {path}")

    def _on_measurement_finished(self, capture: MeasurementCapture) -> None:
        self.status_label.setText("Measure complete")
        freq = capture.get("FREQ")
        amp = capture.get("AMP", "PKPK")
        freq_text = _format_measurement(freq)
        amp_text = _format_measurement(amp)
        self.summary_label.setText(f"{capture.channel}: freq {freq_text}, amplitude {amp_text}")
        self._log(f"*IDN? {capture.idn}")
        self._log(f"profile={capture.profile}")
        for measurement in capture.measurements.values():
            self._log(f"{measurement.name}: {_format_measurement(measurement)} raw={measurement.raw}")

    def _on_worker_failed(self, message: str) -> None:
        first_line = message.splitlines()[0] if message else "Unknown error"
        self.status_label.setText(f"Failed: {first_line}")
        self._log(message)

    def _log(self, message: str) -> None:
        self.log_text.append(message)


def _format_measurement(measurement: object | None) -> str:
    if measurement is None:
        return "N/A"
    value = getattr(measurement, "value", None)
    unit = getattr(measurement, "unit", "")
    if value is None:
        return "invalid"
    return f"{value:.9g}{unit}"


def main() -> None:
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    app = QApplication(sys.argv)
    window = ScopeCaptureWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
