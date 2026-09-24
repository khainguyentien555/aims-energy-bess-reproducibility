function m = empty_metric()
m.Vmin        = NaN;
m.VminBus     = NaN;
m.LmaxPct     = NaN;
m.critIdx     = NaN;
m.critFrom    = NaN;
m.critTo      = NaN;
m.HCMpct      = NaN;
m.Ploss_kW    = NaN;
m.loadingPct  = [];
m.iterations  = NaN;
m.converged   = false;
m.BFSresidual = NaN;
end
