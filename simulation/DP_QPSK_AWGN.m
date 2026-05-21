%% 0. Environment Setup
clc; clear; close all;
rng(2025);                  % fixed seed

%% 1. System Parameters

% ESTOL 100G DP-QPSK baseline
Rs = 31.5e9;                % symbol rate

Ts = 1/Rs;

% Modulation --------------------------------------------------------------
% DP-QPSK:
% QPSK = 2 bits/symbol/polarization
% DP = 2 polarizations
num_symbols = 1e6;          % symbols per polarization ??
M = 4;                      % QPSK modulation order
k = log2(M);                % bits per symbol
Npol = 2;                   % dual polarization

Rb_raw = Rs * k * Npol;     % raw bit rate before FEC/overheads [bit/s]

% RRC Filter --------------------------------------------------------------
sps = 4;                        % samples per symbol
rolloff = 0.2;                  % RRC roll-off factor - OpenROAD MSA Spec
span = 16;                      % RRC span in symbols

Fs = Rs * sps;                  % sampling frequency [Hz]
BW_null = Rs * (1 + rolloff);   % theoretical null-to-null bandwidth [Hz]

% Visualization -----------------------------------------------------------
fprintf('\n=== DP-QPSK TX Parameters ===\n');
fprintf('Symbol rate per pol      = %.2f Gbaud\n', Rs/1e9);
fprintf('Raw bit rate             = %.2f Gbps\n', Rb_raw/1e9);
fprintf('Samples per symbol       = %d\n', sps);
fprintf('Sampling frequency       = %.2f GSa/s\n', Fs/1e9);
fprintf('RRC roll-off             = %.2f\n', rolloff);
fprintf('Expected null-null BW    = %.2f GHz\n', BW_null/1e9);
fprintf('=============================\n\n');

%% 2. TX - Data Generation (PRBS)

% Not truly PRBS, in 2020_Nazir_32GBaud_DP-QPSK, they use 2^17 - 1 PRBS
% Generate independent random binary data for X and Y polarizations
% randi([0 1], rows, columns) creates a column vector of 1s and 0s
bits_X = randi([0 1], num_symbols * k, 1);
bits_Y = randi([0 1], num_symbols * k, 1);

%% 3. Symbol Mapping (DP-QPSK)

% Convert the the 2-bit pairs (e.g., [1 0]) into integers (0 to 3). 
% MSB by default
ints_X = bit2int(bits_X, k);
ints_Y = bit2int(bits_Y, k);

% Modulate the symbols into a gray QPSK
symbols_X = pskmod(ints_X, M, pi/4, 'gray');
symbols_Y = pskmod(ints_Y, M, pi/4, 'gray');
% Based on the OpenROAD standard the modulation are different
    %bX = reshape(bits_X, k, []).';     % rows: [bI bQ]
    %symbols_X = ((2*bX(:,1)-1) + 1j*(2*bX(:,2)-1)) / sqrt(2);
%bY = reshape(bits_Y, k, []).';
%symbols_Y = ((2*bY(:,1)-1) + 1j*(2*bY(:,2)-1)) / sqrt(2);

% Check symbol energy
Es_X = mean(abs(symbols_X).^2);
Es_Y = mean(abs(symbols_Y).^2);

fprintf('Mean symbol energy X-pol = %.6f\n', Es_X);
fprintf('Mean symbol energy Y-pol = %.6f\n\n', Es_Y);

assert(abs(Es_X - 1) < 1e-6, 'X-pol symbol energy is not 1');
assert(abs(Es_Y - 1) < 1e-6, 'Y-pol symbol energy is not 1');

%% 4. TX - Pulse Shaping (Root-Raised Cosine)

% We create the Raised Cosine Filter
% https://es.mathworks.com/help/signal/ref/rcosdesign.html
rrc = rcosdesign(rolloff, span, sps, 'sqrt');
%impz(rrc)

% Filter length
% N_h = span * sps + 1;
fprintf('RRC filter length        = %d taps\n', length(rrc));
fprintf('RRC filter energy        = %.6f\n\n', sum(abs(rrc).^2));

