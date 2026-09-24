% IEEE33_BFS_EVCS_BESS_Framework.m
% -------------------------------------------------------------------------
% Complete MATLAB Backward/Forward Sweep (BFS) framework for the IEEE
% 33-bus radial distribution system.
%
% Main features:
%   1) Standard Baran-Wu IEEE 33-bus radial feeder data.
%   2) BFS load-flow solver for radial distribution networks.
%   3) Base-case validation without EVCS/BESS.
%   4) No-BESS EVCS baseline cases:
%        P1/P2 placements x D1-D4 demand scenarios.
%   5) Exported CSV tables for manuscript Table V.
%   6) Exported figures for voltage profile, branch loading, and HCM.
%   7) Modular helper functions for later BESS and allowable-injection work.
%
% Author: Khai Nguyen
% -------------------------------------------------------------------------

clear; clc; close all;

%% ========================================================================
% SETTINGS
% ========================================================================

% Base quantities
cfg.baseMVA = 100;       % MVA
cfg.baseKV  = 12.66;     % kV line-to-line

% Slack-bus voltage.
% Use 1.00 for pure Baran-Wu validation.
% Use 1.05 if representing substation voltage regulation/OLTC.
cfg.Vslack  = 1.05;      % p.u.

% BFS settings
cfg.tol     = 1e-5;      % p.u. voltage convergence threshold
cfg.maxIter = 50;

% Voltage and thermal thresholds used in the manuscript
cfg.Vthr = 0.95;         % p.u.
cfg.Lthr = 100;          % %

% Branch-specific thermal ratings (MVA)
% Feeder-hierarchy assumption: source-side trunk > main trunk > sub-feeder > lateral.
% The original Baran-Wu IEEE 33-bus dataset does not specify thermal ratings.
% The source-side branch 1-2 is assigned the highest rating because it carries
% the aggregate downstream feeder load.

Smax_branch = [
% Branch  From-To   Group           Rating
  6.0;  %  1   1-2   Main trunk / source-side feeder
  5.0;  %  2   2-3   Main trunk
  4.0;  %  3   3-4   Sub-feeder
  4.0;  %  4   4-5   Sub-feeder
  3.5;  %  5   5-6   Sub-feeder
  3.5;  %  6   6-7   Sub-feeder
  3.0;  %  7   7-8   Lateral
  3.0;  %  8   8-9   Lateral
  3.0;  %  9   9-10  Lateral
  3.0;  % 10  10-11  Lateral
  2.5;  % 11  11-12  Lateral
  2.5;  % 12  12-13  Lateral
  2.5;  % 13  13-14  Lateral
  2.5;  % 14  14-15  Lateral
  2.0;  % 15  15-16  Downstream
  2.0;  % 16  16-17  Downstream  ← P2 EVCS corridor
  2.0;  % 17  17-18  Downstream  ← P2 EVCS corridor
  4.0;  % 18   2-19  Sub-feeder
  3.5;  % 19  19-20  Lateral
  3.0;  % 20  20-21  Lateral
  3.0;  % 21  21-22  Lateral
  3.5;  % 22   3-23  Sub-feeder
  3.0;  % 23  23-24  Lateral
  2.5;  % 24  24-25  Lateral
  3.5;  % 25   6-26  Sub-feeder
  3.0;  % 26  26-27  Lateral
  2.5;  % 27  27-28  Lateral
  2.5;  % 28  28-29  Lateral
  2.5;  % 29  29-30  Lateral
  2.0;  % 30  30-31  Downstream  ← P2 EVCS corridor
  2.0;  % 31  31-32  Downstream  ← P2 EVCS corridor
  2.0;  % 32  32-33  Downstream  ← P2 EVCS corridor
];

cfg.Smax_branch = Smax_branch;

% EVCS settings
cfg.Pinst_MW = 0.15;     % MW per active EVCS bus at lambda = 1.0
cfg.pfEVCS   = 0.95;     % lagging
cfg.qFactorEVCS = tan(acos(cfg.pfEVCS));

% EVCS placement scenarios
placements(1).name  = 'P1';
placements(1).label = 'Distributed';
placements(1).buses = [6 10 14 18 22 26];

placements(2).name  = 'P2';
placements(2).label = 'Downstream-concentrated';
placements(2).buses = [14 16 17 18 30 33];

% EV fast-charging demand scenarios
demands(1).name = 'D1'; demands(1).lambda = 0.6; demands(1).label = 'Low';
demands(2).name = 'D2'; demands(2).lambda = 1.0; demands(2).label = 'Base';
demands(3).name = 'D3'; demands(3).lambda = 1.3; demands(3).label = 'Peak';
demands(4).name = 'D4'; demands(4).lambda = 1.6; demands(4).label = 'Stress';

% Output folder
cfg.outDir = 'BFS_outputs';
if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end

%% ========================================================================
%  IEEE 33-BUS DATA
% ========================================================================

[busData0, branchData] = ieee33_data();

Pbase_MW   = sum(busData0(:,2))/1000;
Qbase_MVAr = sum(busData0(:,3))/1000;

fprintf('\n============================================================\n');
fprintf('IEEE 33-BUS BFS FRAMEWORK\n');
fprintf('============================================================\n');
fprintf('Base load: %.3f MW + j%.3f MVAr\n', Pbase_MW, Qbase_MVAr);
fprintf('Vslack   : %.3f p.u.\n', cfg.Vslack);
fprintf('Smax     : branch-specific ratings, %.1f–%.1f MVA\n', ...
    min(cfg.Smax_branch), max(cfg.Smax_branch));
fprintf('EVCS     : %.3f MW per EVCS bus at lambda = 1.0, pf = %.2f\n', ...
    cfg.Pinst_MW, cfg.pfEVCS);

%% ========================================================================
% BASE-CASE VALIDATION WITHOUT EVCS/BESS
% ========================================================================

[Vbase, IbrBase, SbrBase, baseInfo] = bfs_power_flow(busData0, branchData, cfg);
baseMetric = compute_metrics(Vbase, IbrBase, SbrBase, branchData, cfg);

