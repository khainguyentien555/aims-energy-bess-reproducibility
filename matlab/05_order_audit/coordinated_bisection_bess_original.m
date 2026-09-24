function [lambdaBus, P_allow_MW, P_BESS_MW, sizingInfo] = coordinated_bisection_bess_original( ...
    busData0, branchData, cfg, evcsBuses, demandLambda)
% Archival standalone copy of the submitted combined V+L sequential mechanics.
    nb = size(busData0,1);
    P_EVCS_full_MW = zeros(nb,1);
    P_EVCS_full_MW(evcsBuses) = cfg.Pinst_MW * demandLambda;
    lambdaBus = ones(nb,1);
    activeScale = ones(nb,1);

    fullBESS_MW = P_EVCS_full_MW;
    busDataFullBESS = build_case_loads(busData0, evcsBuses, cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, fullBESS_MW);
    [VminB, IminB, SminB, infoMinB] = bfs_power_flow(busDataFullBESS, branchData, cfg);
    metricFullBESS = compute_metrics(VminB, IminB, SminB, branchData, cfg, infoMinB);
    if ~combined_feasible(metricFullBESS,cfg)
        warning('Even full active-power BESS compensation is infeasible under original combined criterion.');
    end

    outer = 0; bisectionSweeps = 0;
    while outer < cfg.maxOuterBisection
        outer = outer + 1;
        P_feeder_EVCS_MW = P_EVCS_full_MW .* activeScale;
        bessMW = P_EVCS_full_MW - P_feeder_EVCS_MW;
        busDataTrial = build_case_loads(busData0, evcsBuses, cfg.Pinst_MW, demandLambda, cfg.qFactorEVCS, bessMW);
        [V,Ibr,Sbr,info] = bfs_power_flow(busDataTrial, branchData, cfg);
        metric = compute_metrics(V,Ibr,Sbr,branchData,cfg,info);
        if combined_feasible(metric,cfg), break; end
        bisectionSweeps = bisectionSweeps + 1;
        [~,idxSort] = sort(P_EVCS_full_MW(evcsBuses),'descend');
        orderedBuses = evcsBuses(idxSort);
        scaleBefore = activeScale;
        for kk=1:numel(orderedBuses)
            j=orderedBuses(kk); lamL=0; lamU=activeScale(j);
            while abs(lamU-lamL)>cfg.bisectionTol
                lamM=0.5*(lamL+lamU);
                trialScale=activeScale; trialScale(j)=lamM;
                P_feeder_trial_MW=P_EVCS_full_MW.*trialScale;
                bessTrialMW=P_EVCS_full_MW-P_feeder_trial_MW;
                bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,bessTrialMW);
                [Vbi,Ibi,Sbi,infoBi]=bfs_power_flow(bd,branchData,cfg);
                metricBi=compute_metrics(Vbi,Ibi,Sbi,branchData,cfg,infoBi);
                if combined_feasible(metricBi,cfg), lamL=lamM; else, lamU=lamM; end
            end
            activeScale(j)=lamL;
        end
        if max(abs(activeScale-scaleBefore))<cfg.bisectionTol, break; end
    end

    lambdaBus=activeScale;
    P_allow_MW=P_EVCS_full_MW.*lambdaBus;
    P_BESS_MW=max(0,P_EVCS_full_MW-P_allow_MW);
    bd=build_case_loads(busData0,evcsBuses,cfg.Pinst_MW,demandLambda,cfg.qFactorEVCS,P_BESS_MW);
    [Vf,If,Sf,infoF]=bfs_power_flow(bd,branchData,cfg);
    metricFinal=compute_metrics(Vf,If,Sf,branchData,cfg,infoF);
    sizingInfo.outerIterations=outer;
    sizingInfo.bisectionSweeps=bisectionSweeps;
    sizingInfo.correctionPassesAfterInitial=max(0,bisectionSweeps-1);
    sizingInfo.finalFeasible=combined_feasible(metricFinal,cfg);
    sizingInfo.finalMetric=metricFinal;
end

function tf=combined_feasible(m,cfg)
    tf=m.converged && m.Vmin>=cfg.Vthr && m.LmaxPct<=cfg.Lthr;
end