% Upsample and filter the data for pulse shaping
% https://www.mathworks.com/help/signal/ref/upfirdn.html
% sps - upsampling
tx_X = upfirdn(symbols_X, rrc, sps);
tx_Y = upfirdn(symbols_Y, rrc, sps);

% Average waveform sample power
Ptx_X_norm = mean(abs(tx_X).^2);
Ptx_Y_norm = mean(abs(tx_Y).^2);

fprintf('Mean sample power X-pol  = %.6f\n', Ptx_X_norm);
fprintf('Mean sample power Y-pol  = %.6f\n', Ptx_Y_norm);
fprintf('Expected approx.         = %.6f (= 1/sps)\n\n', 1/sps);

%% 5. TX - Visualization

% 5.1 Ideal QPSK constellation before pulse shaping -----------------------
figure('Name','Tx Symbols');

subplot(1,2,1);
plot(real(symbols_X), imag(symbols_X), 'bo', 'MarkerFaceColor','b');
grid on; axis square;
xlabel('In-Phase (I)');
ylabel('Quadrature (Q)');
title('X-Polarization'); 
xlim([-1.5 1.5]); ylim([-1.5 1.5]);

subplot(1,2,2);
plot(real(symbols_Y), imag(symbols_Y), 'ro', 'MarkerFaceColor','r');
grid on; axis square;
xlabel('In-Phase (I)'); 
ylabel('Quadrature (Q)');
title('Y-Polarization'); 
xlim([-1.5 1.5]); ylim([-1.5 1.5]);

% 5.2 RRC impulse response ----------------------------------------------
figure('Name','RRC Impulse Response');

t_taps = (-(length(rrc)-1)/2 : (length(rrc)-1)/2) / sps;

stem(t_taps, rrc, 'filled');
grid on;
xlabel('Time [symbols]');
ylabel('Amplitude');
title(sprintf('RRC impulse response: rolloff = %.2f, span = %d, sps = %d', ...
    rolloff, span, sps));

% 5.3 RRC frequency response ----------------------------------------------
figure('Name','RRC Frequency Response');

% H = freq response
% f = frequencies in Hz
[H, f] = freqz(rrc, 1, 4096, Fs);

plot(f/1e9, 20*log10(abs(H)/max(abs(H))), 'LineWidth', 1.2);
grid on;
xlabel('Frequency [GHz]');
ylabel('Magnitude [dB]');
title('RRC frequency response');
ylim([-80 5]);

% 5.4 Transmitted spectrum ------------------------------------------------
figure('Name','Tx Spectrum');

nfft = 4096;
win = hann(2048);
noverlap = 1024;

% https://es.mathworks.com/help/signal/ref/pwelch.html
[Pxx, f_psd] = pwelch(tx_X, win, noverlap, nfft, Fs, 'centered');
[Pyy, ~]     = pwelch(tx_Y, win, noverlap, nfft, Fs, 'centered');

plot(f_psd/1e9, 10*log10(Pxx/max(Pxx)), 'b', 'LineWidth', 1.2);
hold on;
plot(f_psd/1e9, 10*log10(Pyy/max(Pyy)), 'r--', 'LineWidth', 1.2);
grid on;

xlabel('Frequency [GHz]');
ylabel('Normalized PSD [dB]');
title(sprintf('DP-QPSK Tx spectrum, expected null-null BW = %.2f GHz', ...
    BW_null/1e9));
legend('X-pol', 'Y-pol', 'Location', 'best');
ylim([-80 5]);

% 5.5 Eye diagrams of pulse-shaped waveform -------------------------------
eye_tx1 = real(tx_X(span*sps+1 : span*sps+4000));
eye_tx2 = real(tx_Y(span*sps+1 : span*sps+4000));
eye_tx = [eye_tx1, eye_tx2];

eyediagram(eye_tx, 2*sps);

% Grab the axes handles from the current figure
ax = findobj(gcf, 'Type', 'axes');

% Note: findobj grabs handles in reverse order of creation!
% ax(1) is the RIGHT plot, ax(2) is the LEFT plot.
title(ax(2), 'X-pol I-component eye diagram');
title(ax(1), 'Y-pol I-component eye diagram');

%% 6. AWGN Channel: Additive White Gaussian Noise, no fading, no impairments

