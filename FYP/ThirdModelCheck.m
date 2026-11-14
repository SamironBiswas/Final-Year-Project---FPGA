%% arc_model_sim_pv_noise.m
% DC series-arc model (Uriarte et al., IEEE Trans. Smart Grid, 2012) with a
% PV-style noise environment on CURRENT, VOLTAGE and POWER, for generating
% training data. Constant-speed and fixed-gap faults only.
%
% NOISE SOURCES (kept to the few that the literature supports):
%   1. Inverter switching noise: fsw + harmonics (1 kHz to >100 kHz range)
%      and broadband noise                      [Johnson et al., SAND2011-3871C]
%   2. Line-related ripple: 2x grid frequency (single-phase inverter),
%      plus low-order grid harmonics reflected onto the DC side  [same]
%   3. MPPT set-point updates, about once a second, plus anti-islanding spikes
%                                                                [same]
%   4. Irradiance-driven slow variation (drift + cloud ramps; ~3 %/s average
%      ramp during cloud transitions)            [Sandia/cloud-transition papers]
%
% ARC-LIKE NUISANCE EVENTS (label = healthy, but they look arc-like):
%   - crosstalk: pink (1/f) noise bursts, as from an arc on a parallel string
%   - inverter broadband bursts
%   - anti-islanding spike trains
%
% ARC VARIANTS (so arc noise sometimes resembles load noise):
%   'sawtooth' paper's heuristic | 'pink' 1/f arc noise |
%   'bursty' sputtering arc      | 'linesync' arc noise locked to the 2f ripple
%   plus a random arc strength (weak arcs ~ as big as healthy ripple).
%
% HOW THE MEASURED CHANNELS ARE BUILT (detector downstream of the arc):
%   i = i_load(t) * (i_q - j_gap)         series element carries the load current
%   v = v_src(t) - v_gap                  source/bus voltage minus arc drop
%   p = v * i                             from the noisy, quantized v and i
% i_load(t) and v_src(t) contain the noise sources above; voltage ripple is
% coupled to current ripple (anti-phase for low-frequency terms, as at an MPP).
%
% IMPORTANT: noise AMPLITUDES are calibrated to Sandia Fig. 6 (healthy ripple
% ~5 % p-p; arc swing ~3-5x that), read off a plot by eye. MPPT step size,
% voltage coupling factors, nuisance amplitudes and sensor noise are ASSUMED
% - the cited papers show these effects exist but give no numbers I could read.
%
% Needs base MATLAB only (R2016b+). Not run in MATLAB by the author.

clear; clc; close all;

%% ------------------------------------------------------------------------
%  Parameters
% -------------------------------------------------------------------------
P.a = 0.01;  P.b = 0.005;  P.lam = 100;  P.Rclosed = 0.001;   % Table II
P.tpre  = 1.0;                 % healthy time before the fault [s]
P.dt    = 10e-6;               % 100 kHz sampling (detection band is 100 Hz-100 kHz)
P.noise = defaultNoise();
P.arc   = struct('style','sawtooth', 'hold',1, 'cap',0.85, 'jMax',0.20);
% arc.cap  : fixed-gap strength, max q (0.72 weak ... 0.92 violent)
% arc.jMax : constant-speed jitter amplitude
% arc.hold : samples each jitter value is held (lowers arc noise bandwidth)

% Sandia-like single string: about 270 V and 4 A (their Figs. 6 and 7)
C1 = P; C1.type = 'constant'; C1.Vdc = 270; C1.Iload = 4;
C1.tdur = 6.94; C1.speed = 2.54;
C2 = P; C2.type = 'fixed';    C2.Vdc = 270; C2.Iload = 4;
C2.tdur = 3;    C2.xFixed = 6.35;

%% ------------------------------------------------------------------------
%  Figure 1: current for the two fault types (default noise settings)
% -------------------------------------------------------------------------
rng(1);  R1 = simulateArc(C1);
rng(2);  R2 = simulateArc(C2);

figure('Name','Noisy arc current','Position',[100 100 900 550]);
plotCurrent(subplot(2,1,1), R1, 'Constant-speed gap (2.54 mm/s)');
plotCurrent(subplot(2,1,2), R2, 'Fixed gap (6.35 mm)');
xlabel('Time (s)');

reportCalibration(R1, 'constant-speed');
reportCalibration(R2, 'fixed-gap     ');

