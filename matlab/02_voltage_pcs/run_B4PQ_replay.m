%% run_B4PQ_replay.m
% Phase 3 (Option B) canonical MATLAB replay on FROZEN B4-P allocations.
% Reads B4P_canonical_freeze.mat and NEVER re-optimizes B4-P.
%
% Part 1: EVCS PF correction, gamma in [0,1], gamma=1 -> unity PF.
% Part 2: with EVCS fixed at unity PF, additional proportional capacitive
%         support Q_add,j = delta * Q_EVCS0,j, delta >= 0.
% Part 3: PCS/external attribution per bus.
%
% Requires on path:
%   ieee33_data.m
%   bfs_power_flow.m
%   compute_metrics.m
%   empty_metric.m
%   build_loads_B4PQ.m
% and in the Current Folder:
%   B4P_canonical_freeze.mat

clear; clc;

assert(exist('B4P_canonical_freeze.mat','file') == 2, ...
    'B4P_canonical_freeze.mat not found in Current Folder.');

S = load('B4P_canonical_freeze.mat');
assert(isfield(S,'results') && isfield(S,'cfg'), ...
    'Freeze MAT must contain results and cfg.');

cfg = S.cfg;
results = S.results;

[busData0, branchData] = ieee33_data();

Vthr     = 0.95;
tauV_pu  = 1e-9;          % numerical reporting/verification tolerance only
qf       = cfg.qFactorEVCS;
Pinst    = cfg.Pinst_MW;
nGrid    = 301;
deltaMax = 6.0;
deltaTol = 1e-7;
PzeroTol_kW = 1e-6;

if ~isfield(cfg,'tauL_pct')
    cfg.tauL_pct = 1e-6;
end

diary('B4PQ_replay_log.txt');
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=== PHASE 3 (Option B) MATLAB REPLAY ===\n');
fprintf('Frozen B4-P allocations are immutable inputs.\n');
fprintf('BFS tol = %.3e pu | Vthr = %.6f pu | tauV = %.1e pu | tauL = %.1e %%\n\n', ...
    cfg.tol, Vthr, tauV_pu, cfg.tauL_pct);

out = struct([]);

