function write_fm_waveform_bin(out_bin_path, out_mat_path, sample_rate_hz, sample_count, full_scale_vpk, amp0_v, amp1_v, carrier_hz, mod_hz, deviation_hz, ch1_phase_deg)
%WRITE_FM_WAVEFORM_BIN Write interleaved int16 CH0/CH1 FM samples for HostApp UDP send.

[t, y0, y1, phase] = generate_fm_waveform(sample_rate_hz, sample_count, amp0_v, amp1_v, carrier_hz, mod_hz, deviation_hz, ch1_phase_deg);

full_scale_vpk = max(double(full_scale_vpk), eps);
volts = [y0(:), y1(:)];
normalized = max(min(volts ./ full_scale_vpk, 1.0), -1.0);
codes = int16(round(normalized .* 32767.0));

fid = fopen(out_bin_path, 'w');
if fid < 0
    error('Could not open output BIN: %s', out_bin_path);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, reshape(codes.', [], 1), 'int16', 0, 'ieee-le');
clear cleanup;

if nargin >= 2 && ~isempty(out_mat_path)
    save(out_mat_path, 't', 'y0', 'y1', 'phase', 'codes', ...
        'sample_rate_hz', 'sample_count', 'full_scale_vpk', ...
        'amp0_v', 'amp1_v', 'carrier_hz', 'mod_hz', 'deviation_hz', ...
        'ch1_phase_deg');
end

fprintf('Wrote %d sample pairs to %s\n', sample_count, out_bin_path);
end
