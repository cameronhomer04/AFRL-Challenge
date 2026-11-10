function [routeHex, hexMessage, ok, sdrList] = fhSplitRoute(payload)
% FHSPLITROUTE  Take the A* routing number back out of a received payload.
%
%   [routeHex, hexMessage, ok, sdrList] = fhSplitRoute(payload)
%
%   payload    - received message without the 12-character hop header,
%                built by fhAddRoute: [ LL | route | message ]
%   routeHex   - the routing number
%   hexMessage - the message after it ('' if none)
%   ok         - false if the payload has no valid route field
%   sdrList    - SDR IDs on the route (hexToSdrList)
%
% A node decides whether to forward with:
%   isSdrOnRoute(routeHex, myId)   or   any(sdrList == myId)

    routeHex = ''; hexMessage = ''; ok = false; sdrList = [];
    payload = upper(char(payload));
    if numel(payload) < 4
        return;
    end
    n = hex2dec(payload(1:2));
    if n < 2 || numel(payload) < 2 + n
        return;
    end
    routeHex   = payload(3 : 2+n);
    hexMessage = payload(3+n : end);
    try
        sdrList = hexToSdrList(routeHex);
        ok = true;
    catch
        sdrList = [];
    end
end
