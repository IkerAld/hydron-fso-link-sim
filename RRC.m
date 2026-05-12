%% rrc_visualization.m
% Standalone visualization of the root-raised-cosine pulse-shaping filter.
% No symbols, no waveform — just the filter, so you can see what RRC IS
% before using it.
%
% References:
%   Proakis & Salehi, Digital Communications, 5th ed., 2008, §9.2
%   Sklar, Digital Communications, 2nd ed., 2001, §3.3

clc; clear; close all;

%% Parameters (same as the TX script, kept consistent)
Rs      = 31.5e9;       % Symbol rate [Bd]
sps     = 4;            % Samples per symbol
Fs      = Rs * sps;     % Sample rate [Hz]
Ts      = 1/Rs;         % Symbol period [s]
rolloff = 0.1;          % RRC roll-off (verify ESTOL §3)
span    = 16;           % Filter span in symbols
%% Build the filter
% rcosdesign returns a normalized FIR filter.
% 'sqrt' = root-raised-cosine. 'normal' would give raised-cosine directly.
rrc = rcosdesign(rolloff, span, sps, 'sqrt');

% Time axis for the filter, in units of symbol periods
n_taps  = length(rrc);                         % = span*sps + 1 = 65
t_taps  = (-(n_taps-1)/2 : (n_taps-1)/2) / sps;  % in units of Ts

fprintf('Filter has %d taps, length = %.1f symbol periods\n', ...
        n_taps, span);

%% PLOT 1 — RRC impulse response in time
figure('Name','RRC impulse response','Position',[100 100 800 400]);
stem(t_taps, rrc, 'filled', 'MarkerSize', 4); hold on;
plot(t_taps, rrc, 'b-', 'LineWidth', 1);
yline(0, 'k:');
xline(0, 'k:');
grid on;
xlabel('Time t / T_s (symbol periods)');
ylabel('p_{RRC}(t)');
title(sprintf('RRC pulse, \\alpha = %.2f, span = %d T_s, sps = %d', ...
              rolloff, span, sps));
% Mark the symbol instants for reference
for k = -span/2 : span/2
    xline(k, 'r:', 'Alpha', 0.3);
end
legend('FIR taps','Continuous interp.','Location','northeast');

%% PLOT 2 — RRC frequency response
% freqz returns the DTFT of the filter; we rescale frequency to Hz using Fs.
[H_rrc, w] = freqz(rrc, 1, 4096, 'whole');
f = (w/(2*pi) - 0.5) * Fs;            % center around 0 Hz
H_rrc_centered = fftshift(H_rrc);

figure('Name','RRC frequency response','Position',[100 100 800 400]);
plot(f/1e9, 20*log10(abs(H_rrc_centered)/max(abs(H_rrc_centered))), ...
     'b-', 'LineWidth', 1.5);
grid on;
xlabel('Frequency [GHz]');
ylabel('|P_{RRC}(f)| [dB]');
title(sprintf('RRC frequency response, \\alpha = %.2f', rolloff));
ylim([-80 5]);
xlim([-Fs/2 Fs/2]/1e9);

% Mark the key frequencies
xline( Rs/(2)/1e9,            'r--', 'R_s/2');
xline(-Rs/(2)/1e9,            'r--');
xline( Rs*(1+rolloff)/2/1e9,  'g--', 'R_s(1+\alpha)/2');
xline(-Rs*(1+rolloff)/2/1e9,  'g--');
yline(-3, 'k:', '-3 dB');

%% PLOT 3 — Raised-cosine end-to-end (RRC * RRC)
% The cascade of TX and matched RX RRCs. THIS is the pulse that determines
% ISI at the symbol decision instants.
rc = conv(rrc, rrc);
n_rc   = length(rc);
t_rc   = (-(n_rc-1)/2 : (n_rc-1)/2) / sps;

figure('Name','End-to-end raised cosine','Position',[100 100 800 400]);
plot(t_rc, rc/max(rc), 'b-', 'LineWidth', 1.2); hold on;
% Sample at symbol instants — these MUST be zero except at t=0
sym_idx = 1 : sps : n_rc;
stem(t_rc(sym_idx), rc(sym_idx)/max(rc), 'r', 'filled', 'MarkerSize', 6);
yline(0, 'k:');
xline(0, 'k:');
grid on;
xlabel('Time t / T_s (symbol periods)');
ylabel('p_{RC}(t) (normalized)');
title('End-to-end raised cosine = RRC * RRC.  Red dots = symbol instants → ZERO ISI');
legend('Continuous','Sampled at nT_s','Location','northeast');

%% PLOT 4 — Compare three roll-off factors
% Build intuition for what alpha does
figure('Name','Effect of roll-off','Position',[100 100 1000 700]);
alphas = [0.1, 0.25, 0.5];
colors = {'b','r','g'};

% Time-domain comparison
subplot(2,1,1);
for i = 1:length(alphas)
    h = rcosdesign(alphas(i), span, sps, 'sqrt');
    t_h = (-(length(h)-1)/2 : (length(h)-1)/2) / sps;
    plot(t_h, h, colors{i}, 'LineWidth', 1.3); hold on;
end
grid on; yline(0,'k:'); xline(0,'k:');
xlabel('t / T_s'); ylabel('p_{RRC}(t)');
title('RRC time-domain pulse vs. \alpha');
legend(arrayfun(@(a) sprintf('\\alpha = %.2f',a), alphas, ...
                'UniformOutput', false));

% Frequency-domain comparison
subplot(2,1,2);
for i = 1:length(alphas)
    h = rcosdesign(alphas(i), span, sps, 'sqrt');
    [H,w] = freqz(h, 1, 4096, 'whole');
    H = fftshift(H);
    f = (w/(2*pi) - 0.5) * Fs;
    plot(f/1e9, 20*log10(abs(H)/max(abs(H))), ...
         colors{i}, 'LineWidth', 1.3); hold on;
end
grid on;
xlabel('Frequency [GHz]'); ylabel('|P_{RRC}(f)| [dB]');
title('RRC frequency response vs. \alpha');
ylim([-80 5]); xlim([-Fs/1.5 Fs/1.5]/1e9);
legend(arrayfun(@(a) sprintf('\\alpha = %.2f',a), alphas, ...
                'UniformOutput', false));

%% PLOT 5 — Verify the Nyquist ISI criterion numerically
% At t = nTs (n != 0), the RC pulse should be zero (machine precision).
isi_samples = rc(sym_idx);
[~, peak_idx] = max(abs(isi_samples));
isi_samples_normalized = isi_samples / isi_samples(peak_idx);

fprintf('\nNyquist ISI check (RC sampled at nT_s):\n');
fprintf('  Peak (n=0):     %.6f\n', isi_samples_normalized(peak_idx));
fprintf('  Max |ISI|:      %.2e\n', ...
        max(abs(isi_samples_normalized([1:peak_idx-1, peak_idx+1:end]))));
fprintf('  → Should be near zero (limited by truncation only).\n');