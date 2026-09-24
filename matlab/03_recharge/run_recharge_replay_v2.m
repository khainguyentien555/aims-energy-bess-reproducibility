%% run_recharge_replay_v2.m
% Phase 5 canonical MATLAB replay:
% synchronous common-recovery recharge on FROZEN B4-P allocations.
%
% IMPORTANT:
% - Never re-optimizes B4-P or B4-PQ.
% - EVCS stress demand is absent during recharge.
% - Background feeder load is scaled by alpha_off.
% - BESS charging is active-only at unity PF.
% - Phase-3 Q_add is NOT carried into recharge.
% - P_ch is NOT silently clipped. The symmetric rating is an explicit
%   feasibility constraint, so the energy identity remains exact.
%
% Requires in Current Folder / MATLAB path:
%   B4P_canonical_freeze.mat
%   ieee33_data.m
%   bfs_power_flow.m
%   compute_metrics.m
%   empty_metric.m
%   build_loads_recharge_v2.m

clear; clc;

assert(exist('B4P_canonical_freeze.mat','file') == 2, ...
    'B4P_canonical_freeze.mat not found.');
assert(exist('ieee33_data','file') == 2, 'ieee33_data.m not found.');
assert(exist('bfs_power_flow','file') == 2, 'bfs_power_flow.m not found.');
assert(exist('compute_metrics','file') == 2, 'compute_metrics.m not found.');
assert(exist('build_loads_recharge_v2','file') == 2, ...
    'build_loads_recharge_v2.m not found.');

S = load('B4P_canonical_freeze.mat');
assert(isfield(S,'cfg') && isfield(S,'results'), ...
    'Freeze MAT must contain cfg and results.');
cfg = S.cfg;
results = S.results;

[busData0, branchData] = ieee33_data();

% Phase-4A production values. The canonical B4-P freeze may not contain
% etaDis/etaCh because those parameters were not needed in thermal sizing.
eta_dis = 0.95;
eta_ch  = 0.95;
if isfield(cfg,'etaDis')
    assert(abs(cfg.etaDis-eta_dis) < 1e-12, ...
        'cfg.etaDis differs from frozen Phase-4A production value 0.95.');
    eta_dis = cfg.etaDis;
end
if isfield(cfg,'etaCh')
    assert(abs(cfg.etaCh-eta_ch) < 1e-12, ...
        'cfg.etaCh differs from frozen Phase-4A production value 0.95.');
    eta_ch = cfg.etaCh;
end

Vthr = 0.95;
Lthr = 100.0;
if isfield(cfg,'Vthr'), assert(abs(cfg.Vthr-Vthr)<1e-12); end
if isfield(cfg,'Lthr'), assert(abs(cfg.Lthr-Lthr)<1e-12); end

Tpeaks = [2 4 6];
alphas = [0.50 0.70 0.85 1.00];

% Numerical gates
tauCap       = 1e-10;   % p.u. ratio
tauMonoV     = 1e-9;    % pu
tauMonoL     = 1e-7;    % percentage points
tauMonoR     = 1e-10;   % ratio
tauEnergyMWh = 1e-9;
tauVBind     = 1e-6;    % pu
tauLBind     = 1e-4;    % percentage points
tauRatioBind = 1e-6;
tauScale     = 2e-6;    % normalized Trec/Tpeak invariance
nSweep       = 121;
maxBracket_h = 1000;

diary('recharge_replay_log.txt');
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=== PHASE 5 MATLAB CANONICAL REPLAY v2 ===\n');
fprintf('Frozen B4-P allocations are immutable.\n');
fprintf('eta_dis=%.6f | eta_ch=%.6f | Vthr=%.6f | Lthr=%.3f%%\n', ...
    eta_dis,eta_ch,Vthr,Lthr);
fprintf('BFS tol from canonical cfg = %.3e pu\n\n',cfg.tol);

%% D. Analytical PCS power/efficiency floor
fprintf('D. PCS power/efficiency recovery floor:\n');
fprintf('   T_floor = T_peak/(eta_dis*eta_ch)\n');
for Tp = Tpeaks
    fprintf('   T_peak=%d h -> T_floor=%.9f h\n', ...
        Tp,Tp/(eta_dis*eta_ch));
end

