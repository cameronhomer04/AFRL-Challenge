function [payloadBits, hexMessage] = hexToBits(hexMessage)
% HEXTOBITS  Convert a hexadecimal message into a column of bits.
%
%   [payloadBits, hexMessage] = hexToBits(hexMessage)
%
%   hexMessage  - string or char, e.g. "8ceeb834aa3a" (spaces are ignored)
%   payloadBits - column of 0/1, 4 bits per hex character, MSB first.
%                 Leading zeros are kept: "04" -> 0000 0100.
%   hexMessage  - the cleaned, upper-case message as a char row vector

    hexMessage = upper(regexprep(char(hexMessage), '\s+', ''));

    if isempty(hexMessage)
        error("Hex message cannot be empty.");
    end
    if any(~isstrprop(hexMessage, "xdigit"))
        error("Message must contain hexadecimal characters only: 0-9 and A-F.");
    end

    % Convert every hex character separately so leading zeros survive.
    hexValues  = arrayfun(@hex2dec, hexMessage);
    nibbleBits = dec2bin(hexValues, 4) - '0';     % one 4-bit row per character
    payloadBits = reshape(nibbleBits.', [], 1);
end
