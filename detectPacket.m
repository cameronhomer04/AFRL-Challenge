function sync = detectPacket(rxMatched, knownPreambleDiff, numPacketSymbols, samplesPerSymbol)
% DETECTPACKET  Find symbol timing and packet start by differential preamble correlation.
%
%   sync = detectPacket(rxMatched, knownPreambleDiff, numPacketSymbols, samplesPerSymbol)
%
%   rxMatched         - matched-filter output (complex column)
%   knownPreambleDiff - exp(1j * preamble phase increments 2..end)
%   numPacketSymbols  - preamble + payload symbols. When the length is not
%                       known in advance, pass the maximum (cfg.maxPacketSymbols).
%   samplesPerSymbol  - oversampling factor
%
%   sync - struct with fields
%       timingOffset        best sampling phase (1..samplesPerSymbol)
%       metric              normalised preamble correlation peak (0..1)
%       timingMetrics       peak metric for every sampling phase
%       correlation         metric over time at the best phase
%       preambleStartSymbol first preamble symbol in the decimated stream
%       preambleStartSample same position as a sample index in rxMatched
%       packetSymbols       the numPacketSymbols symbols of the packet
%
% Correlating phase changes rather than absolute phase makes this robust
% to an unknown carrier phase.

    knownPreambleDiff = knownPreambleDiff(:);
    L = numel(knownPreambleDiff);

    bestMetric   = -Inf;
    bestOffset   = 1;
    bestLocation = 1;
    bestCorr     = [];
    bestZ        = [];
    timingMetrics = zeros(samplesPerSymbol, 1);

    for timingOffset = 1:samplesPerSymbol
        z = rxMatched(timingOffset:samplesPerSymbol:end);
        if length(z) < numPacketSymbols + 5
            continue;
        end

        zDiff = z(2:end) .* conj(z(1:end-1));     % differential phase
        if length(zDiff) < L
            continue;
        end

        corrOutput   = conv(zDiff, flipud(conj(knownPreambleDiff)), "valid");
        energyWindow = conv(abs(zDiff).^2, ones(L, 1), "valid");
        normalizedMetric = abs(corrOutput) ./ sqrt(L * energyWindow + eps);

        % Only consider preamble starts with room for the whole packet
        % after them, so a packet cut off at the end of the capture can't win.
        lastStart = length(z) - numPacketSymbols + 1;
        [localMetric, localLocation] = max(normalizedMetric(1:min(lastStart, end)));
        timingMetrics(timingOffset) = localMetric;

        if localMetric > bestMetric
            bestMetric   = localMetric;
            bestOffset   = timingOffset;
            bestLocation = localLocation;
            bestCorr     = normalizedMetric;
            bestZ        = z;
        end
    end

    packetEndSymbol = bestLocation + numPacketSymbols - 1;
    if packetEndSymbol > length(bestZ)
        error("A complete packet was not captured. Increase captureFrames.");
    end

    sync.timingOffset        = bestOffset;
    sync.metric              = bestMetric;
    sync.timingMetrics       = timingMetrics;
    sync.correlation         = bestCorr;
    sync.preambleStartSymbol = bestLocation;
    sync.preambleStartSample = bestOffset + (bestLocation - 1) * samplesPerSymbol;
    sync.packetSymbols       = bestZ(bestLocation:packetEndSymbol);
end
