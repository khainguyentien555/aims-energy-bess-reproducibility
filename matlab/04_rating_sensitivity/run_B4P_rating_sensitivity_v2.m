%% run_B4P_rating_sensitivity_v2.m
% Phase 6 canonical MATLAB replay:
% local thermal-rating sensitivity of the FROZEN centralized thermal-only B4-P.
%
% IMPORTANT:
% - Loads the canonical B4-P MAT file for lineage.
% - Runs beta_S = 1.00 FIRST as a hard reproduction gate.
% - Only after the baseline passes, runs beta_S = 0.90 and 1.10.
% - The ONLY physical parameter changed is cfg.Smax_branch.
% - Does NOT run B4-PQ, PCS, energy, or recharge.
%
% Requires:
%   B4P_canonical_freeze.mat
%   centralized_thermal_B4P.m
%   ieee33_data.m
%   build_case_loads.m
%   bfs_power_flow.m
%   compute_metrics.m
%   empty_metric.m

clear; clc;

assert(exist('B4P_canonical_freeze.mat','file') == 2, ...
    'B4P_canonical_freeze.mat not found.');
assert(exist('centralized_thermal_B4P','file') == 2, ...
    'centralized_thermal_B4P.m not found.');

S = load('B4P_canonical_freeze.mat');
assert(isfield(S,'results') && isfield(S,'cfg') && isfield(S,'caseList'), ...
    'Canonical freeze MAT must contain results, cfg, and caseList.');

frozenResults = S.results;
cfg0 = S.cfg;
caseList = S.caseList;

assert(isfield(cfg0,'Smax_branch'), ...
    'Canonical cfg does not contain Smax_branch.');
Smax_baseline = cfg0.Smax_branch(:);

% Reuse exact canonical configuration. No manual reconstruction.
cfg = cfg0;

% Reproduction tolerances: stricter than 0.1-kW manuscript precision.
tolTotal_kW = 0.05;
tolAlloc_kW = 0.05;

% Sensitivity levels. Baseline is deliberately run FIRST.
betaOrder = [1.00 0.90 1.10];

diary('B4P_rating_sensitivity_log.txt');
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('=== PHASE 6 MATLAB CANONICAL REPLAY v2 ===\n');
fprintf('Purpose: local sensitivity of adopted planning-threshold branch ratings.\n');
fprintf('ONLY cfg.Smax_branch is scaled.\n');
fprintf('Baseline beta=1.00 is a hard gate and is run first.\n\n');

ALL = struct([]);
RbyBeta = cell(numel(betaOrder),1);

for bi = 1:numel(betaOrder)
    beta = betaOrder(bi);
    cfg.Smax_branch = beta*Smax_baseline;

    fprintf('\n===== beta_S = %.2f =====\n', beta);
    R = centralized_thermal_B4P(busData_from_freeze(), branchData_from_freeze(), ...
        cfg, caseList);

    % Attach sensitivity tag.
    for k = 1:numel(R)
        R(k).beta_S = beta;
    end

    % Hard baseline gate BEFORE any sensitivity interpretation.
    if abs(beta-1.00) < 1e-12
        fprintf('\n--- BASELINE REPRODUCTION GATE ---\n');

        assert(numel(R) == numel(frozenResults), ...
            'Baseline result count differs from canonical freeze.');

        for k = 1:numel(R)
            idx = find(strcmp({frozenResults.name},R(k).name),1);
            assert(~isempty(idx),'Case %s missing from canonical freeze.',R(k).name);
            fr = frozenResults(idx);

            dTotal = abs(R(k).P_BESS_total_kW - fr.P_BESS_total_kW);

            % Compare frozen bus allocation in the canonical bus ordering.
            assert(isequal(R(k).evcsBuses(:),fr.evcsBuses(:)), ...
                'EVCS bus ordering changed for %s.',R(k).name);
            dAlloc = max(abs(R(k).alloc_kW(:)-fr.alloc_kW(:)));

            fprintf('%-7s | dTotal=%.6g kW | max dAlloc=%.6g kW\n', ...
                R(k).name,dTotal,dAlloc);

            if dTotal > tolTotal_kW || dAlloc > tolAlloc_kW
                error(['BASELINE REPRODUCTION FAILED for %s. ' ...
                       'Do not continue Phase 6.'],R(k).name);
            end
        end

        fprintf('BASELINE REPRODUCTION beta_S=1.00: PASS\n');
    end

    RbyBeta{bi} = R;
    ALL = [ALL R]; %#ok<AGROW>
end

%% Build 24-point summary table in beta order 0.90,1.00,1.10
betasOut = [0.90 1.00 1.10];
Rows = {};
BusRows = {};

