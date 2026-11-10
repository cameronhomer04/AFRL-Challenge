function hexMessage = bitsToHex(bits)
% BITSTOHEX  Convert a column of bits back into a hexadecimal message.
%
%   hexMessage = bitsToHex(bits)
%
%   bits       - vector of 0/1, length a multiple of 4, MSB first
%   hexMessage - upper-case char row vector, e.g. '8CEEB834AA3A'

    bits = bits(:);
    if mod(numel(bits), 4) ~= 0
        error("Recovered payload length is not divisible by 4.");
    end

    nibbleBits = reshape(bits, 4, []).';          % one 4-bit row per character
    hexValues  = bin2dec(char(nibbleBits + '0'));
    hexMessage = upper(reshape(dec2hex(hexValues, 1).', 1, []));
end
