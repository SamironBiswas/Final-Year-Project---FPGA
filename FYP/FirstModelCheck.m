%% arc_model_sim.m
% Simulation of the heuristic DC series-arc model from:
%   F. M. Uriarte et al., "A DC Arc Model for Series Faults in Low Voltage
%   Microgrids," IEEE Trans. Smart Grid, vol. 3, no. 4, 2012.
%
% Model (per-unit, Vbase = Vdc, Ibase = Iload):
%   v_q   = 1/2 + 1/2*tanh(alpha*(q-1))                      Eq. (1)
%   e_gap = 1/2*(a + b*x_gap)*(tanh(lam*q) - tanh(lam*(q-1))) Eq. (2), 0<q<1
%   i_q   = 1/2 - 1/2*tanh(alpha*(q-1))                      Eq. (3)
%   j_gap = e_gap * Iload / Vdc  (= e_gap in p.u.)           Eq. (4)
%   v_gap = v_q + e_gap,   i_gap = i_q - j_gap
%   R_gap = (Vdc/Iload)*exp(2*alpha*(q-1))                   Eq. (5)
%   alpha = -1/2*log(Rclosed*Iload/Vdc)                      Eq. (7)
%   q     = x_gap / x_crit  (arc quenches when q >= 1)
%
% The q(t) trajectories (the "arc randomness") follow the paper's
% descriptions for each fault type; where the paper is not explicit the
% choices are marked "INTERPRETATION" below and are easy to change.
%
% Run the script directly. Needs base MATLAB only (R2016b+ for local
% functions in scripts).

clear; clc; close all;
rng(1);                       % reproducible randomness; change for new runs

%% ------------------------------------------------------------------------
%  Common parameters (Table II of the paper)
% -------------------------------------------------------------------------
P.a       = 0.01;     % gap EMF turn-on voltage        [p.u.]
P.b       = 0.005;    % gap EMF slope                  [p.u. per mm]
P.lam     = 100;      % e_gap rise/decay rate
P.Rclosed = 0.001;    % resistance with electrodes closed [ohm]
P.tpre    = 1.0;      % healthy time before fault starts [s]

%% ------------------------------------------------------------------------
%  Figure 1: the three fault types (cases from Table II / Section VII)
% -------------------------------------------------------------------------
% Case 1: constant-speed gap (2.54 mm/s), Rload = 3.986 ohm
C1 = P;  C1.type = 'constant';  C1.Vdc = 650;  C1.Iload = 650/3.986;
C1.dt = 50e-6;  C1.tdur = 6.94;  C1.speed = 2.54;   % mm/s
C1.sMax = 0.30; C1.sStep = 0.10;     % INTERPRETATION: jitter amplitude/step

% Case 2: fixed gap of 6.35 mm, same load
C2 = P;  C2.type = 'fixed';     C2.Vdc = 650;  C2.Iload = 650/3.986;
C2.dt = 100e-6; C2.tdur = 8;     C2.xFixed = 6.35;   % mm

% Case 3: accelerated gap (falling conductor), Rload = 7.679 ohm
C3 = P;  C3.type = 'accel';     C3.Vdc = 650;  C3.Iload = 650/7.679;
C3.dt = 50e-6;  C3.tdur = 0.16;                       % fault duration [s]

R1 = simulateArc(C1);
R2 = simulateArc(C2);
R3 = simulateArc(C3);

figure('Name','Arc current - three fault types','Position',[100 100 900 750]);
plotCurrent(subplot(3,1,1), R1, 'Constant-speed gap (2.54 mm/s)');
plotCurrent(subplot(3,1,2), R2, 'Fixed gap (6.35 mm)');
plotCurrent(subplot(3,1,3), R3, 'Accelerated gap (9800 mm/s^2)');
xlabel('Time (s)');

%% ------------------------------------------------------------------------
%  Figure 2: sample values - different system voltage / load current
%  (fixed-gap fault, p.u. current, shows the effect of alpha on the arc)
% -------------------------------------------------------------------------
samples = [ 650 163;      % Vdc [V], Iload [A]
            400  50;
            800 200 ];
figure('Name','Arc current - sample Vdc / Iload','Position',[150 150 900 700]);
for n = 1:size(samples,1)
    S = C2;  S.Vdc = samples(n,1);  S.Iload = samples(n,2);  S.tdur = 3;
    R = simulateArc(S);
    ax = subplot(size(samples,1),1,n);
    plot(ax, R.t, R.igap_pu, 'Color',[0 0.45 0.15]); grid on;
    ylim([0 1.05]); ylabel('i_{gap} (p.u.)');
    title(ax, sprintf('Fixed gap: Vdc = %g V, Iload = %g A  (alpha = %.3f)', ...
                      S.Vdc, S.Iload, R.alpha));
end
xlabel('Time (s)');

