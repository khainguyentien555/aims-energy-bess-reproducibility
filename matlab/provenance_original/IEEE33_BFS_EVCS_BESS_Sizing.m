clear; clc; close all;

%% ========================================================================
% SETTINGS
% ========================================================================

% Base quantities
cfg.baseMVA = 100;       % MVA
cfg.baseKV  = 12.66;     % kV line-to-line

% Slack-bus voltage
cfg.Vslack  = 1.05;      % p.u.

% BFS settings
cfg.tol     = 1e-5;      % p.u.
cfg.maxIter = 50;

% Voltage and branch-loading thresholds
cfg.Vthr = 0.95;         % p.u.
cfg.Lthr = 100;          % %

% Bisection settings
cfg.bisectionTol      = 1e-3;
cfg.maxOuterBisection = 8;

% BESS / SoC assumptions for energy post-processing
cfg.SoCmin  = 0.20;
cfg.SoCmax  = 0.90;
cfg.etaDis  = 0.95;
cfg.etaCh   = 0.95;
cfg.pfBESSCharge = 1.00; % BESS recharge is modelled as active load at unity PF
cfg.qFactorBESSCharge = tan(acos(cfg.pfBESSCharge));
cfg.Tdis_h  = 4.0;       % discharge duration for energy rating
cfg.Tchg_h  = 7.0;       % available off-peak charging window

% Branch-specific thermal ratings (MVA)
% Feeder-hierarchy planning assumption. Original IEEE 33-bus data do not
% specify continuous thermal ratings.
cfg.Smax_branch = [
  6.0;  %  1   1-2
  5.0;  %  2   2-3
  4.0;  %  3   3-4
  4.0;  %  4   4-5
  3.5;  %  5   5-6
  3.5;  %  6   6-7
  3.0;  %  7   7-8
  3.0;  %  8   8-9
  3.0;  %  9   9-10
  3.0;  % 10  10-11
  2.5;  % 11  11-12
  2.5;  % 12  12-13
  2.5;  % 13  13-14
  2.5;  % 14  14-15
  2.0;  % 15  15-16
  2.0;  % 16  16-17
  2.0;  % 17  17-18
  4.0;  % 18   2-19
  3.5;  % 19  19-20
  3.0;  % 20  20-21
  3.0;  % 21  21-22
  3.5;  % 22   3-23
  3.0;  % 23  23-24
  2.5;  % 24  24-25
  3.5;  % 25   6-26
  3.0;  % 26  26-27
  2.5;  % 27  27-28
  2.5;  % 28  28-29
  2.5;  % 29  29-30
  2.0;  % 30  30-31
  2.0;  % 31  31-32
  2.0;  % 32  32-33
];

% EVCS settings
cfg.Pinst_MW = 0.15;     % MW per active EVCS bus at demand multiplier = 1.0
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

% Fixed-percentage BESS baseline
cfg.fixedBessFraction = 0.20;

% Output folder
cfg.outDir = 'BFS_BESS_outputs';
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
fprintf('IEEE 33-BUS EVCS-BESS SIZING SCRIPT\n');
fprintf('============================================================\n');
fprintf('Base load : %.3f MW + j%.3f MVAr\n', Pbase_MW, Qbase_MVAr);
fprintf('Vslack    : %.3f p.u.\n', cfg.Vslack);
fprintf('EVCS      : %.3f MW per EVCS bus at lambda = 1.0, PF = %.2f\n', ...
    cfg.Pinst_MW, cfg.pfEVCS);
fprintf('BESS      : co-located active-power compensation only\n');
fprintf('Output dir: %s\n', cfg.outDir);

%% ========================================================================
% BASE CASE WITHOUT EVCS/BESS
% ========================================================================

[Vbase, IbrBase, SbrBase, baseInfo] = bfs_power_flow(busData0, branchData, cfg);
baseMetric = compute_metrics(Vbase, IbrBase, SbrBase, branchData, cfg, baseInfo);

fprintf('\nBASE CASE WITHOUT EVCS/BESS\n');
fprintf('------------------------------------------------------------\n');
print_metric('Base', baseMetric, cfg);

%% ========================================================================
% NO-BESS BASELINE CASES
% ========================================================================

nPlacements = numel(placements);
nDemands    = numel(demands);
nCases      = nPlacements * nDemands;

caseNames      = cell(nCases,1);
placementCol   = cell(nCases,1);
demandCol      = cell(nCases,1);
demandLambda   = zeros(nCases,1);
rhoCol_pct     = zeros(nCases,1);
metricsBefore  = repmat(empty_metric(), nCases, 1);
metricsAfter   = repmat(empty_metric(), nCases, 1);

allVBefore       = zeros(33,nCases);
allLoadingBefore = zeros(32,nCases);
allVAfter        = zeros(33,nCases);
allLoadingAfter  = zeros(32,nCases);

% Store proposed BESS sizing results
BESS_total_MW   = zeros(nCases,1);
BESS_total_kW   = zeros(nCases,1);
Energy_total_MWh = zeros(nCases,1);
FeasibleAfter   = false(nCases,1);
OuterIterations = zeros(nCases,1);
BisectionSweeps = zeros(nCases,1);
CorrectionPassesAfterInitial = zeros(nCases,1);

% Off-peak BESS recharge verification arrays
OffpeakFeasible        = false(nCases,1);
OffpeakVmin_pu         = NaN(nCases,1);
OffpeakLmax_pct        = NaN(nCases,1);
OffpeakHCM_pct         = NaN(nCases,1);
OffpeakPloss_kW        = NaN(nCases,1);
OffpeakPch_kW          = zeros(nCases,1);       % feasible/curtailed charging power
OffpeakPchTarget_kW    = zeros(nCases,1);       % unconstrained target charging power
OffpeakCurtailment_pct = zeros(nCases,1);       % feasible Pch / target Pch * 100
OffpeakTchgReq_h       = zeros(nCases,1);       % recharge duration required at feasible Pch
OffpeakWithinWindow    = true(nCases,1);        % true if target recharge is feasible within cfg.Tchg_h

% Bus-level allowable table accumulator
AllowPlacement = {};
AllowDemand    = {};
AllowCase      = {};
AllowBus       = [];
AllowPEVCS_kW  = [];
AllowLambdaMax = [];
AllowPallow_kW = [];
AllowPBESS_kW  = [];

fprintf('\nSTEP 2-3: NO-BESS BASELINE AND PROPOSED BESS SIZING\n');
fprintf('------------------------------------------------------------\n');

idx = 0;

