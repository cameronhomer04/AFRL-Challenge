function tf = isSdrOnRoute(hexStr, sdrId)
% ISSDRONROUTE  Check whether an SDR is listed in a routing number.
%
%   tf = isSdrOnRoute(hexStr, sdrId)
%
%   hexStr - routing number made by routeToSdrMask (either format)
%   sdrId  - one SDR ID, or a vector of IDs
%   tf     - true where that SDR is on the route (same size as sdrId)
%
% Example: isSdrOnRoute('010D', 3)  -> true
%          isSdrOnRoute('010D', 2)  -> false
% Needs hexToSdrList.m in the same folder.

    tf = ismember(sdrId, hexToSdrList(hexStr));
end