%% ------------------------------------------------------------------------
%  Figure 3: constant-speed case, voltage / current / power / resistance
% -------------------------------------------------------------------------
figure('Name','Constant-speed fault details','Position',[200 100 900 800]);
subplot(4,1,1); plot(R1.t,R1.vgap_pu,'b'); grid on; ylabel('v_{gap} (p.u.)');
title('Constant-speed fault - details');
subplot(4,1,2); plot(R1.t,R1.igap_pu,'Color',[0 0.45 0.15]); grid on; ylabel('i_{gap} (p.u.)');
subplot(4,1,3); plot(R1.t,R1.pgap_pu,'r'); grid on; ylabel('p_{gap} (p.u.)');
subplot(4,1,4); semilogy(R1.t,R1.Rgap,'k'); grid on; ylabel('R_{gap} (\Omega)');
xlabel('Time (s)');

fprintf('alpha (case 1) = %.4f\n', R1.alpha);
fprintf('Peak arc power, constant-speed: %.3f p.u. (paper: ~0.25)\n', max(R1.pgap_pu));
fprintf('Peak arc power, fixed gap     : %.3f p.u.\n', max(R2.pgap_pu));
fprintf('Peak arc power, accelerated   : %.3f p.u.\n', max(R3.pgap_pu));

%% ========================================================================
%  Local functions
% =========================================================================
function R = simulateArc(P)
    dt  = P.dt;
    tpre = P.tpre;

    switch P.type
        case 'constant', tend = tpre + 1.1*P.tdur;
        case 'fixed',    tend = tpre + P.tdur;
        case 'accel',    tend = tpre + 1.3*P.tdur;
        otherwise, error('Unknown fault type');
    end
    t = (0:dt:tend).';
    N = numel(t);
    tau = max(t - tpre, 0);              % time since fault start [s]

    % ---- alpha from assumed closed-electrode resistance, Eq. (7) --------
    alpha = -0.5*log(P.Rclosed*P.Iload/P.Vdc);

    % ---- distance ratio q(t) and gap distance x_gap(t) [mm] -------------
    q = zeros(N,1);
    switch P.type
        case 'constant'
            xgap = P.speed*tau;                        % constant speed
            qTrend = tau / P.tdur;                     % x_gap / nominal x_crit
            s = 0; quenched = false;
            for k = 2:N
                if t(k) < tpre, q(k) = 0; continue; end
                if quenched
                    q(k) = q(k-1) + 0.002;             % arc collapses
                    continue;
                end
                % INTERPRETATION: saw-tooth jitter built from Eq. (11),
                % rand()^10 increments, reset at an upper bound, added
                % on top of the deterministic ramp x_gap/x_crit.
                s = s + rand()^10 * P.sStep;
                if s > P.sMax, s = rand()*P.sMax; end
                q(k) = qTrend(k) + s;
                if q(k) >= 1, quenched = true; end     % q>1 -> extinction
            end

        case 'fixed'
            xgap = P.xFixed * (tau > 0);               % electrodes dwell
            for k = 2:N
                if t(k) < tpre, q(k) = 0; continue; end
                q(k) = q(k-1) + rand()^10;             % Eq. (11)
                if q(k) > 0.9, q(k) = rand(); end      % reset: burns forever
            end

        case 'accel'
            xgap = 0.5*9800*tau.^2;                    % mm
            q = (tau / P.tdur).^2;                     % Eq. (12), no jitter
    end

    % ---- per-unit gap voltage and current -------------------------------
    inArc = (q > 0) & (q < 1);
    vq   = 0.5 + 0.5*tanh(alpha*(q-1));                            % (1)
    iq   = 0.5 - 0.5*tanh(alpha*(q-1));                            % (3)
    egap = 0.5*(P.a + P.b*xgap) .* ...
           (tanh(P.lam*q) - tanh(P.lam*(q-1))) .* inArc;           % (2)
    jgap = egap;                       % Eq. (4) in p.u. (Iload/Vdc = 1)
    vgap = vq + egap;
    igap = iq - jgap;
    Rgap = (P.Vdc/P.Iload) * exp(2*alpha*(q-1));                   % (5)

    R.t = t;  R.q = q;  R.alpha = alpha;  R.xgap = xgap;
    R.vgap_pu = vgap;  R.igap_pu = igap;  R.pgap_pu = vgap.*igap;
    R.vgap = vgap*P.Vdc;  R.igap = igap*P.Iload;  R.Rgap = Rgap;
    R.P = P;
end

function plotCurrent(ax, R, ttl)
    plot(ax, R.t, R.igap, 'Color',[0 0.45 0.15]); grid(ax,'on');
    ylabel(ax, 'i_{gap} (A)');
    title(ax, ttl);
    xline(ax, R.P.tpre, 'k--', 'fault starts', 'LabelVerticalAlignment','bottom');
    ylim(ax, [0 1.1*R.P.Iload]);
end