for p = 1:nPlacements
    for d = 1:nDemands
        idx = idx + 1;

        placement = placements(p);
        demand    = demands(d);
        caseName  = sprintf('%s/%s', placement.name, demand.name);

        caseNames{idx}    = caseName;
        placementCol{idx} = placement.name;
        demandCol{idx}    = demand.name;
        demandLambda(idx) = demand.lambda;
        rhoCol_pct(idx)   = numel(placement.buses) * cfg.Pinst_MW * demand.lambda / Pbase_MW * 100;

        % ---- No-BESS case ----
        bessZero = zeros(33,1);
        busDataNoBESS = build_case_loads(busData0, placement.buses, ...
            cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, bessZero);

        [V0, Ibr0, Sbr0, info0] = bfs_power_flow(busDataNoBESS, branchData, cfg);
        metric0 = compute_metrics(V0, Ibr0, Sbr0, branchData, cfg, info0);
        metricsBefore(idx) = metric0;
        allVBefore(:,idx) = abs(V0);
        allLoadingBefore(:,idx) = metric0.loadingPct;

        % ---- Proposed BESS sizing via coordinated bisection ----
        [lambdaBus, P_allow_MW, P_BESS_MW, sizingInfo] = coordinated_bisection_bess( ...
            busData0, branchData, cfg, placement.buses, demand.lambda);
        OuterIterations(idx) = sizingInfo.outerIterations;
        BisectionSweeps(idx) = sizingInfo.bisectionSweeps;
        CorrectionPassesAfterInitial(idx) = sizingInfo.correctionPassesAfterInitial;

        BESS_total_MW(idx) = sum(P_BESS_MW);
        BESS_total_kW(idx) = BESS_total_MW(idx) * 1000;
        Energy_total_MWh(idx) = compute_energy_rating_MWh(BESS_total_MW(idx), cfg);

        % ---- Post-BESS BFS validation ----
        busDataAfter = build_case_loads(busData0, placement.buses, ...
            cfg.Pinst_MW, demand.lambda, cfg.qFactorEVCS, P_BESS_MW);

        [V1, Ibr1, Sbr1, info1] = bfs_power_flow(busDataAfter, branchData, cfg);
        metric1 = compute_metrics(V1, Ibr1, Sbr1, branchData, cfg, info1);
        metricsAfter(idx) = metric1;
        allVAfter(:,idx) = abs(V1);
        allLoadingAfter(:,idx) = metric1.loadingPct;

        FeasibleAfter(idx) = is_metric_feasible(metric1, cfg);

        % ---- Off-peak BESS recharge BFS verification ----
        % The BESS is recharged during the off-peak window using the
        % energy removed during the discharge interval. Charging power is
        % distributed across the installed BESS buses in proportion to their
        % discharge ratings. EVCS demand is not present during this check.
        [metricOp, PchBus_MW, PchTotal_MW, offpeakInfo] = run_offpeak_charging_check( ...
            busData0, branchData, cfg, P_BESS_MW);

        OffpeakFeasible(idx)        = is_metric_feasible(metricOp, cfg);
        OffpeakVmin_pu(idx)         = metricOp.Vmin;
        OffpeakLmax_pct(idx)        = metricOp.LmaxPct;
        OffpeakHCM_pct(idx)         = metricOp.HCMpct;
        OffpeakPloss_kW(idx)        = metricOp.Ploss_kW;
        OffpeakPch_kW(idx)          = PchTotal_MW * 1000;
        OffpeakPchTarget_kW(idx)    = offpeakInfo.PchTarget_MW * 1000;
        OffpeakCurtailment_pct(idx) = offpeakInfo.curtailmentFactor * 100;
        OffpeakTchgReq_h(idx)       = offpeakInfo.TchgRequired_h;
        OffpeakWithinWindow(idx)    = offpeakInfo.rechargeWithinWindow;

        % ---- Accumulate bus-level allowable rows ----
        P_EVCS_full_MW = zeros(33,1);
        P_EVCS_full_MW(placement.buses) = cfg.Pinst_MW * demand.lambda;

        for bb = placement.buses
            AllowPlacement{end+1,1} = placement.name; %#ok<SAGROW>
            AllowDemand{end+1,1}    = demand.name; %#ok<SAGROW>
            AllowCase{end+1,1}      = caseName; %#ok<SAGROW>
            AllowBus(end+1,1)       = bb; %#ok<SAGROW>
            AllowPEVCS_kW(end+1,1)  = P_EVCS_full_MW(bb) * 1000; %#ok<SAGROW>
            AllowLambdaMax(end+1,1) = lambdaBus(bb); %#ok<SAGROW>
            AllowPallow_kW(end+1,1) = P_allow_MW(bb) * 1000; %#ok<SAGROW>
            AllowPBESS_kW(end+1,1)  = P_BESS_MW(bb) * 1000; %#ok<SAGROW>
        end

        fprintf('\n%s\n', caseName);
        print_metric('Before', metric0, cfg);
        fprintf(['Proposed BESS total = %.3f MW | Energy rating = %.3f MWh | ' ...
         'outer iterations = %d | bisection sweeps = %d | correction passes = %d\n'], ...
        BESS_total_MW(idx), Energy_total_MWh(idx), ...
        sizingInfo.outerIterations, sizingInfo.bisectionSweeps, ...
        sizingInfo.correctionPassesAfterInitial);
        print_metric('After ', metric1, cfg);
        fprintf('Off-peak recharge: Pch = %.3f MW (target %.3f MW, %.1f%%) | Vmin = %.5f | Lmax = %.2f%% | Feasible = %d | Treq = %.2f h\n', ...
            PchTotal_MW, offpeakInfo.PchTarget_MW, offpeakInfo.curtailmentFactor*100, ...
            metricOp.Vmin, metricOp.LmaxPct, OffpeakFeasible(idx), offpeakInfo.TchgRequired_h);

        if ~FeasibleAfter(idx)
            warning('%s remains infeasible after active-power BESS sizing. Check Q support, voltage threshold, or BESS formulation.', caseName);
        end
    end
end
PassSummary = table(caseNames(:), OuterIterations, BisectionSweeps, CorrectionPassesAfterInitial, ...
    'VariableNames', {'Case','OuterIterations','BisectionSweeps','CorrectionPassesAfterInitial'});

disp(PassSummary);

maxCorrectionPass = max(CorrectionPassesAfterInitial);

fprintf('\nMaximum correction passes after initial bisection = %d\n', maxCorrectionPass);

writetable(PassSummary, fullfile(cfg.outDir, 'Outer_loop_pass_summary.csv'));
%% ========================================================================
%  STEP 3: EXPORT TABLE V - NO-BESS BASELINE
% ========================================================================

TableV = build_metric_table(caseNames, placementCol, demandCol, demandLambda, rhoCol_pct, ...
    metricsBefore, cfg, 'Before');
writetable(TableV, fullfile(cfg.outDir, 'TableV_baseline_no_BESS_results.csv'));

fprintf('\nTABLE V: BASELINE GRID-IMPACT SUMMARY WITHOUT BESS\n');
fprintf('------------------------------------------------------------\n');
disp(TableV);

%% ========================================================================
%  EXPORT TABLE - POST-BESS VALIDATION
% ========================================================================

