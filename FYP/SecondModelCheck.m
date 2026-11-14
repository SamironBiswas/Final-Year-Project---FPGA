%% arc_model_sim_noise.m
% DC series-arc model (Uriarte et al., IEEE Trans. Smart Grid, 2012) with a
% realistic NOISY LOAD CURRENT, intended for generating training data.
%
% The arc is a series element, so it carries whatever the load draws:
%       i_gap(t) = i_load(t) * ( i_q(q) - j_gap(q) )          [p.u.]
% where i_load(t) (p.u. of nominal Iload) contains
%   (1) inverter / converter noise
%         - switching-frequency ripple + harmonics (with slow frequency wander)
%         - low-frequency DC-link ripple (2x grid freq, or 6x for 3-phase rect.)
%         - broadband (band-limited) switching noise
%   (2) load variations
%         - slow random drift (Ornstein-Uhlenbeck process)
%         - random load steps (converter / MPPT / appliance changes) with a
%           first-order response
% Because the noise sits inside i_load(t), it is present in the healthy
% state, is carried through the burning arc, and disappears when the arc
% extinguishes (series circuit opens) - which is physically what happens.
%
% NOTE: all noise magnitudes below are engineering assumptions, NOT values
% from the paper. Calibrate them against measurements from your own system.
% The arc-side jitter (q) is the paper's heuristic, validated by the authors
% only on envelopes / power / energy, not on frequency content.
%
% Needs base MATLAB only (R2016b+ for local functions in scripts).

clear; clc; close all;
rng(1);

%% ------------------------------------------------------------------------
%  Arc parameters (Table II of the paper)
% -------------------------------------------------------------------------
P.a       = 0.01;     % gap EMF turn-on voltage [p.u.]
P.b       = 0.005;    % gap EMF slope [p.u./mm]
P.lam     = 100;      % e_gap rise/decay rate
P.Rclosed = 0.001;    % closed-electrode resistance [ohm]
P.tpre    = 1.0;      % healthy time before the fault [s]
P.dt      = 10e-6;    % 100 kHz sampling (needed to resolve switching ripple)
P.noise   = defaultNoise();

C1 = P; C1.type='constant'; C1.Vdc=650; C1.Iload=650/3.986;
C1.tdur=6.94; C1.speed=2.54; C1.sMax=0.30; C1.sStep=0.10;

C2 = P; C2.type='fixed';    C2.Vdc=650; C2.Iload=650/3.986;
C2.tdur=3;    C2.xFixed=6.35;

C3 = P; C3.type='accel';    C3.Vdc=650; C3.Iload=650/7.679;
C3.tdur=0.16;

%% ------------------------------------------------------------------------
%  Figure 1: three fault types with noisy load current
% -------------------------------------------------------------------------
R1 = simulateArc(C1);
R2 = simulateArc(C2);
R3 = simulateArc(C3);

figure('Name','Noisy arc current - three fault types','Position',[100 100 900 750]);
plotCurrent(subplot(3,1,1), R1, 'Constant-speed gap (2.54 mm/s)');
plotCurrent(subplot(3,1,2), R2, 'Fixed gap (6.35 mm)');
plotCurrent(subplot(3,1,3), R3, 'Accelerated gap (9800 mm/s^2)');
xlabel('Time (s)');

%% ------------------------------------------------------------------------
%  Figure 2: what the noise looks like (constant-speed case)
% -------------------------------------------------------------------------
Cq = C1;  Cq.noise.enable = false;          % same seed -> same arc, no noise
rng(1);   Rq = simulateArc(Cq);

figure('Name','Noise decomposition','Position',[150 80 950 850]);

subplot(4,1,1);                              % load-variation profile
plot(R1.t, R1.iload_pu, 'k'); grid on;
ylabel('i_{load} (p.u.)');
title('Load-current multiplier: drift + steps + ripple (full record)');

