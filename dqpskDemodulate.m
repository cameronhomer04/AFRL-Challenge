function [payloadBits, payloadDiff, decisionDistance] = dqpskDemodulate(packetSymbols, numPreambleSymbols, numPayloadSymbols)
% DQPSKDEMODULATE  Recover payload bits from frequency-corrected packet symbols.
%
%   [payloadBits, payloadDiff, decisionDistance] = ...
%       dqpskDemodulate(packetSymbols, numPreambleSymbols, numPayloadSymbols)
%
%   packetSymbols      - corrected packet from correctFrequencyOffset
%   numPreambleSymbols - symbols before the part to decode. Pass the
%                        preamble length to decode the field right after
%                        it, or preamble + length field to skip that too.
%   numPayloadSymbols  - how many symbols to decode
%   payloadBits      - recovered bits (column, 2 per payload symbol)
%   payloadDiff      - differential payload values, scaled so their average
%                      magnitude is 1 (for constellation plots)
%   decisionDistance - distance of each payload value from the nearest
%                      ideal point: about 0 = clean, 0.77 = halfway to a
%                      wrong decision
%
% The first payload symbol is decided from the step between the last
% preamble symbol and the first payload symbol.

    packetSymbols = packetSymbols(:);
    rxDifferential = packetSymbols(2:end) .* conj(packetSymbols(1:end-1));
    payloadDiff = rxDifferential(numPreambleSymbols : numPreambleSymbols + numPayloadSymbols - 1);

    % Scale to the unit circle so the decision distance and the constellation
    % plot don't depend on the received signal strength. Decisions use only
    % the phase, so this does not change any bits.
    payloadDiff = payloadDiff / (mean(abs(payloadDiff)) + eps);

    idealPhaseIncrements = pi/4 + (0:3)*(pi/2);

    % N-by-4 phase error to each ideal increment; nearest one wins.
    phaseErrorMatrix = angle(exp(1j * (angle(payloadDiff) - idealPhaseIncrements)));
    [~, dibits] = min(abs(phaseErrorMatrix), [], 2);
    dibits = dibits - 1;                             % indices 1..4 -> dibits 0..3

    idealPoints = exp(1j * idealPhaseIncrements);
    decisionDistance = min(abs(payloadDiff - idealPoints), [], 2);

    % 0 -> 00, 1 -> 01, 2 -> 10, 3 -> 11
    bitPairs = [floor(dibits/2), mod(dibits, 2)];
    payloadBits = reshape(bitPairs.', [], 1);
end