% Force all metric arrays to be column vectors.  Do not transpose the
% arrayfun output blindly because metricsBefore/metricsAfter are already
% nCases-by-1 struct arrays; a transpose would create 1-by-nCases rows and
% make table() fail with "All table variables must have the same number of rows".
Vmin_before   = arrayfun(@(m)m.Vmin, metricsBefore);    Vmin_before  = Vmin_before(:);
Vmin_after    = arrayfun(@(m)m.Vmin, metricsAfter);     Vmin_after   = Vmin_after(:);
Lmax_before   = arrayfun(@(m)m.LmaxPct, metricsBefore); Lmax_before  = Lmax_before(:);
Lmax_after    = arrayfun(@(m)m.LmaxPct, metricsAfter);  Lmax_after   = Lmax_after(:);
HCM_before    = arrayfun(@(m)m.HCMpct, metricsBefore);  HCM_before   = HCM_before(:);
HCM_after     = arrayfun(@(m)m.HCMpct, metricsAfter);   HCM_after    = HCM_after(:);
Ploss_before  = arrayfun(@(m)m.Ploss_kW, metricsBefore);Ploss_before = Ploss_before(:);
Ploss_after   = arrayfun(@(m)m.Ploss_kW, metricsAfter); Ploss_after  = Ploss_after(:);
AfterStatus   = strings(nCases,1);

for k = 1:nCases
    if FeasibleAfter(k)
        AfterStatus(k) = "Feasible";
    else
        AfterStatus(k) = "Infeasible";
    end
end

Table6 = table(caseNames(:), placementCol(:), demandCol(:), demandLambda(:), ...
    Vmin_before, Vmin_after, Vmin_after - Vmin_before, ...
    Lmax_before, Lmax_after, Lmax_after - Lmax_before, ...
    HCM_before, HCM_after, HCM_after - HCM_before, ...
    Ploss_before, Ploss_after, Ploss_after - Ploss_before, ...
    BESS_total_kW, Energy_total_MWh, FeasibleAfter, AfterStatus, ...
    OffpeakPchTarget_kW, OffpeakPch_kW, OffpeakCurtailment_pct, ...
    OffpeakTchgReq_h, OffpeakWithinWindow, ...
    OffpeakVmin_pu, OffpeakLmax_pct, OffpeakHCM_pct, ...
    OffpeakPloss_kW, OffpeakFeasible, ...
    'VariableNames', {'Case','Placement','Demand','Demand_lambda', ...
    'Vmin_before_pu','Vmin_after_pu','Delta_Vmin_pu', ...
    'Lmax_before_pct','Lmax_after_pct','Delta_Lmax_pct', ...
    'HCM_before_pct','HCM_after_pct','Delta_HCM_pct', ...
    'Ploss_before_kW','Ploss_after_kW','Delta_Ploss_kW', ...
    'PBESS_total_kW','EBESS_total_MWh','Feasible_after','Status_after', ...
    'Offpeak_Pch_target_kW','Offpeak_Pch_feasible_kW','Offpeak_curtailment_pct', ...
    'Offpeak_Tchg_required_h','Offpeak_recharge_within_window', ...
    'Offpeak_Vmin_pu','Offpeak_Lmax_pct', ...
    'Offpeak_HCM_pct','Offpeak_Ploss_kW','Offpeak_feasible'});

fprintf('\nTABLE 6: POWER-FLOW VALIDATION BEFORE AND AFTER PROPOSED BESS\n');
fprintf('------------------------------------------------------------\n');
disp(Table6);
writetable(Table6, fullfile(cfg.outDir, 'Table6_post_BESS_validation.csv'));

Table9_Offpeak = Table6(:, {'Case','Placement','Demand','PBESS_total_kW', ...
    'EBESS_total_MWh','Offpeak_Pch_target_kW','Offpeak_Pch_feasible_kW', ...
    'Offpeak_curtailment_pct','Offpeak_Tchg_required_h','Offpeak_recharge_within_window', ...
    'Offpeak_Vmin_pu','Offpeak_Lmax_pct','Offpeak_HCM_pct','Offpeak_Ploss_kW','Offpeak_feasible'});
writetable(Table9_Offpeak, fullfile(cfg.outDir, 'Table9_offpeak_charging_feasibility.csv'));

%% ========================================================================
% EXPORT TABLE - BUS-LEVEL ALLOWABLE INJECTION
% ========================================================================

Table7 = table(AllowCase, AllowPlacement, AllowDemand, AllowBus, ...
    AllowPEVCS_kW, AllowLambdaMax, AllowPallow_kW, AllowPBESS_kW, ...
    'VariableNames', {'Case','Placement','Demand','Bus', ...
    'P_EVCS_kW','lambda_max','P_allow_kW','P_BESS_kW'});

fprintf('\nTABLE 7: BUS-LEVEL ALLOWABLE INJECTION AND BESS RATING\n');
fprintf('------------------------------------------------------------\n');
disp(Table7);
writetable(Table7, fullfile(cfg.outDir, 'Table7_allowable_BESS_bus_level.csv'));

Table7_D4 = Table7(strcmp(Table7.Demand,'D4'), :);
writetable(Table7_D4, fullfile(cfg.outDir, 'Table7_D4_bus_level_allowable_BESS.csv'));

%% ========================================================================
%  B4-PQ REACTIVE-SUPPORT SENSITIVITY
% ========================================================================
% B4-PQ keeps the proposed B4 active-power BESS discharge unchanged and
% adds local reactive-power compensation at EVCS buses. This section is
% intended to quantify how much Q support is needed to close the residual
% voltage gap after thermal restoration by active-power BESS.

pfList = [0.97 0.98 0.99];

% Voltage-limited cases after B4-P active-power compensation
voltageLimitedIdx = find(Vmin_after < cfg.Vthr);
nVL = numel(voltageLimitedIdx);
nPF = numel(pfList);

B4PQ_Case      = cell(nVL,1);
B4PQ_Placement = cell(nVL,1);
B4PQ_Demand    = cell(nVL,1);
B4P_Vmin       = NaN(nVL,1);
B4P_Lmax       = NaN(nVL,1);
B4P_HCM        = NaN(nVL,1);
B4P_Ploss      = NaN(nVL,1);

Vmin_pf        = NaN(nVL,nPF);
Lmax_pf        = NaN(nVL,nPF);
HCM_pf         = NaN(nVL,nPF);
Ploss_pf       = NaN(nVL,nPF);
Qcomp_pf_kvar  = NaN(nVL,nPF);
MinPF_tested   = NaN(nVL,1);

Gamma_min      = NaN(nVL,1);
Qcomp_min_kvar = NaN(nVL,1);
PF_equiv       = NaN(nVL,1);
B4PQ_Vmin      = NaN(nVL,1);
B4PQ_Lmax      = NaN(nVL,1);
B4PQ_HCM       = NaN(nVL,1);
B4PQ_Ploss     = NaN(nVL,1);

fprintf('\nSTEP 5B: B4-PQ REACTIVE-SUPPORT SENSITIVITY\n');
fprintf('------------------------------------------------------------\n');