%% ------------------------------------------------------------------------
%  Figure 2: what the noise looks like (fixed-gap case, current only)
% -------------------------------------------------------------------------
Cq = C2;  Cq.noise.enable = false;           % same arc, no noise
rng(2);   Rq = simulateArc(Cq);

figure('Name','Noise decomposition (current)','Position',[150 60 950 880]);

subplot(4,1,1);                              % slow components
plot(R2.t, R2.comp.slow, 'k'); grid on;
ylabel('slow multiplier (p.u.)');
title('Irradiance drift/clouds + MPPT steps (full record)');

subplot(4,1,2);                              % healthy zoom
zw = R2.t > 0.50 & R2.t < 0.54;
plot(R2.t(zw)*1e3, R2.i(zw), 'Color',[0 0.45 0.15]); hold on;
plot(Rq.t(zw)*1e3, Rq.i(zw), 'r--'); grid on;
legend('with noise','no noise','Location','best');
xlabel('Time (ms)'); ylabel('i (A)');
title('Zoom, healthy (40 ms): 100 Hz ripple + switching + broadband');

subplot(4,1,3);                              % arc zoom
t0 = C2.tpre + 1.0;
zw = R2.t > t0 & R2.t < t0 + 0.04;
plot(R2.t(zw)*1e3, R2.i(zw), 'Color',[0 0.45 0.15]); hold on;
plot(Rq.t(zw)*1e3, Rq.i(zw), 'r--'); grid on;
xlabel('Time (ms)'); ylabel('i (A)');
title('Zoom, arc burning (40 ms)');

subplot(4,1,4);                              % spectra
fs = 1/C2.dt;
wH = R2.t >= 0.2 & R2.t < 0.7;
wA = R2.t >= C2.tpre+0.5 & R2.t < C2.tpre+1.0;
[fH, AH] = ampSpectrum(R2.i(wH), fs);
[fA, AA] = ampSpectrum(R2.i(wA), fs);
[fQ, AQ] = ampSpectrum(Rq.i(wA), fs);
semilogx(fH(2:end), 20*log10(AH(2:end)+eps), 'b'); hold on;
semilogx(fA(2:end), 20*log10(AA(2:end)+eps), 'Color',[0 0.45 0.15]);
semilogx(fQ(2:end), 20*log10(AQ(2:end)+eps), 'r');
grid on; xlabel('Frequency (Hz)'); ylabel('Amplitude (dB re 1 A)');
legend('healthy, noisy','arc, noisy','arc, no noise','Location','southwest');
title('Current spectra (0.5 s windows). Sandia: arc rises above baseline ~100 Hz-100 kHz');

%% ------------------------------------------------------------------------
%  Figure 3: randomized batch (current only)
%  Each run draws its own operating point, inverter/noise settings, arc
%  style and arc strength, and its own nuisance events.
%  Red = nuisance event (arc-like noise, but NO series arc: label 0).
% -------------------------------------------------------------------------
bases = {C1, C2};
bases{1}.tdur = 2;  bases{2}.tdur = 1.5;
figure('Name','Randomized batch (current)','Position',[200 40 1100 900]);
rng(10);
for n = 1:8
    k  = mod(n-1,2) + 1;
    Cn = randomizeRun(bases{k});
    Rn = simulateArc(Cn);
    ax = subplot(4,2,n);
    plot(ax, Rn.t, Rn.i, 'Color',[0 0.45 0.15]); hold(ax,'on');
    ip = Rn.i;  ip(Rn.nuis == 0) = NaN;
    plot(ax, Rn.t, ip, 'r');
    plot(ax, [Cn.tpre Cn.tpre], [0 1.6*Cn.Iload], 'k--'); grid(ax,'on');
    ylim(ax, [0 1.6*Cn.Iload]);
    title(ax, sprintf('%s | %s, hold %d | %s inv, fsw %.0f kHz | %.0f V/%.0f A', ...
          Cn.type, Cn.arc.style, Cn.arc.hold, Cn.noise.inv.type, ...
          Cn.noise.inv.fsw/1e3, Cn.Vdc, Cn.Iload), 'FontSize',8);
end
% Per-run outputs for training: Rn.i, Rn.v, Rn.p (A, V, W), Rn.label
% (0 healthy, 1 arc burning, 2 extinguished) and Rn.nuis (0 none,
% 1 crosstalk burst, 2 inverter burst, 3 anti-islanding spike).

