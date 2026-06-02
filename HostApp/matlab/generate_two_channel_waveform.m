function [t, y0, y1] = generate_two_channel_waveform(sample_rate_hz, sample_count, amp0_v, freq0_hz, en0, amp1_v, freq1_hz, en1)
%GENERATE_TWO_CHANNEL_WAVEFORM Generate two DAC waveform channels for the host app.
% Amplitudes are Vpk. Outputs are voltage-domain row vectors.

t = (0:sample_count-1) ./ sample_rate_hz;
y0 = zeros(1, sample_count);
y1 = zeros(1, sample_count);

if en0
    y0 = amp0_v .* sin(2*pi*freq0_hz.*t);
end

if en1
    y1 = amp1_v .* sin(2*pi*freq1_hz.*t);
end

end