for ii = 1:nVL
    c = voltageLimitedIdx(ii);

    cname = caseNames{c};
    pname = placementCol{c};
    dname = demandCol{c};
    lambda = demandLambda(c);

    pIdx = find(strcmp({placements.name}, pname), 1);
    dIdx = find(strcmp({demands.name}, dname), 1);
    evcsBuses = placements(pIdx).buses;

    % Reconstruct B4 active-power BESS vector from the bus-level table.
    bessMW = zeros(33,1);
    rowMask = strcmp(Table7.Case, cname);
    rowIdx = find(rowMask);
    for rr = rowIdx(:).'
        bessMW(Table7.Bus(rr)) = Table7.P_BESS_kW(rr) / 1000;
    end

    % Baseline B4-P validation at original EVCS PF = 0.95
    busDataB4P = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, lambda, cfg.qFactorEVCS, bessMW);
    [Vb4p, Ib4p, Sb4p, infob4p] = bfs_power_flow(busDataB4P, branchData, cfg);
    metB4P = compute_metrics(Vb4p, Ib4p, Sb4p, branchData, cfg, infob4p);

    B4PQ_Case{ii}      = cname;
    B4PQ_Placement{ii} = pname;
    B4PQ_Demand{ii}    = dname;
    B4P_Vmin(ii)       = metB4P.Vmin;
    B4P_Lmax(ii)       = metB4P.LmaxPct;
    B4P_HCM(ii)        = metB4P.HCMpct;
    B4P_Ploss(ii)      = metB4P.Ploss_kW;

    % A) Power-factor correction sensitivity: 0.97, 0.98, 0.99
    for pp = 1:nPF
        pfStar = pfList(pp);
        qFactorStar = tan(acos(pfStar));

        busDataPF = build_case_loads(busData0, evcsBuses, ...
            cfg.Pinst_MW, lambda, qFactorStar, bessMW);
        [Vpf, Ipf, Spf, infopf] = bfs_power_flow(busDataPF, branchData, cfg);
        metPF = compute_metrics(Vpf, Ipf, Spf, branchData, cfg, infopf);

        Vmin_pf(ii,pp) = metPF.Vmin;
        Lmax_pf(ii,pp) = metPF.LmaxPct;
        HCM_pf(ii,pp)  = metPF.HCMpct;
        Ploss_pf(ii,pp)= metPF.Ploss_kW;

        % Equivalent reactive compensation relative to the original PF = 0.95.
        Qcomp_pf_kvar(ii,pp) = numel(evcsBuses) * cfg.Pinst_MW * lambda * ...
            max(cfg.qFactorEVCS - qFactorStar, 0) * 1000;
    end

    okPF = find(Vmin_pf(ii,:) >= cfg.Vthr & Lmax_pf(ii,:) <= cfg.Lthr, 1, 'first');
    if ~isempty(okPF)
        MinPF_tested(ii) = pfList(okPF);
    end

    % B) Minimum proportional Q compensation by bisection.
    % Q_comp_j = gamma * Q_EVCS_j, 0 <= gamma <= 1.
    gammaL = 0.0;
    gammaU = 1.0;
    tolGamma = 1e-4;
    maxGammaIter = 60;

    % Check full Q compensation first.
    busDataFullQ = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, lambda, 0.0, bessMW);
    [VfullQ, IfullQ, SfullQ, infoFullQ] = bfs_power_flow(busDataFullQ, branchData, cfg);
    metFullQ = compute_metrics(VfullQ, IfullQ, SfullQ, branchData, cfg, infoFullQ);

    if metFullQ.Vmin < cfg.Vthr || metFullQ.LmaxPct > cfg.Lthr
        warning('Full local Q compensation is still infeasible for %s.', cname);
        gammaMin = NaN;
        metMin = metFullQ;
    else
        metMin = metFullQ;
        for itg = 1:maxGammaIter
            gammaMid = 0.5 * (gammaL + gammaU);
            qFactorMid = (1 - gammaMid) * cfg.qFactorEVCS;

            busDataMid = build_case_loads(busData0, evcsBuses, ...
                cfg.Pinst_MW, lambda, qFactorMid, bessMW);
            [Vmid, Imid, Smid, infoMid] = bfs_power_flow(busDataMid, branchData, cfg);
            metMid = compute_metrics(Vmid, Imid, Smid, branchData, cfg, infoMid);

            feasibleMid = metMid.converged && metMid.Vmin >= cfg.Vthr && metMid.LmaxPct <= cfg.Lthr;

            if feasibleMid
                gammaU = gammaMid;
                metMin = metMid;
            else
                gammaL = gammaMid;
            end

            if (gammaU - gammaL) <= tolGamma
                break;
            end
        end
        gammaMin = gammaU;

        % Re-evaluate exactly at gammaMin for reporting.
        qFactorMin = (1 - gammaMin) * cfg.qFactorEVCS;
        busDataMinQ = build_case_loads(busData0, evcsBuses, ...
            cfg.Pinst_MW, lambda, qFactorMin, bessMW);
        [VminQ, IminQ, SminQ, infoMinQ] = bfs_power_flow(busDataMinQ, branchData, cfg);
        metMin = compute_metrics(VminQ, IminQ, SminQ, branchData, cfg, infoMinQ);
    end

    Gamma_min(ii)      = gammaMin;
    Qcomp_min_kvar(ii) = gammaMin * numel(evcsBuses) * cfg.Pinst_MW * lambda * cfg.qFactorEVCS * 1000;
    PF_equiv(ii)       = 1 / sqrt(1 + ((1 - gammaMin) * cfg.qFactorEVCS)^2);
    B4PQ_Vmin(ii)      = metMin.Vmin;
    B4PQ_Lmax(ii)      = metMin.LmaxPct;
    B4PQ_HCM(ii)       = metMin.HCMpct;
    B4PQ_Ploss(ii)     = metMin.Ploss_kW;

    fprintf('%s | B4-P Vmin = %.4f, Lmax = %.2f%% | gamma_min = %.4f | Qmin = %.1f kvar | pf_eq = %.4f | B4-PQ Vmin = %.4f\n', ...
        cname, metB4P.Vmin, metB4P.LmaxPct, Gamma_min(ii), Qcomp_min_kvar(ii), PF_equiv(ii), B4PQ_Vmin(ii));
end

B4PQ_TablePF = table(B4PQ_Case, B4PQ_Placement, B4PQ_Demand, ...
    B4P_Vmin, B4P_Lmax, B4P_HCM, B4P_Ploss, ...
    Vmin_pf(:,1), Vmin_pf(:,2), Vmin_pf(:,3), ...
    Lmax_pf(:,1), Lmax_pf(:,2), Lmax_pf(:,3), ...
    Qcomp_pf_kvar(:,1), Qcomp_pf_kvar(:,2), Qcomp_pf_kvar(:,3), ...
    MinPF_tested, ...
    'VariableNames', {'Case','Placement','Demand', ...
    'B4P_Vmin_pu','B4P_Lmax_pct','B4P_HCM_pct','B4P_Ploss_kW', ...
    'Vmin_pf097_pu','Vmin_pf098_pu','Vmin_pf099_pu', ...
    'Lmax_pf097_pct','Lmax_pf098_pct','Lmax_pf099_pct', ...
    'Qcomp_pf097_kvar','Qcomp_pf098_kvar','Qcomp_pf099_kvar', ...
    'Min_pf_tested'});