subplot(4,1,2);                              % zoom: ripple in healthy state
zw = R1.t > 0.50 & R1.t < 0.504;
plot(R1.t(zw)*1e3, R1.igap(zw),'Color',[0 0.45 0.15]); hold on;
plot(Rq.t(zw)*1e3, Rq.igap(zw),'r--'); grid on;
legend('with noise','no noise','Location','best');
xlabel('Time (ms)'); ylabel('i_{gap} (A)');
title('Zoom, healthy state (4 ms): switching ripple');

subplot(4,1,3);                              % zoom: arc burning
t0 = C1.tpre + 3.0;
zw = R1.t > t0 & R1.t < t0 + 0.004;
plot(R1.t(zw)*1e3, R1.igap(zw),'Color',[0 0.45 0.15]); hold on;
plot(Rq.t(zw)*1e3, Rq.igap(zw),'r--'); grid on;
xlabel('Time (ms)'); ylabel('i_{gap} (A)');
title('Zoom, arc burning (4 ms)');

subplot(4,1,4);                              % spectra
fs = 1/C1.dt;
wH = R1.t >= 0.2 & R1.t < 0.7;                       % healthy window (0.5 s)
wA = R1.t >= C1.tpre+2 & R1.t < C1.tpre+2.5;         % arc window    (0.5 s)
[fH, AH] = ampSpectrum(R1.igap(wH), fs);
[fA, AA] = ampSpectrum(R1.igap(wA), fs);
[fQ, AQ] = ampSpectrum(Rq.igap(wA), fs);
semilogx(fH(2:end), 20*log10(AH(2:end)+eps), 'b'); hold on;
semilogx(fA(2:end), 20*log10(AA(2:end)+eps), 'Color',[0 0.45 0.15]);
semilogx(fQ(2:end), 20*log10(AQ(2:end)+eps), 'r');
grid on; xlabel('Frequency (Hz)'); ylabel('Amplitude (dB re 1 A)');
legend('healthy, noisy','arc, noisy','arc, no noise','Location','southwest');
title('Amplitude spectra (0.5 s windows)');

%% ------------------------------------------------------------------------
%  Section 3: small batch with RANDOMIZED noise settings per run
%  (domain randomization: stops a classifier keying on one noise "style")
% -------------------------------------------------------------------------
types = {'constant','fixed','accel'};
bases = {C1, C2, C3};
bases{1}.tdur = 2;  bases{2}.tdur = 1.5;              % shorter for the demo
figure('Name','Randomized-noise batch','Position',[200 100 1000 700]);
for n = 1:6
    k  = mod(n-1,3) + 1;
    Cn = bases{k};
    Cn.noise = randomizeNoise(defaultNoise(), Cn.dt);
    Rn = simulateArc(Cn);
    ax = subplot(3,2,n);
    plot(ax, Rn.t, Rn.igap, 'Color',[0 0.45 0.15]); grid on;
    ylim([0 1.4*Cn.Iload]);
    title(ax, sprintf('%s | fsw = %.1f kHz, line = %g Hz', types{k}, ...
          Cn.noise.inv.fsw/1e3, Cn.noise.inv.fLine));
    % Rn.label: 0 = healthy, 1 = arc burning, 2 = arc extinguished
end

%% ========================================================================
%  Local functions
% =========================================================================
function N = defaultNoise()
    N.enable = true;
    % ---- inverter / converter -------------------------------------------
    N.inv.fsw      = 20e3;            % switching frequency [Hz]
    N.inv.harmAmp  = [0.010 0.004];   % fsw harmonics 1,2,.. (peak, frac. of Iload)
    N.inv.fswWander= 0.002;           % slow fractional wander of fsw (std)
    N.inv.fLine    = 100;             % DC-link ripple [Hz]: 2*50 single-phase,
                                      %   300 for 3-phase rectifier at 50 Hz
    N.inv.lineAmp  = [0.020 0.006];   % line-ripple harmonics 1,2 (peak, frac.)
    N.inv.bbStd    = 0.004;           % broadband noise std (frac. of Iload)
    N.inv.bbCorner = 20e3;            % broadband noise corner [Hz]
    % ---- load variations ------------------------------------------------
    N.load.driftStd  = 0.02;          % slow drift std (frac.)
    N.load.driftTau  = 2.0;           % drift correlation time [s]
    N.load.stepRate  = 0.5;           % load-step events per second
    N.load.stepStd   = 0.10;          % step size std (frac. of Iload)
    N.load.stepTau   = 5e-3;          % response time of a load step [s]
