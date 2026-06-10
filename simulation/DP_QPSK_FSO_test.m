%% 0. Environment Setup
clc;
clear;
close all;
%rng(2025); % h_turb_norm = 1.0657, h_point_norm = 1.0290
rng(256); % h_turb_norm = 0.3147, h_point_norm = 1.0284

% Latex setup
set(groot, 'defaultTextInterpreter', 'latex');
set(groot, 'defaultLegendInterpreter', 'latex');
set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
% Typography
set(groot, 'defaultAxesFontSize', 12); % tick labels
set(groot, 'defaultAxesLabelFontSizeMultiplier', 13/12); % axis labels ≈ 13 pt
set(groot, 'defaultAxesTitleFontSizeMultiplier', 14/12); % title ≈ 14 pt
set(groot, 'defaultAxesTitleFontWeight', 'normal');
% Lines and axes
set(groot, 'defaultLineLineWidth', 1.3);
set(groot, 'defaultAxesBox', 'on');
set(groot, 'defaultAxesXGrid', 'on');
set(groot, 'defaultAxesYGrid', 'on');

%% 1. System Parameters

% 1.1 ESTOL 100G DP-QPSK baseline modulation config -----------------------
% DP-QPSK:
% QPSK = 2 bits/symbol/polarization
% DP = 2 polarizations
sig.Rs = 31.5e9; % symbol rate [bauds]
%sig.num_sym = 1e6; % symbols per polarization
sig.num_sym = 1e5; % DEVELOPMENT SIZE
sig.M = 4; % QPSK modulation order
sig.Npol = 2; % dual polarization
% RRC Filter
sig.sps = 4; % samples per symbol
sig.rolloff = 0.2; % RRC roll-off factor - OpenROAD MSA Spec
sig.span = 16; % RRC sig.span in symbols
% OpenROADM / ESTOL specs
% Pre-FEC BER threshold oFEC
sig.BER_preFEC = 2.0e-2;
% Calculated variables
sig.Ts = 1 / sig.Rs;
sig.k = log2(sig.M); % bits per symbol
sig.Rb_raw = sig.Rs * sig.k * sig.Npol; % raw bit rate before FEC/overheads [bit/s]
sig.Fs = sig.Rs * sig.sps; % sampling frequency [Hz]
sig.BW_null = sig.Rs * (1 + sig.rolloff); % theoretical null-to-null bandwidth [Hz]

% 1.2 FSO scenario inputs -------------------------------------------------
% Worst-case design point: el = 15 deg, 1550 nm band, bad conditions.
% Check Link Budget for more info
% Site characteristics
scen.h_site = 578; % site altitude above MSL [m]
scen.h_site_ogs = 598; % OGS altitude above MSL [m]
scen.D_rx = 0.8; % OGS telescope diameter [m]
% Atmospheric effects
scen.el_deg = 15; % design elevation [deg]
scen.el_rad = deg2rad(scen.el_deg);
scen.wl = 1554.13e-9; % wavelength [m], ESTOL L2
scen.t_z = 0.891; % zenith transmittance bad, 1550 nm
% Turbulence effects
scen.h_orbit = 530e3; % satellite altitude [m]
% Calculated variables
scen.h_ogs = scen.h_site_ogs - scen.h_site;
% Pointing effects
scen.R_E = 6371e3; % mean Earth radius [m]
scen.theta_tx_rad = 380e-6; % FWHM [rad]
% Calculated variables
scen.l_slant = sqrt((scen.R_E + scen.h_ogs).^2.*sin(scen.el_rad).^2 ...
    +2*(scen.h_orbit - scen.h_ogs).*(scen.R_E + scen.h_ogs) ...
    +(scen.h_orbit - scen.h_ogs).^2) - (scen.R_E + scen.h_ogs) .* sin(scen.el_rad); % [m]
scen.w_z = scen.l_slant * scen.theta_tx_rad; % 1/e^2 beam radius at ground [m]
scen.a_rx = scen.D_rx / 2; % aperture radius [m]
scen.nu_ap = sqrt(pi) * scen.a_rx / (sqrt(2) * scen.w_z); % Farid nu parameter [-]
scen.A0_pt = erf(scen.nu_ap)^2; % on-axis collected fraction [-]
% Pre-lock pointing jitter
%scen.sigma_jit_rad = 0.85 * scen.theta_tx_rad / 2; % RMS jitter per axis [rad]
% Post-lock pointing jitter
scen.sigma_jit_rad = 35e-6; % per-axis RMS, worst case TBIRD (Y axis)
%scen.beta_pj = scen.theta_tx_rad^2 / (4 * log(2) * (scen.sigma_jit_rad^2) );
scen.beta_pj = scen.theta_tx_rad^2 / scen.sigma_jit_rad^2 / (8 * log(2));

% 1.3 FSO channel inputs --------------------------------------------------
% Lognormal sampling
ch.n_distr = 2e5;
% Simulation
ch.EbN0_dB_vec = 0:1:12; % Sweep of values to plot the BER
%ch.nframes = 200; % The bigger, the bigger the tails
ch.nframes = 20; % DEVELOPMENT SIZE
% Aperture averaging
ch.h_d = 12e3; % Tropopause layer height [m]
ch.el_max_deg = 10; % Angle used in the GB paper

% 1.4 Visualization -------------------------------------------------------
fprintf('\n=== DP-QPSK TX Parameters ===\n');
fprintf('Symbol rate per pol      = %.2f Gbaud\n', sig.Rs/1e9);
fprintf('Raw bit rate             = %.2f Gbps\n', sig.Rb_raw/1e9);
fprintf('Samples per symbol       = %d\n', sig.sps);
fprintf('Sampling frequency       = %.2f GSa/s\n', sig.Fs/1e9);
fprintf('RRC roll-off             = %.2f\n', sig.rolloff);
fprintf('Expected null-null BW    = %.2f GHz\n', sig.BW_null/1e9);
fprintf('=============================\n');

fprintf('\n=== FSO Scenario ===\n');
fprintf('Site altitude            = %.1f m\n', scen.h_site);
fprintf('OGS height               = %.1f m\n', scen.h_ogs);
fprintf('Site OGS altitude        = %.1f m\n', scen.h_site_ogs);
fprintf('Design elevation         = %.1f deg\n', scen.el_deg);
fprintf('Wavelength               = %.2f nm\n', scen.wl*1e9);
fprintf('Zenith transmittance     = %.3f\n', scen.t_z);
fprintf('====================\n\n');