B4PQ_TableQmin = table(B4PQ_Case, B4PQ_Placement, B4PQ_Demand, ...
    B4P_Vmin, cfg.Vthr - B4P_Vmin, B4P_Lmax, B4P_HCM, B4P_Ploss, ...
    Gamma_min, Qcomp_min_kvar, PF_equiv, ...
    B4PQ_Vmin, B4PQ_Lmax, B4PQ_HCM, B4PQ_Ploss, ...
    'VariableNames', {'Case','Placement','Demand', ...
    'B4P_Vmin_pu','Voltage_deficit_pu','B4P_Lmax_pct','B4P_HCM_pct','B4P_Ploss_kW', ...
    'gamma_min','Qcomp_min_kvar','PF_equiv_after_Q_support', ...
    'B4PQ_Vmin_pu','B4PQ_Lmax_pct','B4PQ_HCM_pct','B4PQ_Ploss_kW'});

fprintf('\nB4-PQ PF SENSITIVITY TABLE\n');
disp(B4PQ_TablePF);

fprintf('\nB4-PQ MINIMUM Q SUPPORT TABLE\n');
disp(B4PQ_TableQmin);

writetable(B4PQ_TablePF, fullfile(cfg.outDir, 'Table_B4PQ_pf_sensitivity.csv'));
writetable(B4PQ_TableQmin, fullfile(cfg.outDir, 'Table_B4PQ_min_Q_support.csv'));



%% ========================================================================
% TABLE - BASELINE COMPARISON FOR CRITICAL CASE P2/D4
% ========================================================================

criticalPlacement = placements(strcmp({placements.name}, 'P2'));
criticalDemand    = demands(strcmp({demands.name}, 'D4'));

Table8 = run_baseline_comparison_P2D4(busData0, branchData, cfg, ...
    criticalPlacement.buses, criticalDemand.lambda, Table7, 'P2/D4');

fprintf('\nTABLE 8: MULTI-BASELINE COMPARISON UNDER P2/D4\n');
fprintf('------------------------------------------------------------\n');
disp(Table8);
writetable(Table8, fullfile(cfg.outDir, 'Table8_baseline_comparison_P2D4.csv'));

%% ========================================================================
%  EXPORT EXCEL
% ========================================================================

xlsxName = fullfile(cfg.outDir, 'Section5_BESS_Results_From_MATLAB.xlsx');

try
    writetable(TableV, xlsxName, 'Sheet', 'TableV_NoBESS');
    writetable(Table6, xlsxName, 'Sheet', 'Table6_PostBESS');
    writetable(Table7, xlsxName, 'Sheet', 'Table7_BusLevel');
    writetable(Table7_D4, xlsxName, 'Sheet', 'Table7_D4');
    writetable(Table8, xlsxName, 'Sheet', 'Table8_Baselines');
    writetable(Table9_Offpeak, xlsxName, 'Sheet', 'Table9_Offpeak');
    if exist('B4PQ_TablePF','var')
        writetable(B4PQ_TablePF, xlsxName, 'Sheet', 'B4PQ_PF');
    end
    if exist('B4PQ_TableQmin','var')
        writetable(B4PQ_TableQmin, xlsxName, 'Sheet', 'B4PQ_MinQ');
    end
    fprintf('\nXLSX workbook exported: %s\n', xlsxName);
catch ME
    warning('Could not export XLSX workbook. CSV files were still exported. Details: %s', ME.message);
end

%% ========================================================================
% EXPORT PROFILE MATRICES AND FIGURES
% ========================================================================

export_profiles_and_figures(caseNames, allVBefore, allVAfter, ...
    allLoadingBefore, allLoadingAfter, Table6, placements, demands, cfg);

fprintf('\nDONE. All outputs are saved in folder: %s\n', cfg.outDir);
fprintf('Main files:\n');
fprintf('  - Table6_post_BESS_validation.csv\n');
fprintf('  - Table7_allowable_BESS_bus_level.csv\n');
fprintf('  - Table8_baseline_comparison_P2D4.csv\n');
fprintf('  - Table9_offpeak_charging_feasibility.csv\n');
fprintf('  - Section5_BESS_Results_From_MATLAB.xlsx\n');

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

function busData = build_case_loads(busData0, evcsBuses, Pinst_MW, lambda, qFactorEVCS, bessMW, allowExport)
    % Add EVCS constant-PQ demand and subtract active BESS discharge.
    %
    % BESS convention:
    %   - Active discharge reduces net active load.
    %   - Reactive EVCS demand is still based on full EVCS demand.
    %   - No BESS reactive support is modelled.

    if nargin < 6 || isempty(bessMW)
        bessMW = zeros(33,1);
    end
    if nargin < 7 || isempty(allowExport)
        allowExport = false;
    end

    busData = busData0;

    Pevcs_MW   = Pinst_MW * lambda;
    Qevcs_MVAr = Pevcs_MW * qFactorEVCS;

    for b = evcsBuses
        busData(b,2) = busData(b,2) + Pevcs_MW * 1000;
        busData(b,3) = busData(b,3) + Qevcs_MVAr * 1000;
    end

    for b = 1:33
        if bessMW(b) > 0
            busData(b,2) = busData(b,2) - bessMW(b) * 1000;
        end
    end

    % Prevent unintended net export for co-located BESS.
    % For explicit upstream-BESS sensitivity tests, allowExport can be true.
    if ~allowExport
        for b = 1:33
            busData(b,2) = max(busData(b,2), 0);
        end
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

        Ibus = conj(Sload ./ V);

        % Backward sweep
        Idown = Ibus;
        for l = nl:-1:1
            fromBus = branchData(l,1);
            toBus   = branchData(l,2);

            Ibr(l) = Idown(toBus);
            Idown(fromBus) = Idown(fromBus) + Ibr(l);
        end

        % Forward sweep
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

    Sbr = V(branchData(:,1)) .* conj(Ibr) * cfg.baseMVA;

    info.iterations = iter;
    info.converged  = converged;
    info.z          = z;
    info.baseMVA    = cfg.baseMVA;
end

function metric = compute_metrics(V, Ibr, Sbr, branchData, cfg, info)
    if nargin < 6
        info.iterations = NaN;
        info.converged = true;
    end

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
    metric.Vmin       = Vmin;
    metric.VminBus    = VminBus;
    metric.LmaxPct    = LmaxPct;
    metric.critIdx    = critIdx;
    metric.critFrom   = branchData(critIdx,1);
    metric.critTo     = branchData(critIdx,2);
    metric.HCMpct     = HCMpct;
    metric.Ploss_kW   = Ploss_kW;
    metric.loadingPct = loadingPct;
    metric.iterations = info.iterations;
    metric.converged  = info.converged;
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

function tf = is_metric_feasible(metric, cfg)
    tf = metric.converged && ...
         metric.Vmin >= cfg.Vthr && ...
         metric.LmaxPct <= cfg.Lthr;
end

