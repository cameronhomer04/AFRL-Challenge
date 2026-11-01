function [rxBuffer, info] = captureSamples(cfg, radioRx)
% CAPTURESAMPLES  Record enough frames to be sure of one whole packet.
%
%   [rxBuffer, info] = captureSamples(cfg, radioRx)
%
%   cfg      - settings from qpskConfig
%   radioRx  - comm.SDRuReceiver (sdr.rx from setupSdrNode)
%
%   rxBuffer - captured complex baseband samples (double column)
%   info     - struct: captureFrames, overflow
%
% The receiver does not know how long the incoming message is, so the
% capture is sized for about 10 of the longest possible packets
% (cfg.maxPacketSymbols), and never fewer than 10 frames.
% The receiver is not released here; the caller does that.

    longestPacketSamples = ...
        (cfg.maxPacketSymbols + 2*cfg.filterSpan + 10) * cfg.samplesPerSymbol;
    desiredSamples = max(10 * longestPacketSamples, 10 * cfg.samplesPerFrame);
    info.captureFrames = ceil(desiredSamples / cfg.samplesPerFrame);
    info.overflow = false;

    rxBuffer = complex(zeros(0, 1, "single"));
    for frameNum = 1:info.captureFrames
        [rxFrame, dataLength, overflow] = radioRx();

        if overflow
            info.overflow = true;
            warning("RX overflow occurred on frame %d.", frameNum);
        end
        if dataLength > 0
            rxBuffer = [rxBuffer; complex(single(rxFrame(1:dataLength)))]; %#ok<AGROW>
        end
    end

    if info.overflow
        warning("One or more RX overflows occurred. Reduce capture load or increase SamplesPerFrame.");
    end
    if isempty(rxBuffer)
        error("No samples were received.");
    end

    rxBuffer = double(rxBuffer(:));
end
