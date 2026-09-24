clear; clc;

% ================= USER SWITCH =================
RUN_ORIGINAL_COMBINED = false; % First run: false. Optional provenance run: true.
% =================================================

fprintf('============================================================\n');
fprintf('FINAL 720-ORDER AUDIT — THERMAL-ONLY SEQUENTIAL COMPARATOR\n');
fprintf('============================================================\n');
fprintf('MATLAB: %s\n', version);

% Locate canonical freeze.
freezeCandidates = {fullfile(pwd,'B4P_canonical_freeze.mat'), ...
                    fullfile(pwd,'..','B4P_canonical_freeze.mat')};
freezeFile = '';
for ii=1:numel(freezeCandidates)
    if exist(freezeCandidates{ii},'file')
        freezeFile=freezeCandidates{ii}; break;
    end
end
if isempty(freezeFile)
    [f,p]=uigetfile('*.mat','Select canonical B4P_canonical_freeze.mat');
    if isequal(f,0), error('Canonical freeze not selected.'); end
    freezeFile=fullfile(p,f);
end

F=load(freezeFile);
required={'cfg','caseList','results'};
for ii=1:numel(required)
    if ~isfield(F,required{ii}), error('Freeze missing field: %s',required{ii}); end
end
cfg=F.cfg; caseList=F.caseList; centralResults=F.results;

% Sequential-algorithm settings come from the authoritative submitted routine.
% These are absent from the centralized freeze because they are not centralized-solver settings.
if ~isfield(cfg,'bisectionTol'),      cfg.bisectionTol=1e-3; end
if ~isfield(cfg,'maxOuterBisection'),cfg.maxOuterBisection=8; end
if ~isfield(cfg,'tauL_pct'),          cfg.tauL_pct=1e-6; end

fprintf('Freeze: %s\n',freezeFile);
fprintf('BFS tol = %.3e pu | maxIter = %d\n',cfg.tol,cfg.maxIter);
fprintf('Vslack = %.4f pu | Lthr = %.8f %%\n',cfg.Vslack,cfg.Lthr);
fprintf('Sequential bisectionTol = %.3e | maxOuter = %d\n',cfg.bisectionTol,cfg.maxOuterBisection);
fprintf('Branch-rating checksum sum(Smax) = %.6f MVA\n',sum(cfg.Smax_branch));

[busData0,branchData]=ieee33_data();

wanted={'P1/D3','P1/D4','P2/D2','P2/D3','P2/D4'};
ordersIdx=perms(1:6);
if size(ordersIdx,1)~=720 || size(unique(ordersIdx,'rows'),1)~=720
    error('Permutation generation failed: expected 720 unique orders.');
end

% Preallocate 3600-row table arrays.
nCases=numel(wanted); nOrd=720; N=nCases*nOrd;
Case=strings(N,1); Permutation_ID=zeros(N,1);
Order=zeros(N,6); Bus=zeros(N,6); Alloc_kW=zeros(N,6);
P_BESS_total_kW=zeros(N,1); Vmin_pu=zeros(N,1); Lmax_pct=zeros(N,1);
CritFrom=zeros(N,1); CritTo=zeros(N,1); BFS_converged=false(N,1);
BFS_iterations=zeros(N,1); BFS_residual_pu=zeros(N,1); Thermal_feasible=false(N,1);
OuterIterations=zeros(N,1); BisectionSweeps=zeros(N,1);

