% Only the published branch-current limits are imported here.
% The source-study DER configuration, 4-MVA source limit, and other operating assumptions are not reproduced.
%% run_external_current_validation.m
% SECOND-REVISION INDEPENDENT BRANCH-CURRENT VALIDATION
%
% External branch-current parameterization:
%   Branches 1-2     : 200 A
%   Branches 3-5     : 150 A
%   Branches 6-7     : 100 A
%   Branches 22-29   : 100 A
%   All others       : 50 A
%
% Published IEEE 33-bus parameterization:
% Sosnowski et al., IEEE SmartGridComm 2024
% DOI: 10.1109/SmartGridComm60555.2024.10738110
%
% IMPORTANT:
% - Current limits are enforced DIRECTLY in amperes.
% - They are NOT converted into author-defined MVA limits.
% - Voltage is not imposed in the active-power sizing check.
% - If no feasible active-only allocation exists, a minimax-current
%   diagnostic is reported rather than forcing a finite BESS size.

clear;
clear functions;
clc;
rehash;

%% ------------------------------------------------------------------------
% Dependency gate
% -------------------------------------------------------------------------
assert(exist('B4P_canonical_freeze.mat','file') == 2, ...
    'B4P_canonical_freeze.mat not found.');
assert(exist('ieee33_data','file') == 2, ...
    'ieee33_data.m not found.');
assert(exist('bfs_power_flow','file') == 2, ...
    'bfs_power_flow.m not found.');
assert(exist('build_case_loads','file') == 2, ...
    'build_case_loads.m not found.');
assert(exist('fmincon','file') == 2, ...
    'Optimization Toolbox / fmincon is required.');

S = load('B4P_canonical_freeze.mat');

assert(isfield(S,'cfg') && isfield(S,'caseList'), ...
    'Canonical freeze must contain cfg and caseList.');

cfg = S.cfg;
caseList = S.caseList;

[busData0, branchData] = ieee33_data();

%% ------------------------------------------------------------------------
% Canonical numerical controls
% -------------------------------------------------------------------------
assert(abs(cfg.baseKV - 12.66) < 1e-12);
assert(abs(cfg.Vslack - 1.05) < 1e-12);

cfg.tol = 1e-12;
cfg.maxIter = 200;

if ~isfield(cfg,'nStarts'), cfg.nStarts = 16; end
if ~isfield(cfg,'fminconConstrTol'), cfg.fminconConstrTol = 1e-9; end
if ~isfield(cfg,'fminconOptTol'), cfg.fminconOptTol = 1e-9; end
if ~isfield(cfg,'fminconStepTol'), cfg.fminconStepTol = 1e-12; end

tauI = 1e-6;     % current-ratio feasibility tolerance
rng(1,'twister');

%% ------------------------------------------------------------------------
% External published current limits
% -------------------------------------------------------------------------
nBranch = size(branchData,1);
assert(nBranch == 32,'Expected 32 branches.');

Imax_A = 50*ones(nBranch,1);

Imax_A(1:2)   = 200;
Imax_A(3:5)   = 150;
Imax_A(6:7)   = 100;
Imax_A(22:29) = 100;

Ibase_A = cfg.baseMVA*1e6/(sqrt(3)*cfg.baseKV*1e3);

Branch = (1:nBranch).';
FromBus = branchData(:,1);
ToBus = branchData(:,2);

Tlimits = table(Branch,FromBus,ToBus,Imax_A);
writetable(Tlimits,'external_current_limits.csv');
if exist('external_current_validation.log','file')
    delete('external_current_validation.log');
end
diary('external_current_validation.log');
%% ------------------------------------------------------------------------
% Logging
% -------------------------------------------------------------------------
diary('external_current_validation.log');
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf('SECOND-REVISION EXTERNAL CURRENT-LIMIT VALIDATION\n');
fprintf('MATLAB: %s\n',version);
fprintf('Base: %.3f MVA, %.3f kV\n',cfg.baseMVA,cfg.baseKV);
fprintf('Vslack = %.6f pu\n',cfg.Vslack);
fprintf('BFS tol = %.3e pu | maxIter = %d\n',cfg.tol,cfg.maxIter);
fprintf('Ibase = %.9f A\n',Ibase_A);
fprintf('============================================================\n\n');