%% ========================================================================
%  Local functions
% =========================================================================
function Z = defaultNoise()
% Amplitudes are fractions of nominal (peak unless stated).
    Z.enable = true;
    % ---- inverter / converter (current-referred) -------------------------
    Z.inv.type     = 'single';        % 'single' (strong 2f ripple) or 'three'
    Z.inv.f0       = 50;              % grid frequency [Hz]
    Z.inv.fsw      = 20e3;            % switching frequency [Hz]
    Z.inv.swAmp    = [0.005 0.0025];  % fsw and 2*fsw harmonic amplitudes
    Z.inv.swWander = 0.002;           % slow fractional wander of fsw (std)
    Z.inv.lineAmp2 = 0.010;           % 2f ripple (single-phase) amplitude
    Z.inv.h50      = [0.0015 0.0015 0.001];  % f0, 3*f0, 5*f0 harmonics
    Z.inv.bbStd    = 0.0035;          % broadband noise std
    Z.inv.bbCorner = 20e3;            % broadband corner [Hz]
    % ---- voltage coupling (ASSUMED) ---------------------------------------
    Z.v.kLow    = 0.5;                % dv/v = -kLow * di/i for low-freq terms
    Z.v.kIrr    = 0.05;               % voltage rises slightly with irradiance
    Z.v.swScale = 1.0;                % switching ripple in v vs in i
    Z.v.bbStd   = 0.0025;             % voltage broadband noise std
    % ---- sensors (ASSUMED) -------------------------------------------------
    Z.sens.iStd = 0.0015;  Z.sens.vStd = 0.001;   % std, fraction of nominal
    Z.sens.bits = 12;      Z.sens.fsFactor = 1.5; % ADC bits, full scale/nominal
    % ---- irradiance (slow) -------------------------------------------------
    Z.irr.driftStd   = 0.015;  Z.irr.driftTau = 3;   % slow drift
    Z.irr.cloudRate  = 0.15;                          % cloud events per second
    Z.irr.cloudDepth = [0.05 0.40];                   % dip depth (fraction)
    Z.irr.cloudRamp  = [1 5];                         % ramp time [s]
    Z.irr.cloudHold  = [0.5 4];                       % hold time [s]
    % ---- MPPT (update step size ASSUMED) ----------------------------------
    Z.mppt.period = 1.0;  Z.mppt.periodJitter = 0.2;  % update about every 1 s
    Z.mppt.stepStd = 0.008;  Z.mppt.tau = 5e-3;       % set-point step
    Z.mppt.transAmp = 0.025; Z.mppt.transTau = 0.02;  Z.mppt.transFreq = 120;
    % ---- arc-like nuisance events (amplitudes ASSUMED) --------------------
    Z.nuis.crossRate = 0.4;  Z.nuis.crossStd = [0.01 0.04]; Z.nuis.crossDur = [0.05 0.5];
    Z.nuis.burstRate = 0.4;  Z.nuis.burstAmp = [0.02 0.06]; Z.nuis.burstDur = [1e-3 2e-2];
    Z.nuis.islPeriod = Inf;  Z.nuis.islAmp = [0.02 0.08];   Z.nuis.islTau = 0.5e-3;
    Z.nuis.vCoupling = -0.3;          % nuisance in v relative to nuisance in i
end