row=0;
tStart=tic;
for ci=1:nCases
    cname=wanted{ci};
    ic=find(strcmp({caseList.name},cname),1);
    if isempty(ic), error('Case %s missing from freeze caseList.',cname); end
    C=caseList(ic); ev=C.evcsBuses(:).';
    if numel(ev)~=6, error('%s does not have six EVCS buses.',cname); end

    fprintf('\n[%d/%d] %s — running 720 thermal-only orders...\n',ci,nCases,cname);
    for kk=1:nOrd
        row=row+1;
        ord=ev(ordersIdx(kk,:));
        [~,~,PBESS,info]=coordinated_bisection_bess_permuted_thermal( ...
            busData0,branchData,cfg,ev,C.lambda,ord);
        m=info.finalMetric;
        Case(row)=string(cname); Permutation_ID(row)=kk;
        Order(row,:)=ord; Bus(row,:)=ev; Alloc_kW(row,:)=PBESS(ev).'*1000;
        P_BESS_total_kW(row)=sum(PBESS)*1000;
        Vmin_pu(row)=m.Vmin; Lmax_pct(row)=m.LmaxPct;
        CritFrom(row)=m.critFrom; CritTo(row)=m.critTo;
        BFS_converged(row)=m.converged; BFS_iterations(row)=m.iterations;
        BFS_residual_pu(row)=m.BFSresidual;
        Thermal_feasible(row)=info.finalFeasible;
        OuterIterations(row)=info.outerIterations; BisectionSweeps(row)=info.bisectionSweeps;
    end
end
runtime=toc(tStart);
if row~=3600, error('Expected 3600 rows, obtained %d.',row); end

T=table(Case,Permutation_ID, ...
    Order(:,1),Order(:,2),Order(:,3),Order(:,4),Order(:,5),Order(:,6), ...
    Bus(:,1),Bus(:,2),Bus(:,3),Bus(:,4),Bus(:,5),Bus(:,6), ...
    Alloc_kW(:,1),Alloc_kW(:,2),Alloc_kW(:,3),Alloc_kW(:,4),Alloc_kW(:,5),Alloc_kW(:,6), ...
    P_BESS_total_kW,Vmin_pu,Lmax_pct,CritFrom,CritTo,BFS_converged,BFS_iterations, ...
    BFS_residual_pu,Thermal_feasible,OuterIterations,BisectionSweeps, ...
    'VariableNames',{'Case','Permutation_ID','Order1','Order2','Order3','Order4','Order5','Order6', ...
    'Bus1','Bus2','Bus3','Bus4','Bus5','Bus6','PBESS1_kW','PBESS2_kW','PBESS3_kW','PBESS4_kW','PBESS5_kW','PBESS6_kW', ...
    'P_BESS_total_kW','Vmin_pu','Lmax_pct','CritFrom','CritTo','BFS_converged','BFS_iterations','BFS_residual_pu', ...
    'Thermal_feasible','OuterIterations','BisectionSweeps'});
writetable(T,'order_audit_thermal_all3600_FINAL.csv');

% Build case summary + independent endpoint replays.
SCase=strings(nCases,1); Central=zeros(nCases,1); Best=zeros(nCases,1); BestEx=zeros(nCases,1);
Worst=zeros(nCases,1); WorstEx=zeros(nCases,1); BestPerm=zeros(nCases,1); WorstPerm=zeros(nCases,1);
BestOrder=zeros(nCases,6); WorstOrder=zeros(nCases,6); BestAlloc=zeros(nCases,6); WorstAlloc=zeros(nCases,6);
BestReplayPass=false(nCases,1); WorstReplayPass=false(nCases,1);
BestReplayLmax=zeros(nCases,1); WorstReplayLmax=zeros(nCases,1);
BestReplayVmin=zeros(nCases,1); WorstReplayVmin=zeros(nCases,1);

