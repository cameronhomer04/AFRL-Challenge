function [sdrList, format] = hexToSdrList(hexStr)
% HEXTOSDRLIST  List every SDR ID in a routing number.
%
%   [sdrList, format] = hexToSdrList(hexStr)
%
%   hexStr  - routing number made by routeToSdrMask, e.g. '010D' or '13...'
%   sdrList - sorted column of the SDR IDs on the route, e.g. [1; 3; 4; 9]
%   format  - 'bitmask' or 'list', read from the first digit
%
% First digit '0' = bitmask follows, '1' = W followed by IDs of W digits each
% (see routeToSdrMask). Errors on an unknown format or a broken length.

    hexStr = upper(regexprep(char(hexStr), '\s', ''));
    if numel(hexStr) < 2 || isempty(regexp(hexStr, '^[0-9A-F]+$', 'once'))
        error('Routing number must be a hex string of at least 2 digits.');
    end

    body = hexStr(2:end);
    switch hexStr(1)
        case '0'                                     % bitmask
            format = 'bitmask';
            vals = hex2dec(fliplr(body)');           % right-most digit first
            bits = false(4, numel(vals));
            for j = 1:numel(vals)
                bits(:, j) = bitget(vals(j), 1:4)' == 1;
            end
            sdrList = find(bits(:));

        case '1'                                     % list of IDs
            format = 'list';
            w = hex2dec(body(1));
            idDigits = body(2:end);
            if w == 0 || isempty(idDigits) || mod(numel(idDigits), w) ~= 0
                error('List routing number has a broken length (ID width %d).', w);
            end
            sdrList = sort(hex2dec(reshape(idDigits, w, [])'));

        otherwise
            error('Unknown routing number format digit ''%s''.', hexStr(1));
    end
end