%% ------------------------------------------------------------------------
% GATE 0: Unmodified base feeder
% -------------------------------------------------------------------------
[Vb,Ib,Sb,infoB] = bfs_power_flow(busData0,branchData,cfg);
mBase = current_metric(Vb,Ib,branchData,Imax_A,Ibase_A,infoB);

fprintf('=== GATE 0: UNMODIFIED BASE FEEDER ===\n');
fprintf('Vmin       = %.9f pu\n',mBase.Vmin);
fprintf('Rmax       = %.9f\n',mBase.Rmax);
fprintf('Icrit      = %.6f A\n',mBase.Icrit_A);
fprintf('Ilimit     = %.6f A\n',mBase.Ilimit_A);
fprintf('CritBranch = %d-%d\n',mBase.critFrom,mBase.critTo);
fprintf('BFSres     = %.3e pu\n',mBase.BFSresidual);

baseFeasible = mBase.converged && mBase.Rmax <= 1 + tauI;

fprintf('Base current-feasible = %d\n\n',baseFeasible);

Tbase = table( ...
    mBase.Vmin,mBase.Rmax,mBase.Icrit_A,mBase.Ilimit_A, ...
    mBase.critFrom,mBase.critTo,mBase.BFSresidual,baseFeasible, ...
    'VariableNames',{'Vmin_pu','Rmax','Icrit_A','Ilimit_A', ...
    'CritFrom','CritTo','BFS_residual_pu','Current_feasible'});

writetable(Tbase,'external_current_base_check.csv');

%% ------------------------------------------------------------------------
% GATES 1-3: 8 EVCS cases
% -------------------------------------------------------------------------
Rows = {};
BusRows = {};

