function metric = compute_metrics(V, Ibr, Sbr, branchData, cfg, info)
if nargin < 6
    info.iterations = NaN;
    info.converged = true;
    info.residual = NaN;
elseif ~isfield(info,'residual')
    info.residual = NaN;
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
metric.Vmin        = Vmin;
metric.VminBus     = VminBus;
metric.LmaxPct     = LmaxPct;
metric.critIdx     = critIdx;
metric.critFrom    = branchData(critIdx,1);
metric.critTo      = branchData(critIdx,2);
metric.HCMpct      = HCMpct;
metric.Ploss_kW    = Ploss_kW;
metric.loadingPct  = loadingPct;
metric.iterations  = info.iterations;
metric.converged   = info.converged;
metric.BFSresidual = info.residual;
end