%% H. Background-only feasibility: hard gate
fprintf('\nH. Background-only feasibility:\n');
BgRows = cell(numel(alphas),7);
for ia = 1:numel(alphas)
    a = alphas(ia);
    bd = busData0;
    bd(:,2) = a*busData0(:,2);
    bd(:,3) = a*busData0(:,3);

    [V,Ib,Sb,info] = bfs_power_flow(bd,branchData,cfg);
    m = compute_metrics(V,Ib,Sb,branchData,cfg,info);

    feasible = m.converged && m.Vmin >= Vthr && m.LmaxPct <= Lthr;
    fprintf(['   alpha=%.2f | Vmin=%.9f | Lmax=%.6f%% | ' ...
             'BFSres=%.3e | feasible=%d\n'], ...
        a,m.Vmin,m.LmaxPct,m.BFSresidual,feasible);

    BgRows(ia,:) = {a,m.Vmin,m.LmaxPct,m.VminBus, ...
        sprintf('%d-%d',m.critFrom,m.critTo),m.BFSresidual,feasible};

    if ~feasible
        error(['Background-only state is infeasible at alpha_off=%.2f. ' ...
               'Recharge duration cannot repair an infeasible zero-charge base state.'],a);
    end
end

Tbackground = cell2table(BgRows,'VariableNames', ...
    {'alpha_off','Vmin_pu','Lmax_pct','Vmin_bus','critical_branch', ...
     'BFS_residual_pu','feasible'});
writetable(Tbackground,'recharge_background_check.csv');

%% Main 60-point matrix
fprintf('\nRecharge matrix:\n');
fprintf(['Case   Tp alpha  Ebw_MWh  Tfloor_h  Trec_h    Pch_kW ' ...
         'maxR    Vmin      Lmax%%    vbus branch  binding\n']);

Rows = {};
BusRows = {};

