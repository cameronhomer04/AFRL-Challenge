function [hexStr, sdrList, onRoute, format] = routeToSdrMask(path, sdrBank, numSdrs)
% ROUTETOSDRMASK  Turn an A* path into the shortest SDR routing number.
%
%   [hexStr, sdrList, onRoute, format] = routeToSdrMask(path, sdrBank, numSdrs)
%
%   path    - N-by-2 list of [row, col] squares from astar
%   sdrBank - cell array, sdrBank{row, col} = IDs of the SDRs in that square
%   numSdrs - (optional) total number of SDRs, only used to check the IDs.
%             Default: highest ID in the bank.
%
%   hexStr  - routing number. The first hex digit says which format follows;
%             both formats are built and the shorter one is sent:
%
%     '0' + BITMASK  one bit per SDR, bit k set = SDR k is on the route.
%                    Right-most digit = SDRs 1-4. Leading zeros above the
%                    highest SDR on the route are left off.
%                    Best when the route uses many of the SDRs (small network).
%                    Example: SDRs 1, 3, 4, 9  -> '0' + '10D' = '010D'
%
%     '1' + W + LIST each SDR ID written out in W hex digits (W = digits
%                    needed for the highest ID on the route).
%                    Best when the route uses few of many SDRs (big network).
%                    Example: SDRs 108, 160, 3039 -> '1' + '3' + '06C' '0A0' 'BDF'
%                                              = '13' '06C0A0BDF'
%
%   sdrList - sorted column of the SDR IDs on the route (no repeats)
%   onRoute - logical row vector, onRoute(k) is true if SDR k is on the route
%   format  - 'bitmask' or 'list', whichever was chosen
%
% The receiver needs no settings: hexToSdrList and isSdrOnRoute read the
% format digit and decode either format.

    if isempty(path)
        error('Path is empty: there is no route to encode.');
    end

    idx   = sub2ind(size(sdrBank), path(:,1), path(:,2));
    cells = sdrBank(idx);

    empty = cellfun(@isempty, cells);
    if any(empty)
        k = find(empty, 1);
        error('Path square (%d,%d) has no SDR in the bank.', path(k,1), path(k,2));
    end

    ids = cellfun(@(v) v(:)', cells, 'UniformOutput', false);
    sdrList = unique([ids{:}])';
    maxId   = max(sdrList);

    if nargin < 3 || isempty(numSdrs)
        allIds  = cellfun(@(v) v(:)', sdrBank, 'UniformOutput', false);
        numSdrs = max([allIds{:}]);
    end
    if maxId > numSdrs
        error('SDR %d is on the route but numSdrs is only %d.', maxId, numSdrs);
    end

    % ---- Format 0: bitmask (only as wide as the highest SDR on the route) ----
    nDigits = ceil(maxId / 4);
    bits = false(1, 4 * nDigits);
    bits(sdrList) = true;
    vals = zeros(1, nDigits);
    for j = 1:nDigits                        % digit j from the right = SDRs 4j-3 .. 4j
        vals(j) = bits(4*j-3 : 4*j) * [1; 2; 4; 8];
    end
    maskDigits = dec2hex(fliplr(vals), 1)';
    maskHex = ['0', maskDigits(:)'];

    % ---- Format 1: list of IDs, W hex digits each ----
    w = numel(dec2hex(maxId));
    if w > 15
        error('SDR IDs are too large for the list format.');
    end
    listDigits = dec2hex(sdrList, w)';
    listHex = ['1', dec2hex(w, 1), listDigits(:)'];

    % ---- Send whichever is shorter (bitmask on a tie) ----
    if numel(listHex) < numel(maskHex)
        hexStr = listHex;
        format = 'list';
    else
        hexStr = maskHex;
        format = 'bitmask';
    end

    onRoute = false(1, numSdrs);
    onRoute(sdrList) = true;
end
