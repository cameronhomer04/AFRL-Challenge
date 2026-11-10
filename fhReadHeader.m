function [slot, pktIdx, ok] = fhReadHeader(bits)
% FHREADHEADER  Read the hop header made by fhHeaderBits.
%
%   [slot, pktIdx, ok] = fhReadHeader(bits)
%
%   bits   - demodulated bits of a packet; the first 48 are the header
%            (extra payload bits after them are ignored)
%   slot   - hop slot counter the packet was sent in
%   pktIdx - packet number inside that slot
%   ok     - false if the CRC fails (bit errors): ignore slot and pktIdx then
%
%   [slot, k, ok] = fhReadHeader(rxBits);
%   if ok, rxState = fhRxFollow(rxState, cfg, slot); end

    bits = double(bits(:));
    if numel(bits) < 48
        error('fhReadHeader:short', 'Need at least 48 bits, got %d.', numel(bits));
    end
    body = bits(1:40);
    crc  = bits(41:48);
    ok   = isequal(toBits(fhCrc8(body), 8), crc);
    slot   = (2.^(31:-1:0)) * body(1:32);
    pktIdx = (2.^(7:-1:0))  * body(33:40);
end

function b = toBits(v, n)
    b = mod(floor(v ./ 2.^(n-1:-1:0)'), 2);
end
