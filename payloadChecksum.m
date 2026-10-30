function checksum = payloadChecksum(hexMessage)
% PAYLOADCHECKSUM  8-bit XOR checksum of a hexadecimal message.
%
%   checksum = payloadChecksum(hexMessage)
%
%   hexMessage - char or string of hex digits, e.g. '8CEEB834AA3A'
%   checksum   - XOR of the message bytes, 0..255. A message with an odd
%                number of digits is padded with a trailing '0' first.
%
% The transmitter appends this to the packet; the receiver recomputes it
% to tell whether the message arrived intact. It catches any single bit
% error, but not every multi-bit error.

    h = upper(char(hexMessage));
    if mod(numel(h), 2) ~= 0
        h = [h '0'];
    end

    bytes = hex2dec(reshape(h, 2, []).');
    checksum = 0;
    for k = 1:numel(bytes)
        checksum = bitxor(checksum, bytes(k));
    end
end
