function [lambdaBus, P_allow_MW, P_BESS_MW, sizingInfo] = coordinated_bisection_bess_permuted_thermal( ...
    busData0, branchData, cfg, evcsBuses, demandLambda, orderedBuses)
% Thermal-only sequential comparator for revised Eq. (3).
% Mechanics are copied from submitted coordinated_bisection_bess.
% ONLY the feasibility predicate is changed to: converged && Lmax <= Lthr.
% Processing order is supplied explicitly.
    validate_order(evcsBuses,orderedBuses);
    nb=size(busData0,1);
    P_EVCS_full_MW=zeros(nb,1); P_EVCS_full_MW(evcsBuses)=cfg.Pinst_MW*demandLambda;
    activeScale=ones(nb,1);

    fullBESS_MW=P_EVCS_full_MW;
    bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,fullBESS_MW);
    [V,I,S,inf]=bfs_power_flow(bd,branchData,cfg); mfull=compute_metrics(V,I,S,branchData,cfg,inf);
    if ~thermal_feasible(mfull,cfg)
        warning('Full active compensation remains thermally infeasible.');
    end

    outer=0; bisectionSweeps=0;
    while outer<cfg.maxOuterBisection
        outer=outer+1;
        bessMW=P_EVCS_full_MW-P_EVCS_full_MW.*activeScale;
        bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,bessMW);
        [V,I,S,inf]=bfs_power_flow(bd,branchData,cfg); m=compute_metrics(V,I,S,branchData,cfg,inf);
        if thermal_feasible(m,cfg), break; end
        bisectionSweeps=bisectionSweeps+1;
        scaleBefore=activeScale;
        for kk=1:numel(orderedBuses)
            j=orderedBuses(kk); lamL=0; lamU=activeScale(j);
            while abs(lamU-lamL)>cfg.bisectionTol
                lamM=0.5*(lamL+lamU);
                trialScale=activeScale; trialScale(j)=lamM;
                bessTrialMW=P_EVCS_full_MW-P_EVCS_full_MW.*trialScale;
                bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,bessTrialMW);
                [Vb,Ib,Sb,infb]=bfs_power_flow(bd,branchData,cfg); mb=compute_metrics(Vb,Ib,Sb,branchData,cfg,infb);
                if thermal_feasible(mb,cfg), lamL=lamM; else, lamU=lamM; end
            end
            activeScale(j)=lamL;
        end
        if max(abs(activeScale-scaleBefore))<cfg.bisectionTol, break; end
    end

    lambdaBus=activeScale;
    P_allow_MW=P_EVCS_full_MW.*lambdaBus;
    P_BESS_MW=max(0,P_EVCS_full_MW-P_allow_MW);
    bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,P_BESS_MW);
    [Vf,If,Sf,infoF]=bfs_power_flow(bd,branchData,cfg); mf=compute_metrics(Vf,If,Sf,branchData,cfg,infoF);
    sizingInfo.outerIterations=outer; sizingInfo.bisectionSweeps=bisectionSweeps;
    sizingInfo.correctionPassesAfterInitial=max(0,bisectionSweeps-1);
    sizingInfo.finalFeasible=thermal_feasible(mf,cfg); sizingInfo.finalMetric=mf;
end
function tf=thermal_feasible(m,cfg), tf=m.converged && m.LmaxPct<=cfg.Lthr; end
function validate_order(ev,ord)
    if numel(ord)~=numel(ev) || ~isequal(sort(ord(:)),sort(ev(:)))
        error('orderedBuses must be a permutation of evcsBuses.');
    end
end
