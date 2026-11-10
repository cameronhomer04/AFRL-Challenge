function fhSaveRoute(sdrHex, sdrList, numSdrs, fileName)
% FHSAVEROUTE  Save the A* routing number so runNode_FH can send it.
%
%   fhSaveRoute(sdrHex, sdrList, numSdrs)
%   fhSaveRoute(sdrHex, sdrList, numSdrs, fileName)   % default 'route_hex.mat'
%
%   sdrHex   - routing number from routeToSdrMask (e.g. '010D' or '13...')
%   sdrList  - SDR IDs on the route, from routeToSdrMask
%   numSdrs  - number of SDRs in the bank
%   fileName - where to save it
%
% Add ONE line to astar_demo.m (or astar_fh_sync_demo.m), right after
% routeToSdrMask has made sdrHex:
%
%   fhSaveRoute(sdrHex, sdrList, numSdrs);
%
% The file holds routeHex, routeSdrs, numSdrs and created (time saved).
% Copy it next to runNode_FH.m on every node that transmits the route.

    if nargin < 4 || isempty(fileName)
        fileName = 'route_hex.mat';
    end
    routeHex  = upper(regexprep(char(sdrHex), '\s', ''));
    routeSdrs = sdrList(:)';
    created   = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<NASGU>
    hexToSdrList(routeHex);                 % errors if the routing number is broken

    save(fileName, 'routeHex', 'routeSdrs', 'numSdrs', 'created');
    fprintf('Routing number saved to %s: %d hex digits, %d SDRs on the route.\n', ...
            fileName, numel(routeHex), numel(routeSdrs));

    % A packet holds 255 hex characters: 12 hop header + 2 route length
    % + the route + the message.
    room = 255 - 12 - 2 - numel(routeHex);
    if room < 1
        warning(['This routing number (%d hex digits) is too long for one packet ' ...
                 '(at most 240 with a 1-digit message). Use a smaller SDR bank, ' ...
                 'e.g. Option B in astar_demo.m with your real radios.'], numel(routeHex));
    else
        fprintf('Room left in each packet for the message: %d hex characters.\n', room);
    end
end