function P = randomizeRun(P)
% Random operating point, noise settings, arc style/strength for one run.
    fs = 1/P.dt;
    lg = @(s) exp(s*randn);
    ops = [650 163.07; 270 4; 400 8; 600 10];       % [Vdc Iload]
    op  = ops(randi(size(ops,1)), :);
    P.Vdc = op(1);  P.Iload = op(2);

    Z = defaultNoise();
    if rand < 0.7, Z.inv.type = 'single'; else, Z.inv.type = 'three'; end
    if rand < 0.7, Z.inv.f0 = 50; else, Z.inv.f0 = 60; end
    Z.inv.fsw      = 5e3 + (0.4*fs - 5e3)*rand;
    Z.inv.swAmp    = Z.inv.swAmp * lg(0.4);
    Z.inv.swWander = Z.inv.swWander * lg(0.5);
    Z.inv.lineAmp2 = Z.inv.lineAmp2 * lg(0.4);
    Z.inv.h50      = Z.inv.h50 * lg(0.4);
    Z.inv.bbStd    = Z.inv.bbStd * lg(0.4);
    Z.v.kLow       = 0.2 + 0.8*rand;
    Z.v.swScale    = 0.5 + rand;
    Z.v.bbStd      = Z.v.bbStd * lg(0.4);
    Z.irr.driftStd = Z.irr.driftStd * lg(0.5);
    Z.irr.cloudRate= 0.3*rand;
    Z.mppt.period  = 0.5 + rand;
    Z.mppt.stepStd = Z.mppt.stepStd * lg(0.5);
    Z.mppt.transAmp= Z.mppt.transAmp * lg(0.5);
    Z.nuis.crossRate = (rand < 0.6) * 0.8 * rand;
    Z.nuis.burstRate = (rand < 0.5) * 1.0 * rand;
    if rand < 0.4, Z.nuis.islPeriod = 0.5 + 1.5*rand; else, Z.nuis.islPeriod = Inf; end
    Z.nuis.vCoupling = (2*(rand < 0.5) - 1) * (0.1 + 0.5*rand);
    bitsList = [10 12 14 16];
    Z.sens.bits = bitsList(randi(4));
    P.noise = Z;

    styles = {'sawtooth','pink','bursty','linesync'};
    holds  = [1 2 5 10 20];
    P.arc.style = styles{randi(4)};
    P.arc.hold  = holds(randi(5));
    P.arc.cap   = 0.72 + 0.20*rand;     % weak ... violent
    P.arc.jMax  = 0.10 + 0.20*rand;
end

function R = simulateArc(P)
    dt = P.dt;  tpre = P.tpre;  Z = P.noise;
    switch P.type
        case 'constant', tend = tpre + 1.1*P.tdur;
        case 'fixed',    tend = tpre + P.tdur;
        otherwise, error('Unknown fault type');
    end
    t = (0:dt:tend).';
    n = numel(t);
    alpha = -0.5*log(P.Rclosed*P.Iload/P.Vdc);               % Eq. (7)

    % ---- arc distance ratio q(t) (generated BEFORE the noise so that a
    %      noise-free twin run with the same rng seed has the identical arc)
    iF  = find(t >= tpre, 1);
    nf  = n - iF + 1;
    jit = arcJitter(P.arc.style, nf, dt, P.arc.hold, Z.inv.f0);   % in [0,1]
    q   = zeros(n,1);
    switch P.type
        case 'constant'
            xgap = P.speed * max(t - tpre, 0);
            q(iF:n) = (t(iF:n) - tpre)/P.tdur + P.arc.jMax*jit;
            kq = find(q >= 1, 1);
            if ~isempty(kq)                                  % arc collapses
                q(kq:n) = q(kq) + 200*(t(kq:n) - t(kq));
            end
        case 'fixed'
            xgap = P.xFixed * (t >= tpre);
            q(iF:n) = P.arc.cap * jit;                       % never reaches 1
    end

    % ---- paper's arc model (per unit) ------------------------------------
    inArc = (q > 0) & (q < 1);
    vq   = 0.5 + 0.5*tanh(alpha*(q-1));                      % (1)
    iq   = 0.5 - 0.5*tanh(alpha*(q-1));                      % (3)
    egap = 0.5*(P.a + P.b*xgap) .* ...
           (tanh(P.lam*q) - tanh(P.lam*(q-1))) .* inArc;     % (2)
    vgap = vq + egap;
    igapClean = iq - egap;                                   % (4), Iload/Vdc = 1 p.u.

    % ---- noise environment -----------------------------------------------
    if Z.enable
        [mi, mv, nuis, comp] = loadNoise(t, Z);
    else
        mi = ones(n,1);  mv = ones(n,1);  nuis = zeros(n,1);
        comp.slow = ones(n,1);
    end
    i_pu = mi .* igapClean;                                  % current: series element
    v_pu = mv - vgap;                                        % voltage downstream of arc
    i = i_pu * P.Iload;
    v = v_pu * P.Vdc;

    % ---- sensors: additive noise + ADC quantization ----------------------
    if Z.enable
        i = i + Z.sens.iStd*P.Iload*randn(n,1);
        v = v + Z.sens.vStd*P.Vdc*randn(n,1);
        if Z.sens.bits > 0
            qi = 2*Z.sens.fsFactor*P.Iload/2^Z.sens.bits;
            qv = 2*Z.sens.fsFactor*P.Vdc  /2^Z.sens.bits;
            i = round(i/qi)*qi;
            v = round(v/qv)*qv;
        end
    end
    p = v .* i;                                              % power from measured v, i

    label = zeros(n,1);                                      % 0 healthy
    label(t >= tpre & q <  1) = 1;                           % 1 arc burning
    label(t >= tpre & q >= 1) = 2;                           % 2 extinguished

    R.t = t;  R.q = q;  R.label = label;  R.nuis = nuis;
    R.i = i;  R.v = v;  R.p = p;                             % A, V, W
    R.iClean = igapClean*P.Iload;  R.vClean = (1 - vgap)*P.Vdc;
    R.comp = comp;  R.alpha = alpha;  R.P = P;
