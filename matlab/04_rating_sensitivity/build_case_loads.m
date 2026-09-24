function busData = build_case_loads(busData0, evcsBuses, Pinst_MW, lambda, qFactorEVCS, bessMW, allowExport)
% Exact production load-construction convention.
% BESS active discharge reduces net active load.
% EVCS reactive demand remains based on full EVCS demand.
% No BESS reactive support is included in B4-P.

if nargin < 6 || isempty(bessMW)
    bessMW = zeros(33,1);
end
if nargin < 7 || isempty(allowExport)
    allowExport = false;
end

busData = busData0;

Pevcs_MW   = Pinst_MW * lambda;
Qevcs_MVAr = Pevcs_MW * qFactorEVCS;

for b = evcsBuses
    busData(b,2) = busData(b,2) + Pevcs_MW * 1000;
    busData(b,3) = busData(b,3) + Qevcs_MVAr * 1000;
end

for b = 1:33
    if bessMW(b) > 0
        busData(b,2) = busData(b,2) - bessMW(b) * 1000;
    end
end

if ~allowExport
    for b = 1:33
        busData(b,2) = max(busData(b,2), 0);
    end
end
end