%% 2. TX - Data Generation (PRBS)

% Not truly PRBS, in 2020_Nazir_32GBaud_DP-QPSK, they use 2^17 - 1 PRBS
% Generate independent random binary data for X and Y polarizations
% randi([0 1], rows, columns) creates a column vector of 1s and 0s
bits_X = randi([0, 1], sig.num_sym*sig.k, 1);
bits_Y = randi([0, 1], sig.num_sym*sig.k, 1);

%% 3. TX - Symbol Mapping (DP-QPSK)

% Convert the the 2-bit pairs (e.g., [1 0]) into integers (0 to 3).
% MSB by default
%ints_X = bit2int(bits_X, sig.k);
%ints_Y = bit2int(bits_Y, sig.k);

% Bits per polarization: [bI bQ]
bX = reshape(bits_X, sig.k, []).'; % Nsym x 2, columns = [bI bQ]
bY = reshape(bits_Y, sig.k, []).';

% OpenROADM relative amplitude map, normalized to unit symbol energy
symbols_X = ((2*bX(:,1)-1) + 1j*(2*bX(:,2)-1)) / sqrt(2);
symbols_Y = ((2*bY(:,1)-1) + 1j*(2*bY(:,2)-1)) / sqrt(2);

% Modulate the symbols into a gray QPSK
%symbols_X = pskmod(ints_X, sig.M, pi/4, 'gray');
%symbols_Y = pskmod(ints_Y, sig.M, pi/4, 'gray');

% Check symbol energy
Es_X = mean(abs(symbols_X).^2);
Es_Y = mean(abs(symbols_Y).^2);

fprintf('Mean symbol energy X-pol = %.6f\n', Es_X);
fprintf('Mean symbol energy Y-pol = %.6f\n\n', Es_Y);

assert(abs(Es_X-1) < 1e-6, 'X-pol symbol energy is not 1');
assert(abs(Es_Y-1) < 1e-6, 'Y-pol symbol energy is not 1');

%% 4. TX - Pulse Shaping (Root-Raised Cosine)

% We create the Raised Cosine Filter
% https://es.mathworks.com/help/signal/ref/rcosdesign.html
rrc = rcosdesign(sig.rolloff, sig.span, sig.sps, 'sqrt');
%impz(rrc)

% Filter length
% N_h = sig.span * sig.sps + 1;
fprintf('RRC filter length        = %d taps\n', length(rrc));
fprintf('RRC filter energy        = %.6f\n\n', sum(abs(rrc).^2));

% Upsample and filter the data for pulse shaping
% https://www.mathworks.com/help/signal/ref/upfirdn.html
% sig.sps - upsampling
tx_X = upfirdn(symbols_X, rrc, sig.sps);
tx_Y = upfirdn(symbols_Y, rrc, sig.sps);

% Average waveform sample power
Ptx_X_norm = mean(abs(tx_X).^2);
Ptx_Y_norm = mean(abs(tx_Y).^2);

fprintf('Mean sample power X-pol  = %.6f\n', Ptx_X_norm);
fprintf('Mean sample power Y-pol  = %.6f\n', Ptx_Y_norm);
fprintf('Expected approx.         = %.6f (= 1/sps)\n\n', 1/sig.sps);

%% 5. TX - Visualization

% 5.1 Ideal QPSK constellation before pulse shaping -----------------------
figure('Name', 'Tx Symbols');

subplot(1, 2, 1);
plot(real(symbols_X), imag(symbols_X), 'bo', 'MarkerFaceColor', 'b');
grid on; axis square;
xlabel('In-Phase (I)');
ylabel('Quadrature (Q)');
title('X-Polarization');
xlim([-1.5, 1.5]);
ylim([-1.5, 1.5]);

subplot(1, 2, 2);
plot(real(symbols_Y), imag(symbols_Y), 'ro', 'MarkerFaceColor', 'r');
grid on; axis square;
xlabel('In-Phase (I)');
ylabel('Quadrature (Q)');
title('Y-Polarization');
xlim([-1.5, 1.5]);
ylim([-1.5, 1.5]);

% 5.1b Ideal QPSK constellation before pulse shaping ----------------------
figure('Name','Tx Symbols alt');

theta = linspace(0, 2*pi, 500);
unit_circle = exp(1j*theta);

tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

% X-polarization
nexttile;
plot(real(unit_circle), imag(unit_circle), 'k--', ...
    'LineWidth', 0.8, 'Color', [0.45 0.45 0.45]);
hold on;
plot(real(symbols_X), imag(symbols_X), 'bo', ...
    'MarkerFaceColor', 'b', ...
    'MarkerSize', 5);
grid on; axis square;
xlabel('In-phase ($I$)');
ylabel('Quadrature ($Q$)');
title('X-Polarization');
xlim([-1.5 1.5]); ylim([-1.5 1.5]);

% Y-polarization
nexttile;
plot(real(unit_circle), imag(unit_circle), 'k--', ...
    'LineWidth', 0.8, 'Color', [0.45 0.45 0.45]);
hold on;
plot(real(symbols_Y), imag(symbols_Y), 'ro', ...
    'MarkerFaceColor', 'r', ...
    'MarkerSize', 5);
grid on; axis square;
xlabel('In-phase Amplitude ($I$)');
ylabel('Quadrature Amplitude ($Q$)');
title('Y-Polarization');
xlim([-1.5 1.5]); ylim([-1.5 1.5]);


% 5.2 RRC impulse response ----------------------------------------------
figure('Name', 'RRC Impulse Response');

t_taps = (-(length(rrc) - 1) / 2:(length(rrc) - 1) / 2) / sig.sps;

stem(t_taps, rrc, 'filled');
grid on;
xlabel('Time [symbols]');
ylabel('Amplitude');
title(sprintf('RRC impulse response: rolloff = %.2f, span = %d, sps = %d', ...
    sig.rolloff, sig.span, sig.sps));

% 5.3 RRC frequency response ----------------------------------------------
figure('Name', 'RRC Frequency Response');

% H = freq response
% f = frequencies in Hz
[H, f] = freqz(rrc, 1, 4096, sig.Fs);

plot(f/1e9, 20*log10(abs(H)/max(abs(H))));
grid on;
xlabel('Frequency [GHz]');
ylabel('Magnitude [dB]');
title('RRC frequency response');
ylim([-80, 5]);