end

function [mi, mv, nuis, comp] = loadNoise(t, Z)
% Returns the current multiplier mi, source-voltage multiplier mv (both p.u.
% of nominal), the nuisance-event id vector and the slow components.
    n = numel(t);  dt = t(2) - t(1);  fs = 1/dt;

    % ---- (4) irradiance: drift + cloud ramps ----------------------------
    irr = colouredNoise(n, dt, Z.irr.driftTau, Z.irr.driftStd) ...
          + cloudEvents(t, Z.irr);
    % ---- (3) MPPT updates ------------------------------------------------
    [mStep, mTrans] = mpptNoise(t, Z.mppt);

    % ---- (1) inverter switching: tone + harmonics, wandering frequency ---
    fInst = Z.inv.fsw * (1 + colouredNoise(n, dt, 0.1, Z.inv.swWander));
    ph  = 2*pi*cumsum(fInst)*dt;
    swI = zeros(n,1);  swV = zeros(n,1);
    for h = 1:numel(Z.inv.swAmp)
        if h*Z.inv.fsw*1.05 >= fs/2
            warning('arcsim:alias', ...
                'Switching harmonic %d is above Nyquist and was dropped.', h);
            continue;
        end
        swI = swI + Z.inv.swAmp(h)*sin(h*ph + 2*pi*rand);
        swV = swV + Z.v.swScale*Z.inv.swAmp(h)*sin(h*ph + 2*pi*rand);
    end
    tauBB = 1/(2*pi*Z.inv.bbCorner);
    bbI = colouredNoise(n, dt, tauBB, Z.inv.bbStd);
    bbV = colouredNoise(n, dt, tauBB, Z.v.bbStd);

    % ---- (2) line-related ripple ------------------------------------------
    f0 = Z.inv.f0;
    if strcmp(Z.inv.type, 'three')
        lf = [6 12]*f0;  la = [0.4 0.12]*Z.inv.lineAmp2;
    else
        lf = [2 4]*f0;   la = [1 0.3]*Z.inv.lineAmp2;
    end
    lineI = zeros(n,1);
    for k = 1:numel(lf)
        lineI = lineI + la(k)*sin(2*pi*lf(k)*t + 2*pi*rand);
    end
    hf = [1 3 5]*f0;
    for k = 1:numel(hf)
        lineI = lineI + Z.inv.h50(k)*sin(2*pi*hf(k)*t + 2*pi*rand);
    end

    % ---- arc-like nuisance events (additive, fraction of nominal) --------
    [nuisI, nuis] = nuisanceEvents(t, Z.nuis);

    % ---- combine -----------------------------------------------------------
    mi = (1 + irr + mStep + mTrans) .* (1 + swI + lineI + bbI) + nuisI;
    mi = max(mi, 0);
    mv = 1 - Z.v.kLow*(mStep + mTrans + lineI) + Z.v.kIrr*irr ...
         + swV + bbV + Z.nuis.vCoupling*nuisI;

    comp.slow = 1 + irr + mStep;
    comp.irr = irr;  comp.mStep = mStep;  comp.lineI = lineI;
end

