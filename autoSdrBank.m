function [sdrBank, numSdrs] = autoSdrBank(map, sdrsPerCell)
% AUTOSDRBANK  Build a coordinate -> SDR list bank by numbering SDRs in order.
%
%   [sdrBank, numSdrs] = autoSdrBank(map)
%   [sdrBank, numSdrs] = autoSdrBank(map, sdrsPerCell)
%
%   map         - occupancy grid, nonzero = obstacle / dead node (gets no SDR)
%   sdrsPerCell - (optional) number of SDRs centred in each square, same size
%                 as map. Default: 1 SDR in every free square.
%
%   sdrBank     - cell array the same size as map. sdrBank{row, col} lists
%                 the IDs of every SDR in that square; [] means no SDR.
%   numSdrs     - total number of SDRs (= the highest ID handed out)
%
% IDs are handed out 1, 2, 3, ... reading the map row by row, left to right.
% Use this for simulation. For real hardware, fill the bank by hand with the
% IDs of your actual SDRs (see applySdrBank).

    [rows, cols] = size(map);
    if nargin < 2 || isempty(sdrsPerCell)
        sdrsPerCell = ones(rows, cols);
    end
    if ~isequal(size(sdrsPerCell), [rows, cols])
        error('sdrsPerCell must be the same size as map (%d x %d).', rows, cols);
    end
    if any(sdrsPerCell(:) < 0 | sdrsPerCell(:) ~= round(sdrsPerCell(:)))
        error('sdrsPerCell must contain whole numbers of 0 or more.');
    end

    sdrBank = cell(rows, cols);
    nextId  = 1;
    for r = 1:rows
        for c = 1:cols
            k = sdrsPerCell(r, c);
            if map(r, c) == 0 && k > 0
                sdrBank{r, c} = nextId : nextId + k - 1;
                nextId = nextId + k;
            end
        end
    end
    numSdrs = nextId - 1;
end
