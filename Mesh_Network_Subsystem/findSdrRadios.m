function radios = findSdrRadios(x310Addresses)
% FINDSDRRADIOS  Every working B210 and X310 this computer can reach.
%
%   radios = findSdrRadios()
%   radios = findSdrRadios(x310Addresses)
%
%   x310Addresses - (optional) IP addresses to probe for X310s, e.g.
%                   {'192.168.10.2', '192.168.40.2'}. Use this if an X310
%                   is not found by the automatic search.
%
%   radios - struct array, one element per radio, with fields
%       Platform  'B210' or 'X310'
%       Address   serial number (B210) or IP address (X310)
%
% Use selectSdrRadio to pick one by platform.

    if nargin < 1, x310Addresses = {}; end
    x310Addresses = cellstr(x310Addresses);

    found = findsdru;                                  % automatic search
    for k = 1:numel(x310Addresses)                     % plus any listed IPs
        found = [found(:); findsdru(x310Addresses{k})]; %#ok<AGROW>
    end

    radios = struct('Platform', {}, 'Address', {});
    for k = 1:numel(found)
        r = found(k);
        if ~strcmp(r.Status, 'Success'), continue; end

        switch char(r.Platform)
            case 'B210'
                address = char(r.SerialNum);
            case 'X310'
                address = char(r.IPAddress);
            otherwise
                continue;                              % unsupported platform
        end

        % Skip a radio already found (e.g. by both searches).
        if any(strcmp({radios.Address}, address)), continue; end
        radios(end+1) = struct('Platform', char(r.Platform), 'Address', address); %#ok<AGROW>
    end

    if isempty(radios)
        error("No working B210 or X310 found.");
    end
end