for ci=1:nCases
    cname=wanted{ci}; SCase(ci)=string(cname);
    rcen=centralResults(strcmp({centralResults.name},cname));
    if isempty(rcen), error('Centralized result missing for %s.',cname); end
    Central(ci)=rcen.P_BESS_total_kW;
    mask=strcmp(T.Case,cname) & T.Thermal_feasible;
    if sum(mask)==0, error('No thermally feasible sequential orders for %s.',cname); end
    rows=find(mask); vals=T.P_BESS_total_kW(rows);
    [Best(ci),ib]=min(vals); [Worst(ci),iw]=max(vals);
    rb=rows(ib); rw=rows(iw);
    BestPerm(ci)=T.Permutation_ID(rb); WorstPerm(ci)=T.Permutation_ID(rw);
    BestOrder(ci,:)=[T.Order1(rb) T.Order2(rb) T.Order3(rb) T.Order4(rb) T.Order5(rb) T.Order6(rb)];
    WorstOrder(ci,:)=[T.Order1(rw) T.Order2(rw) T.Order3(rw) T.Order4(rw) T.Order5(rw) T.Order6(rw)];
    BestAlloc(ci,:)=[T.PBESS1_kW(rb) T.PBESS2_kW(rb) T.PBESS3_kW(rb) T.PBESS4_kW(rb) T.PBESS5_kW(rb) T.PBESS6_kW(rb)];
    WorstAlloc(ci,:)=[T.PBESS1_kW(rw) T.PBESS2_kW(rw) T.PBESS3_kW(rw) T.PBESS4_kW(rw) T.PBESS5_kW(rw) T.PBESS6_kW(rw)];
    BestEx(ci)=100*(Best(ci)-Central(ci))/Central(ci);
    WorstEx(ci)=100*(Worst(ci)-Central(ci))/Central(ci);

    ic=find(strcmp({caseList.name},cname),1); C=caseList(ic); ev=C.evcsBuses(:).';
    mb=replay_alloc(busData0,branchData,cfg,ev,C.lambda,BestAlloc(ci,:)/1000);
    mw=replay_alloc(busData0,branchData,cfg,ev,C.lambda,WorstAlloc(ci,:)/1000);
    BestReplayPass(ci)=mb.converged && mb.LmaxPct<=cfg.Lthr+cfg.tauL_pct;
    WorstReplayPass(ci)=mw.converged && mw.LmaxPct<=cfg.Lthr+cfg.tauL_pct;
    BestReplayLmax(ci)=mb.LmaxPct; WorstReplayLmax(ci)=mw.LmaxPct;
    BestReplayVmin(ci)=mb.Vmin; WorstReplayVmin(ci)=mw.Vmin;
end

Summary=table(SCase,Central,Best,BestEx,Worst,WorstEx,BestPerm,WorstPerm, ...
    'VariableNames',{'Case','Centralized_reference_kW','Best_sequential_kW','Best_excess_pct','Worst_sequential_kW','Worst_excess_pct','Best_permutation_ID','Worst_permutation_ID'});
writetable(Summary,'order_audit_thermal_summary_FINAL.csv');
writetable(Summary(:,1:6),'Table5a_order_sensitivity_FINAL.csv');

BW=table(SCase,BestPerm,WorstPerm, ...
    BestOrder(:,1),BestOrder(:,2),BestOrder(:,3),BestOrder(:,4),BestOrder(:,5),BestOrder(:,6), ...
    WorstOrder(:,1),WorstOrder(:,2),WorstOrder(:,3),WorstOrder(:,4),WorstOrder(:,5),WorstOrder(:,6), ...
    BestAlloc(:,1),BestAlloc(:,2),BestAlloc(:,3),BestAlloc(:,4),BestAlloc(:,5),BestAlloc(:,6), ...
    WorstAlloc(:,1),WorstAlloc(:,2),WorstAlloc(:,3),WorstAlloc(:,4),WorstAlloc(:,5),WorstAlloc(:,6), ...
    BestReplayPass,WorstReplayPass,BestReplayLmax,WorstReplayLmax,BestReplayVmin,WorstReplayVmin, ...
    'VariableNames',{'Case','BestPermutationID','WorstPermutationID', ...
    'BestOrder1','BestOrder2','BestOrder3','BestOrder4','BestOrder5','BestOrder6', ...
    'WorstOrder1','WorstOrder2','WorstOrder3','WorstOrder4','WorstOrder5','WorstOrder6', ...
    'BestAlloc1_kW','BestAlloc2_kW','BestAlloc3_kW','BestAlloc4_kW','BestAlloc5_kW','BestAlloc6_kW', ...
    'WorstAlloc1_kW','WorstAlloc2_kW','WorstAlloc3_kW','WorstAlloc4_kW','WorstAlloc5_kW','WorstAlloc6_kW', ...
    'BestReplayPass','WorstReplayPass','BestReplayLmax_pct','WorstReplayLmax_pct','BestReplayVmin_pu','WorstReplayVmin_pu'});
writetable(BW,'order_audit_best_worst_FINAL.csv');

save('order_audit_thermal_FINAL.mat','T','Summary','BW','cfg','runtime','freezeFile','-v7.3');

