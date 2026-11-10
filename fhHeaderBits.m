function bits = fhHeaderBits(slot, pktIdx)
% FHHEADERBITS  48-bit hop header to put at the front of each packet.
%
%   bits = fhHeaderBits(slot)
%   bits = fhHeaderBits(slot, pktIdx)
%
%   slot   - hop slot counter (0 .. 2^32-1) the packet is sent in
%   pktIdx - (optional) packet number inside this slot (0 .. 255), so the
%            receiver can tell when the transmitter is about to hop. Default 0.
%   bits   - 48-by-1 column of 0/1 (double), most significant bit first:
%              [ slot (32) | pktIdx (8) | CRC-8 (8) ]
%
% Prepend these to your payload bits before QPSK modulation:
%   txBits = [fhHeaderBits(slot, k); payloadBits];
% The receiver reads them back with fhReadHeader and uses the slot number
% to join the hop sequence (see fhRxFollow).

    if nargin < 2 || isempty(pktIdx), pktIdx = 0; end
    if slot < 0 || slot >= 2^32 || slot ~= round(slot)
        error('fhHeaderBits:slot', 'slot must be a whole number from 0 to 2^32-1.');
    end
    if pktIdx < 0 || pktIdx > 255 || pktIdx ~= round(pktIdx)
        error('fhHeaderBits:pkt', 'pktIdx must be a whole number from 0 to 255.');
    end
    body = [toBits(slot, 32); toBits(pktIdx, 8)];
    bits = [body; toBits(fhCrc8(body), 8)];
end

function b = toBits(v, n)
    b = mod(floor(v ./ 2.^(n-1:-1:0)'), 2);
end