fprintf('\nBASE CASE WITHOUT EVCS/BESS\n');
fprintf('------------------------------------------------------------\n');
print_metric('Base', baseMetric, cfg);

% Export base voltage and branch loading
baseVoltageTable = table((1:33)', abs(Vbase), ...
    'VariableNames', {'Bus','Voltage_pu'});
writetable(baseVoltageTable, fullfile(cfg.outDir, 'Base_voltage_profile.csv'));

baseBranchLabels = make_branch_labels(branchData);
baseLoadingTable = table((1:32)', baseBranchLabels, cfg.Smax_branch(:), ...
    baseMetric.loadingPct, abs(SbrBase), ...
    'VariableNames', {'BranchNo','Branch','Smax_MVA','Loading_pct','S_MVA'});
writetable(baseLoadingTable, fullfile(cfg.outDir, 'Base_branch_loading.csv'));

%% ========================================================================
% BASELINE CASES WITHOUT BESS
% ========================================================================

nPlacements = numel(placements);
nDemands    = numel(demands);
nCases      = nPlacements * nDemands;

caseNames     = cell(nCases,1);
placementCol  = cell(nCases,1);
demandCol     = cell(nCases,1);
lambdaCol     = zeros(nCases,1);
rhoCol_pct    = zeros(nCases,1);
metrics       = repmat(empty_metric(), nCases, 1);

allV          = zeros(33,nCases);
allLoading    = zeros(32,nCases);
allSbr_MVA    = zeros(32,nCases);

idx = 0;
fprintf('\nSECTION III: BASELINE EVCS CASES WITHOUT BESS\n');
fprintf('------------------------------------------------------------\n');

for p = 1:nPlacements
    for d = 1:nDemands
        idx = idx + 1;

        placement = placements(p);
        demand    = demands(d);

        % Add EVCS load. No BESS is applied in Section III.
        bessMW = zeros(33,1);
        busData = build_case_loads(busData0, placement.buses, ...
            cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, bessMW);

        [V, Ibr, Sbr, info] = bfs_power_flow(busData, branchData, cfg);
        metric = compute_metrics(V, Ibr, Sbr, branchData, cfg);

        caseName = sprintf('%s/%s', placement.name, demand.name);
        caseNames{idx}    = caseName;
        placementCol{idx} = placement.name;
        demandCol{idx}    = demand.name;
        lambdaCol(idx)    = demand.lambda;
        rhoCol_pct(idx)   = numel(placement.buses) * cfg.Pinst_MW * demand.lambda / Pbase_MW * 100;

        metrics(idx)      = metric;
        allV(:,idx)       = abs(V);
        allLoading(:,idx) = metric.loadingPct;
        allSbr_MVA(:,idx) = abs(Sbr);

        print_metric(caseName, metric, cfg);
    end
end

%% ========================================================================
% EXPORT
% ========================================================================

Vmin_pu      = arrayfun(@(m)m.Vmin, metrics).';
Vmin_bus     = arrayfun(@(m)m.VminBus, metrics).';
Lmax_pct     = arrayfun(@(m)m.LmaxPct, metrics).';
HCM_pct      = arrayfun(@(m)m.HCMpct, metrics).';
Ploss_kW     = arrayfun(@(m)m.Ploss_kW, metrics).';
Iterations   = arrayfun(@(m)m.iterations, metrics).';
Converged    = arrayfun(@(m)m.converged, metrics).';

criticalBranch = strings(nCases,1);
status          = strings(nCases,1);

for k = 1:nCases
    criticalBranch(k) = sprintf('B%d-B%d', metrics(k).critFrom, metrics(k).critTo);

    vViolation = Vmin_pu(k) < cfg.Vthr;
    lViolation = Lmax_pct(k) > cfg.Lthr;

    if vViolation && lViolation
        status(k) = "Thermal + voltage violation";
    elseif lViolation
        status(k) = "Thermal violation";
    elseif vViolation
        status(k) = "Voltage violation";
    else
        status(k) = "Feasible";
    end
end

% Force all table variables to be column vectors with the same row count
caseNames    = caseNames(:);
placementCol = placementCol(:);
demandCol    = demandCol(:);

