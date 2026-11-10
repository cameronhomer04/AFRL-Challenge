function payload = fhAddRoute(routeHex, hexMessage)
% FHADDROUTE  Put an A* routing number in front of a message.
%
%   payload = fhAddRoute(routeHex, hexMessage)
%
%   routeHex   - routing number from routeToSdrMask / route_hex.mat
%   hexMessage - the message ('' to send the route alone)
%   payload    - [ LL | route | message ], all hex, where LL is the route's
%                length in hex characters, written as 2 hex digits.
%                Example: route '010D', message '1100A0C'
%                         -> '04' '010D' '1100A0C' = '04010D1100A0C'
%
% fhSplitRoute undoes this. The hop header (12 characters) is added in
% front of the payload later, by the transmitter.

    routeHex = upper(regexprep(char(routeHex), '\s', ''));
    if isempty(routeHex)
        error('fhAddRoute:empty', 'The routing number is empty.');
    end
    if numel(routeHex) > 255
        error('fhAddRoute:long', 'The routing number is %d hex digits; at most 255 fit.', ...
              numel(routeHex));
    end
    hexToSdrList(routeHex);                 % errors if the routing number is broken

    hexMessage = char(hexMessage);
    if ~isempty(regexprep(hexMessage, '\s', ''))
        [~, hexMessage] = hexToBits(hexMessage);   % clean, upper case
    else
        hexMessage = '';
    end
    payload = [sprintf('%02X', numel(routeHex)), routeHex, hexMessage];
end