function c = cloudEvents(t, C)
% Cloud passages: ramp down, hold, ramp up (current dips, p.u.).
    T = t(end);  c = zeros(size(t));
    tk = -log(rand())/C.cloudRate;
    while tk < T
        depth = C.cloudDepth(1) + diff(C.cloudDepth)*rand;
        r1 = C.cloudRamp(1) + diff(C.cloudRamp)*rand;
        h  = C.cloudHold(1) + diff(C.cloudHold)*rand;
        r2 = C.cloudRamp(1) + diff(C.cloudRamp)*rand;
        c = c + interp1([tk tk+r1 tk+r1+h tk+r1+h+r2], [0 -depth -depth 0], ...
                        t, 'linear', 0);
        tk = tk + r1 + h + r2 - log(rand())/C.cloudRate;
    end
    c = max(c, -0.8);
end

function [step, trans] = mpptNoise(t, M)
% MPPT set-point update about every M.period s: a small step (smoothed by the
% inverter response) plus a short damped oscillation at the update instant.
    n = numel(t);  dt = t(2) - t(1);  T = t(end);
    ev = [];  tk = M.period*rand();
    while tk < T
        ev(end+1) = tk;                                      %#ok<AGROW>
        tk = tk + M.period*(1 + M.periodJitter*(2*rand - 1));
    end
    target = zeros(n,1);  trans = zeros(n,1);
    level = 0;  iPrev = 1;
    for k = 1:numel(ev)
        i = min(n, round(ev(k)/dt) + 1);
        target(iPrev:i-1) = level;
        level = 0.5*level + M.stepStd*randn;
        iPrev = i;
        m  = (i:min(n, i + round(6*M.transTau/dt))).';
        tt = (m - i)*dt;
        trans(m) = trans(m) + M.transAmp*(2*rand - 1) .* exp(-tt/M.transTau) ...
                              .* cos(2*pi*M.transFreq*tt);
    end
    target(iPrev:end) = level;
    a = exp(-dt/M.tau);
    step = filter(1-a, [1 -a], target);
end

