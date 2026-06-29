% LinkBudget_LEO_ESTOL_OP.m
%
% LEO-to-PL Optical Communications Telescope Laboratory (OCTL)
% optical downlink budget.
% https://ipnpr.jpl.nasa.gov/progress_report/42-161/161M.pdf
% https://ntrs.nasa.gov/api/citations/20230007959/downloads/TBIRD-smallsat-2023.pdf
%
% Conventions:
%   - SI units throughout. Angles named *_deg or *_rad explicitly.
%   - Powers in dBm, losses/gains in dB (negative loss = attenuation).
%   - Constants in UPPER_CASE, parameters in lower_case.
%   - All reporting consolidated in section 9. No disp() mid-computation.
%
% Based on: LinkBudget_OLEODL_20240514.m
% Revision: 2026-05-11
%% Local functions
function P_W = dBm_to_W(P_dBm)
% Convert dBm to watts.
P_W = 10.^(P_dBm ./ 10) / 1e3;
end
%% 0. Environment
clc;
clearvars;
close all

% Latex setup
set(groot, 'defaultTextInterpreter', 'latex');
set(groot, 'defaultLegendInterpreter', 'latex');
set(groot, 'defaultAxesTickLabelInterpreter', 'latex');
% Typography
set(groot, 'defaultAxesFontSize', 20); % tick labels
set(groot, 'defaultLegendFontSize', 12);
set(groot, 'defaultAxesLabelFontSizeMultiplier', 13/12); % axis labels ≈ 13 pt
set(groot, 'defaultAxesTitleFontSizeMultiplier', 14/12); % title ≈ 14 pt
set(groot, 'defaultAxesTitleFontWeight', 'normal');
% Lines and axes
set(groot, 'defaultLineLineWidth', 1.3);
set(groot, 'defaultAxesBox', 'on');
set(groot, 'defaultAxesXGrid', 'on');
set(groot, 'defaultAxesYGrid', 'on');
%% 1. Physical constants
% BIPM, The International System of Units (SI), 9th ed., 2019, §2.3.1.
C = 299792458; % [m/s], speed of light
H = 6.62607015e-34; % [J*s], Planck constant
R_E = 6.3710088e6; % [m] IUGG mean Earth radius R1
%% 2. Mission / scenario inputs
% --- Transmitter (satellite) ---
% Wavelength presets [m]:  OSIRIS-FLP=1550e-9, FLP=1545e-9, TBIRD=1550e-9
%wl = 1550e-9;                       % [m]
wl = 1554.13e-9; % [m], ESTOL specs (L2 for DP-QPSK)

% Tx optical power presets [dBm]: FLP-OSIRISv1=30 (1W), TBIRD=29.0309 (0.8W)
% KIODO references suggest 100 mW or 50 mW (20 dBm in book may be peak).
p_tx_w = 6; % [W]
p_tx = 10 * log10(p_tx_w*1e3); % [dBm]

% Datarate presets [bps]: OSIRIS-FLP=39e6, KIODO=125e6, TBIRD=126e9
% M = 2^b = 16; DP-QPSK, dual 4 bits
% dr = r_s*log2(M)
dr = 126e9; % [bps], with headers

% Receiver sensitivity: photons per bit at BER target.
% 250 ppb: APD-RFE-100-OLD at BER=1e-3 (OSIRISv1). 320 ppb: RFE-300-NEW.
ppb = 5; % [ppb], TBIRD value

% Tx FWHM divergence presets [rad]: OSIRIS-FLP=1e-3, KIODO=5.5e-6,
% TBIRD=380e-6, TBIRD2=600e-6
% THEY STATE THAT 100urad could be supported with same config.!!
theta_tx_rad = 380e-6; % [rad], full-width half-max - FWHM

% Orbit altitude presets [m]: LUCE/OICETS=610e3, FLP=595e3, TBIRD=530e3
h_orbit = 530e3; % [m], TBIRD value

% --- Receiver (OGS) ---
% OGS altitude above MSL [m]: OP-OGS=578, GSOC-OGS=650
% NASA Table - https://atmos.jpl.nasa.gov/ground.htm
h_ogs = 578; % [m]

% Primary aperture presets [m]: GSOC=0.3, Infra-FE4.41.0-17=2.5e-3, Infra-FE5.61.0-17=5.6e-3
% NASA Table = 1m - https://ipnpr.jpl.nasa.gov/progress_report/42-161/161M.pdf
d_rx_o = 0.8; % [m], TBIRD outer aperture
d_rx_i = d_rx_o / 3; % [m], central obscuration (Cassegrain ~1/3)
%d_rx_i = 0.16;                     % [m], TOGS has 16cm secondary obscuration
area_rx = pi * (d_rx_o / 2)^2 - pi * (d_rx_i / 2)^2; % [m^2]
%% 3. Atmospheric & pointing parameters
% Zenith transmittance (Giggenbach LB-paper Table). Pick one row.
t_z = 0.891; % 1550 nm, bad conditions
% t_z = 0.705;      % 800nm bad conditions
% t_z = 0.950;      % 800nm good conditions
% t_z = 0.891;      % 1550nm bad conditions
% t_z = 0.986;      % 1550nm good conditions

