function write_complex_ram_waveform_bin(out_bin_path, out_mat_path, sample_rate_hz, sample_count, full_scale_vpk, target_vpk)
%WRITE_COMPLEX_RAM_WAVEFORM_BIN Generate a periodic complex single-channel RAM waveform.
% Output format is HostApp interleaved int16 CH0/CH1, with CH1 held at zero.

sample_rate_hz = double(sample_rate_hz);
sample_count = double(sample_count);
full_scale_vpk = max(double(full_scale_vpk), eps);
target_vpk = double(target_vpk);

if sample_rate_hz <= 0
    error('sample_rate_hz must be positive');
end
if sample_count <= 0
    error('sample_count must be positive');
end

n = (0:(sample_count - 1)).';
t = n ./ sample_rate_hz;
bin_hz = sample_rate_hz ./ sample_count;

% Integer-bin tones keep the RAM loop phase-continuous.
k0 = 340;
k1 = 520;
k2 = 860;
k3 = 1220;
fm_k = 7;
am_k = 5;

phase0 = 2 .* pi .* k0 .* n ./ sample_count;
fm_phase = phase0 + 0.95 .* sin(2 .* pi .* fm_k .* n ./ sample_count);
envelope = 0.72 + 0.20 .* sin(2 .* pi .* am_k .* n ./ sample_count + 0.3) ...
              + 0.08 .* sin(2 .* pi .* 2 .* am_k .* n ./ sample_count + 1.1);

y = 0.50 .* envelope .* sin(fm_phase) ...
  + 0.26 .* sin(2 .* pi .* k1 .* n ./ sample_count + 0.4) ...
  + 0.16 .* sin(2 .* pi .* k2 .* n ./ sample_count + 1.3) ...
  + 0.09 .* sin(2 .* pi .* k3 .* n ./ sample_count + 2.1) ...
  + 0.05 .* sin(2 .* pi .* 2 .* k0 .* n ./ sample_count + 0.6) ...
  + 0.035 .* sin(2 .* pi .* 3 .* k0 .* n ./ sample_count + 1.7);

peak = max(abs(y));
if peak > 0
    y = y ./ peak .* target_vpk;
end

y0 = y;
y1 = zeros(size(y0));
volts = [y0, y1];
normalized = max(min(volts ./ full_scale_vpk, 1.0), -1.0);
codes = int16(round(normalized .* 32767.0));

fid = fopen(out_bin_path, 'w');
if fid < 0
    error('Could not open output BIN: %s', out_bin_path);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, reshape(codes.', [], 1), 'int16', 0, 'ieee-le');
clear cleanup;

metadata = struct();
metadata.sample_rate_hz = sample_rate_hz;
metadata.sample_count = sample_count;
metadata.full_scale_vpk = full_scale_vpk;
metadata.target_vpk = target_vpk;
metadata.bin_hz = bin_hz;
metadata.tone_bins = [k0, k1, k2, k3];
metadata.tone_hz = metadata.tone_bins .* bin_hz;
metadata.am_hz = am_k .* bin_hz;
metadata.fm_hz = fm_k .* bin_hz;

if nargin >= 2 && ~isempty(out_mat_path)
    save(out_mat_path, 't', 'y0', 'y1', 'codes', 'metadata');
end

fprintf('Wrote complex RAM waveform: %d sample pairs to %s\n', sample_count, out_bin_path);
fprintf('Tone frequencies: %.6f MHz, %.6f MHz, %.6f MHz, %.6f MHz\n', metadata.tone_hz ./ 1e6);
end
