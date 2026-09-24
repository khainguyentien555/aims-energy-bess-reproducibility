function results = centralized_thermal_B4P(busData0, branchData, cfg, caseList)
% CENTRALIZED_THERMAL_B4P
% Revised B4-P:
% centralized nonlinear optimization with BFS power-flow evaluation
% in the nonlinear constraint loop; THERMAL-ONLY sizing.
%
%   minimize   sum_j P_j^BESS
%   subject to L_l(P^BESS) <= 100% for every branch
%              0 <= P_j^BESS <= P_j^EVCS
%
% Voltage is intentionally NOT part of B4-P.
% Residual voltage is handled later in B4-PQ.

if ~isfield(cfg,'Pinst_MW'),       cfg.Pinst_MW = 0.15; end
if ~isfield(cfg,'qFactorEVCS'),    cfg.qFactorEVCS = tan(acos(0.95)); end
if ~isfield(cfg,'Lthr'),           cfg.Lthr = 100; end
if ~isfield(cfg,'tauL_pct'),       cfg.tauL_pct = 1e-6; end
if ~isfield(cfg,'nStarts'),        cfg.nStarts = 16; end
if ~isfield(cfg,'fminconConstrTol'), cfg.fminconConstrTol = 1e-9; end
if ~isfield(cfg,'fminconOptTol'),  cfg.fminconOptTol = 1e-9; end
if ~isfield(cfg,'fminconStepTol'), cfg.fminconStepTol = 1e-12; end

Lthr   = cfg.Lthr;
nStarts = cfg.nStarts;
rng(1,'twister');

opts = optimoptions('fmincon', ...
    'Algorithm','sqp', ...
    'Display','off', ...
    'SpecifyObjectiveGradient',true, ...
    'ConstraintTolerance',cfg.fminconConstrTol, ...
    'OptimalityTolerance',cfg.fminconOptTol, ...
    'StepTolerance',cfg.fminconStepTol, ...
    'MaxFunctionEvaluations',5000, ...
    'MaxIterations',1000);

results = struct([]);

for ci = 1:numel(caseList)
    C   = caseList(ci);
    ev  = C.evcsBuses(:).';
    nE  = numel(ev);
    Pev = cfg.Pinst_MW * C.lambda;
    lb  = zeros(nE,1);
    ub  = Pev*ones(nE,1);

    % Thermal pre-screen with zero BESS.
    m0 = eval_alloc(zeros(nE,1), ev, C.lambda, busData0, branchData, cfg);
    if ~m0.converged
        error('BFS did not converge during no-BESS pre-screen for %s.', C.name);
    end

    if m0.LmaxPct <= Lthr + cfg.tauL_pct
        e0 = struct('exitflag',NaN,'firstorderopt',NaN,'iterations',0, ...
                    'funcCount',0,'constrviolation',NaN);
        results = append_result(results, C, zeros(nE,1), 0.0, m0, e0, ...
            m0.LmaxPct-Lthr, 0.0, 0.0, 0, ...
            'THERMALLY FEASIBLE WITHOUT STORAGE', nan(nStarts,1), nan(nStarts,nE));
        continue;
    end

    objs = nan(nStarts,1);
    Xs   = nan(nStarts,nE);
    exitInfo = repmat(struct('exitflag',NaN,'firstorderopt',NaN,'iterations',NaN, ...
                             'funcCount',NaN,'constrviolation',NaN), nStarts, 1);

    for s = 1:nStarts
        if s == 1
            x0 = ub;
        elseif s == 2
            x0 = 0.5*ub;
        else
            x0 = ub(:).*rand(nE,1);
        end

        [x,~,ef,out] = fmincon(@objfun, x0, [],[],[],[], lb, ub, ...
            @(x) nlcon(x, ev, C.lambda, busData0, branchData, cfg, Lthr), opts);

        mm = eval_alloc(x, ev, C.lambda, busData0, branchData, cfg);

        constrviol = NaN;
        if isfield(out,'constrviolation')
            constrviol = out.constrviolation;
        end
        fcount = NaN;
        if isfield(out,'funcCount')
            fcount = out.funcCount;
        end

        exitInfo(s) = struct('exitflag',ef, ...
            'firstorderopt',out.firstorderopt, ...
            'iterations',out.iterations, ...
            'funcCount',fcount, ...
            'constrviolation',constrviol);

        % Canonical starts are accepted only when fmincon reports success
        % AND the decoupled physical replay satisfies the declared tolerances.
        if ef > 0 && mm.converged && mm.LmaxPct <= Lthr + cfg.tauL_pct
            objs(s) = sum(x);
            Xs(s,:) = x(:).';
        end
    end

    valid = ~isnan(objs);
    if ~any(valid)
        error('No successful thermally feasible fmincon solution found for case %s.', C.name);
    end

    validObj = objs(valid);
    Xvalid = Xs(valid,:);
    Ivalid = find(valid);
    [fbest, ib] = min(validObj);
    xbest = Xvalid(ib,:).';
    einfo = exitInfo(Ivalid(ib));

    % Objective spread over all successful feasible starts.
    objSpread_kW = (max(validObj)-min(validObj))*1000;

    % Allocation spread only among starts within 0.1 kW of the best objective.
    nearMask = validObj <= fbest + 1e-4; % MW; 0.1 kW
    near = Xvalid(nearMask,:);
    allocSpread_kW = max(max(near,[],1)-min(near,[],1))*1000;

    % Decoupled post-optimization BFS replay.
    mrep = eval_alloc(xbest, ev, C.lambda, busData0, branchData, cfg);
    maxViol_pct = mrep.LmaxPct - Lthr;

    if ~mrep.converged || maxViol_pct > cfg.tauL_pct
        error('Best solution failed decoupled BFS replay for %s.', C.name);
    end

    results = append_result(results, C, xbest, fbest, mrep, einfo, ...
        maxViol_pct, objSpread_kW, allocSpread_kW, sum(valid), ...
        'THERMAL RESTORATION REQUIRED', objs, Xs);
