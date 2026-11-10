function rx = receivePacket(cfg, rxBuffer)
% RECEIVEPACKET  Find and decode one packet in a capture, with no prior knowledge of it.
%
%   rx = receivePacket(cfg, rxBuffer)
%
%   cfg      - settings from qpskConfig
%   rxBuffer - samples from captureSamples
%
%   rx - struct with fields
%       valid            true if a sensible length field was decoded
%       checksumOK       true if the payload checksum matches
%       hexMessage       recovered message ('' if not valid)
%       numHexChars      value read from the length field
%       payloadBits      recovered payload bits
%       freqOffsetHz     estimated residual carrier offset
%       decisionDistance distance of each payload symbol from its ideal point
%       sync             timing / packet-start details from detectPacket
%       matched          matched-filter output (for plots)
%       packetSymbols, packetCorrected, payloadDiff, numPacketSymbols (for plots)
%
% Steps: matched filter -> preamble sync -> frequency correction ->
% read the length field -> decode payload and checksum.

    numPreambleSymbols = cfg.preambleLength  / 2;
    numLengthSymbols   = cfg.lengthFieldBits / 2;
    numChecksumSymbols = cfg.checksumBits    / 2;

    % Known preamble, as phase changes (the same on every node).
    [~, preamblePhaseInc] = dqpskModulate(makePreambleBits(cfg.preambleLength));
    knownPreambleDiff = exp(1j * preamblePhaseInc(2:end));

    rx.valid = false;
    rx.checksumOK = false;
    rx.hexMessage = '';
    rx.numHexChars = 0;
    rx.payloadBits = zeros(0, 1);
    rx.decisionDistance = zeros(0, 1);
    rx.payloadDiff = zeros(0, 1);

    % ---- Matched filter and sync (room for the longest possible packet) ----
    rx.matched = filter(cfg.rrcFilter, 1, rxBuffer);
    rx.sync = detectPacket(rx.matched, knownPreambleDiff, ...
                           cfg.maxPacketSymbols, cfg.samplesPerSymbol);

    % ---- Frequency correction from the preamble ----
    [corrected, phasePerSymbol] = correctFrequencyOffset(rx.sync.packetSymbols, knownPreambleDiff);
    rx.freqOffsetHz = phasePerSymbol * cfg.symbolRate / (2*pi);

    % ---- Length field ----
    lengthBits = dqpskDemodulate(corrected, numPreambleSymbols, numLengthSymbols);
    rx.numHexChars = bin2dec(char(lengthBits.' + '0'));

    rx.numPacketSymbols = numPreambleSymbols + numLengthSymbols + ...
                          2*rx.numHexChars + numChecksumSymbols;
    rx.packetSymbols   = rx.sync.packetSymbols(1:min(rx.numPacketSymbols, end));
    rx.packetCorrected = corrected(1:min(rx.numPacketSymbols, end));

    if rx.numHexChars < 1 || rx.numHexChars > cfg.maxHexChars
        return;                                      % length field is garbage
    end
    rx.valid = true;

    % ---- Payload and checksum ----
    numPayloadSymbols = 2 * rx.numHexChars;
    [bodyBits, bodyDiff, bodyDist] = dqpskDemodulate(corrected, ...
        numPreambleSymbols + numLengthSymbols, numPayloadSymbols + numChecksumSymbols);

    numPayloadBits   = 4 * rx.numHexChars;
    rx.payloadBits   = bodyBits(1:numPayloadBits);
    rx.payloadDiff   = bodyDiff(1:numPayloadSymbols);
    rx.decisionDistance = bodyDist(1:numPayloadSymbols);

    rx.hexMessage = bitsToHex(rx.payloadBits);
    checksumRx    = bin2dec(char(bodyBits(numPayloadBits+1:end).' + '0'));
    rx.checksumOK = (checksumRx == payloadChecksum(rx.hexMessage));
end