for beta = betasOut
    R = ALL(abs([ALL.beta_S]-beta)<1e-12);

    for k = 1:numel(R)
        r = R(k);

        Rows(end+1,:) = { ...
            string(r.name), beta, r.P_BESS_total_kW, ...
            r.P_BESS_total_kW > 1e-6, r.Lmax_pct, ...
            r.loadingResidual_pct, r.Vmin, ...
            sprintf('%d-%d',r.critFrom,r.critTo), ...
            r.exitflag, r.nValidStarts, r.objSpread_kW, ...
            r.allocSpread_kW, r.BFS_residual_pu}; %#ok<SAGROW>

        for j = 1:numel(r.evcsBuses)
            BusRows(end+1,:) = {string(r.name),beta,r.evcsBuses(j), ...
                r.alloc_kW(j)}; %#ok<SAGROW>
        end
    end
end

T = cell2table(Rows,'VariableNames', ...
    {'Case','beta_S','P_BESS_total_kW','thermal_BESS_required', ...
     'Lmax_pct','loadingResidual_signed_pct','Vmin_pu', ...
     'critical_branch','exitflag','nValidStarts','objSpread_kW', ...
     'allocSpread_kW','BFS_residual_pu'});

Tbus = cell2table(BusRows,'VariableNames', ...
    {'Case','beta_S','Bus','P_BESS_kW'});

%% Cross-beta sensitivity summary
Cases = string({frozenResults.name}).';
nC = numel(Cases);

P090 = zeros(nC,1);
P100 = zeros(nC,1);
P110 = zeros(nC,1);
DeltaP_090_kW = zeros(nC,1);
DeltaP_110_kW = zeros(nC,1);
Pct_090 = nan(nC,1);
Pct_110 = nan(nC,1);
Required_090 = false(nC,1);
Required_100 = false(nC,1);
Required_110 = false(nC,1);

for i = 1:nC
    c = Cases(i);
    P090(i) = T.P_BESS_total_kW(T.Case==c & abs(T.beta_S-.90)<1e-12);
    P100(i) = T.P_BESS_total_kW(T.Case==c & abs(T.beta_S-1.0)<1e-12);
    P110(i) = T.P_BESS_total_kW(T.Case==c & abs(T.beta_S-1.10)<1e-12);

    Required_090(i) = P090(i)>1e-6;
    Required_100(i) = P100(i)>1e-6;
    Required_110(i) = P110(i)>1e-6;

    DeltaP_090_kW(i) = P090(i)-P100(i);
    DeltaP_110_kW(i) = P110(i)-P100(i);

    if P100(i)>1e-6
        Pct_090(i) = 100*DeltaP_090_kW(i)/P100(i);
        Pct_110(i) = 100*DeltaP_110_kW(i)/P100(i);
    end
end

Tsens = table(Cases,P090,P100,P110,Required_090,Required_100,Required_110, ...
    DeltaP_090_kW,DeltaP_110_kW,Pct_090,Pct_110);

%% Structural monotonicity check
% Increasing thermal ratings must not increase the minimum thermal-BESS total
% beyond numerical/reporting tolerance.
if any(P090 < P100 - 0.05) || any(P100 < P110 - 0.05)
    error('Unexpected non-monotone thermal-rating sensitivity detected.');
end
fprintf('\nCross-beta total-BESS monotonicity: PASS\n');

%% Export
writetable(T,'B4P_rating_sensitivity_MATLAB.csv');
writetable(Tbus,'B4P_rating_sensitivity_perbus_MATLAB.csv');
writetable(Tsens,'B4P_rating_sensitivity_compact_MATLAB.csv');

save('B4P_rating_sensitivity_canonical.mat', ...
    'ALL','T','Tbus','Tsens','betasOut','Smax_baseline','cfg0','caseList','-v7.3');

fprintf('\n=== COMPACT SENSITIVITY SUMMARY ===\n');
disp(Tsens);

fprintf('Saved canonical Phase-6 artifacts:\n');
fprintf('  B4P_rating_sensitivity_canonical.mat\n');
fprintf('  B4P_rating_sensitivity_log.txt\n');
fprintf('  B4P_rating_sensitivity_MATLAB.csv\n');
fprintf('  B4P_rating_sensitivity_perbus_MATLAB.csv\n');
fprintf('  B4P_rating_sensitivity_compact_MATLAB.csv\n');
fprintf('\nPHASE 6 MATLAB REPLAY: PASS IF SCRIPT REACHES THIS LINE WITHOUT ERROR.\n');

%% ---- local lineage helpers ----
function busData0 = busData_from_freeze()
    [busData0,~] = ieee33_data();
end

function branchData = branchData_from_freeze()
    [~,branchData] = ieee33_data();
end
