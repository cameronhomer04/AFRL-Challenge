function crc = fhCrc8(bits)
% FHCRC8  CRC-8 (polynomial x^8+x^2+x+1, 0x07, initial value 0) of a bit vector.
%
%   crc = fhCrc8(bits)   % bits: 0/1 vector, most significant bit first
%   crc: 0..255
%
% Used by fhHeaderBits / fhReadHeader to catch corrupted hop headers.

    crc = 0;
    for k = 1:numel(bits)
        fb = bitxor(bitshift(crc, -7), bits(k));      % top bit xor input bit
        crc = mod(crc * 2, 256);
        if fb
            crc = bitxor(crc, 7);
        end
    end
end
