function [map, numSdrs] = applySdrBank(map, sdrBank)
% APPLYSDRBANK  Check an SDR bank and block every square that has no SDR.
%
%   [map, numSdrs] = applySdrBank(map, sdrBank)
%
%   map     - occupancy grid, nonzero = obstacle / dead node
%   sdrBank - cell array the same size as map; sdrBank{row, col} lists the
%             IDs of the SDRs centred in that square, [] for none.
%             Example:  sdrBank = cell(rows, cols);
%                       sdrBank{1, 1} = 1;
%                       sdrBank{2, 2} = [3 4 5 6 7];   % square with 5 SDRs
%
%   map     - the same grid with every square that has no SDR set to 1,
%             so A* can only route through squares that contain a radio.
%   numSdrs - highest SDR ID in the bank (sets the routing number width)
%
% Errors if an ID is not a positive whole number or appears in more than
% one square (one radio can only be in one place). Warns about SDRs that
% sit on obstacle squares, since A* will never route through them.

    [rows, cols] = size(map);
    if ~iscell(sdrBank) || ~isequal(size(sdrBank), [rows, cols])
        error('sdrBank must be a cell array the same size as map (%d x %d).', rows, cols);
    end

    allIds = [];
    for k = 1:numel(sdrBank)
        ids = sdrBank{k};
        if isempty(ids), continue; end
        if ~isnumeric(ids) || any(ids(:) < 1 | ids(:) ~= round(ids(:)))
            [r, c] = ind2sub([rows, cols], k);
            error('sdrBank{%d,%d} must contain positive whole-number IDs.', r, c);
        end
        if map(k) ~= 0
            [r, c] = ind2sub([rows, cols], k);
            warning('SDR(s) %s at (%d,%d) sit on an obstacle and will not be used.', ...
                    mat2str(ids(:)'), r, c);
        end
        allIds = [allIds, ids(:)']; %#ok<AGROW>
    end

    if isempty(allIds)
        error('The SDR bank is empty: no square contains an SDR.');
    end
    sortedIds = sort(allIds);
    dupIds = unique(sortedIds([false, diff(sortedIds) == 0]));
    if ~isempty(dupIds)
        error('SDR ID(s) %s appear more than once in the bank.', mat2str(dupIds));
    end

    noSdr = cellfun(@isempty, sdrBank);
    map(noSdr) = 1;                      % no radio in this square: dead node
    numSdrs = max(allIds);
end
