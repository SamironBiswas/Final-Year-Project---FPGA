%% arc_model_sim_pv_noise.m
% DC series-arc model (Uriarte et al., IEEE Trans. Smart Grid, 2012) with a
% PV-style noise environment on CURRENT, VOLTAGE and POWER, for generating
% training data. Constant-speed and fixed-gap faults only.
% [Script stripped for headless dataset generation]

clear; clc;

%% ------------------------------------------------------------------------
%  Base Parameters
% -------------------------------------------------------------------------
P.a = 0.01;  P.b = 0.005;  P.lam = 100;  P.Rclosed = 0.001;   
P.tpre  = 1.0;                 
P.dt    = 10e-6;               
P.noise = defaultNoise();
P.arc   = struct('style','sawtooth', 'hold',1, 'cap',0.85, 'jMax',0.20, 'rampDur', 0.05);

%% ------------------------------------------------------------------------
%  Dataset Generation Execution
% -------------------------------------------------------------------------


% Target quotas (30,000 total frames at 1:4 ratio)
target_arc = 5000;
target_normal = 5000;
X_arc = []; Y_arc = [];
X_normal = []; Y_normal = [];

% Base Configuration for Fixed-Gap Generation
C_base = P;
C_base.type = 'fixed';
C_base.xFixed = 6.35; % 6.35 mm gap

disp('Starting dataset generation. This may take several minutes...');

