function [nodeWeight, sdrCount] = bankToWeights(sdrBank, baseWeight)
% BANKTOWEIGHTS  Turn an SDR bank into A* node weights.
%
%   [nodeWeight, sdrCount] = bankToWeights(sdrBank)
%   [nodeWeight, sdrCount] = bankToWeights(sdrBank, baseWeight)
%
%   sdrBank    - cell array, sdrBank{row, col} = IDs of the SDRs in that square
%   baseWeight - (optional) positive matrix, same size as the bank, holding
%                any other cost factors you calculate elsewhere.
%                Default: 1 everywhere.
%
%   nodeWeight - baseWeight .* (number of SDRs in the square). A square
%                that needs 5 SDRs costs 5x as much to route through, so
%                editing the bank changes the path the next time A* runs.
%   sdrCount   - number of SDRs in each square (0 where there are none)
%
% Squares with no SDR get weight baseWeight (A* never enters them anyway,
% because applySdrBank turns them into dead nodes).

    sdrCount = cellfun(@numel, sdrBank);

    if nargin < 2 || isempty(baseWeight)
        baseWeight = ones(size(sdrBank));
    end
    if ~isequal(size(baseWeight), size(sdrBank))
        error('baseWeight must be the same size as sdrBank (%d x %d).', ...
              size(sdrBank, 1), size(sdrBank, 2));
    end
    if any(baseWeight(:) <= 0) || any(isnan(baseWeight(:)))
        error('All base weights must be positive numbers.');
    end

    nodeWeight = baseWeight .* max(sdrCount, 1);
end