% 5.4 Transmitted spectrum ------------------------------------------------
figure('Name', 'Tx Spectrum');

nfft = 4096;
win = hann(2048);
noverlap = 1024;

% https://es.mathworks.com/help/signal/ref/pwelch.html
[Pxx, f_psd] = pwelch(tx_X, win, noverlap, nfft, sig.Fs, 'centered');
[Pyy, ~] = pwelch(tx_Y, win, noverlap, nfft, sig.Fs, 'centered');

plot(f_psd/1e9, 10*log10(Pxx/max(Pxx)), 'b');
hold on;
plot(f_psd/1e9, 10*log10(Pyy/max(Pyy)), 'r--');
grid on;

xlabel('Frequency [GHz]');
ylabel('Normalized PSD [dB]');
title(sprintf('DP-QPSK Tx spectrum, expected null-null BW = %.2f GHz', ...
    sig.BW_null/1e9));
legend('X-pol', 'Y-pol', 'Location', 'best');
ylim([-80, 5]);

% 5.5 Eye diagrams of pulse-shaped waveform -------------------------------
eye_tx1 = real(tx_X(sig.span*sig.sps+1:sig.span*sig.sps+4000));
eye_tx2 = real(tx_Y(sig.span*sig.sps+1:sig.span*sig.sps+4000));
eye_tx = [eye_tx1, eye_tx2];

eyediagram(eye_tx, 2*sig.sps);

% Grab the axes handles from the current figure
ax = findobj(gcf, 'Type', 'axes');

% Note: findobj grabs handles in reverse order of creation!
% ax(1) is the RIGHT plot, ax(2) is the LEFT plot.
title(ax(2), 'X-pol I-component eye diagram');
title(ax(1), 'Y-pol I-component eye diagram');

%% 6. Free Space Optical Channel - Setup

% 6.1 Atmospheric effects -------------------------------------------------
% Beer-Lambert with plane-parallel airmass m = 1/sin(el).
% Valid for el >~ 10 deg; below that, use Kasten-Young airmass.
% Refer to Giggenbach paper
m_air = 1 / sin(scen.el_rad); % airmass
h_atm = scen.t_z^m_air; % linear power transmittance
a_atm_dB = 10 * log10(h_atm); % [dB], negative = loss

fprintf('=== FSO Channel: atmosphere ===\n');
fprintf('Airmass                  = %.3f\n', m_air);
fprintf('h_atm (linear power)     = %.4f\n', h_atm);
fprintf('a_atm                    = %.2f dB\n', a_atm_dB);
fprintf('===============================\n\n');

% 6.2 Turbulence effects --------------------------------------------------
% h starts with the ogs height
h_low = linspace(scen.h_site_ogs, scen.h_site_ogs+2e3, 500); % OGS-2 km
h_mid = linspace(scen.h_site_ogs+2e3, 20e3, 500); % 2–20 km
h_high = linspace(20e3, scen.h_orbit, 500); % 20 km-sat. orbit
h_vec = unique([h_low, h_mid, h_high]); % MSL height vector [m]
h_agl_vec = h_vec - scen.h_site; % AGL height vector [m]

% Optical / geometry constants
k_opt = 2 * pi / scen.wl; % optical wavenumber [rad/m]
zeta_rad = pi / 2 - scen.el_rad; % zenith angle [rad]

% Different models
% HV-5/7. Refer to Carrasco papaer
% 2020_Carrasco_Free-space_optical_links_for_space_communication_n.pdf
prof(1) = struct('name', 'HV night', 'type', 'HV', 'A0', 1.7e-14, 'v', 21, ...
    'col', [0, 0.45, 0.74], 'style', '-');
prof(2) = struct('name', 'HV day', 'type', 'HV', 'A0', 1.7e-13, 'v', 30, ...
    'col', [0.85, 0.33, 0.10], 'style', '-');
% 2021_Knoedler_Atmospheric Turbulence Statistics and Profile Modeling
prof(3) = struct('name', 'MHV night', 'type', 'MHV', 'A0', 4.64e-15, 'v', 21, ...
    'col', [0, 0.45, 0.74], 'style', '--');
prof(4) = struct('name', 'MHV day', 'type', 'MHV', 'A0', 1.7e-13, 'v', 30, ...
    'col', [0.85, 0.33, 0.10], 'style', '--');

% Compute Cn2s
Cn2_all = cell(1, numel(prof));
sigma_R2_all = zeros(1, numel(prof));

for p = 1:numel(prof)
    switch prof(p).type
        case 'HV' % Carrasco Eq. (8.22), h in AGL
            h_arg = h_agl_vec;
        case 'MHV' % Knoedler Eq. (1), h + h_s = MSL
            h_arg = h_vec;
    end

    Cn2_all{p} = 0.00594 * (prof(p).v / 27)^2 .* (1e-5 .* h_arg).^10 .* exp(-h_arg/1000) ...
        +2.7e-16 .* exp(-h_arg/1500) ...
        +prof(p).A0 .* exp(-h_arg/100);

    integrand = Cn2_all{p} .* (h_agl_vec - scen.h_ogs).^(5 / 6);
    sigma_R2_all(p) = 2.25 * k_opt^(7 / 6) * sec(zeta_rad)^(11 / 6) * trapz(h_agl_vec, integrand);
end

% Reference profile (MHV night) for downstream plots
Cn2 = Cn2_all{3};
sigma_R2_MHV = sigma_R2_all(3);
sigma_R12_5_MHV = sigma_R2_MHV^(6 / 5);

% Point-receiver scintillation index (Carrasco / Andrews-Phillips)
% sigma_R2_MHV < 1 => weak turbulence
% Giggenbach 2008 for weak turbulence. sigma_R2 aprox= sigma_I2. CORRECT
sigma_I2_dl = exp(0.49*sigma_R2_MHV/(1 + 1.11 * sigma_R12_5_MHV)^(7 / 6) ...
    +0.51*sigma_R2_MHV/(1 + 0.69 * sigma_R12_5_MHV)^(5 / 6)) - 1;

% Aperture averaging
L_turb = ch.h_d * (scen.el_deg / 90) ...
    / ((scen.el_deg / 90)^2 + (ch.el_max_deg / 90)^2);
rho_i = 1.5 * sqrt(L_turb*scen.wl/(2 * pi));

A_f = (1 + 1.062 * (scen.D_rx ./ (2 * rho_i)).^2).^(-7 / 6);

