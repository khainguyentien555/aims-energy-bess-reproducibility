%% run_baseline_assessment_for_repo.m
% GitHub packaging helper. No new algorithm is introduced.
% Replays all eight no-BESS baseline cases using the production BFS settings
% used for the paper-facing baseline values and exports machine-readable CSVs.
clear; clc;

cfg.baseMVA = 100;
cfg.baseKV = 12.66;
cfg.Vslack = 1.05;
cfg.Vthr = 0.95;
cfg.Lthr = 100;
cfg.Smax_branch = [6;5;4;4;3.5;3.5;3;3;3;3;2.5;2.5;2.5;2.5;2;2;2;4;3.5;3;3;3.5;3;2.5;3.5;3;2.5;2.5;2.5;2;2;2];
cfg.Pinst_MW = 0.15;
cfg.pfEVCS = 0.95;
cfg.qFactorEVCS = tan(acos(cfg.pfEVCS));
cfg.tol = 1e-5;
cfg.maxIter = 50;

[busData0, branchData] = ieee33_data();
P1 = [6 10 14 18 22 26];
P2 = [14 16 17 18 30 33];
defs = {'P1/D1',P1,0.6;'P1/D2',P1,1.0;'P1/D3',P1,1.3;'P1/D4',P1,1.6; ...
        'P2/D1',P2,0.6;'P2/D2',P2,1.0;'P2/D3',P2,1.3;'P2/D4',P2,1.6};

Rows = {};
Vprof = zeros(33,size(defs,1));
Lprof = zeros(32,size(defs,1));
for k = 1:size(defs,1)
    name=defs{k,1}; ev=defs{k,2}; lam=defs{k,3};
    bd = build_case_loads(busData0,ev,cfg.Pinst_MW,lam,cfg.qFactorEVCS,zeros(33,1),false);
    [V,I,S,info]=bfs_power_flow(bd,branchData,cfg);
    m=compute_metrics(V,I,S,branchData,cfg,info);
    Rows(end+1,:)={string(name),m.Vmin,m.VminBus,m.LmaxPct,sprintf('%d-%d',m.critFrom,m.critTo),m.HCMpct,m.Ploss_kW,info.iterations,info.converged}; %#ok<SAGROW>
    Vprof(:,k)=abs(V);
    Lprof(:,k)=m.loadingPct;
end
T=cell2table(Rows,'VariableNames',{'Case','Vmin_pu','Vmin_bus','Lmax_pct','critical_branch','HCM_pct','Ploss_kW','BFS_iterations','Converged'});
writetable(T,'baseline_metrics_repo.csv');
Tv=array2table([(1:33).' Vprof]);
varNamesV = ["Bus", matlab.lang.makeValidName(string(defs(:,1).'))];
Tv.Properties.VariableNames = cellstr(varNamesV);
writetable(Tv,'baseline_voltage_profiles_repo.csv');
Tl=array2table([(1:32).' Lprof]);
varNamesL = ["BranchNo", matlab.lang.makeValidName(string(defs(:,1).'))];
Tl.Properties.VariableNames = cellstr(varNamesL);
writetable(Tl,'baseline_branch_loading_repo.csv');
fprintf('Baseline helper replay complete.
');