for k = 1:numel(results)
    r   = results(k);
    ev  = r.evcsBuses(:).';
    lam = r.lambda;

    % Immutable frozen active allocation.
    bess = zeros(33,1);
    bess(ev) = r.alloc_kW(:)/1000;

    % Lineage check: the active total must exactly reproduce the frozen total
    % to floating-point/reporting precision.
    frozenTotal_kW = sum(bess)*1000;
    if abs(frozenTotal_kW - r.P_BESS_total_kW) > 1e-6
        error('Frozen allocation total mismatch in %s.', r.name);
    end

    Qevcs0_bus_kVAr = Pinst*lam*qf*1000;
    Q_PFC_kVAr = numel(ev)*Qevcs0_bus_kVAr;

    % No reactive support: must reproduce frozen B4-P Vmin/Lmax.
    mPre = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,0,0);
    if ~mPre.converged
        error('BFS failed at frozen B4-P replay for %s.', r.name);
    end
    if abs(mPre.Vmin-r.Vmin) > 1e-8 || abs(mPre.LmaxPct-r.Lmax_pct) > 1e-6
        error('Frozen B4-P physics replay mismatch for %s.', r.name);
    end

    % Part 1: full PF correction (unity PF).
    mUPF = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,1,0);
    if ~mUPF.converged
        error('BFS failed at unity-PF replay for %s.', r.name);
    end
    pfSufficient = mUPF.Vmin >= Vthr - tauV_pu;

    % Part 2: verify Vmin(delta) monotonicity numerically before bisection.
    dd = linspace(0,deltaMax,nGrid);
    vv = nan(size(dd));
    ll = nan(size(dd));

    for ii = 1:numel(dd)
        mm = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,1,dd(ii));
        if ~mm.converged
            error('BFS failed during delta sweep for %s at delta=%.6g.', r.name, dd(ii));
        end
        vv(ii) = mm.Vmin;
        ll(ii) = mm.LmaxPct;
    end

    monoV = all(diff(vv) >= -1e-10);
    if ~monoV
        error('Vmin(delta) monotonicity check FAILED for %s. Do not bisect.', r.name);
    end

    if pfSufficient
        dstar = 0;
        mPost = mUPF;
    elseif vv(end) < Vthr - tauV_pu
        error(['deltaMax=%.3f is insufficient for %s: Vmin(deltaMax)=%.9f. ' ...
               'Increase only after physical review.'], deltaMax, r.name, vv(end));
    else
        f = @(d) vmin_only(busData0,branchData,cfg,ev,lam,qf,bess,1,d) - Vthr;
        dstar = bisect_delta(f,0,deltaMax,deltaTol);
        mPost = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,1,dstar);
    end

    if ~mPost.converged
        error('Post-support BFS failed for %s.', r.name);
    end
    if mPost.Vmin < Vthr - tauV_pu
        error('Voltage target not restored for %s: Vmin=%.12f.', r.name, mPost.Vmin);
    end
    if mPost.LmaxPct > cfg.Lthr + cfg.tauL_pct
        error('Thermal constraint violated after Q support for %s: Lmax=%.12f%%.', ...
            r.name, mPost.LmaxPct);
    end

    Qadd_bus_kVAr = dstar * Qevcs0_bus_kVAr;
    Qadd_total_kVAr = numel(ev) * Qadd_bus_kVAr;

    o.name = r.name;
    o.class = r.class;
    o.evcsBuses = ev;
    o.lambda = lam;
    o.alloc_kW = r.alloc_kW;
    o.P_BESS_total_kW = r.P_BESS_total_kW;

    o.Vmin_pre = mPre.Vmin;
    o.Lmax_pre = mPre.LmaxPct;
    o.Vmin_unityPF = mUPF.Vmin;
    o.Lmax_unityPF = mUPF.LmaxPct;
    o.PF_sufficient = pfSufficient;

    o.Q_PFC_kVAr = Q_PFC_kVAr;
    o.monotone_Vmin_delta = monoV;
    o.delta_star = dstar;
    o.Q_add_bus_kVAr = Qadd_bus_kVAr;
    o.Q_add_total_kVAr = Qadd_total_kVAr;

    o.Vmin_post = mPost.Vmin;
    o.Lmax_post = mPost.LmaxPct;
    o.limitBus = mPost.VminBus;
    o.BFS_converged = mPost.converged;
    o.BFS_residual_pu = mPost.BFSresidual;

    if isempty(out)
        out = o;
    else
        out(end+1) = o; %#ok<AGROW>
    end

    fprintf(['%-7s | Vpre=%.6f Lupre=%.6f%% | Vupf=%.6f PFok=%d | ' ...
             'mono=%d delta*=%.6f | Q_PFC=%.3f Q_add=%.3f kVAr | ' ...
             'Vpost=%.9f Lpost=%.6f%% limBus=%d BFSres=%.3e\n'], ...
        r.name,mPre.Vmin,mPre.LmaxPct,mUPF.Vmin,pfSufficient,monoV,dstar, ...
        Q_PFC_kVAr,Qadd_total_kVAr,mPost.Vmin,mPost.LmaxPct,mPost.VminBus, ...
        mPost.BFSresidual);
end

%% Summary CSV
n = numel(out);
Case = strings(n,1);
P_BESS_total_kW = zeros(n,1);
Vmin_B4P_pu = zeros(n,1);
Lmax_B4P_pct = zeros(n,1);
Vmin_unityPF_pu = zeros(n,1);
Lmax_unityPF_pct = zeros(n,1);
PF_sufficient = false(n,1);
Q_PFC_kVAr = zeros(n,1);
delta_star = zeros(n,1);
Q_add_total_kVAr = zeros(n,1);
Vmin_post_pu = zeros(n,1);
Lmax_post_pct = zeros(n,1);
limiting_bus = zeros(n,1);
BFS_residual_pu = zeros(n,1);
monotone = false(n,1);

