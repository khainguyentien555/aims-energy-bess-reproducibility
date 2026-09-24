function [busData, Pch_kW] = build_loads_recharge_v2( ...
    busData0, allocBus_kW, Ebw_MWh, alpha_off, T, eta_ch)
% BUILD_LOADS_RECHARGE_V2
%
% Post-stress recovery state:
%   - stressed EVCS demand is absent,
%   - background P and Q are both scaled by alpha_off,
%   - installed BESS units recharge simultaneously,
%   - recharge is active-only at unity PF,
%   - no Phase-3 Q_add is carried into this state.
%
% IMPORTANT:
% P_ch is NOT clipped to the BESS rating here.
% The symmetric rating P_ch <= P_BESS is checked explicitly by the caller.
% This prevents a hidden cap from violating the common-recovery energy
% identity at candidate T.
%
% Inputs:
%   allocBus_kW : frozen B4-P active BESS rating (33x1, kW)
%   Ebw_MWh     : battery-side energy to restore (33x1, MWh)
%   alpha_off   : background-load multiplier
%   T           : candidate common recovery duration (h)
%   eta_ch      : charging efficiency
%
% Output:
%   Pch_kW      : unconstrained grid/AC-side charging power needed to
%                 restore Ebw_MWh in exactly T hours.

assert(T > 0,'Recharge duration T must be positive.');
assert(eta_ch > 0 && eta_ch <= 1,'eta_ch must lie in (0,1].');
assert(alpha_off >= 0,'alpha_off must be nonnegative.');

busData = busData0;
busData(:,2) = alpha_off*busData0(:,2);
busData(:,3) = alpha_off*busData0(:,3);

Pch_kW = Ebw_MWh(:)/(eta_ch*T)*1000;

% Numerical hygiene: energy must be zero where no BESS exists.
Pch_kW(allocBus_kW(:) <= 0 & abs(Ebw_MWh(:)) <= 1e-14) = 0;

busData(:,2) = busData(:,2) + Pch_kW;
% Unity-PF recharge: no added reactive charging load.
end