function [lambdaBus, P_allow_MW, P_BESS_MW, sizingInfo] = coordinated_bisection_bess( ...
    busData0, branchData, cfg, evcsBuses, demandLambda)

    nb = size(busData0,1);

    P_EVCS_full_MW = zeros(nb,1);
    P_EVCS_full_MW(evcsBuses) = cfg.Pinst_MW * demandLambda;

    lambdaBus = ones(nb,1);
    activeScale = ones(nb,1);

    % Feasibility check with zero active EVCS import, i.e., full active BESS.
    % EVCS reactive demand remains.
    fullBESS_MW = P_EVCS_full_MW;
    busDataFullBESS = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, fullBESS_MW);
    [VminB, IminB, SminB, infoMinB] = bfs_power_flow(busDataFullBESS, branchData, cfg);
    metricFullBESS = compute_metrics(VminB, IminB, SminB, branchData, cfg, infoMinB);

    if ~is_metric_feasible(metricFullBESS, cfg)
        warning(['Even full active-power BESS compensation is infeasible. ' ...
                 'This indicates that reactive demand, voltage threshold, or branch ratings may be binding.']);
    end

   outer = 0;
    bisectionSweeps = 0;

    while outer < cfg.maxOuterBisection
        outer = outer + 1;

        P_feeder_EVCS_MW = P_EVCS_full_MW .* activeScale;
        bessMW = P_EVCS_full_MW - P_feeder_EVCS_MW;

        busDataTrial = build_case_loads(busData0, evcsBuses, ...
            cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, bessMW);
        [V, Ibr, Sbr, info] = bfs_power_flow(busDataTrial, branchData, cfg);
        metric = compute_metrics(V, Ibr, Sbr, branchData, cfg, info);

        if is_metric_feasible(metric, cfg)
            break;
        end

        bisectionSweeps = bisectionSweeps + 1;

        % Process larger charging buses first. In the present test cases the
        % per-bus EVCS rating is equal, so this preserves the listed order;
        % the sorting is kept for extensibility to unequal EVCS capacities.
        [~, idxSort] = sort(P_EVCS_full_MW(evcsBuses), 'descend');
        orderedBuses = evcsBuses(idxSort);

        scaleBefore = activeScale;

        for kk = 1:numel(orderedBuses)
            j = orderedBuses(kk);

            lamL = 0;
            lamU = activeScale(j);

            while abs(lamU - lamL) > cfg.bisectionTol
                lamM = 0.5 * (lamL + lamU);

                trialScale = activeScale;
                trialScale(j) = lamM;

                P_feeder_trial_MW = P_EVCS_full_MW .* trialScale;
                bessTrialMW = P_EVCS_full_MW - P_feeder_trial_MW;

                busDataBi = build_case_loads(busData0, evcsBuses, ...
                    cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, bessTrialMW);
                [Vbi, Ibi, Sbi, infoBi] = bfs_power_flow(busDataBi, branchData, cfg);
                metricBi = compute_metrics(Vbi, Ibi, Sbi, branchData, cfg, infoBi);

                if is_metric_feasible(metricBi, cfg)
                    lamL = lamM;
                else
                    lamU = lamM;
                end
            end

            activeScale(j) = lamL;
        end

        if max(abs(activeScale - scaleBefore)) < cfg.bisectionTol
            % No meaningful improvement; stop to avoid endless looping.
            break;
        end
    end

    lambdaBus = activeScale;
    P_allow_MW = P_EVCS_full_MW .* lambdaBus;
    P_BESS_MW = max(0, P_EVCS_full_MW - P_allow_MW);

    % Final full-network verification of the coordinated bisection result.
    busDataFinal = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, P_BESS_MW);
    [Vf, If, Sf, infoF] = bfs_power_flow(busDataFinal, branchData, cfg);
    metricFinal = compute_metrics(Vf, If, Sf, branchData, cfg, infoF);
    finalFeasible = is_metric_feasible(metricFinal, cfg);

    if outer >= cfg.maxOuterBisection && ~finalFeasible
        warning('coordinated_bisection: outer loop reached max iterations (%d) for demand lambda = %.3f; final solution is still infeasible.', ...
            cfg.maxOuterBisection, demandLambda);
    end

    sizingInfo.outerIterations = outer;
    sizingInfo.bisectionSweeps = bisectionSweeps;
    sizingInfo.correctionPassesAfterInitial = max(0, bisectionSweeps - 1);
    sizingInfo.finalFeasible = finalFeasible;
    sizingInfo.finalMetric = metricFinal;
end

function [metricOp, PchBus_MW, PchTotal_MW, offpeakInfo] = run_offpeak_charging_check(busData0, branchData, cfg, P_BESS_MW)
    % Off-peak recharge BFS verification with automatic charging curtailment.
    %
    % The target recharge power is derived from the energy removed during the
    % EVCS peak window. If this target recharge creates a voltage or thermal
    % violation, a scalar bisection search curtails the charging power to the
    % maximum feasible off-peak value. This matches the manuscript statement
    % that off-peak charging is verified and curtailed if necessary.

    nb = size(busData0,1);
    offpeakInfo.PchTarget_MW = 0;
    offpeakInfo.curtailmentFactor = 1;
    offpeakInfo.TchgRequired_h = 0;
    offpeakInfo.rechargeWithinWindow = true;

    if sum(P_BESS_MW) <= eps
        PchBus_MW = zeros(nb,1);
        PchTotal_MW = 0;
        metricOp = eval_offpeak_metric(busData0, branchData, cfg, PchBus_MW);
        return;
    end

    % Battery energy withdrawn during the EVCS peak period.
    E_batt_req_MWh_bus = P_BESS_MW(:) * cfg.Tdis_h / cfg.etaDis;

    % Target grid-side active charging power required to restore that energy
    % over the available off-peak charging window.
    PchBus_target_MW = E_batt_req_MWh_bus / (cfg.etaCh * cfg.Tchg_h);
    offpeakInfo.PchTarget_MW = sum(PchBus_target_MW);

    metricTarget = eval_offpeak_metric(busData0, branchData, cfg, PchBus_target_MW);

    if is_metric_feasible(metricTarget, cfg)
        PchBus_MW = PchBus_target_MW;
        PchTotal_MW = sum(PchBus_MW);
        metricOp = metricTarget;
        offpeakInfo.curtailmentFactor = 1;
        offpeakInfo.TchgRequired_h = cfg.Tchg_h;
        offpeakInfo.rechargeWithinWindow = true;
        return;
    end

    % If target recharge is infeasible, curtail the recharge power to the
    % maximum feasible scalar fraction of the target vector.
    lamL = 0;
    lamU = 1;
    metricBest = eval_offpeak_metric(busData0, branchData, cfg, zeros(nb,1));

    if ~is_metric_feasible(metricBest, cfg)
        % This should not occur because the base case was already feasible,
        % but keep the logic explicit for robustness.
        PchBus_MW = zeros(nb,1);
        PchTotal_MW = 0;
        metricOp = metricBest;
        offpeakInfo.curtailmentFactor = 0;
        offpeakInfo.TchgRequired_h = Inf;
        offpeakInfo.rechargeWithinWindow = false;
        warning('Off-peak base case is infeasible even with zero BESS recharge.');
        return;
    end

    while abs(lamU - lamL) > cfg.bisectionTol
        lamM = 0.5 * (lamL + lamU);
        metricM = eval_offpeak_metric(busData0, branchData, cfg, lamM * PchBus_target_MW);
        if is_metric_feasible(metricM, cfg)
            lamL = lamM;
            metricBest = metricM;
        else
            lamU = lamM;
        end
    end

    PchBus_MW = lamL * PchBus_target_MW;
    PchTotal_MW = sum(PchBus_MW);
    metricOp = metricBest;

    offpeakInfo.curtailmentFactor = lamL;
    if lamL > eps
        offpeakInfo.TchgRequired_h = cfg.Tchg_h / lamL;
    else
        offpeakInfo.TchgRequired_h = Inf;
    end
    offpeakInfo.rechargeWithinWindow = offpeakInfo.TchgRequired_h <= cfg.Tchg_h + 1e-9;

    warning('Off-peak recharge target was infeasible and has been curtailed to %.2f%% of the target charging power. Required recharge duration becomes %.2f h.', ...
        lamL*100, offpeakInfo.TchgRequired_h);