% Physically this is one optical DP-QPSK signal.
% In baseband simulation we keep the two polarizations separate.
tx_DP = [tx_X, tx_Y];

% AWGN channel: receiver gets a noised signal
EbN0_dB_vec = 0:1:12;               % Sweep of values to plot the BER
EbN0_lin = 10.^(EbN0_dB_vec/10);

BER_X = zeros(size(EbN0_dB_vec));
BER_Y = zeros(size(EbN0_dB_vec));
BER_total = zeros(size(EbN0_dB_vec));

SER_X = zeros(size(EbN0_dB_vec));
SER_Y = zeros(size(EbN0_dB_vec));
SER_total = zeros(size(EbN0_dB_vec));
SER_DP = zeros(size(EbN0_dB_vec));  

% Exact uncoded Gray-QPSK theory
BER_theory = qfunc(sqrt(2*EbN0_lin));
SER_theory = 2*BER_theory - BER_theory.^2;
SER_DP_theory = 1 - (1 - SER_theory).^2;

% Filters group delay
% Tx RRC group delay = ((span*sps+1) - 1) / 2
% Rx RRC group delay = ((span*sps+1) - 1) / 2
% Total delay  = (((span*sps+1) - 1) / 2) + (((span*sps+1) - 1) / 2)
total_delay = span * sps;

for i = 1:length(EbN0_dB_vec)
    EbN0 = 10^(EbN0_dB_vec(i)/10);

    % QPSK: Es/N0 = k Eb/N0, with Es = 1
    EsN0 = k * EbN0;
    N0 = 1 / EsN0;

    noise_X = sqrt(N0/2) * ...
        (randn(size(tx_X)) + 1j*randn(size(tx_X)));

    noise_Y = sqrt(N0/2) * ...
        (randn(size(tx_Y)) + 1j*randn(size(tx_Y)));

    rx_X = tx_DP(:,1) + noise_X;
    rx_Y = tx_DP(:,2) + noise_Y;

    % Receiver matched filter uses the same RRC filter
    % No up/downsampling
    rxmf_X = upfirdn(rx_X, rrc);
    rxmf_Y = upfirdn(rx_Y, rrc);

    % Downsample at symbol instants
    rx_symbols_X = rxmf_X(total_delay + 1 : sps : total_delay + num_symbols*sps);
    rx_symbols_Y = rxmf_Y(total_delay + 1 : sps : total_delay + num_symbols*sps);

    % Demodulate the gray QPSK into symbols
    ints_hat_X = pskdemod(rx_symbols_X, M, pi/4, 'gray');
    ints_hat_Y = pskdemod(rx_symbols_Y, M, pi/4, 'gray');

    % Convert the the integers (0 to 3) into 2-bit pairs (e.g., [1 0]). 
    % MSB by default
    bits_hat_X = int2bit(ints_hat_X, k);
    bits_hat_Y = int2bit(ints_hat_Y, k);

    % BER
    BER_X(i) = mean(bits_X ~= bits_hat_X);
    BER_Y(i) = mean(bits_Y ~= bits_hat_Y);
    BER_total(i) = mean([bits_X ~= bits_hat_X; bits_Y ~= bits_hat_Y]);

    % SER
    tx_bits_X_sym = reshape(bits_X, k, []).';
    tx_bits_Y_sym = reshape(bits_Y, k, []).';

    rx_bits_X_sym = reshape(bits_hat_X, k, []).';
    rx_bits_Y_sym = reshape(bits_hat_Y, k, []).';

    sym_err_X = any(tx_bits_X_sym ~= rx_bits_X_sym, 2);
    sym_err_Y = any(tx_bits_Y_sym ~= rx_bits_Y_sym, 2);

    SER_X(i)     = mean(sym_err_X);
    SER_Y(i)     = mean(sym_err_Y);
    SER_total(i) = mean([sym_err_X; sym_err_Y]);

    % DP-symbol error: one error if X or Y symbol is wrong
    SER_DP(i) = mean(sym_err_X | sym_err_Y);

end


%% 10. RX - Visualization

% 10.1 Received spectrum --------------------------------------------------
figure('Name','Rx Spectrum after Matched Filter');