sigma_P2_dl = A_f * sigma_I2_dl; % power scintillation index (aperture-averaged)


% Lognormal parameters (unit mean) feeding the sampler
sigma_2_logn = log(sigma_I2_dl+1);
mu_logn = -0.5 * sigma_2_logn;

% Aperture averaged
sigma_2_logn_av = log(sigma_P2_dl+1);
mu_logn_av = -0.5 * sigma_2_logn_av;

% MonteCarlo sampler: one unit-mean lognormal irradiance gain per call
sample_logn = @(N) exp(mu_logn+sqrt(sigma_2_logn)*randn(N, 1));
% Aperture averaged
sample_logn_av = @(N) exp(mu_logn_av+sqrt(sigma_2_logn_av)*randn(N, 1));

% i.i.d. ensemble for the analytical (fading-averaged) BER and the PDF plot
I_turb = sample_logn(ch.n_distr);
% Aperture averaged
I_turb_av = sample_logn_av(ch.n_distr);

% 6.3 Pointing effects ----------------------------------------------------
% Unit-mean pointing sampler. Inverse-CDF of f(x)=beta*x^(beta-1) on [0,1] is
% x = u^(1/beta); scale by (beta+1)/beta to force unit mean. A0 cancels.
sample_point = @(N) ((scen.beta_pj + 1) / scen.beta_pj) * rand(N, 1).^(1 / scen.beta_pj);

% Normalized pointing scintillation index (closed form, derived from the PDF):
% sigma_p^2 = Var/mean^2 = 1/[beta(beta+2)].
sigma_pt2 = 1 / (scen.beta_pj * (scen.beta_pj + 2));

% i.i.d. ensemble for the analytical (fading-averaged) BER and the PDF plot
I_point = sample_point(ch.n_distr);


fprintf('=== FSO Channel: turbulence (HV-5/7) ===\n');
fprintf('Wind v (HV-5/7)              = %.1f m/s\n', prof(3).v);
fprintf('A0 (ground Cn^2)             = %.2e m^(-2/3)\n', prof(3).A0);
fprintf('Zenith angle                 = %.2f deg\n', rad2deg(zeta_rad));
fprintf('Rytov variance (sigma_R^2)   = %.2f \n', sigma_R2_MHV);
fprintf('Scint. index (sigma_I^2)     = %.2f \n', sigma_I2_dl);
fprintf('Monte Carlo  sampler check     (N = %.0e):\n', ch.n_distr);
fprintf('  mean(I)                    = %.4f (target 1.0000)\n', mean(I_turb));
fprintf('  var(I)                     = %.4f (target %.4f)\n', ...
    var(I_turb), sigma_I2_dl);
fprintf('========================================\n\n');

fprintf('=== FSO Channel: pointing (Farid-Hranilovic) ===\n');
fprintf('  Slant range L (el=%.0f deg)  = %.1f km\n', scen.el_deg, scen.l_slant/1e3);
fprintf('  Beam radius at ground w_z  = %.1f m\n', scen.w_z);
fprintf('  On-axis fraction A0        = %.3e  (-> link budget)\n', scen.A0_pt);
fprintf('  beta_pj (= gamma^2)        = %.3f\n', scen.beta_pj);
fprintf('  Pointing scint. sigma_p^2  = %.4f\n', sigma_pt2);
fprintf('  MC sampler: mean(h_p)      = %.4f (target 1.0000)\n', mean(I_point));
fprintf('  MC sampler: var(h_p)       = %.4f (target %.4f)\n', var(I_point), sigma_pt2);
fprintf('========================================\n\n');
%% 7. Free Space Optical Channel - Setup Visualization

% 7.1 Cn2 profiles and Rytov, A0 and wind values --------------------------
figure('Name', 'Cn2 profile models: HV vs MHV');

hold on; grid on;

set(gca, 'XScale', 'log', 'YScale', 'log');

for p = 1:numel(prof)

    loglog(Cn2_all{p}, max(h_agl_vec, 1), ...
        'Color', prof(p).col, ...
        'LineStyle', prof(p).style, ...
        'DisplayName', sprintf(['%s, $A_0 = %.2e\\,\\mathrm{m}^{-2/3}$, ', ...
        '$v = %.0f\\,\\mathrm{m/s}$'], ...
        prof(p).name, prof(p).A0, prof(p).v));
end

xlabel('$C_n^2(h)$ [$\mathrm{m}^{-2/3}$]');
ylabel('$h - h_0$ [$\mathrm{m}$]');
title(sprintf('HV / MHV turbulence profiles, $\\epsilon = %.0f^\\circ$', scen.el_deg));
legend('Location', 'northeast');

xlim([1e-19, 1e-12]);
%ylim([1e-3 30]);

% 7.2 Lognormal probability distribution ----------------------------------
figure('Name', 'Log-normal intensity PDF');

[counts, edges] = histcounts(I_turb, 120, 'Normalization', 'pdf');
centers = 0.5 * (edges(1:end-1) + edges(2:end));
[counts_av, edges_av] = histcounts(I_turb_av, 120, 'Normalization', 'pdf');
centers_av = 0.5 * (edges_av(1:end-1) + edges_av(2:end));

I_grid = linspace(1e-3, max(I_turb), 2000);
I_grid_av = linspace(1e-3, max(I_turb_av), 2000);
% Theoretical PDF of the lognormal distribution
p_I = 1 ./ (I_grid * sqrt(2*pi*sigma_2_logn)) .* ...
    exp(-(log(I_grid) - mu_logn).^2./(2 * sigma_2_logn));
p_I_av = 1 ./ (I_grid_av * sqrt(2*pi*sigma_2_logn_av)) .* ...
    exp(-(log(I_grid_av) - mu_logn_av).^2./(2 * sigma_2_logn_av));
stairs(centers, counts, 'LineWidth', 1.0);
hold on; grid on;
semilogy(I_grid, p_I);
stairs(centers_av, counts_av, 'LineWidth', 1.0);
semilogy(I_grid_av, p_I_av);
set(gca, 'YScale', 'log');

xlabel('$I_n = I/\langle I\rangle$');
ylabel('$p_{I_n}(i)$');
title(sprintf(['Log-normal normalized irradiance PDF, ', ...
    '$\\sigma_I^2=%.3f$, $\\sigma_{I,ap}^2=%.3f$'], ...
    sigma_I2_dl, sigma_P2_dl));