for k = 1:numel(results)
    r = results(k);

    % Zero-BESS cases require no recovery and are omitted from the 60-point table.
    if r.P_BESS_total_kW <= 1e-9
        continue;
    end

    ev = r.evcsBuses(:).';
    allocBus_kW = zeros(33,1);
    allocBus_kW(ev) = r.alloc_kW(:);

    % Frozen-lineage check.
    assert(abs(sum(allocBus_kW)-r.P_BESS_total_kW) <= 1e-6, ...
        'Frozen allocation total mismatch for %s.',r.name);

    for Tp = Tpeaks
        % Frozen Phase-4 convention: battery-side energy withdrawn.
        Ebw_MWh = (allocBus_kW/1000) * Tp / eta_dis;
        Tfloor = Tp/(eta_dis*eta_ch);

        for ia = 1:numel(alphas)
            a = alphas(ia);

            state = @(T) recharge_state(busData0,branchData,cfg, ...
                allocBus_kW,Ebw_MWh,a,T,eta_ch,Vthr,Lthr,tauCap);

            % First obtain a network-feasible upper bracket.
            s0 = state(Tfloor);
            if s0.ok
                hi = Tfloor;
                needBisection = false;
            else
                needBisection = true;
                hi = Tfloor;
                while true
                    hi = hi*1.5;
                    if hi > maxBracket_h
                        error('Could not bracket feasible recharge state: %s Tp=%g alpha=%.2f.', ...
                            r.name,Tp,a);
                    end
                    sh = state(hi);
                    if sh.ok
                        break;
                    end
                end
            end

            % Mandatory monotonicity gate over the ENTIRE bisection interval.
            % For floor-feasible points, extend to 3*Tfloor to audit direction.
            sweepHi = max(hi,3*Tfloor);
            Tg = linspace(Tfloor,sweepHi,nSweep);
            Vg = zeros(size(Tg));
            Lg = zeros(size(Tg));
            Rg = zeros(size(Tg));

            for ii = 1:numel(Tg)
                sg = state(Tg(ii));
                if ~sg.BFS_converged
                    error('BFS failed in monotonicity sweep: %s Tp=%g alpha=%.2f T=%.9f.', ...
                        r.name,Tp,a,Tg(ii));
                end
                Vg(ii) = sg.Vmin;
                Lg(ii) = sg.Lmax;
                Rg(ii) = sg.maxRatio;
            end

            monoV = all(diff(Vg) >= -tauMonoV);
            monoL = all(diff(Lg) <=  tauMonoL);
            monoR = all(diff(Rg) <=  tauMonoR);

            if ~(monoV && monoL && monoR)
                error(['Monotonicity gate FAILED: %s Tp=%g alpha=%.2f ' ...
                       '(monoV=%d monoL=%d monoR=%d).'], ...
                    r.name,Tp,a,monoV,monoL,monoR);
            end

            % Bisection only after the monotonicity gate.
            if ~needBisection
                Trec = Tfloor;
            else
                lo = Tfloor;
                for it = 1:100
                    mid = 0.5*(lo+hi);
                    sm = state(mid);
                    if sm.ok
                        hi = mid;
                    else
                        lo = mid;
                    end
                    if (hi-lo) <= 1e-10
                        break;
                    end
                end
                Trec = hi;
            end

            sf = state(Trec);
            if ~sf.ok
                error('Final recharge replay is infeasible: %s Tp=%g alpha=%.2f.', ...
                    r.name,Tp,a);
            end

            % Energy identity: no hidden clipping is permitted.
            energyRestored_bus = eta_ch*(sf.Pch_kW/1000)*Trec;
            energyErr_bus = energyRestored_bus - Ebw_MWh;
            idxB = allocBus_kW > 0;
            maxEnergyErr = max(abs(energyErr_bus(idxB)));

            if maxEnergyErr > tauEnergyMWh
                error(['Recharge energy identity FAILED: %s Tp=%g alpha=%.2f ' ...
                       'max error %.3e MWh.'],r.name,Tp,a,maxEnergyErr);
            end
            if any(abs(sf.Pch_kW(~idxB)) > 1e-12)
                error('A zero-BESS bus received charging power in %s.',r.name);
            end

            % Explicit active-constraint classification.
            activePCS = abs(sf.maxRatio-1) <= tauRatioBind;
            activeV   = abs(sf.Vmin-Vthr) <= tauVBind;
            activeL   = abs(sf.Lmax-Lthr) <= tauLBind;

            activeNames = strings(0,1);
            if activePCS, activeNames(end+1) = "PCS"; end %#ok<SAGROW>
            if activeV,   activeNames(end+1) = "V";   end %#ok<SAGROW>
            if activeL,   activeNames(end+1) = "L";   end %#ok<SAGROW>

            if numel(activeNames) == 0
                bind = "none";
            elseif numel(activeNames) == 1
                if activePCS
                    bind = "PCS-power";
                elseif activeV
                    bind = "voltage";
                else
                    bind = "thermal";
                end
            else
                bind = "joint(" + strjoin(activeNames,"+") + ")";
            end

            fprintf(['%-6s %2g %.2f %8.4f %9.4f %9.4f %8.2f ' ...
                     '%.5f %.7f %9.4f %4d %-6s %s\n'], ...
                r.name,Tp,a,sum(Ebw_MWh),Tfloor,Trec,sum(sf.Pch_kW), ...
                sf.maxRatio,sf.Vmin,sf.Lmax,sf.vbus, ...
                sprintf('%d-%d',sf.critFrom,sf.critTo),bind);

            Rows(end+1,:) = {string(r.name),Tp,a,sum(Ebw_MWh),Tfloor,Trec, ...
                sum(sf.Pch_kW),sf.maxRatio,sf.Vmin,sf.Lmax,sf.vbus, ...
                sprintf('%d-%d',sf.critFrom,sf.critTo),sf.BFS_residual, ...
                bind,monoV,monoL,monoR,maxEnergyErr}; %#ok<SAGROW>

            bessBuses = find(idxB);
            for jj = 1:numel(bessBuses)
                b = bessBuses(jj);
                BusRows(end+1,:) = {string(r.name),Tp,a,b,allocBus_kW(b), ...
                    Ebw_MWh(b),sf.Pch_kW(b),sf.Pch_kW(b)/allocBus_kW(b), ...
                    energyRestored_bus(b),energyErr_bus(b)}; %#ok<SAGROW>
            end
        end
    end
end

Trecharge = cell2table(Rows,'VariableNames', ...
    {'Case','T_peak_h','alpha_off','E_batt_wd_total_MWh','T_floor_h', ...
     'T_rec_star_h','P_ch_total_kW','max_Pch_over_rating','Vmin_pu', ...
     'Lmax_pct','critical_voltage_bus','critical_branch','BFS_residual_pu', ...
     'binding_constraint','monotone_V','monotone_L','monotone_ratio', ...
     'max_energy_identity_error_MWh'});

Tperbus = cell2table(BusRows,'VariableNames', ...
    {'Case','T_peak_h','alpha_off','Bus','P_BESS_kW','E_batt_wd_MWh', ...
     'P_ch_kW','P_ch_over_rating','E_restored_MWh','energy_error_MWh'});

writetable(Trecharge,'recharge_matrix_MATLAB.csv');
writetable(Tperbus,'recharge_perbus_Pch_MATLAB.csv');