% If lambdaCol was accidentally stored as only D1-D4, expand it to 8 rows
if numel(lambdaCol) == numel(demands)
    lambdaCol = repmat([demands.lambda].', numel(placements), 1);
else
    lambdaCol = lambdaCol(:);
end

rhoCol_pct      = rhoCol_pct(:);
Vmin_pu         = Vmin_pu(:);
Vmin_bus        = Vmin_bus(:);
Lmax_pct        = Lmax_pct(:);
criticalBranch  = criticalBranch(:);
HCM_pct         = HCM_pct(:);
Ploss_kW        = Ploss_kW(:);
Iterations      = Iterations(:);
Converged       = Converged(:);
status          = status(:);

TableV = table(caseNames, placementCol, demandCol, lambdaCol, rhoCol_pct, ...
    Vmin_pu, Vmin_bus, Lmax_pct, criticalBranch, HCM_pct, Ploss_kW, ...
    Iterations, Converged, status, ...
    'VariableNames', {'Case','Placement','Demand','lambda','rho_pct', ...
    'Vmin_pu','Vmin_bus','Lmax_pct','Critical_branch','HCM_pct', ...
    'Ploss_kW','Iterations','Converged','Status'});

fprintf('\nTABLE V: BASELINE GRID-IMPACT SUMMARY WITHOUT BESS\n');
fprintf('------------------------------------------------------------\n');
disp(TableV);

writetable(TableV, fullfile(cfg.outDir, 'TableV_baseline_no_BESS_results.csv'));

%% ========================================================================
% EXPORT PROFILE MATRICES
% ========================================================================

voltageProfiles = array2table([(1:33)', allV], ...
    'VariableNames', [{'Bus'}, matlab.lang.makeValidName(caseNames')]);
writetable(voltageProfiles, fullfile(cfg.outDir, 'Voltage_profiles_no_BESS.csv'));

branchLabels = make_branch_labels(branchData);
branchLoadingProfiles = array2table([(1:32)', allLoading], ...
    'VariableNames', [{'BranchNo'}, matlab.lang.makeValidName(caseNames')]);
branchLoadingProfiles.Branch = branchLabels;
branchLoadingProfiles = movevars(branchLoadingProfiles, 'Branch', 'After', 'BranchNo');
writetable(branchLoadingProfiles, fullfile(cfg.outDir, 'Branch_loading_no_BESS.csv'));

branchSProfiles = array2table([(1:32)', allSbr_MVA], ...
    'VariableNames', [{'BranchNo'}, matlab.lang.makeValidName(caseNames')]);
branchSProfiles.Branch = branchLabels;
branchSProfiles = movevars(branchSProfiles, 'Branch', 'After', 'BranchNo');
writetable(branchSProfiles, fullfile(cfg.outDir, 'Branch_apparent_power_no_BESS_MVA.csv'));

%% ========================================================================
% GENERATE FIGURES FOR SECTION III
% ========================================================================

% Fig. 3: voltage profiles
fig = figure('Name','Fig3 Voltage profiles without BESS','Color','w');
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

nexttile;
plot(1:33, allV(:,1:4), 'LineWidth', 1.2);
hold on; yline(cfg.Vthr, '--', sprintf('V_{thr}=%.2f', cfg.Vthr));
grid on; box on;
xlabel('Bus number');
ylabel('Voltage magnitude (p.u.)');
title('P1: Distributed placement');
legend({demands.name}, 'Location','southwest');

nexttile;
plot(1:33, allV(:,5:8), 'LineWidth', 1.2);
hold on; yline(cfg.Vthr, '--', sprintf('V_{thr}=%.2f', cfg.Vthr));
grid on; box on;
xlabel('Bus number');
ylabel('Voltage magnitude (p.u.)');
title('P2: Downstream-concentrated placement');
legend({demands.name}, 'Location','southwest');

exportgraphics(fig, fullfile(cfg.outDir, 'Fig3_voltage_profiles_no_BESS.png'), 'Resolution', 300);

% Fig. 4: branch loading for P1/D4 and P2/D4
fig = figure('Name','Fig4 Branch loading without BESS','Color','w');
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

idxP1D4 = find(strcmp(caseNames,'P1/D4'));
idxP2D4 = find(strcmp(caseNames,'P2/D4'));

nexttile;
bar(allLoading(:,idxP1D4));
hold on; yline(cfg.Lthr, '--', sprintf('L_{thr}=%.0f%%', cfg.Lthr));
grid on; box on;
xlabel('Branch number');
ylabel('Loading (%)');
title('P1/D4');

nexttile;
bar(allLoading(:,idxP2D4));
hold on; yline(cfg.Lthr, '--', sprintf('L_{thr}=%.0f%%', cfg.Lthr));
grid on; box on;
xlabel('Branch number');
ylabel('Loading (%)');
title('P2/D4');

exportgraphics(fig, fullfile(cfg.outDir, 'Fig4_branch_loading_no_BESS.png'), 'Resolution', 300);

% Fig. 5: HCM comparison
fig = figure('Name','Fig5 HCM comparison without BESS','Color','w');
bar(HCM_pct);
hold on; yline(0, '--', '0% margin');
grid on; box on;
xticks(1:nCases);
xticklabels(caseNames);
xtickangle(45);
ylabel('HCM (%)');
title('Thermal hosting-capacity margin without BESS');
exportgraphics(fig, fullfile(cfg.outDir, 'Fig5_HCM_no_BESS.png'), 'Resolution', 300);

fprintf('\nExported outputs are saved in folder: %s\n', cfg.outDir);
fprintf('Key file for Section III: %s\n', fullfile(cfg.outDir, 'TableV_baseline_no_BESS_results.csv'));

%% ========================================================================
%  OPTIONAL: BRANCH-RATING SENSITIVITY FOR BASE CASE
% ========================================================================

fprintf('\nBASE-CASE BRANCH-RATING SENSITIVITY\n');
fprintf('------------------------------------------------------------\n');

ratingScaleCases = [0.9 1.0 1.1];

for rr = 1:numel(ratingScaleCases)
    tmpCfg = cfg;
    tmpCfg.Smax_branch = cfg.Smax_branch * ratingScaleCases(rr);

    tmpMetric = compute_metrics(Vbase, IbrBase, SbrBase, branchData, tmpCfg);

    fprintf('Rating scale = %.1f: Lmax = %.2f%%, HCM = %.2f%%\n', ...
        ratingScaleCases(rr), tmpMetric.LmaxPct, tmpMetric.HCMpct);
end

%% ========================================================================
% BISECTION — ALLOWABLE INJECTION AND B4 BESS SIZING
% ========================================================================

fprintf('\nSTEP 4: BISECTION — FEEDER-CONSTRAINED BESS SIZING (B4)\n');
fprintf('------------------------------------------------------------\n');

bisect_tol   = 1e-3;   % lambda convergence tolerance
bisect_maxIt = 30;

% Results storage
B4 = struct();
B4.PBESS_MW   = zeros(33, nCases);   % BESS at each bus, each case
B4.Pallow_MW  = zeros(33, nCases);
B4.metrics    = repmat(empty_metric(), nCases, 1);

for idx = 1:nCases
    p = ceil(idx/nDemands);
    d = mod(idx-1, nDemands) + 1;

    placement = placements(p);
    demand    = demands(d);
    evcsBuses = placement.buses;
    nEvcs     = numel(evcsBuses);

    Pevcs_MW  = cfg.Pinst_MW * demand.lambda;   % per bus
    bessMW    = zeros(33,1);                     % start: no BESS

    % Outer loop: repeat until no violations remain
    for outerIt = 1:5
        % Check current feasibility
        busData = build_case_loads(busData0, evcsBuses, ...
            cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, bessMW);
        [V, Ibr, Sbr, ~] = bfs_power_flow(busData, branchData, cfg);
        m = compute_metrics(V, Ibr, Sbr, branchData, cfg);

        if m.Vmin >= cfg.Vthr && m.LmaxPct <= cfg.Lthr
            break   % already feasible
        end

        % Sort EVCS buses by demand (descending) — process highest first
        [~, sortOrd] = sort(Pevcs_MW * ones(1,nEvcs), 'descend');
        sortedBuses  = evcsBuses(sortOrd);

        for jj = 1:nEvcs
            busJ = sortedBuses(jj);

            lambdaL = 0;
            lambdaU = 1;

            for bit = 1:bisect_maxIt
                lambdaM = (lambdaL + lambdaU) / 2;

                % Test: set bus J to lambda_M, keep others at current
                testBESS = bessMW;
                testBESS(busJ) = max(0, Pevcs_MW - lambdaM * Pevcs_MW);

                busData_test = build_case_loads(busData0, evcsBuses, ...
                    cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, testBESS);
                [Vt, It, St, ~] = bfs_power_flow(busData_test, branchData, cfg);
                mt = compute_metrics(Vt, It, St, branchData, cfg);

                if mt.Vmin >= cfg.Vthr && mt.LmaxPct <= cfg.Lthr
                    lambdaL = lambdaM;   % feasible → try more injection
                else
                    lambdaU = lambdaM;   % infeasible → reduce
                end

                if (lambdaU - lambdaL) <= bisect_tol
                    break
                end
            end

            % Fix allowable injection at this bus
            Pallow_j = lambdaL * Pevcs_MW;
            bessMW(busJ) = max(0, Pevcs_MW - Pallow_j);
        end
    end

    % Final post-BESS validation
    busData = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, bessMW);
    [Vf, If, Sf, ~] = bfs_power_flow(busData, branchData, cfg);
    mf = compute_metrics(Vf, If, Sf, branchData, cfg);

    B4.PBESS_MW(:,idx)  = bessMW;
    B4.metrics(idx)     = mf;

    caseName = sprintf('%s/%s', placements(p).name, demands(d).name);
    fprintf('B4 %-8s: Vmin=%.4f | Lmax=%.2f%% | HCM=%.2f%% | Ploss=%.1fkW | PBESS=%.1fkW\n', ...
        caseName, mf.Vmin, mf.LmaxPct, mf.HCMpct, mf.Ploss_kW, ...
        sum(bessMW)*1000);
end


%% ========================================================================
% BASELINES B1, B2, B3
% ========================================================================

fprintf('\nSTEP 5: BASELINES B1 / B2 / B3\n');
fprintf('------------------------------------------------------------\n');

B1.metrics = repmat(empty_metric(), nCases, 1);
B2.metrics = repmat(empty_metric(), nCases, 1);
B3.metrics = repmat(empty_metric(), nCases, 1);

for idx = 1:nCases
    p = ceil(idx/nDemands);
    d = mod(idx-1, nDemands) + 1;

    placement = placements(p);
    demand    = demands(d);
    evcsBuses = placement.buses;

    totalBESS_MW = sum(B4.PBESS_MW(:,idx));   % same total as B4

    % --- B1: aggregated at Bus 1 ---
    bessMW_B1 = zeros(33,1);
    bessMW_B1(1) = totalBESS_MW;
    bd = build_case_loads(busData0, evcsBuses, cfg.Pinst_MW, ...
        demand.lambda, cfg.qFactorEVCS, bessMW_B1);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfg);
    B1.metrics(idx) = compute_metrics(V,I,S,branchData,cfg);

    % --- B2: aggregated at Bus 2 ---
    bessMW_B2 = zeros(33,1);
    bessMW_B2(2) = totalBESS_MW;
    bd = build_case_loads(busData0, evcsBuses, cfg.Pinst_MW, ...
        demand.lambda, cfg.qFactorEVCS, bessMW_B2);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfg);
    B2.metrics(idx) = compute_metrics(V,I,S,branchData,cfg);

    % --- B3: fixed 20% at each EVCS bus ---
    Pevcs_MW  = cfg.Pinst_MW * demand.lambda;
    bessMW_B3 = zeros(33,1);
    for b = evcsBuses
        bessMW_B3(b) = 0.20 * Pevcs_MW;
    end
    bd = build_case_loads(busData0, evcsBuses, cfg.Pinst_MW, ...
        demand.lambda, cfg.qFactorEVCS, bessMW_B3);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfg);
    B3.metrics(idx) = compute_metrics(V,I,S,branchData,cfg);

    caseName = sprintf('%s/%s', placement.name, demand.name);
    fprintf('%-8s | B1 Lmax=%.1f%% | B2 Lmax=%.1f%% | B3 Lmax=%.1f%%\n', ...
        caseName, B1.metrics(idx).LmaxPct, ...
        B2.metrics(idx).LmaxPct, B3.metrics(idx).LmaxPct);
end

%% ========================================================================
% EXPORT COMPARISON
% ========================================================================

fid = fopen(fullfile(cfg.outDir, 'Table_B0_B4_comparison.csv'), 'w');
fprintf(fid, 'Case,Baseline,Vmin_pu,Lmax_pct,HCM_pct,Ploss_kW,PBESS_kW\n');

baselineNames = {'B0','B1','B2','B3','B4'};
allMetrics    = {metrics, B1.metrics, B2.metrics, B3.metrics, B4.metrics};

for idx = 1:nCases
    p = ceil(idx/nDemands);
    d = mod(idx-1, nDemands) + 1;
    caseName = sprintf('%s/%s', placements(p).name, demands(d).name);

    for bl = 1:5
        m = allMetrics{bl}(idx);

        if bl == 4   % B3
            Pevcs_MW = cfg.Pinst_MW * demands(d).lambda;
            pbess_kW = 0.20 * Pevcs_MW * numel(placements(p).buses) * 1000;
        elseif bl == 5   % B4
            pbess_kW = sum(B4.PBESS_MW(:,idx)) * 1000;
        elseif bl == 1   % B0
            pbess_kW = 0;
        else   % B1, B2
            pbess_kW = sum(B4.PBESS_MW(:,idx)) * 1000;
        end

        fprintf(fid, '%s,%s,%.4f,%.2f,%.2f,%.1f,%.1f\n', ...
            caseName, baselineNames{bl}, ...
            m.Vmin, m.LmaxPct, m.HCMpct, m.Ploss_kW, pbess_kW);
    end
end

fclose(fid);
fprintf('\nExported: Table_B0_B4_comparison.csv\n');
fprintf('Done.\n');

%% ========================================================================
% BRANCH-RATING SENSITIVITY — P2/D4 ONLY
% ========================================================================

fprintf('\nSTEP 7: BRANCH-RATING SENSITIVITY — P2/D4\n');
fprintf('------------------------------------------------------------\n');

ratingScales  = [0.9, 1.0, 1.1];
sens_placement = placements(2);          % P2
sens_demand    = demands(4);             % D4
sens_evcsBuses = sens_placement.buses;
sens_Pevcs_MW  = cfg.Pinst_MW * sens_demand.lambda;

% Storage
nScales = numel(ratingScales);
sens_results = struct();

for rs = 1:nScales
    scale = ratingScales(rs);

    % Apply scaled ratings
    cfgS = cfg;
    cfgS.Smax_branch = cfg.Smax_branch * scale;

    %-- B0: no BESS --
    bd = build_case_loads(busData0, sens_evcsBuses, ...
        cfg.Pinst_MW, sens_demand.lambda, cfg.qFactorEVCS, zeros(33,1));
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
    sens_results(rs).B0 = compute_metrics(V,I,S,branchData,cfgS);
    sens_results(rs).B0.PBESS_kW = 0;

    %-- B4: re-run bisection with scaled ratings --
    bessMW = zeros(33,1);
    for outerIt = 1:5
        bd = build_case_loads(busData0, sens_evcsBuses, ...
            cfg.Pinst_MW, sens_demand.lambda, cfg.qFactorEVCS, bessMW);
        [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
        m = compute_metrics(V,I,S,branchData,cfgS);
        if m.Vmin >= cfgS.Vthr && m.LmaxPct <= cfgS.Lthr
            break
        end
        for jj = 1:numel(sens_evcsBuses)
            busJ   = sens_evcsBuses(jj);
            lL = 0; lU = 1;
            for bit = 1:30
                lM = (lL+lU)/2;
                tBESS = bessMW;
                tBESS(busJ) = max(0, sens_Pevcs_MW*(1-lM));
                bd_t = build_case_loads(busData0, sens_evcsBuses, ...
                    cfg.Pinst_MW, sens_demand.lambda, cfg.qFactorEVCS, tBESS);
                [Vt,It,St,~] = bfs_power_flow(bd_t, branchData, cfgS);
                mt = compute_metrics(Vt,It,St,branchData,cfgS);
                if mt.Vmin >= cfgS.Vthr && mt.LmaxPct <= cfgS.Lthr
                    lL = lM;
                else
                    lU = lM;
                end
                if (lU-lL) <= 1e-3, break; end
            end
            bessMW(busJ) = max(0, sens_Pevcs_MW - lL*sens_Pevcs_MW);
        end
    end
    bd = build_case_loads(busData0, sens_evcsBuses, ...
        cfg.Pinst_MW, sens_demand.lambda, cfg.qFactorEVCS, bessMW);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
    sens_results(rs).B4 = compute_metrics(V,I,S,branchData,cfgS);
    sens_results(rs).B4.PBESS_kW = sum(bessMW)*1000;
    totalBESS_MW = sum(bessMW);

    %-- B1: aggregated Bus 1 --
    bMW = zeros(33,1); bMW(1) = totalBESS_MW;
    bd = build_case_loads(busData0, sens_evcsBuses, cfg.Pinst_MW, ...
        sens_demand.lambda, cfg.qFactorEVCS, bMW);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
    sens_results(rs).B1 = compute_metrics(V,I,S,branchData,cfgS);
    sens_results(rs).B1.PBESS_kW = totalBESS_MW*1000;

    %-- B2: aggregated Bus 2 --
    bMW = zeros(33,1); bMW(2) = totalBESS_MW;
    bd = build_case_loads(busData0, sens_evcsBuses, cfg.Pinst_MW, ...
        sens_demand.lambda, cfg.qFactorEVCS, bMW);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
    sens_results(rs).B2 = compute_metrics(V,I,S,branchData,cfgS);
    sens_results(rs).B2.PBESS_kW = totalBESS_MW*1000;

    %-- B3: fixed 20% --
    bMW = zeros(33,1);
    for b = sens_evcsBuses
        bMW(b) = 0.20 * sens_Pevcs_MW;
    end
    bd = build_case_loads(busData0, sens_evcsBuses, cfg.Pinst_MW, ...
        sens_demand.lambda, cfg.qFactorEVCS, bMW);
    [V,I,S,~] = bfs_power_flow(bd, branchData, cfgS);
    sens_results(rs).B3 = compute_metrics(V,I,S,branchData,cfgS);
    sens_results(rs).B3.PBESS_kW = sum(bMW)*1000;

    fprintf('Scale=%.1f | B0 Lmax=%.2f%% | B4 Lmax=%.2f%% HCM=%.2f%% PBESS=%.1fkW\n', ...
        scale, sens_results(rs).B0.LmaxPct, ...
        sens_results(rs).B4.LmaxPct, ...
        sens_results(rs).B4.HCMpct, ...
        sens_results(rs).B4.PBESS_kW);
end

%-- Export sensitivity CSV --
fid2 = fopen(fullfile(cfg.outDir, 'Table_sensitivity_P2D4.csv'), 'w');
fprintf(fid2, 'Scale,Baseline,Vmin_pu,Lmax_pct,HCM_pct,Ploss_kW,PBESS_kW\n');
blNames = {'B0','B1','B2','B3','B4'};
for rs = 1:nScales
    for bl = 1:5
        m = sens_results(rs).(blNames{bl});
        fprintf(fid2, '%.1f,%s,%.4f,%.2f,%.2f,%.1f,%.1f\n', ...
            ratingScales(rs), blNames{bl}, ...
            m.Vmin, m.LmaxPct, m.HCMpct, m.Ploss_kW, m.PBESS_kW);
    end
end
fclose(fid2);
fprintf('Exported: Table_sensitivity_P2D4.csv\n');


%% ========================================================================
%  24-HOUR SoC TRAJECTORY — P2/D4
% ========================================================================

fprintf('\nSTEP 8: 24-HOUR SoC TRAJECTORY — P2/D4\n');
fprintf('------------------------------------------------------------\n');

% --- Parameters ---
PBESS_kW    = 1440.0;       % discharge power (kW)
Pch_unc_kW  = 911.8;        % unconstrained recharge power (kW)
Pch_con_kW  = 168.3;        % feeder-constrained recharge power (kW)
eta_dis     = 0.95;
eta_ch      = 0.95;
SoC_max     = 0.90;
SoC_min     = 0.20;
delta_SoC   = SoC_max - SoC_min;   % 0.70 usable range

% Energy capacity
t_dis_h     = 4.0;          % discharge duration (h)
E_rated_kWh = (PBESS_kW * t_dis_h) / (eta_dis * delta_SoC);
fprintf('E_rated = %.1f kWh (%.2f MWh)\n', E_rated_kWh, E_rated_kWh/1000);

% dSoC/dt rates
dSoC_dis = PBESS_kW   / (eta_dis * E_rated_kWh);   % per hour (discharge)
dSoC_unc = Pch_unc_kW * eta_ch / E_rated_kWh;       % per hour (unconstrained)
dSoC_con = Pch_con_kW * eta_ch / E_rated_kWh;       % per hour (constrained)

T_recharge_unc = delta_SoC / dSoC_unc;
T_recharge_con = delta_SoC / dSoC_con;
fprintf('Unconstrained recharge time : %.2f h\n', T_recharge_unc);
fprintf('Feeder-constrained recharge : %.2f h\n', T_recharge_con);

% --- Timeline definition (hours from midnight Day 1) ---
% 00:00–17:00  idle, SoC = SoC_max
% 17:00–21:00  discharge (4h)
% 21:00–23:00  idle
% 23:00–06:00  off-peak window (7h) → recharge
% Plot window: 0h to 35h (captures end of 7h window at h=30)

dt      = 0.01;             % time step (h)
t_start = 0;
t_end   = 35;
t_vec   = (t_start : dt : t_end)';

% Key time markers (hours from midnight)
t_dis_start = 17;
t_dis_end   = 21;
t_idle_end  = 23;
t_rch_start = 23;
t_rch_end   = 30;           % end of 7h window

% --- Compute SoC trajectories ---
SoC_unc = zeros(size(t_vec));
SoC_con = zeros(size(t_vec));

for k = 1:numel(t_vec)
    t = t_vec(k);

    if t < t_dis_start
        % Idle before discharge
        SoC_unc(k) = SoC_max;
        SoC_con(k) = SoC_max;

    elseif t <= t_dis_end
        % Discharging
        elapsed = t - t_dis_start;
        s = SoC_max - dSoC_dis * elapsed;
        SoC_unc(k) = max(s, SoC_min);
        SoC_con(k) = max(s, SoC_min);

    elseif t <= t_rch_start
        % Idle after discharge
        SoC_unc(k) = SoC_min;
        SoC_con(k) = SoC_min;

    else
        % Recharge phase
        elapsed = t - t_rch_start;

        % Unconstrained
        s_unc = SoC_min + dSoC_unc * elapsed;
        SoC_unc(k) = min(s_unc, SoC_max);

        % Feeder-constrained
        s_con = SoC_min + dSoC_con * elapsed;
        SoC_con(k) = min(s_con, SoC_max);
    end
end

% SoC at end of 7h recharge window
SoC_con_at_window_end = SoC_min + dSoC_con * 7;
SoC_unc_at_window_end = min(SoC_min + dSoC_unc * 7, SoC_max);
SoC_deficit = SoC_max - SoC_con_at_window_end;

fprintf('SoC at end of 7h window (unconstrained) : %.4f\n', SoC_unc_at_window_end);
fprintf('SoC at end of 7h window (constrained)   : %.4f\n', SoC_con_at_window_end);
fprintf('SoC deficit after 7h window             : %.4f (%.1f%%)\n', ...
    SoC_deficit, SoC_deficit*100);

% --- Extended trajectory for feeder-constrained (beyond 7h window) ---
t_ext  = (t_rch_start : dt : t_rch_start + T_recharge_con + 1)';
SoC_ext = min(SoC_min + dSoC_con * (t_ext - t_rch_start), SoC_max);

% --- Figure ---
fig = figure('Name','Fig12 SoC Trajectory P2/D4', ...
    'Color','w','Position',[100 100 900 420]);

hold on;

% Shaded regions
patch([t_dis_start t_dis_end t_dis_end t_dis_start], ...
    [0 0 1 1], [1 0.85 0.85], 'EdgeColor','none','FaceAlpha',0.4);
patch([t_rch_start t_rch_end t_rch_end t_rch_start], ...
    [0 0 1 1], [0.85 0.92 1.0], 'EdgeColor','none','FaceAlpha',0.4);

% Extended feeder-constrained (beyond window, dashed)
mask_ext = t_ext >= t_rch_end;
plot(t_ext(mask_ext), SoC_ext(mask_ext), '--', ...
    'Color',[0.85 0.33 0.10], 'LineWidth',1.4);

% Main trajectories
plot(t_vec, SoC_unc, '-',  'Color',[0.0  0.45 0.74], 'LineWidth',2.2);
plot(t_vec, SoC_con, '-',  'Color',[0.85 0.33 0.10], 'LineWidth',2.2);

% Threshold lines
yline(SoC_max, ':', 'SoC_{max}=0.90', ...
    'Color',[0.3 0.3 0.3],'LineWidth',1.0,'LabelHorizontalAlignment','left');
yline(SoC_min, ':', 'SoC_{min}=0.20', ...
    'Color',[0.3 0.3 0.3],'LineWidth',1.0,'LabelHorizontalAlignment','left');

% Annotation: SoC deficit at window end
plot(t_rch_end, SoC_con_at_window_end, 'o', ...
    'Color',[0.85 0.33 0.10],'MarkerSize',8,'MarkerFaceColor',[0.85 0.33 0.10]);
plot(t_rch_end, SoC_max, 's', ...
    'Color',[0.0 0.45 0.74],'MarkerSize',8,'MarkerFaceColor',[0.0 0.45 0.74]);

% Deficit arrow annotation
annotation('doublearrow', ...
    'X', [t_rch_end+0.3, t_rch_end+0.3] / t_end, ...
    'Y', [SoC_con_at_window_end, SoC_max], ...
    'Color','k','LineWidth',1.2);
text(t_rch_end + 0.5, (SoC_con_at_window_end + SoC_max)/2, ...
    sprintf('Deficit\n%.2f p.u.', SoC_deficit), ...
    'FontSize', 9, 'Color','k');

% Required recharge time marker
text(t_rch_start + T_recharge_con/2, SoC_min - 0.05, ...
    sprintf('Required: %.1f h', T_recharge_con), ...
    'FontSize', 9, 'Color',[0.85 0.33 0.10], ...
    'HorizontalAlignment','center');

% Axis and labels
xlim([0 t_end]);
ylim([0.05 1.00]);
xticks(0:2:t_end);
xlabel('Time (h from midnight)', 'FontSize',11);
ylabel('State of Charge (p.u.)', 'FontSize',11);
title('SoC Trajectory — P2/D4 (B4 BESS)', 'FontSize',12);

legend({'Discharge window','Off-peak window (7 h)', ...
        sprintf('Constrained (extended, beyond window)'), ...
        sprintf('Unconstrained recharge (%.0f kW)', Pch_unc_kW), ...
        sprintf('Feeder-constrained recharge (%.0f kW)', Pch_con_kW)}, ...
    'Location','southeast','FontSize',9);

% Region labels
text(mean([t_dis_start t_dis_end]), 0.93, 'EVCS peak\n(discharge)', ...
    'FontSize',9,'HorizontalAlignment','center','Color',[0.6 0.1 0.1]);
text(mean([t_rch_start t_rch_end]), 0.93, 'Off-peak window\n(7 h)', ...
    'FontSize',9,'HorizontalAlignment','center','Color',[0.1 0.3 0.7]);

grid on; box on;
hold off;

exportgraphics(fig, fullfile(cfg.outDir, 'Fig12_SoC_trajectory_P2D4.png'), ...
    'Resolution', 300);
fprintf('Exported: Fig12_SoC_trajectory_P2D4.png\n');

% --- Export SoC data CSV ---
fid3 = fopen(fullfile(cfg.outDir, 'SoC_trajectory_P2D4.csv'), 'w');
fprintf(fid3, 'Time_h,SoC_unconstrained,SoC_feeder_constrained\n');
for k = 1:numel(t_vec)
    fprintf(fid3, '%.2f,%.4f,%.4f\n', t_vec(k), SoC_unc(k), SoC_con(k));
end
fclose(fid3);
fprintf('Exported: SoC_trajectory_P2D4.csv\n');

% --- Print summary ---
fprintf('\nSoC Summary P2/D4:\n');
fprintf('  E_rated              = %.1f kWh = %.2f MWh\n', E_rated_kWh, E_rated_kWh/1000);
fprintf('  Discharge rate       = %.4f p.u./h\n', dSoC_dis);
fprintf('  Unconstrained rate   = %.4f p.u./h  →  recharge in %.2f h\n', dSoC_unc, T_recharge_unc);
fprintf('  Feeder-constr. rate  = %.4f p.u./h  →  recharge in %.2f h\n', dSoC_con, T_recharge_con);
fprintf('  SoC deficit at 7h    = %.4f (%.1f%% of usable range)\n', ...
    SoC_deficit, SoC_deficit/delta_SoC*100);

%% ========================================================================
%  LOCAL FUNCTIONS
% ========================================================================

function [busData, branchData] = ieee33_data()
    % Bus load data: [bus, P_kW, Q_kVAr]
    busData = [
         1     0     0;
         2   100    60;
         3    90    40;
         4   120    80;
         5    60    30;
         6    60    20;
         7   200   100;
         8   200   100;
         9    60    20;
        10    60    20;
        11    45    30;
        12    60    35;
        13    60    35;
        14   120    80;
        15    60    10;
        16    60    20;
        17    60    20;
        18    90    40;
        19    90    40;
        20    90    40;
        21    90    40;
        22    90    40;
        23    90    50;
        24   420   200;
        25   420   200;
        26    60    25;
        27    60    25;
        28    60    20;
        29   120    70;
        30   200   600;
        31   150    70;
        32   210   100;
        33    60    40
    ];

    % Closed radial branch data: [from, to, R_ohm, X_ohm]
    branchData = [
         1   2   0.0922   0.0470;
         2   3   0.4930   0.2511;
         3   4   0.3660   0.1864;
         4   5   0.3811   0.1941;
         5   6   0.8190   0.7070;
         6   7   0.1872   0.6188;
         7   8   1.7114   1.2351;
         8   9   1.0300   0.7400;
         9  10   1.0440   0.7400;
        10  11   0.1966   0.0650;
        11  12   0.3744   0.1238;
        12  13   1.4680   1.1550;
        13  14   0.5416   0.7129;
        14  15   0.5910   0.5260;
        15  16   0.7463   0.5450;
        16  17   1.2890   1.7210;
        17  18   0.7320   0.5740;
         2  19   0.1640   0.1565;
        19  20   1.5042   1.3554;
        20  21   0.4095   0.4784;
        21  22   0.7089   0.9373;
         3  23   0.4512   0.3083;
        23  24   0.8980   0.7091;
        24  25   0.8960   0.7011;
         6  26   0.2030   0.1034;
        26  27   0.2842   0.1447;
        27  28   1.0590   0.9337;
        28  29   0.8042   0.7006;
        29  30   0.5075   0.2585;
        30  31   0.9744   0.9630;
        31  32   0.3105   0.3619;
        32  33   0.3410   0.5302
    ];
end

function busData = build_case_loads(busData0, evcsBuses, Pinst_MW, lambda, qFactorEVCS, bessMW)
    % Add EVCS demand and subtract BESS active-power discharge.
    %
    % Inputs:
    %   busData0    : base load data [bus, P_kW, Q_kVAr]
    %   evcsBuses   : active EVCS bus indices
    %   Pinst_MW    : per-bus EVCS active power at lambda = 1.0
    %   lambda      : demand multiplier
    %   qFactorEVCS : tan(acos(pf))
    %   bessMW      : 33x1 vector of local BESS active discharge in MW
    %
    % Output:
    %   busData     : modified constant-PQ bus load data

    if nargin < 6 || isempty(bessMW)
        bessMW = zeros(33,1);
    end

    busData = busData0;

    Pevcs_MW   = Pinst_MW * lambda;
    Qevcs_MVAr = Pevcs_MW * qFactorEVCS;

    for b = evcsBuses
        busData(b,2) = busData(b,2) + Pevcs_MW * 1000;
        busData(b,3) = busData(b,3) + Qevcs_MVAr * 1000;
    end

    % BESS discharge as negative active load. No reactive support assumed.
    for b = 1:33
        if bessMW(b) > 0
            busData(b,2) = busData(b,2) - bessMW(b) * 1000;
        end
    end

    % Prevent negative net active load unless intentionally modelling export.
    % For this paper, BESS offsets EVCS load and should not create net export.
    for b = 1:33
        busData(b,2) = max(busData(b,2), 0);
    end
end

function [V, Ibr, Sbr, info] = bfs_power_flow(busData, branchData, cfg)
    nb = size(busData,1);
    nl = size(branchData,1);

    baseZ = cfg.baseKV^2 / cfg.baseMVA; % ohm
    z = (branchData(:,3) + 1i*branchData(:,4)) / baseZ;

    Ppu = zeros(nb,1);
    Qpu = zeros(nb,1);

    for k = 1:nb
        b = busData(k,1);
        Ppu(b) = busData(k,2) / 1000 / cfg.baseMVA;
        Qpu(b) = busData(k,3) / 1000 / cfg.baseMVA;
    end

    Sload = Ppu + 1i*Qpu;

    V = cfg.Vslack * ones(nb,1);
    Ibr = zeros(nl,1);
    converged = false;

    for iter = 1:cfg.maxIter
        Vold = V;

        % Bus current injection for constant-power loads.
        Ibus = conj(Sload ./ V);

        % Backward sweep: accumulate branch currents from leaves to root.
        Idown = Ibus;
        for l = nl:-1:1
            fromBus = branchData(l,1);
            toBus   = branchData(l,2);

            Ibr(l) = Idown(toBus);
            Idown(fromBus) = Idown(fromBus) + Ibr(l);
        end

        % Forward sweep: update voltage from root to leaves.
        V(1) = cfg.Vslack + 0i;
        for l = 1:nl
            fromBus = branchData(l,1);
            toBus   = branchData(l,2);

            V(toBus) = V(fromBus) - z(l) * Ibr(l);
        end

        if max(abs(V - Vold)) < cfg.tol
            converged = true;
            break;
        end
    end

    % Branch apparent power in MVA on system base.
    Sbr = V(branchData(:,1)) .* conj(Ibr) * cfg.baseMVA;

    info.iterations = iter;
    info.converged  = converged;
    info.z          = z;
    info.baseMVA    = cfg.baseMVA;
end

function metric = compute_metrics(V, Ibr, Sbr, branchData, cfg)
    SmaxVec = cfg.Smax_branch(:);
    SbrAbs  = abs(Sbr(:));

    loadingPct = SbrAbs ./ SmaxVec * 100;
    [LmaxPct, critIdx] = max(loadingPct);

    HCMpct = min((SmaxVec - SbrAbs) ./ SmaxVec) * 100;

    baseZ = cfg.baseKV^2 / cfg.baseMVA;
    rpu = branchData(:,3) / baseZ;
    Ploss_pu = sum(abs(Ibr).^2 .* rpu);
    Ploss_kW = Ploss_pu * cfg.baseMVA * 1000;

    [Vmin, VminBus] = min(abs(V));

    metric = empty_metric();
    metric.Vmin      = Vmin;
    metric.VminBus   = VminBus;
    metric.LmaxPct   = LmaxPct;
    metric.critIdx   = critIdx;
    metric.critFrom  = branchData(critIdx,1);
    metric.critTo    = branchData(critIdx,2);
    metric.HCMpct    = HCMpct;
    metric.Ploss_kW  = Ploss_kW;
    metric.loadingPct = loadingPct;
    metric.iterations = NaN;
    metric.converged  = true;
end

function m = empty_metric()
    m.Vmin       = NaN;
    m.VminBus    = NaN;
    m.LmaxPct    = NaN;
    m.critIdx    = NaN;
    m.critFrom   = NaN;
    m.critTo     = NaN;
    m.HCMpct     = NaN;
    m.Ploss_kW   = NaN;
    m.loadingPct = [];
    m.iterations = NaN;
    m.converged  = false;
end

function print_metric(caseName, m, cfg)
    vFlag = "";
    lFlag = "";

    if m.Vmin < cfg.Vthr
        vFlag = " | V-viol.";
    end

    if m.LmaxPct > cfg.Lthr
        lFlag = " | L-viol.";
    end

    fprintf('%-8s: Vmin = %.5f p.u. at Bus %2d | Lmax = %7.2f%% at Branch %2d-%2d | HCM = %7.2f%% | Ploss = %8.3f kW%s%s\n', ...
        caseName, m.Vmin, m.VminBus, m.LmaxPct, m.critFrom, m.critTo, ...
        m.HCMpct, m.Ploss_kW, vFlag, lFlag);
end

function labels = make_branch_labels(branchData)
    labels = strings(size(branchData,1),1);
    for k = 1:size(branchData,1)
        labels(k) = sprintf('%d-%d', branchData(k,1), branchData(k,2));
    end
end


