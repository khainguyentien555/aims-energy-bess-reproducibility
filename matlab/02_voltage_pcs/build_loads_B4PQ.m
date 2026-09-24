function busData = build_loads_B4PQ(busData0, evcsBuses, Pinst_MW, lambda, qFactorEVCS, bessMW, gamma, delta)
% BUILD_LOADS_B4PQ
% Residual-voltage support convention (Option B):
%
% Original EVCS reactive demand:
%   Q_EVCS0 = P_EVCS * tan(acos(pf_EVCS))
%
% Part 1:
%   gamma in [0,1] represents EVCS PF correction.
%   gamma = 1 gives unity PF at the EVCS active load.
%
% Part 2:
%   delta >= 0 is ADDITIONAL local capacitive support beyond unity PF,
%   distributed proportionally to Q_EVCS0:
%       Q_add,j = delta * Q_EVCS0,j
%
% Therefore the net incremental reactive contribution at each EVCS bus is
%   (1 - gamma - delta) * Q_EVCS0.
%
% Active B4-P allocations are frozen and immutable.
% Active net load is clamped at >=0, matching the production convention.
% Reactive power is intentionally NOT clamped, because additional capacitive
% support may make the incremental EVCS-site Q contribution negative.

if nargin < 7 || isempty(gamma), gamma = 0; end
if nargin < 8 || isempty(delta), delta = 0; end

if gamma < 0 || gamma > 1
    error('gamma must lie in [0,1] for the Option-B PF-correction layer.');
end
if delta < 0
    error('delta must be nonnegative.');
end

busData = busData0;

Pevcs_MW = Pinst_MW * lambda;
Qevcs0_MVAr = Pevcs_MW * qFactorEVCS;

for b = evcsBuses
    busData(b,2) = busData(b,2) + Pevcs_MW*1000;
    busData(b,3) = busData(b,3) + (1-gamma-delta)*Qevcs0_MVAr*1000;
end

for b = 1:size(busData,1)
    if bessMW(b) > 0
        busData(b,2) = busData(b,2) - bessMW(b)*1000;
    end
end

for b = 1:size(busData,1)
    busData(b,2) = max(busData(b,2),0);
end
end
