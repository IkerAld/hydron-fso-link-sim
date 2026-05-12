%% 0. Environment Setup
clc; clear; close all;
rng(2025);                  % fixed seed

%% 1. System Parameters
% ESTOL - 100Gbps; DP-QPSK
Rs = 31.5e9;                % symbol rate
%Ts = 1/Rs = 31.75e-10 s (31.746 ps)

% Modulation --------------------------------------------------------------
num_symbols = 1e5;          % symbols per polarization ??
M = 4;                      % QPSK modulation order
k = log2(M);                % bits per symbol

% RRC Filter --------------------------------------------------------------
sps = 4;                    % samples per symbol on the line ??
Fs = Rs * sps;              % simulation sample rate [Hz]
rolloff = 0.5;              % roll-off ??
span = 16;                  % RRC filter span in symbols ??
%BW = Rs*(1+rolloff) = 34.65e9 Hz (34.65 GHz)

%% 2. Data Generation (PRBS)
% Generate independent random binary data for X and Y polarizations
% randi([0 1], rows, columns) creates a column vector of 1s and 0s
bits_X = randi([0 1], num_symbols * k, 1);
bits_Y = randi([0 1], num_symbols * k, 1);

%% 3. Symbol Mapping (DP-QPSK)
% Convert the the 2-bit pairs (e.g., [1 0]) into integers (0 to 3). 
% MSB by default
ints_X = bit2int(bits_X, k);
ints_Y = bit2int(bits_Y, k);

% Modulate th symbols into a gray QPSK
symbols_X = pskmod(ints_X, M, pi/4, 'gray');
symbols_Y = pskmod(ints_Y, M, pi/4, 'gray');

% Check unit symbol energy on each polarization
assert(abs(mean(abs(symbols_X).^2) - 1) < 1e-6,...
    'X-pol symbol energy != 1');
assert(abs(mean(abs(symbols_Y).^2) - 1) < 1e-6, ...
    'Y-pol symbol energy != 1');

%% 4. Pulse Shaping (Root-Raised Cosine)
% We create the Raised Cosine Filter
% https://es.mathworks.com/help/signal/ref/rcosdesign.html
rrc = rcosdesign(rolloff, span, sps, 'sqrt');
%impz(rrc)

% Visualize the RRC filter ------------------------------------------------
% Impulse response
%length(rrc) = 65 = span*sps+1
figure('Name','RRC impulse response');
t_taps = (-(length(rrc)-1)/2 : (length(rrc)-1)/2) / sps; 
stem(t_taps, rrc, 'filled'); grid on;
xlabel('t / T_s'); ylabel('p_{RRC}(t)');
title(sprintf('RRC: \\alpha=%.2f, span=%d, sps=%d → %d taps',...
    rolloff, span, sps, length(rrc)));

% Frequency response
% H = freq response
% f = frequencies in Hz
[H, f] = freqz(rrc, 1, 4096, Fs);    
freqz(rrc)

figure('Name','RRC frequency response');
plot(f/1e9, 20*log10(abs(H)/max(abs(H))), 'b-', 'LineWidth', 1.2);
grid on;
xlabel('Frequency [GHz]');
ylabel('|P_{RRC}(f)| [dB]');
title(sprintf('RRC frequency response, \\alpha = %.2f', rolloff));
ylim([-80 5]);

% Upsample and filter the data for pulse shaping---------------------------
tx_X = upfirdn(symbols_X, rrc, sps);
tx_Y = upfirdn(symbols_Y, rrc, sps);


%% 5. Visualization
% --- Symbol constellation (unchanged from before)
figure('Name','Tx symbols');
subplot(1,2,1);
plot(real(symbols_X), imag(symbols_X), 'bo', 'MarkerFaceColor','b');
title('X-Polarization (Ideal)'); xlabel('In-Phase (I)'); ...
    ylabel('Quadrature (Q)');
grid on; axis square; xlim([-1.5 1.5]); ylim([-1.5 1.5]);

subplot(1,2,2);
plot(real(symbols_Y), imag(symbols_Y), 'ro', 'MarkerFaceColor','r');
title('Y-Polarization'); xlabel('In-Phase (I)'); ylabel('Quadrature (Q)');
grid on; axis square; xlim([-1.5 1.5]); ylim([-1.5 1.5]);


%N = length(tx_X);
%X = fftshift(fft(tx_X)) / N;     % reorder + normalize
%f = (-N/2 : N/2-1) * Fs / N;     % proper frequency axis in Hz
%figure();
%plot(f/1e9, 20*log10(abs(X)));
%xlabel('Frequency [GHz]'); ylabel('|FFT| [dB]');
%grid on;

% TX power spectrum, BW should be Rs*(1+rolloff)
% 
% https://es.mathworks.com/help/signal/ref/pwelch.html
figure('Name','Tx spectrum');
subplot(1,2,1);
[Pxx, f] = pwelch(tx_X, hann(4096), 2048, 4096, Fs, 'centered');
plot(f/1e9, 10*log10(Pxx/max(Pxx)));     % normalized to peak at 0 dB
title(sprintf('Tx_x PSD — expected occupied BW \\approx %.2f GHz', ...
              Rs*(1+rolloff)/1e9));

subplot(1,2,2);
[Pxy, f] = pwelch(tx_Y, hann(4096), 2048, 4096, Fs, 'centered');
plot(f/1e9, 10*log10(Pxy/max(Pxy)));     % normalized to peak at 0 dB
title(sprintf('Tx_y PSD — expected occupied BW \\approx %.2f GHz', ...
              Rs*(1+rolloff)/1e9));

% Eye diagram
eyediagram(tx_X(span*sps+1 : span*sps+2000), 2*sps);
title('Tx_x eye diagram');

eyediagram(tx_Y(span*sps+1 : span*sps+2000), 2*sps);
title('Tx_y eye diagram');