% Text log.
fid=fopen('order_audit_thermal_FINAL.log','w');
fprintf(fid,'MATLAB %s\n',version);
fprintf(fid,'Freeze: %s\n',freezeFile);
fprintf(fid,'BFS tol %.16e | maxIter %d | Vslack %.12g | Lthr %.12g\n',cfg.tol,cfg.maxIter,cfg.Vslack,cfg.Lthr);
fprintf(fid,'bisectionTol %.16e | maxOuter %d | tauL_pct %.16e\n',cfg.bisectionTol,cfg.maxOuterBisection,cfg.tauL_pct);
fprintf(fid,'Rows: %d | runtime_s %.3f\n',height(T),runtime);
fprintf(fid,'\nCase,Central,Best,BestExcessPct,Worst,WorstExcessPct,BestReplay,WorstReplay\n');
for ci=1:nCases
    fprintf(fid,'%s,%.12f,%.12f,%.12f,%.12f,%.12f,%d,%d\n',SCase(ci),Central(ci),Best(ci),BestEx(ci),Worst(ci),WorstEx(ci),BestReplayPass(ci),WorstReplayPass(ci));
end
fclose(fid);

fprintf('\n=== MANUSCRIPT-READY TABLE 5(a) ===\n');
disp(Summary(:,1:6));
fprintf('Runtime: %.1f s\n',runtime);

allPass = height(T)==3600 && all(BestReplayPass) && all(WorstReplayPass);
if allPass
    fprintf('\nFINAL 720-ORDER AUDIT: PASS\n');
else
    fprintf('\nFINAL 720-ORDER AUDIT: FAIL — inspect endpoint replay/table.\n');
    error('Final audit gate failed.');
end

if RUN_ORIGINAL_COMBINED
    fprintf('\nOriginal-combined provenance pass requested.\n');
    run_original_combined_720(busData0,branchData,cfg,caseList,wanted,ordersIdx);
end

function m=replay_alloc(busData0,branchData,cfg,ev,lambda,allocMW)
    bess=zeros(size(busData0,1),1); bess(ev)=allocMW(:);
    bd=build_case_loads(busData0,ev,cfg.Pinst_MW,lambda,cfg.qFactorEVCS,bess,false);
    [V,I,S,info]=bfs_power_flow(bd,branchData,cfg);
    m=compute_metrics(V,I,S,branchData,cfg,info);
end

function run_original_combined_720(busData0,branchData,cfg,caseList,wanted,ordersIdx)
    nCases=numel(wanted); nOrd=size(ordersIdx,1); N=nCases*nOrd;
    Case=strings(N,1); Permutation_ID=zeros(N,1); Ptotal=zeros(N,1); Vmin=zeros(N,1); Lmax=zeros(N,1); Feasible=false(N,1);
    O=zeros(N,6); row=0;
    for ci=1:nCases
        cname=wanted{ci}; ic=find(strcmp({caseList.name},cname),1); C=caseList(ic); ev=C.evcsBuses(:).';
        fprintf('Original combined %s...\n',cname);
        for kk=1:nOrd
            row=row+1; ord=ev(ordersIdx(kk,:));
            [~,~,PBESS,info]=coordinated_bisection_bess_permuted_original(busData0,branchData,cfg,ev,C.lambda,ord);
            Case(row)=string(cname); Permutation_ID(row)=kk; O(row,:)=ord; Ptotal(row)=sum(PBESS)*1000;
            Vmin(row)=info.finalMetric.Vmin; Lmax(row)=info.finalMetric.LmaxPct; Feasible(row)=info.finalFeasible;
        end
    end
    TC=table(Case,Permutation_ID,O(:,1),O(:,2),O(:,3),O(:,4),O(:,5),O(:,6),Ptotal,Vmin,Lmax,Feasible, ...
        'VariableNames',{'Case','Permutation_ID','Order1','Order2','Order3','Order4','Order5','Order6','P_BESS_total_kW','Vmin_pu','Lmax_pct','Combined_feasible'});
    writetable(TC,'order_audit_original_combined_all_FINAL.csv');
    save('order_audit_original_combined_FINAL.mat','TC','cfg','-v7.3');
end