for ci = 1:numel(caseList)

    C = caseList(ci);
    ev = C.evcsBuses(:).';
    nE = numel(ev);

    Pev = cfg.Pinst_MW*C.lambda;
    ub = Pev*ones(nE,1);

    fprintf('\n============================================================\n');
    fprintf('CASE %s\n',C.name);
    fprintf('============================================================\n');

    % ---------------------------------------------------------------
    % GATE 1A: No BESS
    % ---------------------------------------------------------------
    m0 = eval_alloc_current( ...
        zeros(nE,1),ev,C.lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

    fprintf('No BESS     : Rmax=%.9f | branch=%d-%d | I=%.4f/%.1f A\n', ...
        m0.Rmax,m0.critFrom,m0.critTo,m0.Icrit_A,m0.Ilimit_A);

    % ---------------------------------------------------------------
    % GATE 1B: Full active compensation diagnostic
    % ---------------------------------------------------------------
    mf = eval_alloc_current( ...
        ub,ev,C.lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

    fprintf('Full comp   : Rmax=%.9f | branch=%d-%d | I=%.4f/%.1f A\n', ...
        mf.Rmax,mf.critFrom,mf.critTo,mf.Icrit_A,mf.Ilimit_A);

    % ---------------------------------------------------------------
    % GATE 2: Minimax current-ratio optimization
    % Finds the smallest achievable maximum branch-current ratio
    % over the admissible active-only BESS allocation.
    % ---------------------------------------------------------------
    MM = solve_minimax_current( ...
        ev,C.lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

    fprintf(['Minimax      : Rmax=%.9f | Pdiag=%.6f kW | ' ...
             'branch=%d-%d | validStarts=%d\n'], ...
        MM.Rmax,sum(MM.xbest)*1000, ...
        MM.metric.critFrom,MM.metric.critTo,MM.nValidStarts);

    currentFeasible = MM.Rmax <= 1 + tauI;

    % ---------------------------------------------------------------
    % GATE 3: If possible, solve minimum-BESS current-constrained sizing.
    % Otherwise report network-remediation / active-only infeasibility.
    % ---------------------------------------------------------------
    if currentFeasible

        SZ = solve_minimum_bess_current( ...
            MM.xbest,ev,C.lambda,busData0,branchData,cfg, ...
            Imax_A,Ibase_A,tauI);

        Psize_kW = sum(SZ.xbest)*1000;
        mSelected = SZ.metric;
        nValidSizing = SZ.nValidStarts;

        status = "CURRENT-FEASIBLE WITH ACTIVE-ONLY BESS";

        fprintf(['Sizing       : P=%.6f kW | Rmax=%.9f | ' ...
                 'branch=%d-%d | validStarts=%d\n'], ...
            Psize_kW,mSelected.Rmax, ...
            mSelected.critFrom,mSelected.critTo,nValidSizing);

        xSizing = SZ.xbest;

    else

        Psize_kW = NaN;
        mSelected = MM.metric;
        nValidSizing = 0;

        status = "ACTIVE-ONLY CURRENT FEASIBILITY NOT ACHIEVABLE";
        xSizing = nan(nE,1);

        fprintf(['Verdict      : ACTIVE-ONLY CURRENT FEASIBILITY ' ...
                 'NOT ACHIEVABLE within 0 <= P_BESS <= P_EVCS.\n']);
    end

    fprintf('Fresh replay : Rmax=%.9f | Vmin=%.9f | BFSres=%.3e\n', ...
        mSelected.Rmax,mSelected.Vmin,mSelected.BFSresidual);

    Rows(end+1,:) = { ...
        string(C.name), ...
        m0.Rmax, ...
        sprintf('%d-%d',m0.critFrom,m0.critTo), ...
        m0.Icrit_A, ...
        mf.Rmax, ...
        sprintf('%d-%d',mf.critFrom,mf.critTo), ...
        MM.Rmax, ...
        sum(MM.xbest)*1000, ...
        sprintf('%d-%d',MM.metric.critFrom,MM.metric.critTo), ...
        currentFeasible, ...
        Psize_kW, ...
        mSelected.Rmax, ...
        sprintf('%d-%d',mSelected.critFrom,mSelected.critTo), ...
        mSelected.Vmin, ...
        mSelected.BFSresidual, ...
        MM.nValidStarts, ...
        nValidSizing, ...
        status}; %#ok<SAGROW>

    for j = 1:nE
        BusRows(end+1,:) = { ...
            string(C.name),ev(j), ...
            MM.xbest(j)*1000, ...
            xSizing(j)*1000}; %#ok<SAGROW>
    end
end

T = cell2table(Rows,'VariableNames',{ ...
    'Case', ...
    'NoBESS_Rmax', ...
    'NoBESS_critical_branch', ...
    'NoBESS_Icrit_A', ...
    'FullComp_Rmax', ...
    'FullComp_critical_branch', ...
    'Minimax_Rmax', ...
    'Minimax_active_BESS_kW', ...
    'Minimax_critical_branch', ...
    'Current_feasible', ...
    'Minimum_BESS_kW_if_feasible', ...
    'Selected_Rmax', ...
    'Selected_critical_branch', ...
    'Selected_Vmin_pu', ...
    'BFS_residual_pu', ...
    'Minimax_valid_starts', ...
    'Sizing_valid_starts', ...
    'Status'});

Tbus = cell2table(BusRows,'VariableNames',{ ...
    'Case','Bus','Minimax_BESS_kW','Sizing_BESS_kW_if_feasible'});

writetable(T,'external_current_validation_summary.csv');
writetable(Tbus,'external_current_validation_perbus.csv');

%% ------------------------------------------------------------------------
% GATE 4: Exact nominal beta-star boundary
% beta_star = Lmax,0 / 100 for the zero-storage state.
% -------------------------------------------------------------------------
BetaRows = {};

fprintf('\n============================================================\n');
fprintf('EXACT ZERO-STORAGE beta_star AUDIT\n');
fprintf('============================================================\n');

for ci = 1:numel(caseList)

    C = caseList(ci);
    ev = C.evcsBuses(:).';

    bessZero = zeros(size(busData0,1),1);

    bd = build_case_loads( ...
        busData0,ev,cfg.Pinst_MW,C.lambda, ...
        cfg.qFactorEVCS,bessZero,false);

    [V,Ibr,Sbr,info] = bfs_power_flow(bd,branchData,cfg);

    if ~info.converged
        error('BFS failed in beta-star audit for %s.',C.name);
    end

    loadingNom_pct = abs(Sbr(:))./cfg.Smax_branch(:)*100;
    [Lmax0,idx] = max(loadingNom_pct);

    beta_star = Lmax0/100;

    req090 = beta_star > 0.90 + 1e-12;
    req100 = beta_star > 1.00 + 1e-12;
    req110 = beta_star > 1.10 + 1e-12;

    fprintf('%-7s | Lmax0=%10.6f%% | beta*=%.6f | %d-%d\n', ...
        C.name,Lmax0,beta_star, ...
        branchData(idx,1),branchData(idx,2));

    BetaRows(end+1,:) = { ...
        string(C.name),Lmax0,beta_star, ...
        sprintf('%d-%d',branchData(idx,1),branchData(idx,2)), ...
        req090,req100,req110}; %#ok<SAGROW>
end

Tbeta = cell2table(BetaRows,'VariableNames',{ ...
    'Case','Lmax0_pct','beta_star','critical_branch', ...
    'Storage_required_at_beta090', ...
    'Storage_required_at_beta100', ...
    'Storage_required_at_beta110'});

writetable(Tbeta,'beta_star_audit.csv');

%% ------------------------------------------------------------------------
% Engineering current-equivalent table for nominal planning limits
% -------------------------------------------------------------------------
Sunique_MVA = sort(unique(cfg.Smax_branch(:)),'descend');
Iequiv_A = Sunique_MVA*1e6/(sqrt(3)*cfg.baseKV*1e3);

Tequiv = table(Sunique_MVA,Iequiv_A, ...
    'VariableNames',{'Planning_limit_MVA','Equivalent_current_A'});

writetable(Tequiv,'nominal_limit_current_equivalents.csv');

%% ------------------------------------------------------------------------
% Save complete evidence
% -------------------------------------------------------------------------
save('external_current_validation.mat', ...
    'T','Tbus','Tbase','Tbeta','Tlimits','Tequiv', ...
    'cfg','caseList','Imax_A','Ibase_A','baseFeasible','-v7.3');

fprintf('\n============================================================\n');
fprintf('FINAL SUMMARY\n');
fprintf('============================================================\n');
disp(T);
fprintf('\nBeta-star audit:\n');
disp(Tbeta);

fprintf('\nSaved:\n');
fprintf('  external_current_limits.csv\n');
fprintf('  external_current_base_check.csv\n');
fprintf('  external_current_validation_summary.csv\n');
fprintf('  external_current_validation_perbus.csv\n');
fprintf('  beta_star_audit.csv\n');
fprintf('  nominal_limit_current_equivalents.csv\n');
fprintf('  external_current_validation.mat\n');
fprintf('  external_current_validation.log\n');

fprintf('\nEXTERNAL CURRENT VALIDATION COMPLETED.\n');

%% ========================================================================
% LOCAL FUNCTIONS
% ========================================================================

function m = eval_alloc_current( ...
    x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A)

    bessMW = zeros(size(busData0,1),1);
    bessMW(ev) = x(:);

    bd = build_case_loads( ...
        busData0,ev,cfg.Pinst_MW,lambda, ...
        cfg.qFactorEVCS,bessMW,false);

    [V,Ibr,~,info] = bfs_power_flow(bd,branchData,cfg);

    m = current_metric(V,Ibr,branchData,Imax_A,Ibase_A,info);
end

function m = current_metric( ...
    V,Ibr,branchData,Imax_A,Ibase_A,info)

    IA = abs(Ibr(:))*Ibase_A;
    ratio = IA./Imax_A(:);

    [Rmax,idx] = max(ratio);

    m.converged = info.converged;
    m.BFSresidual = info.residual;
    m.Vmin = min(abs(V));

    m.I_A = IA;
    m.ratio = ratio;
    m.Rmax = Rmax;

    m.critIdx = idx;
    m.critFrom = branchData(idx,1);
    m.critTo = branchData(idx,2);

    m.Icrit_A = IA(idx);
    m.Ilimit_A = Imax_A(idx);
end

function OUT = solve_minimax_current( ...
    ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A)

    nE = numel(ev);
    Pev = cfg.Pinst_MW*lambda;

    lbx = zeros(nE,1);
    ubx = Pev*ones(nE,1);

    nStarts = cfg.nStarts;

    opts = optimoptions('fmincon', ...
        'Algorithm','sqp', ...
        'Display','off', ...
        'SpecifyObjectiveGradient',true, ...
        'ConstraintTolerance',cfg.fminconConstrTol, ...
        'OptimalityTolerance',cfg.fminconOptTol, ...
        'StepTolerance',cfg.fminconStepTol, ...
        'MaxFunctionEvaluations',5000, ...
        'MaxIterations',1000);

    bestR = Inf;
    xbest = nan(nE,1);
    mbest = [];

    allR = nan(nStarts,1);
    allX = nan(nStarts,nE);

    for s = 1:nStarts

        if s == 1
            x0 = ubx;
        elseif s == 2
            x0 = 0.5*ubx;
        else
            x0 = ubx.*rand(nE,1);
        end

        m0 = eval_alloc_current( ...
            x0,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

        gamma0 = m0.Rmax + 0.05;

        y0 = [x0;gamma0];
        lb = [lbx;0];
        ub = [ubx;10];

        [y,~,ef] = fmincon( ...
            @minimax_objective,y0,[],[],[],[],lb,ub, ...
            @(y) minimax_constraint( ...
                y,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A), ...
            opts);

        x = y(1:nE);

        m = eval_alloc_current( ...
            x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

        if ef > 0 && m.converged
            allR(s) = m.Rmax;
            allX(s,:) = x(:).';

            if m.Rmax < bestR
                bestR = m.Rmax;
                xbest = x;
                mbest = m;
            end
        end
    end

    valid = ~isnan(allR);

    if ~any(valid)
        error('No successful minimax-current solution was obtained.');
    end

    OUT.Rmax = bestR;
    OUT.xbest = xbest;
    OUT.metric = mbest;
    OUT.nValidStarts = sum(valid);
    OUT.Rspread = max(allR(valid))-min(allR(valid));
    OUT.allR = allR;
    OUT.allX = allX;
end

function [f,g] = minimax_objective(y)

    f = y(end);

    if nargout > 1
        g = zeros(numel(y),1);
        g(end) = 1;
    end
end

function [c,ceq] = minimax_constraint( ...
    y,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A)

    x = y(1:end-1);
    gamma = y(end);

    m = eval_alloc_current( ...
        x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

    c = m.ratio(:) - gamma;

    if ~m.converged
        c(:) = max(c(:),1);
    end

    ceq = [];
end

function OUT = solve_minimum_bess_current( ...
    xminimax,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A,tauI)

    nE = numel(ev);
    Pev = cfg.Pinst_MW*lambda;

    lb = zeros(nE,1);
    ub = Pev*ones(nE,1);

    nStarts = cfg.nStarts;

    opts = optimoptions('fmincon', ...
        'Algorithm','sqp', ...
        'Display','off', ...
        'SpecifyObjectiveGradient',true, ...
        'ConstraintTolerance',cfg.fminconConstrTol, ...
        'OptimalityTolerance',cfg.fminconOptTol, ...
        'StepTolerance',cfg.fminconStepTol, ...
        'MaxFunctionEvaluations',5000, ...
        'MaxIterations',1000);

    objs = nan(nStarts,1);
    allX = nan(nStarts,nE);

    bestObj = Inf;
    xbest = nan(nE,1);
    mbest = [];

    for s = 1:nStarts

        if s == 1
            x0 = xminimax;
        elseif s == 2
            x0 = ub;
        elseif s == 3
            x0 = 0.5*(xminimax + ub);
        else
            x0 = ub.*rand(nE,1);
        end

        [x,~,ef] = fmincon( ...
            @sum_objective,x0,[],[],[],[],lb,ub, ...
            @(x) current_constraint( ...
                x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A), ...
            opts);

        m = eval_alloc_current( ...
            x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

        if ef > 0 && m.converged && m.Rmax <= 1 + tauI

            obj = sum(x);

            objs(s) = obj;
            allX(s,:) = x(:).';

            if obj < bestObj
                bestObj = obj;
                xbest = x;
                mbest = m;
            end
        end
    end

    valid = ~isnan(objs);

    if ~any(valid)
        error(['Minimax indicated current feasibility but minimum-BESS ' ...
               'optimization produced no accepted solution.']);
    end

    OUT.xbest = xbest;
    OUT.metric = mbest;
    OUT.nValidStarts = sum(valid);
    OUT.objSpread_kW = ...
        (max(objs(valid))-min(objs(valid)))*1000;
    OUT.allObjectives_MW = objs;
    OUT.allX = allX;
end

function [f,g] = sum_objective(x)

    f = sum(x);

    if nargout > 1
        g = ones(numel(x),1);
    end
end

function [c,ceq] = current_constraint( ...
    x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A)

    m = eval_alloc_current( ...
        x,ev,lambda,busData0,branchData,cfg,Imax_A,Ibase_A);

    c = m.ratio(:) - 1;

    if ~m.converged
        c(:) = max(c(:),1);
    end

    ceq = [];
end