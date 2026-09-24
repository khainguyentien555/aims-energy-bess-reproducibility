function [V, Ibr, Sbr, info] = bfs_power_flow(busData, branchData, cfg)
% Same BFS stopping rule/physics as IEEE33_BFS_EVCS_BESS_Sizing.m.
% Only added reporting field: info.residual_pu = terminal max |V^k - V^(k-1)|.
    nb = size(busData,1);
    nl = size(branchData,1);

    baseZ = cfg.baseKV^2 / cfg.baseMVA;
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
    residual = Inf;

    for iter = 1:cfg.maxIter
        Vold = V;
        Ibus = conj(Sload ./ V);

        Idown = Ibus;
        for l = nl:-1:1
            fromBus = branchData(l,1);
            toBus   = branchData(l,2);
            Ibr(l) = Idown(toBus);
            Idown(fromBus) = Idown(fromBus) + Ibr(l);
        end

        V(1) = cfg.Vslack + 0i;
        for l = 1:nl
            fromBus = branchData(l,1);
            toBus   = branchData(l,2);
            V(toBus) = V(fromBus) - z(l) * Ibr(l);
        end

        residual = max(abs(V - Vold));
        if residual < cfg.tol
            converged = true;
            break;
        end
    end

    Sbr = V(branchData(:,1)) .* conj(Ibr) * cfg.baseMVA;
    info.iterations  = iter;
    info.converged   = converged;
    info.residual_pu = residual;
    info.z           = z;
    info.baseMVA     = cfg.baseMVA;
end