for k = 1:n
    o = out(k);
    Case(k) = string(o.name);
    P_BESS_total_kW(k) = o.P_BESS_total_kW;
    Vmin_B4P_pu(k) = o.Vmin_pre;
    Lmax_B4P_pct(k) = o.Lmax_pre;
    Vmin_unityPF_pu(k) = o.Vmin_unityPF;
    Lmax_unityPF_pct(k) = o.Lmax_unityPF;
    PF_sufficient(k) = o.PF_sufficient;
    Q_PFC_kVAr(k) = o.Q_PFC_kVAr;
    delta_star(k) = o.delta_star;
    Q_add_total_kVAr(k) = o.Q_add_total_kVAr;
    Vmin_post_pu(k) = o.Vmin_post;
    Lmax_post_pct(k) = o.Lmax_post;
    limiting_bus(k) = o.limitBus;
    BFS_residual_pu(k) = o.BFS_residual_pu;
    monotone(k) = o.monotone_Vmin_delta;
end

Tsummary = table(Case,P_BESS_total_kW,Vmin_B4P_pu,Lmax_B4P_pct, ...
    Vmin_unityPF_pu,Lmax_unityPF_pct,PF_sufficient,Q_PFC_kVAr, ...
    delta_star,Q_add_total_kVAr,Vmin_post_pu,Lmax_post_pct,limiting_bus, ...
    BFS_residual_pu,monotone);

writetable(Tsummary,'B4PQ_summary.csv');
disp(Tsummary);

%% Part 3: per-bus attribution and conditional PCS requirement
rows = {};
fprintf('\n--- Per-bus Q_add attribution + conditional PCS rating ---\n');
fprintf('%-7s %4s %10s %11s %10s %10s  %s\n', ...
    'Case','bus','P_BESS_kW','Q_add_kVAr','Sreq_kVA','headroom%','source');

for k = 1:numel(out)
    o = out(k);
    for j = 1:numel(o.evcsBuses)
        b  = o.evcsBuses(j);
        Pb = o.alloc_kW(j);
        Qa = o.Q_add_bus_kVAr;

        if Pb > PzeroTol_kW
            Sreq = hypot(Pb,Qa);
            hr = (Sreq/Pb - 1)*100;
            src = "BESS PCS candidate (if selected)";
            fprintf('%-7s %4d %10.3f %11.3f %10.3f %10.3f  %s\n', ...
                o.name,b,Pb,Qa,Sreq,hr,src);
        else
            Sreq = NaN;
            hr = NaN;
            src = "External/local reactive resource";
            fprintf('%-7s %4d %10.3f %11.3f %10s %10s  %s\n', ...
                o.name,b,0,Qa,'--','--',src);
        end

        rows(end+1,:) = {string(o.name),b,Pb,Qa,Sreq,hr,src}; %#ok<SAGROW>
    end
end

Tbus = cell2table(rows,'VariableNames', ...
    {'Case','Bus','P_BESS_kW','Q_add_kVAr','S_PCS_required_kVA', ...
     'PCS_headroom_pct','Source_classification'});
writetable(Tbus,'B4PQ_per_bus_PCS.csv');

save('B4PQ_canonical.mat','out','cfg','Tsummary','Tbus','-v7.3');

fprintf('\nSaved:\n');
fprintf('  B4PQ_canonical.mat\n');
fprintf('  B4PQ_replay_log.txt\n');
fprintf('  B4PQ_summary.csv\n');
fprintf('  B4PQ_per_bus_PCS.csv\n');
fprintf('\nPython cross-checks are comparison targets only; MATLAB is not forced to match.\n');

%% ================= local helpers =================
function m = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,gamma,delta)
bd = build_loads_B4PQ(busData0,ev,cfg.Pinst_MW,lam,qf,bess,gamma,delta);
[V,Ibr,Sbr,info] = bfs_power_flow(bd,branchData,cfg);
m = compute_metrics(V,Ibr,Sbr,branchData,cfg,info);
end

function v = vmin_only(busData0,branchData,cfg,ev,lam,qf,bess,gamma,delta)
m = metric_at(busData0,branchData,cfg,ev,lam,qf,bess,gamma,delta);
if ~m.converged
    v = -Inf;
else
    v = m.Vmin;
end
end

function d = bisect_delta(f,lo,hi,tol)
% Requires monotonicity to have been numerically verified upstream.
if f(lo) >= 0
    d = lo;
    return;
end
if f(hi) < 0
    error('Bisection bracket invalid: upper bound is still infeasible.');
end
for it = 1:200
    mid = 0.5*(lo+hi);
    if f(mid) >= 0
        hi = mid;
    else
        lo = mid;
    end
    if (hi-lo) < tol
        break;
    end
end
d = hi;
end