legend({'MC histogram', 'Analytical PDF', 'MC histogram (aperture)', ...
    'Analytical PDF (aperture)'}, 'Location', 'northeast');
xlim([0, 1 + 5 * sqrt(sigma_I2_dl)]);
ylim([1e-4, 2]);

%% 8. Free Space Optical Channel - Simulation

% Physically this is one optical DP-QPSK signal.
tx_DP = [tx_X, tx_Y];

% AWGN channel: receiver gets a noised signal
EbN0_lin = 10.^(ch.EbN0_dB_vec / 10);

% Full-channel error accumulators (ensemble-averaged over frames)
err_X = zeros(size(ch.EbN0_dB_vec));
err_Y = zeros(size(ch.EbN0_dB_vec));
nbits = zeros(size(ch.EbN0_dB_vec));
% Aperture averaged
err_X_av = zeros(size(ch.EbN0_dB_vec));
err_Y_av = zeros(size(ch.EbN0_dB_vec));
% Final channel
err_X_full = zeros(size(ch.EbN0_dB_vec));
err_Y_full = zeros(size(ch.EbN0_dB_vec));

% Filters group delay
% Tx RRC group delay = ((sig.span*sig.sps+1) - 1) / 2
% Rx RRC group delay = ((sig.span*sig.sps+1) - 1) / 2
% Total delay  = (((sig.span*sig.sps+1) - 1) / 2) + (((sig.span*sig.sps+1) - 1) / 2)
total_delay = sig.span * sig.sps;