% https://es.mathworks.com/help/signal/ref/pwelch.html
[Pxx_r, f_psd_r] = pwelch(rxmf_X, win, noverlap, nfft, Fs, 'centered');
[Pyy_r, ~]     = pwelch(rxmf_Y, win, noverlap, nfft, Fs, 'centered');

plot(f_psd_r/1e9, 10*log10(Pxx_r/max(Pxx_r)), 'b', 'LineWidth', 1.2);
hold on;
plot(f_psd_r/1e9, 10*log10(Pyy_r/max(Pyy_r)), 'r--', 'LineWidth', 1.2);
grid on;

xlabel('Frequency [GHz]');
ylabel('Normalized PSD [dB]');
title(sprintf('DP-QPSK Rx spectrum after matched filter, expected null-null BW = %.2f GHz', ...
    BW_null/1e9));
legend('X-pol', 'Y-pol', 'Location', 'best');
ylim([-80 5]);

% 10.2 Eye diagrams after channel -----------------------------------------
eye_rx1 = real(rxmf_X(span*sps+1 : span*sps+4000));
eye_rx2 = real(rxmf_Y(span*sps+1 : span*sps+4000));
eye_rx = [eye_rx1, eye_rx2];

eyediagram(eye_rx, 2*sps);

% Grab the axes handles from the current figure
ax2 = findobj(gcf, 'Type', 'axes');

title(ax2(2), 'X-pol I-component eye diagram after matched filter');
title(ax2(1), 'Y-pol I-component eye diagram after matched filter');

% 10.2 Received constellation after matched filter ------------------------
figure('Name','Rx Symbols after Matched Filter');

subplot(1,2,1);
plot(real(rx_symbols_X(1:2000)), imag(rx_symbols_X(1:2000)), 'bo', ...
    'MarkerFaceColor','b');
grid on; axis square;
xlabel('In-Phase (I)');
ylabel('Quadrature (Q)');
title('Recovered X-Pol. symbols'); 
xlim([-1.5 1.5]); ylim([-1.5 1.5]);

subplot(1,2,2);
plot(real(rx_symbols_Y(1:2000)), imag(rx_symbols_Y(1:2000)), 'ro', ...
    'MarkerFaceColor','r');
grid on; axis square;
xlabel('In-Phase (I)');
ylabel('Quadrature (Q)');
title('Recovered Y-Pol. symbols'); 
xlim([-1.5 1.5]); ylim([-1.5 1.5]);

% 10.3 BER Plot -----------------------------------------------------------
figure('Name','BER vs EbN0');

semilogy(EbN0_dB_vec, BER_theory, 'k-', 'LineWidth', 1.5);
hold on;
semilogy(EbN0_dB_vec, BER_X, 'bo-');
semilogy(EbN0_dB_vec, BER_Y, 'rs-');
semilogy(EbN0_dB_vec, BER_total, 'md-');
grid on;
xlabel('E_b/N_0 [dB]');
ylabel('BER');
title('Gray-coded DP-QPSK AWGN BER validation');
legend('Theory QPSK', 'X-pol', 'Y-pol', 'Total', ...
       'Location', 'southwest');
ylim([1e-6 1]);

% 10.4 SER Plot -----------------------------------------------------------
figure('Name','SER vs EbN0');

semilogy(EbN0_dB_vec, SER_theory, 'k-', 'LineWidth', 1.5);
hold on;
semilogy(EbN0_dB_vec, SER_X, 'bo-');
semilogy(EbN0_dB_vec, SER_Y, 'rs-');
semilogy(EbN0_dB_vec, SER_total, 'md-');
semilogy(EbN0_dB_vec, SER_DP, 'g^-');
semilogy(EbN0_dB_vec, SER_DP_theory, 'k--', 'LineWidth', 1.2);
grid on;
xlabel('E_b/N_0 [dB]');
ylabel('SER');
title('Gray-coded DP-QPSK AWGN SER validation');
legend('Theory per-pol QPSK', 'X-pol', 'Y-pol', ...
       'Total per-pol', 'DP-symbol sim', 'DP-symbol theory', ...
       'Location', 'southwest');
ylim([1e-6 1]);