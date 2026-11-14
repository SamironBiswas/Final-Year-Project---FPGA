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
    % ---- NEW: load drop transient events ----------------------------------
    Z.nuis.dropRate  = 0.5;           % load drop events per second
    Z.nuis.dropDepth = [0.20 0.50];   % fraction of nominal current drop (20% to 50%)
    Z.nuis.dropDur   = [0.05 0.3];    % duration of the drop in seconds
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
    
    % NEW: Randomize load drop occurrences
    Z.nuis.dropRate = (rand < 0.6) * 1.0 * rand; % Occurs in ~60% of runs, up to 1 per sec
    
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

function [nI, id] = nuisanceEvents(t, N)
% Healthy-state disturbances that resemble arcing (label stays 0).
%   id 1: crosstalk-like pink (1/f) noise burst (arc on a parallel string)
%   id 2: inverter broadband burst
%   id 3: anti-islanding style spike train
%   id 4: large transient load drop
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
    
    % ---- NEW: Transient Load Drops (id = 4) -----------------------------
    if isfield(N, 'dropRate') && N.dropRate > 0
        tk = -log(rand())/N.dropRate;                        
        while tk < T
            dur = N.dropDur(1) + diff(N.dropDur)*rand;
            i0 = round(tk/dt) + 1;  i1 = min(n, i0 + round(dur/dt));
            if i1 > i0
                depth = N.dropDepth(1) + diff(N.dropDepth)*rand;
                % Subtract the depth to create a negative step (load drop)
                nI(i0:i1) = nI(i0:i1) - depth; 
                id(i0:i1) = 4;
            end
            tk = tk + dur - log(rand())/N.dropRate;
        end
    end
end