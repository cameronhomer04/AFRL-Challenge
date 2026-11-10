function [txBits, payloadBits, hexMessage] = buildPacketBits(hexMessage, cfg)
% BUILDPACKETBITS  Assemble the full packet as a bit column.
%
%   [txBits, payloadBits, hexMessage] = buildPacketBits(hexMessage, cfg)
%
%   hexMessage  - message to send, 1 to cfg.maxHexChars hex characters
%   cfg         - settings from qpskConfig
%
%   txBits      - [ preamble | length | payload | checksum ] (column of 0/1)
%   payloadBits - the payload part alone (for BER checks in loopback)
%   hexMessage  - the cleaned, upper-case message
%
% The length field holds the number of hex characters, so a receiver
% that does not know the message in advance can still decode it.

    [payloadBits, hexMessage] = hexToBits(hexMessage);
    numHex = numel(hexMessage);

    if numHex > cfg.maxHexChars
        error("Message is %d hex characters; the maximum is %d.", numHex, cfg.maxHexChars);
    end

    preambleBits = makePreambleBits(cfg.preambleLength);
    lengthBits   = dec2bin(numHex, cfg.lengthFieldBits).' - '0';
    checksumBits = dec2bin(payloadChecksum(hexMessage), cfg.checksumBits).' - '0';

    txBits = [preambleBits; lengthBits; payloadBits; checksumBits];
end
