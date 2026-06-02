function [t, y0, y1, phase] = generate_fm_waveform(sample_rate_hz, sample_count, amp0_v, amp1_v, carrier_hz, mod_hz, deviation_hz, ch1_phase_deg)
%GENERATE_FM_WAVEFORM Generate a two-channel periodic FM waveform for AD9173 RAM playback.

if nargin < 8
    ch1_phase_deg = 90;
end

sample_rate_hz = double(sample_rate_hz);
sample_count = double(sample_count);
amp0_v = double(amp0_v);
amp1_v = double(amp1_v);
carrier_hz = double(carrier_hz);
mod_hz = double(mod_hz);
deviation_hz = double(deviation_hz);
ch1_phase_deg = double(ch1_phase_deg);

if sample_rate_hz <= 0
    error('sample_rate_hz must be positive');
end
if sample_count <= 0
    error('sample_count must be positive');
end
if mod_hz <= 0
    error('mod_hz must be positive');
end

t = (0:(sample_count - 1)).' ./ sample_rate_hz;
beta = deviation_hz ./ mod_hz;
phase = 2 .* pi .* carrier_hz .* t + beta .* sin(2 .* pi .* mod_hz .* t);
phase_offset = ch1_phase_deg .* pi ./ 180;

y0 = amp0_v .* sin(phase);
y1 = amp1_v .* sin(phase + phase_offset);
end