% Pointing jitter & beta parameter
%sigma_jit_rad = 0.85 * theta_tx_rad / 2; % yields ~3 dB BW loss
sigma_jit_rad = 35e-6; % per-axis RMS, worst case TBIRD (Y axis)
beta_pj = theta_tx_rad^2 / sigma_jit_rad^2 / (8 * log(2));

% Scintillation model parameters (currently unused; loss forced to 0 below).
psi_scint = 0.3; % log-amplitude variance
p_thr_sci = 1e-1; % outage fraction for ScintiLoss

% Internal optical losses [dB] (negative = loss)
% NASA Table - https://ntrs.nasa.gov/api/citations/20230000434/downloads/Schieler%20paper%20spie2023-tbird-v4.pdf
% https://ntrs.nasa.gov/api/citations/20230007959/downloads/TBIRD-smallsat-2023.pdf
% Transmitter loss presets [dB]: OP:-1
%a_tx = -1.0;                            % Tx internal
a_tx = -0.3; % [dB], https://ntrs.nasa.gov/api/citations/20230007959/downloads/TBIRD-smallsat-2023.pdf
% % Transmitter loss presets [dB]: OP:-4.1
a_rx = -4.1; % Rx incl. splitting for FLP. -14 for KIODO
%% 4. Elevation grid
el_deg_report = 15; % single elevation for tabular report
el_deg = 5:1:90; % grid for plotting

el_rad = deg2rad(el_deg);
el_rad_report = deg2rad(el_deg_report);
%% 5. Geometry: slant range
% Spherical-Earth law-of-cosines, solved for l given local elevation:
l = sqrt((R_E + h_ogs).^2.*sin(el_rad).^2+2*(h_orbit - h_ogs).* ...
    (R_E + h_ogs)+(h_orbit - h_ogs).^2) - (R_E + h_ogs) .* sin(el_rad); % [m]
l_report = sqrt((R_E + h_ogs).^2.*sin(el_rad_report).^2+2*(h_orbit - h_ogs) ...
    .*(R_E + h_ogs)+(h_orbit - h_ogs).^2) - (R_E + h_ogs) .* sin(el_rad_report); % [m]
%% 6. Antenna gains
% Tx: peak on-axis Gaussian gain via FWHM divergence.
% G_tx = 16*ln(2)/theta_FWHM^2  =>  sqrt(16*ln(2)) ≈ 3.3302
% Source: Klein & Degnan, "Optical Antenna Gain. 1: Transmitting Antennas",
%         Appl. Opt. 13(9):2134-2141, 1974. DOI:10.1364/AO.13.002134.
GAUSS_FWHM_FACTOR = sqrt(16*log(2)); % ≈ 3.3302
g_tx = 10 * log10((GAUSS_FWHM_FACTOR / theta_tx_rad)^2); % [dB]

% Rx: effective-area antenna gain.
% Source: Klein & Degnan (1974), companion treatment for Rx aperture.
g_rx = 10 * log10(4*pi*area_rx/wl^2); % [dB]
%% 7. Channel losses (functions of elevation)
% Free-space loss [dB]
a_fsl = 10 * log10((wl ./ (4 * pi .* l)).^2); % [dB]
a_fsl_report = 10 * log10((wl / (4 * pi * l_report))^2); % [dB]

% Atmospheric loss via secant-law from zenith transmittance.
a_atm = 10 * log10(t_z.^(1 ./ sin(el_rad))); % [dB]
a_atm_report = 10 * log10(t_z^(1 / sin(el_rad_report))); % [dB]
%a_atm_report = -0.6; % [dB], https://ntrs.nasa.gov/api/citations/20230007959/downloads/TBIRD-smallsat-2023.pdf

% Beam-wander loss [dB]
% In case of a camera we would not have beam wander losses
a_bw = 10 * log10(beta_pj/(beta_pj + 1)); % [dB]
%a_bw = -0.2; % [dB], https://ntrs.nasa.gov/api/citations/20230007959/downloads/TBIRD-smallsat-2023.pdf

% Scintillation loss [dB]. Forced to 0 here.
%a_sci = (10/log(10)) * ( erfinv(2*p_thr_sci-1) * sqrt(2*log(psi_scint+1)) - 0.5*log(psi_scint+1) );
a_sci = 0; % [dB]
%% 8. Power budget
% Rx power onto detector [dBm] (vector over el_deg)
p_rx = p_tx + a_tx + g_tx + a_fsl + a_bw + a_atm + a_sci + g_rx + a_rx; % [dB]
p_rx_report = p_tx + a_tx + g_tx + a_fsl_report + a_bw + a_atm_report ...
    +a_sci + g_rx + a_rx; % [dB]

