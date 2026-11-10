function [corrected, phasePerSymbol] = correctFrequencyOffset(packetSymbols, knownPreambleDiff)
% CORRECTFREQUENCYOFFSET  Remove residual carrier offset using the known preamble.
%
%   [corrected, phasePerSymbol] = correctFrequencyOffset(packetSymbols, knownPreambleDiff)
%
%   packetSymbols     - packet symbols from detectPacket (preamble first)
%   knownPreambleDiff - exp(1j * preamble phase increments 2..end)
%   corrected         - packetSymbols with the offset removed
%   phasePerSymbol    - estimated extra rotation per symbol (rad).
%                       Offset in Hz = phasePerSymbol * symbolRate / (2*pi).
%
% A frequency offset adds a roughly constant phase step to every
% differential symbol; comparing against the known preamble measures it.

    packetSymbols = packetSymbols(:);
    knownPreambleDiff = knownPreambleDiff(:);
    n = numel(knownPreambleDiff) + 1;           % number of preamble symbols

    rxPreambleDiff = packetSymbols(2:n) .* conj(packetSymbols(1:n-1));
    phasePerSymbol = angle(sum(rxPreambleDiff .* conj(knownPreambleDiff)));

    symbolIndex = (0:numel(packetSymbols)-1).';
    corrected = packetSymbols .* exp(-1j * phasePerSymbol * symbolIndex);
end