% Each frame = one independent frozen turbulence state (T_c >> 31.7 us frame).
% BER curve = ensemble average over frames. Replaces the single block draw.
for j = 1:ch.nframes
    h_turb_norm = sample_logn(1); % one flat gain this frame (scalar)
    % Aperture averaged
    h_turb_norm_av = sample_logn_av(1); % one flat gain this frame (scalar)
    h_point_norm = sample_point(1); % one flat pointing gain this frame
    % Apply FSO channel (amplitude scaling = sqrt of power gain)
    % h_ch = h_atm * h_tur * h_poin
    h_ch_samp = h_atm .* h_turb_norm;
    h_ch_samp_av = h_atm .* h_turb_norm_av;
    h_ch_full = h_atm .* h_turb_norm_av .* h_point_norm;

    for i = 1:length(ch.EbN0_dB_vec)
        % QPSK: Es/N0 = sig.k*Eb/N0, with Es = 1
        EsN0 = sig.k * EbN0_lin(i);
        N0 = 1 / EsN0;
        sigma = sqrt(N0/2);

        % nI_X + nQ_X = sigma * randn(size(tx_DP(:,1))) + sigma * randn(size(tx_DP(:,1)))
        noise_X = sigma * (randn(size(tx_DP(:, 1))) ...
            +1j * randn(size(tx_DP(:, 1))));
        noise_Y = sigma * (randn(size(tx_DP(:, 2))) ...
            +1j * randn(size(tx_DP(:, 2))));

        % Full channel simulation
        rx_X = sqrt(h_ch_samp) .* tx_DP(:, 1) + noise_X;
        rx_Y = sqrt(h_ch_samp) .* tx_DP(:, 2) + noise_Y;
        % Aperture averaged
        rx_X_av = sqrt(h_ch_samp_av) .* tx_DP(:, 1) + noise_X;
        rx_Y_av = sqrt(h_ch_samp_av) .* tx_DP(:, 2) + noise_Y;
        % Final channel
        rx_X_full = sqrt(h_ch_full) .* tx_DP(:, 1) + noise_X;
        rx_Y_full = sqrt(h_ch_full) .* tx_DP(:, 2) + noise_Y;

        % Receiver matched filter uses the same RRC filter
        % No up/downsampling
        rxmf_X = upfirdn(rx_X, rrc);
        rxmf_Y = upfirdn(rx_Y, rrc);
        % Aperture averaged
        rxmf_X_av = upfirdn(rx_X_av, rrc);
        rxmf_Y_av = upfirdn(rx_Y_av, rrc);
        % Final channel
        rxmf_X_full = upfirdn(rx_X_full, rrc);
        rxmf_Y_full = upfirdn(rx_Y_full, rrc);

        % Downsample at symbol instants
        rx_symbols_X_atm_turb = rxmf_X(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
        rx_symbols_Y_atm_turb = rxmf_Y(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
        % Aperture averaged
        rx_symbols_X_av = rxmf_X_av(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
        rx_symbols_Y_av = rxmf_Y_av(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
        % Final channel
        rx_symbols_X_full = rxmf_X_full(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
        rx_symbols_Y_full = rxmf_Y_full(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);

        % Demodulate the gray QPSK into symbols
        
        %ints_hat_X = pskdemod(rx_symbols_X_atm_turb, sig.M, pi/4, 'gray');
        %ints_hat_Y = pskdemod(rx_symbols_Y_atm_turb, sig.M, pi/4, 'gray');
        % Aperture averaged
        ints_hat_X_av = pskdemod(rx_symbols_X_av, sig.M, pi/4, 'gray');
        ints_hat_Y_av = pskdemod(rx_symbols_Y_av, sig.M, pi/4, 'gray');
        % Final channel
        ints_hat_X_full = pskdemod(rx_symbols_X_full, sig.M, pi/4, 'gray');
        ints_hat_Y_full = pskdemod(rx_symbols_Y_full, sig.M, pi/4, 'gray');

        % Convert the the integers (0 to 3) into 2-bit pairs (e.g., [1 0]).
        % MSB by default
        bits_hat_X = int2bit(ints_hat_X, sig.k);
        bits_hat_Y = int2bit(ints_hat_Y, sig.k);
        % Aperture averaged
        bits_hat_X_av = int2bit(ints_hat_X_av, sig.k);
        bits_hat_Y_av = int2bit(ints_hat_Y_av, sig.k);
        % Final channel
        bits_hat_X_full = int2bit(ints_hat_X_full, sig.k);
        bits_hat_Y_full = int2bit(ints_hat_Y_full, sig.k);

        % Optional, we already have the right dimensions
        bits_hat_X = bits_hat_X(:);
        bits_hat_Y = bits_hat_Y(:);
        % Aperture averaged
        bits_hat_X_av = bits_hat_X_av(:);
        bits_hat_Y_av = bits_hat_Y_av(:);
        % Final channel
        bits_hat_X_full = bits_hat_X_full(:);
        bits_hat_Y_full = bits_hat_Y_full(:);

        % Errors
        err_X(i) = err_X(i) + sum(bits_X ~= bits_hat_X(:));
        err_Y(i) = err_Y(i) + sum(bits_Y ~= bits_hat_Y(:));
        % Aperture averaged
        err_X_av(i) = err_X_av(i) + sum(bits_X ~= bits_hat_X_av(:));
        err_Y_av(i) = err_Y_av(i) + sum(bits_Y ~= bits_hat_Y_av(:));
        % Final channel
        err_X_full(i) = err_X_full(i) + sum(bits_X ~= bits_hat_X_full(:));
        err_Y_full(i) = err_Y_full(i) + sum(bits_Y ~= bits_hat_Y_full(:));

        nbits(i) = nbits(i) + numel(bits_X);
    end
end

BER_X = err_X ./ nbits;
BER_Y = err_Y ./ nbits;
BER_total = (err_X + err_Y) ./ (2 * nbits);
% Aperture averaged
BER_X_av = err_X_av ./ nbits;
BER_Y_av = err_Y_av ./ nbits;
BER_total_av = (err_X_av + err_Y_av) ./ (2 * nbits);
% Final channel
BER_X_full = err_X_full ./ nbits;
BER_Y_full = err_Y_full ./ nbits;
BER_total_full = (err_X_full + err_Y_full) ./ (2 * nbits);

% Theoretical Eb/N0 at which Gray-QPSK reaches the pre-FEC threshold:
EbN0_thr_lin = erfcinv(2*sig.BER_preFEC)^2;
EbN0_thr_dB = 10 * log10(EbN0_thr_lin);

% Exact uncoded Gray-QPSK theory
BER_theory = qfunc(sqrt(2*EbN0_lin));
BER_theory_atm = qfunc(sqrt(2*EbN0_lin.*h_atm));
% N×1 samples ⊗ 1×G grid → N×G, mean over the sample dim → 1×G
BER_theory_atm_turb = mean(qfunc(sqrt(2*h_atm.* ...
    (I_turb(:) .* EbN0_lin(:).'))), 1);
% Aperture averaged
BER_theory_atm_turb_av = mean(qfunc(sqrt(2*h_atm.* ...
    (I_turb_av(:) .* EbN0_lin(:).'))), 1);
% Final channel
BER_theory_full = mean(qfunc(sqrt(2*h_atm.* ...
    ((I_turb_av(:) .* I_point(:)) * EbN0_lin(:).'))), 1);

% 8.1 Constellation specific ----------------------------------------------
vis.EbN0_dB = 8; % display operating point [dB]
vis.q = 0.2; % fade quantile (0.5 = median, 0.05 = deep fade)
% Calculated values
vis.EbN0_lin = 10.^(vis.EbN0_dB / 10);
vis.EsN0 = sig.k * vis.EbN0_lin;
vis.N0 = 1 / vis.EsN0;
vis.sigma = sqrt(vis.N0/2);

% Component quantiles (closed-form; could equally use quantile() on the ensembles)
vis.h_turb = exp(mu_logn+sqrt(sigma_2_logn) ...
    *-sqrt(2)*erfcinv(2*vis.q)); % point rx
vis.h_turb_av = exp(mu_logn_av+sqrt(sigma_2_logn_av) ...
    *-sqrt(2)*erfcinv(2*vis.q)); % aperture
vis.h_point = ((scen.beta_pj + 1) / scen.beta_pj) ...
    * vis.q^(1 / scen.beta_pj); % unit-mean, matches sample_point

% Stage gains
vis.h_atm_turb = h_atm * vis.h_turb;
vis.h_atm_turb_av = h_atm * vis.h_turb_av;
vis.h_full = h_atm * vis.h_turb_av * vis.h_point; % per-component product (option a)

% Fresh noise (independent of BER loop)
vis.noise_X = vis.sigma * (randn(size(tx_DP(:, 1))) ...
    +1j * randn(size(tx_DP(:, 1))));
vis.noise_Y = vis.sigma * (randn(size(tx_DP(:, 2))) ...
    +1j * randn(size(tx_DP(:, 2))));

% AWGN only
rx_X_AWGN = tx_DP(:, 1) + vis.noise_X;
rx_Y_AWGN = tx_DP(:, 2) + vis.noise_Y;
% Atmosphere only
rx_X_atm = sqrt(h_atm) .* tx_DP(:, 1) + vis.noise_X;
rx_Y_atm = sqrt(h_atm) .* tx_DP(:, 2) + vis.noise_Y;
% Atmosphere + turbulence (point rx)
rx_X_atm_turb = sqrt(vis.h_atm_turb) .* tx_DP(:, 1) + vis.noise_X;
rx_Y_atm_turb = sqrt(vis.h_atm_turb) .* tx_DP(:, 2) + vis.noise_Y;
% Atmosphere + turbulence (aperture averaged)
rx_X_av = sqrt(vis.h_atm_turb_av) .* tx_DP(:, 1) + vis.noise_X;
rx_Y_av = sqrt(vis.h_atm_turb_av) .* tx_DP(:, 2) + vis.noise_Y;
% Full channel (+ pointing)
rx_X_full = sqrt(vis.h_full) .* tx_DP(:, 1) + vis.noise_X;
rx_Y_full = sqrt(vis.h_full) .* tx_DP(:, 2) + vis.noise_Y;

% Receiver matched filter uses the same RRC filter
rxmf_X_AWGN = upfirdn(rx_X_AWGN, rrc);
rxmf_Y_AWGN = upfirdn(rx_Y_AWGN, rrc);
rxmf_X_atm = upfirdn(rx_X_atm, rrc);
rxmf_Y_atm = upfirdn(rx_Y_atm, rrc);
rxmf_X_atm_turb = upfirdn(rx_X_atm_turb, rrc);
rxmf_Y_atm_turb = upfirdn(rx_Y_atm_turb, rrc);
rxmf_X_av = upfirdn(rx_X_av, rrc);
rxmf_Y_av = upfirdn(rx_Y_av, rrc);
rxmf_X_full = upfirdn(rx_X_full, rrc);
rxmf_Y_full = upfirdn(rx_Y_full, rrc);

rx_symbols_X_AWGN = rxmf_X_AWGN(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_Y_AWGN = rxmf_Y_AWGN(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_X_atm = rxmf_X_atm(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_Y_atm = rxmf_Y_atm(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_X_atm_turb = rxmf_X_atm_turb(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_Y_atm_turb = rxmf_Y_atm_turb(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_X_av = rxmf_X_av(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_Y_av = rxmf_Y_av(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_X_full = rxmf_X_full(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
rx_symbols_Y_full = rxmf_Y_full(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);

%% 9. RX - Visualization

% 9.1 Received spectrum ---------------------------------------------------
figure('Name', 'Rx Spectrum after Matched Filter - AWGN, atmosphere and turbulence');

% https://es.mathworks.com/help/signal/ref/pwelch.html
[Pxx_r, f_psd_r] = pwelch(rxmf_X, win, noverlap, nfft, sig.Fs, 'centered');
[Pyy_r, ~] = pwelch(rxmf_Y, win, noverlap, nfft, sig.Fs, 'centered');

plot(f_psd_r/1e9, 10*log10(Pxx_r/max(Pxx_r)), 'b');
hold on;
plot(f_psd_r/1e9, 10*log10(Pyy_r/max(Pyy_r)), 'r--');
grid on;

xlabel('Frequency [GHz]');
ylabel('Normalized PSD [dB]');
title(sprintf('DP-QPSK Rx spectrum after matched filter, expected null-null BW = %.2f GHz', ...
    sig.BW_null/1e9));
legend('X-pol', 'Y-pol', 'Location', 'best');
ylim([-80, 5]);

% 9.2 Eye diagrams after channel ------------------------------------------
eye_rx1 = real(rxmf_X(sig.span*sig.sps+1:sig.span*sig.sps+4000));
eye_rx2 = real(rxmf_Y(sig.span*sig.sps+1:sig.span*sig.sps+4000));
eye_rx = [eye_rx1, eye_rx2];

eyediagram(eye_rx, 2*sig.sps);

% Grab the axes handles from the current figure
ax2 = findobj(gcf, 'Type', 'axes');

title(ax2(2), 'X-pol I-component eye diagram after matched filter - AWGN, atmosphere and turbulence');
title(ax2(1), 'Y-pol I-component eye diagram after matched filter - AWGN, atmosphere and turbulence');


% 9.3 Consolidated constellation grid: 2 pol × 5 impairment stages --------
figure('Name', 'Rx constellations: impairment progression');
tiledlayout(2, 5, 'TileSpacing', 'compact', 'Padding', 'compact');

stages = { ...
    {rx_symbols_X_AWGN, rx_symbols_Y_AWGN, 'AWGN'}, ...
    {rx_symbols_X_atm, rx_symbols_Y_atm, 'atm (point)'}, ...
    {rx_symbols_X_atm_turb, rx_symbols_Y_atm_turb, 'atm+turb (point)'}, ...
    {rx_symbols_X_av, rx_symbols_Y_av, 'atm+turb (ap.)'}, ...
    {rx_symbols_X_full, rx_symbols_Y_full, 'full (+point., ap.)'}};

for s = 1:5
    % X-pol, top row
    nexttile(s);
    plot(real(stages{s}{1}(1:2000)), imag(stages{s}{1}(1:2000)), '.', ...
        'Color', [0.00, 0.45, 0.74], 'MarkerSize', 4);
    grid on;
    axis square;
    xlim([-1.5, 1.5]);
    ylim([-1.5, 1.5]);
    title(stages{s}{3});
    if s == 1, ylabel('X-pol \quad Q'); end

    % Y-pol, bottom row
    nexttile(s+5);
    plot(real(stages{s}{2}(1:2000)), imag(stages{s}{2}(1:2000)), '.', ...
        'Color', [0.85, 0.33, 0.10], 'MarkerSize', 4);
    grid on;
    axis square;
    xlim([-1.5, 1.5]);
    ylim([-1.5, 1.5]);
    if s == 1, ylabel('Y-pol \quad Q'); end
    xlabel('I');
end

% 9.4 BER table -----------------------------------------------------------

BER_table = table( ...
    ch.EbN0_dB_vec(:), ...
    BER_theory(:), ...
    BER_theory_atm(:), ...
    BER_theory_atm_turb(:), ...
    BER_theory_atm_turb_av(:), ...
    BER_theory_full(:), ...
    BER_X(:), ...
    BER_Y(:), ...
    BER_total_full(:), ...
    'VariableNames', {'EbN0_dB', 'BER_AWGN', 'BER_atm', 'BER_atm_turb_theory', ...
    'BER_atm_turb_theory_av', 'BER_theory_full', 'BER_X', 'BER_Y', 'BER_total_full'});

disp(' ');
disp('=== BER vs Eb/N0 Table ===');
disp(BER_table);

fprintf('\nPre-FEC BER threshold = %.2e\n', sig.BER_preFEC);
fprintf('Theoretical Eb/N0 at pre-FEC threshold = %.3f dB\n\n', EbN0_thr_dB);

% 9.5 BER plot ------------------------------------------------------------
figure('Name', 'BER vs Eb/N0');

semilogy(ch.EbN0_dB_vec, BER_theory, '-', 'Color', [0.00, 0.00, 0.00], 'LineWidth', 1.6);
hold on;
semilogy(ch.EbN0_dB_vec, BER_theory_atm, '-', 'Color', [0.47, 0.67, 0.19], 'LineWidth', 1.6);
semilogy(ch.EbN0_dB_vec, BER_theory_atm_turb, '-', 'Color', [0.00, 0.45, 0.74], 'LineWidth', 1.6);
semilogy(ch.EbN0_dB_vec, BER_theory_atm_turb_av, '-', 'Color', [0.85, 0.33, 0.10], 'LineWidth', 1.6);
semilogy(ch.EbN0_dB_vec, BER_theory_full, '-', 'Color', [0.49, 0.18, 0.56], 'LineWidth', 1.6);
%semilogy(ch.EbN0_dB_vec, BER_X, 'bo-');
%semilogy(ch.EbN0_dB_vec, BER_Y, 'rs-');
%semilogy(ch.EbN0_dB_vec, BER_X_av, 'bo-');
%semilogy(ch.EbN0_dB_vec, BER_Y_av, 'rs-');
semilogy(ch.EbN0_dB_vec, BER_total, 'o-', 'Color', [0.35, 0.35, 0.35], 'MarkerFaceColor', [0.00, 0.45, 0.74], 'MarkerSize', 6);
semilogy(ch.EbN0_dB_vec, BER_total_av, 's-', 'Color', [0.35, 0.35, 0.35], 'MarkerFaceColor', [0.85, 0.33, 0.10], 'MarkerSize', 6);
semilogy(ch.EbN0_dB_vec, BER_total_full, '^-', 'Color', [0.35, 0.35, 0.35], 'MarkerFaceColor', [0.49, 0.18, 0.56], 'MarkerSize', 6);
% Horizontal pre-FEC threshold
yline(sig.BER_preFEC, 'k--', 'Pre-FEC BER $=2.0\times10^{-2}$', ...
    'LineWidth', 1.0, ...
    'LabelHorizontalAlignment', 'left', ...
    'LabelVerticalAlignment', 'bottom', ...
    'FontSize', 12, ...
    'Interpreter', 'latex');
grid on;
grid minor;
xlabel('$E_b/N_0$ (pre-channel) [$\mathrm{dB}$]');
ylabel('BER');
title('Gray-coded DP-QPSK with deterministic atmospheric attenuation, turbulence effects and AWGN');
legend({ ...
    'Theory AWGN', ...
    'Theory atm only', ...
    'Theory atm+turb (point, $D{=}0$)', ...
    sprintf('Theory atm+turb (ap., $D{=}%.1f$\\,m)', scen.D_rx), ...
    sprintf('Theory atm+turb+point (ap., $D{=}%.1f$\\,m)', scen.D_rx), ...
    'Sim atm+turb (point, $D{=}0$)', ...
    sprintf('Sim atm+turb (ap., $D{=}%.1f$\\,m)', scen.D_rx), ...
    sprintf('Sim full (ap., $D{=}%.1f$\\,m)', scen.D_rx)}, ...
    'Location', 'southwest', 'Interpreter', 'latex', 'FontSize', 9);
ylim([1e-6, 1]);
xlim([min(ch.EbN0_dB_vec), max(ch.EbN0_dB_vec)]);

%% Animation
% EbN0_plot_dB = 8;
% EbN0_plot = 10^(EbN0_plot_dB / 10);
% 
% EsN0_plot = sig.k * EbN0_plot;
% N0_plot = 1 / EsN0_plot;
% sigma_plot = sqrt(N0_plot/2);
% 
% % Fixed noise realization per frame or regenerated each frame
% % Better to regenerate each frame to feel "live"
% Nshow = 1000; % plotted symbols
% 
% % Controlled turbulence sweep
% Nanim = 150;
% 
% 
% % Elevation sweep: low elevation -> zenith -> low elevation
% el_seq_deg = [linspace(15, 90, 60), linspace(90, 15, 60)];
% h_atm_seq = scen.t_z.^(1 ./ sind(el_seq_deg));
% 
% figure('Name', 'Animated atmospheric attenuation constellation');
% ax = axes;
% grid(ax, 'on');
% axis(ax, 'square');
% xlim(ax, [-1.5, 1.5]);
% ylim(ax, [-1.5, 1.5]);
% xlabel('In-Phase (I)');
% ylabel('Quadrature (Q)');
% 
% h_sc = scatter(ax, nan, nan, 20, 'b', 'filled');
% 
% for kf = 1:length(el_seq_deg)
% 
%     el_anim = el_seq_deg(kf);
%     h_atm_anim = h_atm_seq(kf);
% 
%     noise_X = sigma_plot * ...
%         (randn(size(tx_DP(:, 1))) + 1j * randn(size(tx_DP(:, 1))));
% 
%     rx_X_anim = sqrt(h_atm_anim) .* tx_DP(:, 1) + noise_X;
% 
%     rxmf_X_anim = upfirdn(rx_X_anim, rrc);
% 
%     rx_symbols_X_anim = rxmf_X_anim( ...
%         total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
% 
%     pts = rx_symbols_X_anim(1:Nshow);
% 
%     set(h_sc, 'XData', real(pts), 'YData', imag(pts));
% 
%     title(sprintf(['Atmosphere-only X-pol constellation, ', ...
%         '$E_b/N_0=%.1f$ dB, $\\epsilon=%.1f^\\circ$, ', ...
%         '$h_{atm}=%.3f$ ($%.2f$ dB)'], ...
%         EbN0_plot_dB, ...
%         el_anim, ...
%         h_atm_anim, ...
%         10*log10(h_atm_anim)), ...
%         'Interpreter', 'latex');
% 
%     drawnow;
%     pause(0.06);
% end
% 
% 
% g = randn(Nanim, 1);
% b = ones(1, 8) / 8; % simple smoothing filter
% g_slow = filter(b, 1, g);
% g_slow = (g_slow - mean(g_slow)) / std(g_slow);
% 
% h_seq = exp(mu_logn+sqrt(sigma_2_logn)*g_slow);
% 
% figure('Name', 'Animated turbulence constellation');
% ax = axes;
% grid(ax, 'on');
% axis(ax, 'square');
% xlim(ax, [-1.5, 1.5]);
% ylim(ax, [-1.5, 1.5]);
% xlabel('In-Phase (I)');
% ylabel('Quadrature (Q)');
% 
% h_sc = scatter(ax, nan, nan, 20, 'b', 'filled');
% 
% for kf = 1:length(h_seq)
% 
%     h_turb_anim = h_seq(kf);
%     h_ch_anim = h_atm * h_turb_anim;
% 
%     noise_X = sigma_plot * (randn(size(tx_DP(:, 1))) + 1j * randn(size(tx_DP(:, 1))));
%     rx_X_anim = sqrt(h_ch_anim) .* tx_DP(:, 1) + noise_X;
% 
%     rxmf_X_anim = upfirdn(rx_X_anim, rrc);
%     rx_symbols_X_anim = rxmf_X_anim(total_delay+1:sig.sps:total_delay+sig.num_sym*sig.sps);
% 
%     pts = rx_symbols_X_anim(1:Nshow);
% 
%     set(h_sc, 'XData', real(pts), 'YData', imag(pts));
% 
%     title(sprintf(['X-pol constellation, $E_b/N_0 = %.1f$ dB, ', ...
%         '$h_{turb}=%.3f$ ($%.2f$ dB), $h_{atm}h_{turb}=%.3f$ ($%.2f$ dB)'], ...
%         EbN0_plot_dB, ...
%         h_turb_anim, 10*log10(h_turb_anim), ...
%         h_ch_anim, 10*log10(h_ch_anim)), ...
%         'Interpreter', 'latex');
% 
%     drawnow;
%     pause(0.08);
% end