function [nI, id] = nuisanceEvents(t, N)
% Healthy-state disturbances that resemble arcing (label stays 0).
%   id 1: crosstalk-like pink (1/f) noise burst (arc on a parallel string)
%   id 2: inverter broadband burst
%   id 3: anti-islanding style spike train
    n = numel(t);  dt = t(2) - t(1);  T = t(end);
    nI = zeros(n,1);  id = zeros(n,1);

    tk = -log(rand())/N.crossRate;                           % crosstalk
    while tk < T
        dur = N.crossDur(1) + diff(N.crossDur)*rand;
        i0 = round(tk/dt) + 1;  i1 = min(n, i0 + round(dur/dt));  L = i1 - i0 + 1;
        if L > 16
            amp = N.crossStd(1) + diff(N.crossStd)*rand;
            env = 0.5 - 0.5*cos(2*pi*(0:L-1).'/(L-1));
            nI(i0:i1) = nI(i0:i1) + amp*pinkNoise(L).*env;
            id(i0:i1) = 1;
        end
        tk = tk + dur - log(rand())/N.crossRate;
    end

    tk = -log(rand())/N.burstRate;                           % broadband bursts
    while tk < T
        dur = N.burstDur(1) + diff(N.burstDur)*rand;
        i0 = round(tk/dt) + 1;  i1 = min(n, i0 + round(dur/dt));  L = i1 - i0 + 1;
        if L > 8
            amp = N.burstAmp(1) + diff(N.burstAmp)*rand;
            env = 0.5 - 0.5*cos(2*pi*(0:L-1).'/(L-1));
            x = colouredNoise(L, dt, 1/(2*pi*20e3), 1);
            nI(i0:i1) = nI(i0:i1) + amp*x.*env;
            id(i0:i1) = 2;
        end
        tk = tk + dur - log(rand())/N.burstRate;
    end

    if isfinite(N.islPeriod)                                 % spike train
        tk = N.islPeriod*rand();
        while tk < T
            i0 = round(tk/dt) + 1;
            m  = (i0:min(n, i0 + round(8*N.islTau/dt))).';
            amp = N.islAmp(1) + diff(N.islAmp)*rand;
            nI(m) = nI(m) + (2*(rand < 0.5) - 1)*amp*exp(-(m - i0)*dt/N.islTau);
            id(m) = 3;
            tk = tk + N.islPeriod;
        end
    end
end

function j = arcJitter(style, nf, dt, holdN, f0)
% Arc fluctuation process j in [0,1], held for `holdN` samples. Different
% styles make arc noise look different - or like load noise ('linesync').
    m = ceil(nf/holdN);
    switch style
        case 'sawtooth'                       % paper: q += rand^10, resets
            j = sawNorm(m);
        case 'pink'                           % 1/f arc noise (Sandia)
            j = min(max(0.35 + 0.20*pinkNoise(m), 0), 1);
        case 'bursty'                         % sputtering: on/off bursts
            j = 0.1*ones(m,1);  pos = 1;  on = rand < 0.5;
            while pos <= m
                md  = 0.08*on + 0.05*(~on);
                len = max(1, round(-log(rand())*md/(holdN*dt)));
                e   = min(m, pos + len - 1);
                if on, j(pos:e) = sawNorm(e - pos + 1); end
                pos = e + 1;  on = ~on;
            end
        case 'linesync'                       % arc noise locked to 2*f0 ripple
            tm  = ((0:m-1).' * holdN) * dt;
            env = 0.35 + 0.65*(0.5 + 0.5*cos(2*pi*2*f0*tm + 2*pi*rand));
            j   = sawNorm(m) .* env;
        otherwise
            error('Unknown arc style');
    end
    j = repelem(j, holdN);
    j = j(1:nf);
end

function s = sawNorm(m)
% Paper's saw-tooth, normalised by its 0.9 reset threshold.
    s = zeros(m,1);  v = 0;
    for k = 1:m
        v = v + rand()^10/0.9;
        if v > 1, v = rand(); end
        s(k) = v;
    end
end

function x = pinkNoise(L)
% Unit-std 1/f (pink) noise of length L via FFT shaping (base MATLAB).
    W    = fft(randn(L,1));
    half = floor(L/2) + 1;
    k    = (0:half-1).';
    sc   = 1./sqrt(max(k,1));  sc(1) = 0;                    % 1/f power, no DC
    Wh   = W(1:half) .* sc;
    if mod(L,2) == 0
        full = [Wh; conj(Wh(end-1:-1:2))];
    else
        full = [Wh; conj(Wh(end:-1:2))];
    end
    x = real(ifft(full));
    x = x/std(x);
end

function y = colouredNoise(n, dt, tau, sd)
% Stationary first-order (Ornstein-Uhlenbeck-type) noise with std = sd.
    phi = exp(-dt/tau);
    y   = filter(sqrt(1-phi^2), [1 -phi], randn(n,1), phi*randn) * sd;
end

function reportCalibration(R, tag)
% Compares ripple with the Sandia Fig. 6 reading (about 5 % p-p healthy,
% arc swing about 3-5x larger).
    dt = R.t(2) - R.t(1);
    hp = R.i - movmean(R.i, round(0.05/dt));                 % remove slow part
    h  = R.label == 0 & R.t > 0.15 & R.t < R.P.tpre - 0.05;
    a  = R.label == 1;
    kQ = find(R.label == 2, 1);
    if ~isempty(kQ), a = a & R.t > R.t(kQ) - 1.0; end        % last 1 s before collapse
    ppH = ppRobust(hp(h)) / mean(R.i(h)) * 100;
    ppA = ppRobust(hp(a)) / mean(R.i(h)) * 100;
    fprintf('%s: healthy p-p = %.1f %% | arc p-p = %.1f %% (%.1fx) | target ~5 %% and ~3-5x\n', ...
            tag, ppH, ppA, ppA/ppH);
end

function pp = ppRobust(x)
    s = sort(x(:));  k = numel(s);
    pp = s(min(k, round(0.995*k))) - s(max(1, round(0.005*k)));
end

function plotCurrent(ax, R, ttl)
    plot(ax, R.t, R.i, 'Color',[0 0.45 0.15]); hold(ax,'on');
    ip = R.i;  ip(R.nuis == 0) = NaN;
    plot(ax, R.t, ip, 'r');                                  % nuisance events
    plot(ax, [R.P.tpre R.P.tpre], [0 1.6*R.P.Iload], 'k--');
    grid(ax,'on');  ylabel(ax, 'i (A)');  title(ax, ttl);
    ylim(ax, [0 1.6*R.P.Iload]);
end

function [f, A] = ampSpectrum(x, fs)
    x = x(:) - mean(x);
    n = numel(x);
    w = 0.5 - 0.5*cos(2*pi*(0:n-1).'/(n-1));                 % Hann window
    X = fft(x .* w);
    m = floor(n/2) + 1;
    A = abs(X(1:m)) * 2 / sum(w);
    f = (0:m-1).' * fs / n;
end