end

function N = randomizeNoise(N, dt)
    fs = 1/dt;
    lg = @(s) exp(s*randn);                         % log-normal scale factor
    N.inv.fsw       = 5e3 + (0.30*fs - 5e3)*rand;   % 5 kHz .. 0.3*fs
    N.inv.harmAmp   = N.inv.harmAmp * lg(0.5);
    N.inv.fswWander = N.inv.fswWander * lg(0.5);
    lineOpts        = [100 120 300 360];            % 50/60 Hz, 1-ph / 3-ph
    N.inv.fLine     = lineOpts(randi(numel(lineOpts)));
    N.inv.lineAmp   = N.inv.lineAmp * lg(0.5);
    N.inv.bbStd     = N.inv.bbStd * lg(0.5);
    N.load.driftStd = N.load.driftStd * lg(0.5);
    N.load.stepRate = 0.1 + 1.9*rand;
    N.load.stepStd  = N.load.stepStd * lg(0.5);
    N.load.stepTau  = N.load.stepTau * lg(0.7);
end

function [m, comp] = loadCurrentMultiplier(t, N)
% Returns i_load(t) in p.u. of nominal Iload, plus its components.
    n  = numel(t);
    dt = t(2) - t(1);
    fs = 1/dt;

    % ---- load variations -------------------------------------------------
    drift = colouredNoise(n, dt, N.load.driftTau, N.load.driftStd);
    steps = loadSteps(n, dt, N.load.stepRate, N.load.stepStd, N.load.stepTau);
    level = max(1 + drift + steps, 0.05);           % never reverse current

    % ---- inverter / converter -------------------------------------------
    % switching ripple with slowly wandering frequency (phase = integral of f)
    fInst = N.inv.fsw * (1 + colouredNoise(n, dt, 0.1, N.inv.fswWander));
    ph    = 2*pi*cumsum(fInst)*dt;
    sw    = zeros(n,1);
    for h = 1:numel(N.inv.harmAmp)
        if h*N.inv.fsw*1.05 >= fs/2
            warning(['Switching harmonic %d (%.1f kHz) is above Nyquist and ' ...
                     'was dropped; reduce dt to include it.'], h, h*N.inv.fsw/1e3);
            continue;
        end
        sw = sw + N.inv.harmAmp(h) * sin(h*ph + 2*pi*rand);
    end
    % DC-link ripple (fixed grid-locked frequency, random phase)
    ln = zeros(n,1);
    for h = 1:numel(N.inv.lineAmp)
        ln = ln + N.inv.lineAmp(h) * sin(2*pi*h*N.inv.fLine*t + 2*pi*rand);
    end
    % band-limited broadband noise
    bb = colouredNoise(n, dt, 1/(2*pi*N.inv.bbCorner), N.inv.bbStd);

    ripple = sw + ln + bb;
    m = level .* (1 + ripple);                       % ripple scales with load
    m = max(m, 0);

    comp.drift = drift;  comp.steps = steps;  comp.level = level;
    comp.sw = sw;  comp.line = ln;  comp.bb = bb;
end

function y = colouredNoise(n, dt, tau, sd)
% Stationary first-order (Ornstein-Uhlenbeck-type) noise, std = sd.
    phi = exp(-dt/tau);
    y   = filter(sqrt(1-phi^2), [1 -phi], randn(n,1), phi*randn) * sd;
end

function s = loadSteps(n, dt, rate, sd, tau)
% Random load steps (Poisson arrivals) smoothed by a first-order response.
    T   = n*dt;
    ev  = cumsum(-log(rand(ceil(3*rate*T)+10,1))/rate);
    ev  = ev(ev < T);
    target = zeros(n,1);
    level = 0;  iPrev = 1;
    for k = 1:numel(ev)
        i = round(ev(k)/dt) + 1;
        target(iPrev:i-1) = level;
        level = max(min(0.6*level + sd*randn, 3*sd), -3*sd);   % bounded
        iPrev = i;
    end
    target(iPrev:end) = level;
    a = exp(-dt/tau);
    s = filter(1-a, [1 -a], target);