end

function metricOp = eval_offpeak_metric(busData0, branchData, cfg, PchBus_MW)
    % Evaluate off-peak BESS recharge as additional active load.
    nb = size(busData0,1);
    busDataOffpeak = busData0;
    QchBus_MVAr = PchBus_MW * cfg.qFactorBESSCharge;

    for b = 1:nb
        if PchBus_MW(b) > 0
            busDataOffpeak(b,2) = busDataOffpeak(b,2) + PchBus_MW(b) * 1000;
            busDataOffpeak(b,3) = busDataOffpeak(b,3) + QchBus_MVAr(b) * 1000;
        end
    end

    [Vop, Ibrop, Sbrop, infoop] = bfs_power_flow(busDataOffpeak, branchData, cfg);
    metricOp = compute_metrics(Vop, Ibrop, Sbrop, branchData, cfg, infoop);
end

function E_MWh = compute_energy_rating_MWh(P_BESS_total_MW, cfg)
    % Simple energy rating using discharge duration and SoC window.
    % Required discharge energy = P * T / eta_dis.
    E_req_MWh = P_BESS_total_MW * cfg.Tdis_h / cfg.etaDis;
    E_MWh = E_req_MWh / max(cfg.SoCmax - cfg.SoCmin, eps);
end

function TableMetric = build_metric_table(caseNames, placementCol, demandCol, demandLambda, rhoCol_pct, metrics, cfg, label)
    nCases = numel(caseNames);

    % Force metric arrays to column vectors.  This avoids table row-mismatch
    % errors when metrics is already an nCases-by-1 struct array.
    Vmin_pu      = arrayfun(@(m)m.Vmin, metrics);      Vmin_pu    = Vmin_pu(:);
    Vmin_bus     = arrayfun(@(m)m.VminBus, metrics);   Vmin_bus   = Vmin_bus(:);
    Lmax_pct     = arrayfun(@(m)m.LmaxPct, metrics);   Lmax_pct   = Lmax_pct(:);
    HCM_pct      = arrayfun(@(m)m.HCMpct, metrics);    HCM_pct    = HCM_pct(:);
    Ploss_kW     = arrayfun(@(m)m.Ploss_kW, metrics);  Ploss_kW   = Ploss_kW(:);
    Iterations   = arrayfun(@(m)m.iterations, metrics);Iterations = Iterations(:);
    Converged    = arrayfun(@(m)m.converged, metrics); Converged  = Converged(:);

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

    TableMetric = table(caseNames(:), placementCol(:), demandCol(:), demandLambda(:), rhoCol_pct(:), ...
        Vmin_pu, Vmin_bus, Lmax_pct, criticalBranch, HCM_pct, Ploss_kW, ...
        Iterations, Converged, status, repmat(string(label), nCases, 1), ...
        'VariableNames', {'Case','Placement','Demand','lambda','rho_pct', ...
        'Vmin_pu','Vmin_bus','Lmax_pct','Critical_branch','HCM_pct', ...
        'Ploss_kW','Iterations','Converged','Status','Metric_set'});
end

function Table8 = run_baseline_comparison_P2D4(busData0, branchData, cfg, evcsBuses, demandLambda, Table7, caseName)

    methods = ["B0_No_BESS"; "B1_Slack_BESS"; "B1b_Bus2_BESS_Sensitivity"; ...
               "B2_Fixed_20pct"; "B3_Proposed"];
    nMethods = numel(methods);

    Vmin_pu = zeros(nMethods,1);
    Lmax_pct = zeros(nMethods,1);
    HCM_pct = zeros(nMethods,1);
    Ploss_kW = zeros(nMethods,1);
    PBESS_total_kW = zeros(nMethods,1);
    Feasible = false(nMethods,1);
    Notes = strings(nMethods,1);

    P_EVCS_full_MW = zeros(33,1);
    P_EVCS_full_MW(evcsBuses) = cfg.Pinst_MW * demandLambda;

    % B0: no BESS
    bessMW_B0 = zeros(33,1);
    metricB0 = run_metric_for_bess(busData0, branchData, cfg, evcsBuses, demandLambda, bessMW_B0, false);

    % B3 proposed: read from Table7
    idxRows = strcmp(Table7.Case, caseName);
    bessMW_B3 = zeros(33,1);
    for r = find(idxRows).'
        bessMW_B3(Table7.Bus(r)) = Table7.P_BESS_kW(r) / 1000;
    end
    metricB3 = run_metric_for_bess(busData0, branchData, cfg, evcsBuses, demandLambda, bessMW_B3, false);

    % B1: slack-bus BESS with the same total power as B3.
    % In this BFS formulation, Bus 1 is an ideal voltage source. An active-power
    % injection at the slack bus reduces apparent source import but does not
    % alter the downstream constant-PQ load currents that drive feeder branch
    % loadings and voltage drops. Consequently, feeder-side metrics remain
    % identical to B0. This is reported deliberately to show why centralized
    % upstream storage cannot selectively relieve downstream EVCS congestion.
    metricB1 = metricB0;
    PBESS_B1_kW = sum(bessMW_B3) * 1000;

    % B1b: upstream non-slack sensitivity. The same total BESS power is placed
    % at Bus 2 and export is allowed. This non-trivial sensitivity tests whether
    % an upstream, near-source storage unit can relieve the critical downstream
    % branches. It typically improves source-side flow but cannot target local
    % downstream overloads as effectively as co-located BESS.
    bessMW_B1b = zeros(33,1);
    bessMW_B1b(2) = sum(bessMW_B3);
    metricB1b = run_metric_for_bess(busData0, branchData, cfg, evcsBuses, demandLambda, bessMW_B1b, true);

    % B2: fixed 20% local BESS at each EVCS bus
    bessMW_B2 = zeros(33,1);
    bessMW_B2(evcsBuses) = cfg.fixedBessFraction * P_EVCS_full_MW(evcsBuses);
    metricB2 = run_metric_for_bess(busData0, branchData, cfg, evcsBuses, demandLambda, bessMW_B2, false);

    metricList = [metricB0, metricB1, metricB1b, metricB2, metricB3];
    bessList_kW = [0; PBESS_B1_kW; sum(bessMW_B1b)*1000; sum(bessMW_B2)*1000; sum(bessMW_B3)*1000];

    for k = 1:nMethods
        Vmin_pu(k) = metricList(k).Vmin;
        Lmax_pct(k) = metricList(k).LmaxPct;
        HCM_pct(k) = metricList(k).HCMpct;
        Ploss_kW(k) = metricList(k).Ploss_kW;
        PBESS_total_kW(k) = bessList_kW(k);
        Feasible(k) = is_metric_feasible(metricList(k), cfg);
    end

    Notes(1) = "Unmitigated EVCS case.";
    Notes(2) = "Same total BESS as proposed, injected at ideal slack; feeder metrics unchanged by construction.";
    Notes(3) = "Same total BESS as proposed, placed at Bus 2 with export allowed; upstream sensitivity test.";
    Notes(4) = "Local BESS equal to 20% of EVCS demand at each EVCS bus.";
    Notes(5) = "Co-located feeder-constrained BESS from allowable-injection search.";

    Table8 = table(methods, Vmin_pu, Lmax_pct, HCM_pct, Ploss_kW, ...
        PBESS_total_kW, Feasible, Notes, ...
        'VariableNames', {'Baseline','Vmin_pu','Lmax_pct','HCM_pct','Ploss_kW', ...
        'PBESS_total_kW','All_constraints_restored','Notes'});
