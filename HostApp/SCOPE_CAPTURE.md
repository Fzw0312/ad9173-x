# Oscilloscope waveform capture

This tool captures oscilloscope waveform data over LAN with SCPI.

Default oscilloscope network settings:

```text
IP: 10.9.122.165
Mask: 255.255.255.0
Gateway: 10.9.122.254
SCPI TCP port: 5025
```

Set the PC Ethernet adapter to the same subnet, for example:

```text
IP: 10.9.122.10
Mask: 255.255.255.0
Gateway: 10.9.122.254
```

Install dependencies if the local virtual environment does not already have them:

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
pip install PyQt5 numpy matplotlib
```

Run the GUI:

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\run_scope_capture.py
```

Test the SCPI connection:

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\tools\capture_scope_waveform.py --idn-only
```

Query automatic measurements, such as frequency and amplitude:

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\tools\capture_scope_waveform.py --measure --channel CHAN1
```

Query selected measurements and append them to CSV:

```powershell
python .\tools\capture_scope_waveform.py --measure --channel CHAN1 --measurement FREQ --measurement AMP --measurement PKPK --save-measurements
```

Capture CH1 and save CSV:

```powershell
cd D:\FPGA\ku5P\ad9173-x\HostApp
python .\tools\capture_scope_waveform.py --channel CHAN1 --points 1000
```

Useful options:

```text
--ip 10.9.122.165       Oscilloscope IP address
--port 5025             SCPI raw socket port
--channel CHAN1         Capture channel
--points 1000           Requested point count
--mode NORM             NORM, RAW, or MAX
--profile siglent       auto, generic, keysight, rigol, siglent, or tektronix
--stop                  Send :STOP before reading
--run-after             Send :RUN after reading
--output-dir captures   Output directory
```

If `--profile auto` cannot match the oscilloscope dialect, specify the vendor profile manually, for example `--profile keysight`, `--profile rigol`, or `--profile tektronix`.

Safety defaults for Siglent SDS2000X Plus:

- The default profile is `siglent`, so the script does not probe unsupported waveform commands first.
- The default point count is 1000, and the GUI limits Siglent capture requests to 100000 points.
- The default output is CSV only; enable NPZ or PNG only when needed.
- A lock file prevents two local capture processes from talking to the oscilloscope at the same time.
- After every query or capture, the tool sends a best-effort local-control command and closes the TCP socket.

If the oscilloscope front panel becomes unresponsive, close the host tool, wait for the LAN session to release, then press the scope `Local` key or restart the scope LAN service.