while (size(X_arc, 1) < target_arc) || (size(X_normal, 1) < target_normal)

    % 1. Set the fault timing
    if size(X_arc, 1) < target_arc
        t_fault = 0.2 + 0.5 * rand();  % Arc ignites between 0.2s and 0.7s
    else
        t_fault = 10.0;                % Normal mode: Push fault outside simulation time
    end

    C_base.tpre = t_fault;
    C_base.tdur = max(1.0 - t_fault, 0.5); % Ensure the simulation always hits at least 1.0s

    % 2. Randomize parameters and run high-frequency simulation (100 kHz)
    Cn = randomizeRun(C_base);
    Rn = simulateArc(Cn);

    % Extract exactly the first 1.0 second of data
    valid_idx = Rn.t <= 1.0;
    current_100k = Rn.i(valid_idx);
    t_100k = Rn.t(valid_idx);

    % 3. Downsample to 16 kHz (so 160 samples = exactly 10 ms)
    % resample(data, target_freq, original_freq)
    current_16k = resample(current_100k, 16000, 100000);

    % Rebuild a perfectly matched time vector for the 16 kHz data
    t_16k = (0:length(current_16k)-1)' / 16000;

    % 4. Strict Labeling: 1 for every sample on or after t_fault, 0 before.
    % This guarantees the label flips instantly, even during the gradual 50ms physical ramp.
    labels_16k = double(t_16k >= t_fault);

    % 5. Frame Extraction (160 samples per frame)
    total_frames = floor(length(current_16k) / 160);

    for f = 1:total_frames
        idx = (f-1)*160 + 1 : f*160;
        frame_c = current_16k(idx);
        frame_l = labels_16k(idx);

        % Save to Arc quota (Ensures ALL samples in frame are > t_fault)
        if all(frame_l == 1) && size(X_arc, 1) < target_arc
            X_arc = [X_arc; frame_c'];
            Y_arc = [Y_arc; 1];

            % Save to Normal quota (Ensures ALL samples in frame are < t_fault)
        elseif all(frame_l == 0) && size(X_normal, 1) < target_normal
            X_normal = [X_normal; frame_c'];
            Y_normal = [Y_normal; 0];
        end
        % Note: Boundary frames containing both 0s and 1s are naturally ignored.
    end

    % Print progress update
    fprintf('Progress: %d/%d Arc | %d/%d Normal\n', ...
        size(X_arc,1), target_arc, size(X_normal,1), target_normal);
end

% Combine the datasets
X_data = [X_normal; X_arc];
Y_data = [Y_normal; Y_arc];

% Shuffle the final dataset to prevent sequential bias during CNN training
fprintf('Shuffling dataset...\n');
shuffle_idx = randperm(size(X_data, 1));
X_data = X_data(shuffle_idx, :);
Y_data = Y_data(shuffle_idx, :);

% Save to file
save('arc_dataset_check.mat', 'X_data', 'Y_data');
fprintf('Exact %d-frame synthetic dataset successfully generated and saved!', (target_arc+target_normal));
%% ========================================================================
%  Local functions
% =========================================================================
function Z = defaultNoise()
    Z.enable = true;
    Z.inv.type     = 'single';        
    Z.inv.f0       = 50;              
    Z.inv.fsw      = 20e3;            
    Z.inv.swAmp    = [0.005 0.0025];  
    Z.inv.swWander = 0.002;           
    Z.inv.lineAmp2 = 0.010;           
    Z.inv.h50      = [0.0015 0.0015 0.001];  
    Z.inv.bbStd    = 0.0035;          
    Z.inv.bbCorner = 20e3;            
    Z.v.kLow    = 0.5;                
    Z.v.kIrr    = 0.05;               
    Z.v.swScale = 1.0;                
    Z.v.bbStd   = 0.0025;             
    Z.sens.iStd = 0.0015;  Z.sens.vStd = 0.001;   
    Z.sens.bits = 12;      Z.sens.fsFactor = 1.5; 
    Z.irr.driftStd   = 0.015;  Z.irr.driftTau = 3;   
    Z.irr.cloudRate  = 0.15;                          
    Z.irr.cloudDepth = [0.05 0.40];                   
    Z.irr.cloudRamp  = [1 5];                         
    Z.irr.cloudHold  = [0.5 4];                       
    Z.mppt.period = 1.0;  Z.mppt.periodJitter = 0.2;  
    Z.mppt.stepStd = 0.008;  Z.mppt.tau = 5e-3;       
    Z.mppt.transAmp = 0.025; Z.mppt.transTau = 0.02;  Z.mppt.transFreq = 120;
    Z.nuis.crossRate = 0.4;  Z.nuis.crossStd = [0.01 0.04]; Z.nuis.crossDur = [0.05 0.5];
    Z.nuis.burstRate = 0.4;  Z.nuis.burstAmp = [0.02 0.06]; Z.nuis.burstDur = [1e-3 2e-2];
    Z.nuis.islPeriod = Inf;  Z.nuis.islAmp = [0.02 0.08];   Z.nuis.islTau = 0.5e-3;
    Z.nuis.vCoupling = -0.3;          
    Z.nuis.dropRate  = 0.5;           
    Z.nuis.dropDepth = [0.20 0.50];   
    Z.nuis.dropDur   = [0.05 0.3];    
end

function P = randomizeRun(P)
    fs = 1/P.dt;
    lg = @(s) exp(s*randn);
    ops = [650 163.07; 270 4; 400 8; 600 10];       
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
    Z.nuis.dropRate = (rand < 0.6) * 1.0 * rand; 

    bitsList = [10 12 14 16];
    Z.sens.bits = bitsList(randi(4));
    P.noise = Z;
    styles = {'sawtooth','pink','bursty','linesync'};
    holds  = [1 2 5 10 20];
    P.arc.style = styles{randi(4)};
    P.arc.hold  = holds(randi(5));
    P.arc.cap   = 0.72 + 0.20*rand;     
    P.arc.jMax  = 0.10 + 0.20*rand;
    P.arc.rampDur = 0.01 + 0.09 * rand();
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
    alpha = -0.5*log(P.Rclosed*P.Iload/P.Vdc);               

    iF  = find(t >= tpre, 1);
    nf  = n - iF + 1;
    jit = arcJitter(P.arc.style, nf, dt, P.arc.hold, Z.inv.f0);   
    q   = zeros(n,1);
    switch P.type
        case 'constant'
            xgap = P.speed * max(t - tpre, 0);
            q(iF:n) = (t(iF:n) - tpre)/P.tdur + P.arc.jMax*jit;
            kq = find(q >= 1, 1);
            if ~isempty(kq)                                  
                q(kq:n) = q(kq) + 200*(t(kq:n) - t(kq));
            end
        case 'fixed'
            % rampDur = P.arc.rampDur; 
            % ramp = min(max((t - tpre) / rampDur, 0), 1);
            % xgap = P.xFixed * ramp;
            % q(iF:n) = P.arc.cap * jit .* ramp(iF:n);
            xgap = P.xFixed * (t >= tpre);
            q(iF:n) = P.arc.cap * jit;
    end

    inArc = (q > 0) & (q < 1);
    vq   = 0.5 + 0.5*tanh(alpha*(q-1));                      
    iq   = 0.5 - 0.5*tanh(alpha*(q-1));                      
    egap = 0.5*(P.a + P.b*xgap) .* ...
           (tanh(P.lam*q) - tanh(P.lam*(q-1))) .* inArc;     
    vgap = vq + egap;
    igapClean = iq - egap;                                   

    if Z.enable
        [mi, mv, nuis, comp] = loadNoise(t, Z);
    else
        mi = ones(n,1);  mv = ones(n,1);  nuis = zeros(n,1);
        comp.slow = ones(n,1);
    end
    i_pu = mi .* igapClean;                                  
    v_pu = mv - vgap;                                        
    i = i_pu * P.Iload;
    v = v_pu * P.Vdc;

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
    p = v .* i;                                              

    label = zeros(n,1);                                      
    label(t >= tpre & q <  1) = 1;                           
    label(t >= tpre & q >= 1) = 2;                           

    R.t = t;  R.q = q;  R.label = label;  R.nuis = nuis;
    R.i = i;  R.v = v;  R.p = p;                             
    R.iClean = igapClean*P.Iload;  R.vClean = (1 - vgap)*P.Vdc;
    R.comp = comp;  R.alpha = alpha;  R.P = P;
end

function [mi, mv, nuis, comp] = loadNoise(t, Z)
    n = numel(t);  dt = t(2) - t(1);  fs = 1/dt;
    irr = colouredNoise(n, dt, Z.irr.driftTau, Z.irr.driftStd) ...
          + cloudEvents(t, Z.irr);
    [mStep, mTrans] = mpptNoise(t, Z.mppt);
    fInst = Z.inv.fsw * (1 + colouredNoise(n, dt, 0.1, Z.inv.swWander));
    ph  = 2*pi*cumsum(fInst)*dt;
    swI = zeros(n,1);  swV = zeros(n,1);
    for h = 1:numel(Z.inv.swAmp)
        if h*Z.inv.fsw*1.05 >= fs/2
            warning('arcsim:alias', 'Switching harmonic %d is above Nyquist and was dropped.', h);
            continue;
        end
        swI = swI + Z.inv.swAmp(h)*sin(h*ph + 2*pi*rand);
        swV = swV + Z.v.swScale*Z.inv.swAmp(h)*sin(h*ph + 2*pi*rand);
    end
    tauBB = 1/(2*pi*Z.inv.bbCorner);
    bbI = colouredNoise(n, dt, tauBB, Z.inv.bbStd);
    bbV = colouredNoise(n, dt, tauBB, Z.v.bbStd);

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

    [nuisI, nuis] = nuisanceEvents(t, Z.nuis);
    mi = (1 + irr + mStep + mTrans) .* (1 + swI + lineI + bbI) + nuisI;
    mi = max(mi, 0);
    mv = 1 - Z.v.kLow*(mStep + mTrans + lineI) + Z.v.kIrr*irr ...
         + swV + bbV + Z.nuis.vCoupling*nuisI;

    comp.slow = 1 + irr + mStep;
    comp.irr = irr;  comp.mStep = mStep;  comp.lineI = lineI;
end

function c = cloudEvents(t, C)
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
    n = numel(t);  dt = t(2) - t(1);  T = t(end);
    ev = [];  tk = M.period*rand();
    while tk < T
        ev(end+1) = tk;                                      
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
    n = numel(t);  dt = t(2) - t(1);  T = t(end);
    nI = zeros(n,1);  id = zeros(n,1);
    
    tk = -log(rand())/N.crossRate;                           
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
    
    tk = -log(rand())/N.burstRate;                           
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
    
    if isfinite(N.islPeriod)                                 
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
    
    if isfield(N, 'dropRate') && N.dropRate > 0
        tk = -log(rand())/N.dropRate;                        
        while tk < T
            dur = N.dropDur(1) + diff(N.dropDur)*rand;
            i0 = round(tk/dt) + 1;  i1 = min(n, i0 + round(dur/dt));
            if i1 > i0
                depth = N.dropDepth(1) + diff(N.dropDepth)*rand;
                nI(i0:i1) = nI(i0:i1) - depth; 
                id(i0:i1) = 4;
            end
            tk = tk + dur - log(rand())/N.dropRate;
        end
    end
end

function j = arcJitter(style, nf, dt, holdN, f0)
    m = ceil(nf/holdN);
    switch style
        case 'sawtooth'                       
            j = sawNorm(m);
        case 'pink'                           
            j = min(max(0.35 + 0.20*pinkNoise(m), 0), 1);
        case 'bursty'                         
            j = 0.1*ones(m,1);  pos = 1;  on = rand < 0.5;
            while pos <= m
                md  = 0.08*on + 0.05*(~on);
                len = max(1, round(-log(rand())*md/(holdN*dt)));
                e   = min(m, pos + len - 1);
                if on, j(pos:e) = sawNorm(e - pos + 1); end
                pos = e + 1;  on = ~on;
            end
        case 'linesync'                       
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
    s = zeros(m,1);  v = 0;
    for k = 1:m
        v = v + rand()^10/0.9;
        if v > 1, v = rand(); end
        s(k) = v;
    end
end

function x = pinkNoise(L)
    W    = fft(randn(L,1));
    half = floor(L/2) + 1;
    k    = (0:half-1).';
    sc   = 1./sqrt(max(k,1));  sc(1) = 0;                    
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
    phi = exp(-dt/tau);
    y   = filter(sqrt(1-phi^2), [1 -phi], randn(n,1), phi*randn) * sd;
end