end

print_summary(results, cfg);
end

function [f,g] = objfun(x)
f = sum(x);
if nargout > 1
    g = ones(numel(x),1);
end
end

function [c,ceq] = nlcon(x, ev, lambda, busData0, branchData, cfg, Lthr)
m = eval_alloc(x, ev, lambda, busData0, branchData, cfg);
c = m.loadingPct(:) - Lthr;
if ~m.converged
    % Non-converged power flow is never admissible.
    c(:) = max(c(:), 1.0);
end
ceq = [];
end

function m = eval_alloc(x, ev, lambda, busData0, branchData, cfg)
bessMW = zeros(size(busData0,1),1);
bessMW(ev) = x(:);
bd = build_case_loads(busData0, ev, cfg.Pinst_MW, lambda, ...
    cfg.qFactorEVCS, bessMW, false);
[V, Ibr, Sbr, info] = bfs_power_flow(bd, branchData, cfg);
m = compute_metrics(V, Ibr, Sbr, branchData, cfg, info);
end

function results = append_result(results, C, xbest, fbest, mrep, einfo, ...
    maxViol_pct, objSpread_kW, allocSpread_kW, nValidStarts, klass, allObj, allX)

r.name             = C.name;
r.evcsBuses        = C.evcsBuses;
r.lambda           = C.lambda;
r.class            = klass;
r.P_BESS_total_kW  = fbest*1000;
r.alloc_kW         = (xbest(:).')*1000;

r.exitflag         = einfo.exitflag;
r.firstorderopt    = einfo.firstorderopt;
r.iterations       = einfo.iterations;
r.funcCount        = einfo.funcCount;
r.fminconConstrViolation = einfo.constrviolation;

r.loadingResidual_pct = maxViol_pct;
r.BFS_converged    = mrep.converged;
r.BFS_iters        = mrep.iterations;
r.BFS_residual_pu  = mrep.BFSresidual;
r.Vmin             = mrep.Vmin;
r.Lmax_pct         = mrep.LmaxPct;
r.critFrom         = mrep.critFrom;
r.critTo           = mrep.critTo;
r.HCM_pct          = mrep.HCMpct;
r.Ploss_kW         = mrep.Ploss_kW;

r.nValidStarts     = nValidStarts;
r.objSpread_kW     = objSpread_kW;
r.allocSpread_kW   = allocSpread_kW;
r.allObjectives_MW = allObj;
r.allAllocations_MW= allX;

if isempty(results)
    results = r;
else
    results(end+1) = r; %#ok<AGROW>
end
end

function print_summary(results, cfg)
fprintf('\n=== CENTRALIZED THERMAL-ONLY B4-P: MATLAB FREEZE ===\n');
fprintf('BFS tol = %.3e pu | loading feasibility tol = %.3e %%\n', cfg.tol, cfg.tauL_pct);
fprintf('%-7s %10s %13s %12s %11s %10s %10s %10s  %s\n', ...
    'Case','Ptot_kW','Lmax_%','Lmax-100','BFSres','exitflag','nStarts','objSpr_kW','class');

for k = 1:numel(results)
    r = results(k);
    fprintf('%-7s %10.1f %13.9f %12.3e %11.3e %10g %10d %10.3e  %s\n', ...
        r.name, r.P_BESS_total_kW, r.Lmax_pct, r.loadingResidual_pct, ...
        r.BFS_residual_pu, r.exitflag, r.nValidStarts, r.objSpread_kW, r.class);
end

fprintf('\nIndependent Python comparison targets only (DO NOT force a match):\n');
fprintf('P1/D3 ~248.5 | P1/D4 ~510.1 | P2/D2 ~205.3 | P2/D3 ~525.5 | P2/D4 ~855.6 kW\n');
fprintf('A material discrepancy must be diagnosed before downstream analysis.\n');
end