end

function R = simulateArc(P)
    dt = P.dt;  tpre = P.tpre;
    switch P.type
        case 'constant', tend = tpre + 1.1*P.tdur;
        case 'fixed',    tend = tpre + P.tdur;
        case 'accel',    tend = tpre + 1.3*P.tdur;
        otherwise, error('Unknown fault type');
    end
    t   = (0:dt:tend).';
    n   = numel(t);
    tau = max(t - tpre, 0);

    alpha = -0.5*log(P.Rclosed*P.Iload/P.Vdc);               % Eq. (7)

    % ---- distance ratio q(t) and gap distance x_gap [mm] ----------------
    q = zeros(n,1);
    switch P.type
        case 'constant'
            xgap = P.speed*tau;
            qTrend = tau / P.tdur;
            s = 0; quenched = false;
            for k = 2:n
                if t(k) < tpre, continue; end
                if quenched, q(k) = q(k-1) + 0.002; continue; end
                s = s + rand()^10 * P.sStep;                 % INTERPRETATION
                if s > P.sMax, s = rand()*P.sMax; end
                q(k) = qTrend(k) + s;
                if q(k) >= 1, quenched = true; end
            end
        case 'fixed'
            xgap = P.xFixed * (tau > 0);
            for k = 2:n
                if t(k) < tpre, continue; end
                q(k) = q(k-1) + rand()^10;                   % Eq. (11)
                if q(k) > 0.9, q(k) = rand(); end
            end
        case 'accel'
            xgap = 0.5*9800*tau.^2;
            q = (tau / P.tdur).^2;                           % Eq. (12)
    end

    % ---- arc voltage / current, per unit ---------------------------------
    inArc = (q > 0) & (q < 1);
    vq   = 0.5 + 0.5*tanh(alpha*(q-1));
    iq   = 0.5 - 0.5*tanh(alpha*(q-1));
    egap = 0.5*(P.a + P.b*xgap) .* (tanh(P.lam*q) - tanh(P.lam*(q-1))) .* inArc;
    jgap = egap;
    vgap = vq + egap;
    igap_clean = iq - jgap;                                  % paper's i_gap

    % ---- noisy load current ----------------------------------------------
    if P.noise.enable
        [ilm, comp] = loadCurrentMultiplier(t, P.noise);
        R.noise = comp;
    else
        ilm = ones(n,1);
    end
    igap = ilm .* igap_clean;                                % series element

    label = zeros(n,1);                                      % 0 healthy
    label(t >= tpre & q < 1)  = 1;                           % 1 arc burning
    label(t >= tpre & q >= 1) = 2;                           % 2 extinguished

    R.t = t;  R.q = q;  R.alpha = alpha;  R.label = label;
    R.iload_pu = ilm;
    R.vgap_pu = vgap;  R.igap_pu = igap;  R.pgap_pu = vgap.*igap;
    R.vgap = vgap*P.Vdc;  R.igap = igap*P.Iload;
    R.igap_clean = igap_clean*P.Iload;
    R.P = P;
end

function plotCurrent(ax, R, ttl)
    plot(ax, R.t, R.igap, 'Color',[0 0.45 0.15]); grid(ax,'on');
    hold(ax,'on');
    plot(ax, [R.P.tpre R.P.tpre], [0 1.5*R.P.Iload], 'k--');
    ylabel(ax, 'i_{gap} (A)');  title(ax, ttl);
    ylim(ax, [0 1.4*R.P.Iload]);
end

function [f, A] = ampSpectrum(x, fs)
    x = x(:) - mean(x);
    n = numel(x);
    w = 0.5 - 0.5*cos(2*pi*(0:n-1)'/(n-1));                  % Hann
    X = fft(x .* w);
    m = floor(n/2) + 1;
    A = abs(X(1:m)) * 2 / sum(w);
    f = (0:m-1)' * fs / n;
end