end

function metric = run_metric_for_bess(busData0, branchData, cfg, evcsBuses, demandLambda, bessMW, allowExport)
    if nargin < 7 || isempty(allowExport)
        allowExport = false;
    end
    busData = build_case_loads(busData0, evcsBuses, ...
        cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, bessMW, allowExport);
    [V, Ibr, Sbr, info] = bfs_power_flow(busData, branchData, cfg);
    metric = compute_metrics(V, Ibr, Sbr, branchData, cfg, info);
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

    fprintf('%-8s: Vmin = %.5f p.u. at Bus %2d | Lmax = %7.2f%% at Branch %2d-%2d | HCM = %7.2f%% | Ploss = %8.3f kW | Iter = %2d%s%s\n', ...
        caseName, m.Vmin, m.VminBus, m.LmaxPct, m.critFrom, m.critTo, ...
        m.HCMpct, m.Ploss_kW, m.iterations, vFlag, lFlag);
end

function labels = make_branch_labels(branchData)
    % Reserved for figure/table annotation. Not required by the main workflow,
    % but kept here for reproducibility if branch labels are needed later.
    labels = strings(size(branchData,1),1);
    for k = 1:size(branchData,1)
        labels(k) = sprintf('%d-%d', branchData(k,1), branchData(k,2));
    end
end

function export_profiles_and_figures(caseNames, allVBefore, allVAfter, ...
    allLoadingBefore, allLoadingAfter, Table6, placements, demands, cfg)

    % Export voltage profiles
    voltageBefore = array2table([(1:33)', allVBefore], ...
        'VariableNames', [{'Bus'}, matlab.lang.makeValidName(caseNames')]);
    writetable(voltageBefore, fullfile(cfg.outDir, 'Voltage_profiles_before_BESS.csv'));

    voltageAfter = array2table([(1:33)', allVAfter], ...
        'VariableNames', [{'Bus'}, matlab.lang.makeValidName(caseNames')]);
    writetable(voltageAfter, fullfile(cfg.outDir, 'Voltage_profiles_after_BESS.csv'));

    % Export loading profiles
    branchNo = (1:32)';
    branchLoadingBefore = array2table([branchNo, allLoadingBefore], ...
        'VariableNames', [{'BranchNo'}, matlab.lang.makeValidName(caseNames')]);
    writetable(branchLoadingBefore, fullfile(cfg.outDir, 'Branch_loading_before_BESS.csv'));

    branchLoadingAfter = array2table([branchNo, allLoadingAfter], ...
        'VariableNames', [{'BranchNo'}, matlab.lang.makeValidName(caseNames')]);
    writetable(branchLoadingAfter, fullfile(cfg.outDir, 'Branch_loading_after_BESS.csv'));

    % Fig. S5-1: before/after Vmin and Lmax by case
    fig = figure('Name','Section5 before-after validation','Color','w');
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(1:height(Table6), Table6.Vmin_before_pu, 'o-', 'LineWidth', 1.2); hold on;
    plot(1:height(Table6), Table6.Vmin_after_pu, 's-', 'LineWidth', 1.2);
    yline(cfg.Vthr, '--', sprintf('V_{thr}=%.2f', cfg.Vthr));
    grid on; box on;
    xticks(1:height(Table6)); xticklabels(Table6.Case); xtickangle(45);
    ylabel('V_{min} (p.u.)');
    legend({'Before BESS','After BESS'}, 'Location','best');

    nexttile;
    plot(1:height(Table6), Table6.Lmax_before_pct, 'o-', 'LineWidth', 1.2); hold on;
    plot(1:height(Table6), Table6.Lmax_after_pct, 's-', 'LineWidth', 1.2);
    yline(cfg.Lthr, '--', sprintf('L_{thr}=%.0f%%', cfg.Lthr));
    grid on; box on;
    xticks(1:height(Table6)); xticklabels(Table6.Case); xtickangle(45);
    ylabel('L_{max} (%)');
    legend({'Before BESS','After BESS'}, 'Location','best');

    exportgraphics(fig, fullfile(cfg.outDir, 'Fig6_before_after_validation.png'), 'Resolution', 300);

    % Fig. S5-2: total BESS power by case
    fig = figure('Name','Total BESS power by case','Color','w');
    bar(Table6.PBESS_total_kW);
    grid on; box on;
    xticks(1:height(Table6)); xticklabels(Table6.Case); xtickangle(45);
    ylabel('Total BESS power (kW)');
    title('Proposed BESS power requirement');
    exportgraphics(fig, fullfile(cfg.outDir, 'Fig7_total_BESS_power_by_case.png'), 'Resolution', 300);

    % Fig. S5-3: D4 branch loading before/after for P1 and P2
    idxP1D4 = find(strcmp(caseNames,'P1/D4'));
    idxP2D4 = find(strcmp(caseNames,'P2/D4'));

    if ~isempty(idxP1D4) && ~isempty(idxP2D4)
        fig = figure('Name','D4 branch loading before-after','Color','w');
        tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

        nexttile;
        plot(1:32, allLoadingBefore(:,idxP1D4), 'o-', 'LineWidth', 1.1); hold on;
        plot(1:32, allLoadingAfter(:,idxP1D4), 's-', 'LineWidth', 1.1);
        yline(cfg.Lthr, '--', sprintf('L_{thr}=%.0f%%', cfg.Lthr));
        grid on; box on;
        xlabel('Branch number'); ylabel('Loading (%)'); title('P1/D4');
        legend({'Before BESS','After BESS'}, 'Location','best');

        nexttile;
        plot(1:32, allLoadingBefore(:,idxP2D4), 'o-', 'LineWidth', 1.1); hold on;
        plot(1:32, allLoadingAfter(:,idxP2D4), 's-', 'LineWidth', 1.1);
        yline(cfg.Lthr, '--', sprintf('L_{thr}=%.0f%%', cfg.Lthr));
        grid on; box on;
        xlabel('Branch number'); ylabel('Loading (%)'); title('P2/D4');
        legend({'Before BESS','After BESS'}, 'Location','best');

        exportgraphics(fig, fullfile(cfg.outDir, 'Fig8_D4_branch_loading_before_after.png'), 'Resolution', 300);
    end
end