%% Cross-point hard consistency checks
fprintf('\nCross-point consistency checks:\n');

% 1) Trec >= floor
if any(Trecharge.T_rec_star_h < Trecharge.T_floor_h - 1e-9)
    error('Found T_rec below analytical PCS floor.');
end
fprintf('  T_rec >= T_floor: PASS\n');

caseNames = unique(Trecharge.Case,'stable');

% 2) Higher alpha_off must not improve/worsen in the wrong direction:
% Trec should be non-decreasing as alpha_off increases.
for ic = 1:numel(caseNames)
    c = caseNames(ic);
    for Tp = Tpeaks
        mask = Trecharge.Case==c & Trecharge.T_peak_h==Tp;
        sub = sortrows(Trecharge(mask,:), 'alpha_off');
        if any(diff(sub.T_rec_star_h) < -1e-8)
            error('alpha_off ordering failed for %s Tp=%g.',c,Tp);
        end
    end
end
fprintf('  alpha_off ordering: PASS\n');

% 3) T_peak ordering + exact normalized scaling implied by this model:
% P_ch = P_BESS*T_peak/(eta_dis*eta_ch*T), so constraints depend on T/T_peak.
maxScaleSpread = 0;
for ic = 1:numel(caseNames)
    c = caseNames(ic);
    for ia = 1:numel(alphas)
        a = alphas(ia);
        mask = Trecharge.Case==c & abs(Trecharge.alpha_off-a)<1e-12;
        sub = sortrows(Trecharge(mask,:), 'T_peak_h');

        if any(diff(sub.T_rec_star_h) < -1e-8)
            error('T_peak ordering failed for %s alpha=%.2f.',c,a);
        end

        normalized = sub.T_rec_star_h ./ sub.T_peak_h;
        spread = max(normalized)-min(normalized);
        maxScaleSpread = max(maxScaleSpread,spread);
        if spread > tauScale
            error('Normalized T_rec/T_peak scaling check failed for %s alpha=%.2f.',c,a);
        end
    end
end
fprintf('  T_peak ordering: PASS\n');
fprintf('  normalized T_rec/T_peak invariance: PASS (max spread %.3e)\n',maxScaleSpread);

% 4) Thermal constraint should be satisfied at every final state.
if any(Trecharge.Lmax_pct > Lthr + 1e-6)
    error('Thermal feasibility failed in final recharge table.');
end

% 5) Voltage constraint should be satisfied at every final state.
if any(Trecharge.Vmin_pu < Vthr - 1e-9)
    error('Voltage feasibility failed in final recharge table.');
end

fprintf('  final V/L feasibility: PASS\n');

save('recharge_canonical.mat','Trecharge','Tperbus','Tbackground', ...
    'cfg','eta_dis','eta_ch','Tpeaks','alphas','-v7.3');

fprintf('\nSaved canonical Phase-5 artifacts:\n');
fprintf('  recharge_canonical.mat\n');
fprintf('  recharge_replay_log.txt\n');
fprintf('  recharge_background_check.csv\n');
fprintf('  recharge_matrix_MATLAB.csv\n');
fprintf('  recharge_perbus_Pch_MATLAB.csv\n');
fprintf('\nPHASE 5 MATLAB REPLAY: PASS IF SCRIPT REACHES THIS LINE WITHOUT ERROR.\n');

%% ======================== local helper ================================
function s = recharge_state(busData0,branchData,cfg,allocBus_kW,Ebw_MWh, ...
    alpha_off,T,eta_ch,Vthr,Lthr,tauCap)

    [bd,Pch_kW] = build_loads_recharge_v2( ...
        busData0,allocBus_kW,Ebw_MWh,alpha_off,T,eta_ch);

    [V,Ib,Sb,info] = bfs_power_flow(bd,branchData,cfg);
    m = compute_metrics(V,Ib,Sb,branchData,cfg,info);

    idx = allocBus_kW > 0;
    ratios = Pch_kW(idx)./allocBus_kW(idx);

    s.Pch_kW = Pch_kW;
    s.maxRatio = max(ratios);
    s.Vmin = m.Vmin;
    s.Lmax = m.LmaxPct;
    s.vbus = m.VminBus;
    s.critFrom = m.critFrom;
    s.critTo = m.critTo;
    s.BFS_converged = m.converged;
    s.BFS_residual = m.BFSresidual;

    capOK = s.maxRatio <= 1 + tauCap;
    s.ok = m.converged && capOK && ...
           s.Vmin >= Vthr && s.Lmax <= Lthr;
end
