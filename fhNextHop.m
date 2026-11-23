function hop = fhNextHop(payload, myId, strict)
% FHNEXTHOP  Apply the repeater rule to one received (or new) payload.
%
%   hop = fhNextHop(payload, myId)
%   hop = fhNextHop(payload, myId, strict)
%
%   payload - message without the 12-character hop header, built by
%             fhAddRoute: [ LL | ordered route | message ]
%   myId    - this node's SDR ID
%   strict  - true (default): act only when my ID is FIRST in the route,
%             i.e. after every node before me has relayed the message.
%             false: act when my ID is ANYWHERE in the route; the IDs in
%             front of mine are skipped (a shortcut, as when a node hears
%             a sender that is closer than the route assumed).
%             runNode_FH sets this from strictNextHop.
%
%   hop - struct:
%       action     what to do, one of
%                    'forward'      my ID acted on: send payloadOut in my own burst
%                    'destination'  my ID was the last one: keep the message
%                    'notMine'      my ID is not first (strict) / not in the route
%                    'unordered'    the route is a bitmask / sorted list: the
%                                   hop order is unknown, so ignore
%                    'invalid'      no readable route in the payload
%       routeIn    route as received ('' if invalid)
%       idsIn      SDR IDs in it, in hop order (column)
%       skipped    IDs in front of mine that were bypassed (empty when strict)
%       routeOut   route after removing my ID ('' unless 'forward')
%       idsOut     SDR IDs left (column)
%       nextId     SDR that should act on my burst (NaN unless 'forward')
%       message    the message part (alert text with the originator ID)
%       payloadOut [ LL | routeOut | message ] to send ('' unless 'forward')
%
% The rule (design rules 2-4; rules 1, 5 and 6 are timing, see fhRunRepeater):
%   if the first ID in the route is not mine  -> ignore   (strict)
%   if my ID is not in the route at all       -> ignore   (not strict)
%   remove every ID up to and including mine
%   if the route is now empty                 -> I am the destination: keep
%   otherwise                                 -> send the shortened route on
% Because an ID leaves the route once it acts, a message can never loop
% back through a node.
%
% The shortened route keeps the ID width W of the original, so it is never
% longer than what arrived.

    if nargin < 3 || isempty(strict)
        strict = true;
    end

    hop = struct('action', 'invalid', 'routeIn', '', 'idsIn', zeros(0, 1), ...
                 'skipped', zeros(0, 1), 'routeOut', '', 'idsOut', zeros(0, 1), ...
                 'nextId', NaN, 'message', '', 'payloadOut', '');

    [routeHex, msg, ok, ids] = fhSplitRoute(payload);
    if ~ok || isempty(ids)
        return;
    end
    hop.routeIn = routeHex;
    hop.idsIn   = ids(:);
    hop.message = msg;

    if routeHex(1) ~= '2'
        hop.action = 'unordered';
        return;
    end

    if strict
        if ids(1) ~= myId
            hop.action = 'notMine';
            return;
        end
        idx = 1;
    else
        idx = find(ids == myId, 1);
        if isempty(idx)
            hop.action = 'notMine';
            return;
        end
    end
    hop.skipped = ids(1:idx-1);
    hop.skipped = hop.skipped(:);

    rest = ids(idx+1:end);
    hop.idsOut = rest(:);
    if isempty(rest)
        hop.action = 'destination';
        return;
    end

    w = hex2dec(routeHex(2));                        % keep the original ID width
    digits = dec2hex(rest, w)';
    hop.routeOut   = ['2', routeHex(2), digits(:)'];
    hop.nextId     = rest(1);
    hop.payloadOut = fhAddRoute(hop.routeOut, msg);
    hop.action     = 'forward';
end