% Power onto OGS aperture (no Rx-internal losses) [dBm]
p_ogs_no_loss = p_rx - a_rx; % [dBm]
p_ogs_with_loss = p_rx; % [dBm]

% Linear intensities onto OGS aperture - Irradiance [W/m^2]
int_ogs_lin = dBm_to_W(p_ogs_no_loss) / area_rx; % [W/m^2]
int_ogs_lin_w_loss = dBm_to_W(p_ogs_with_loss) / area_rx; % [W/m^2]

% Required RFE sensitivity power [W] and [dBm]
p_rfe_w = ppb * H * C * dr / wl; % [W]
p_rfe_dbm = 10 * log10(p_rfe_w*1e3); % [dBm]

% Link margin [dB] at reporting elevation
link_margin_db = p_rx_report - p_rfe_dbm;

% Achievable datarate at received power and ppb [bps]
p_rx_report_w = dBm_to_W(p_rx_report);
dr_achievable = p_rx_report_w / (ppb * H * C / wl);
%% 9. Report (single-elevation summary)
fprintf('\n=== LEO-Ground Link Budget @ el = %.1f deg ===\n', el_deg_report);
fprintf('  Wavelength                       %.0f nm\n', wl*1e9);
fprintf('  Slant range                      %.1f km\n', l_report/1e3);
fprintf('  Tx FWHM divergence               %.1f urad\n', theta_tx_rad*1e6);
fprintf('  Rx antena area                   %.1f m^2\n', area_rx);
fprintf('\n');
fprintf('  Tx mean source power            %+7.2f dBm (%.2f W)\n', p_tx, dBm_to_W(p_tx));
fprintf('  Tx internal loss                %+7.2f dB\n', a_tx);
fprintf('  Tx antenna gain                 %+7.2f dB\n', g_tx);
fprintf('  Pointing (Beam Wander) loss     %+7.2f dB\n', a_bw);
fprintf('  Free-space loss                 %+7.2f dB\n', a_fsl_report);
fprintf('  Atmospheric loss                %+7.2f dB\n', a_atm_report);
fprintf('  Scintillation loss              %+7.2f dB\n', a_sci);
fprintf('  Rx antenna gain                 %+7.2f dB\n', g_rx);
fprintf('  Power into Rx aper.             %+7.2f dBm\n', p_ogs_no_loss(el_deg == el_deg_report));
fprintf('   # intensity onto OGS-aperture incl atmosphere but excl. Rx-losses  %.3f uW/m^2\n', int_ogs_lin(el_deg == el_deg_report)*1e6);
fprintf('   # power into the OGS-aperture - no additional RX-losses            %.3f uW\n', dBm_to_W(p_ogs_no_loss(el_deg == el_deg_report))*1e6);
fprintf('  Rx internal loss                %+7.2f dB\n', a_rx);
fprintf('  Power onto detector             %+7.2f dBm (%.3f nW)\n', p_rx_report, dBm_to_W(p_rx_report)*1e9);
fprintf('   # intensity onto OGS-aperture incl atmosphere including Rx-losses  %.3f uW/m^2\n', int_ogs_lin_w_loss(el_deg == el_deg_report)*1e6);
fprintf('   # power into the OGS-aperture including RX-losses                  %.3f uW\n', dBm_to_W(p_ogs_with_loss(el_deg == el_deg_report))*1e6);
fprintf('  RFE sensitivity                 %+7.2f dBm  (%.2f nW, %d ppb)\n', p_rfe_dbm, p_rfe_w*1e9, ppb);
fprintf('  Link margin                     %+7.2f dB\n', link_margin_db);
fprintf('  Achievable datarate             %.2f Gbps\n', dr_achievable/1e9);
fprintf('\n');
%% 10. Plot: intensity vs elevation
figure('Color', 'w', 'Position', [500, 250, 700, 450]);

plot(el_deg, int_ogs_lin*1e6, '-', 'LineWidth', 2);
hold on;
grid on;
plot(el_deg, int_ogs_lin_w_loss*1e6, '--', 'LineWidth', 2);

xlabel('Elevation [$^\circ$]');
ylabel('Irradiance onto OGS aperture [$\mu\mathrm{W}/\mathrm{m}^{2}$]');


legend({'excl. Rx internal losses', 'incl. Rx internal losses'}, ...
    'Location', 'northwest');
%title(sprintf(['Optical irradiance vs elevation ', ...
%'($\\lambda = %.0f\\,\\mathrm{nm}$, $h_{\\mathrm{orb}} = %.0f\\,\\mathrm{km}$)'], ...
%    wl*1e9, h_orbit/1e3));
