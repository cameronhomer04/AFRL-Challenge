%% Run one SDR node of the DQPSK network
% Choose the node's role below; only the radio objects that role needs are
% created. Put this folder on every computer in the network and change
% only the NODE SETTINGS section on each one.
%
%   role = "tx"    transmit-only node: repeats hexMessage until stopped
%   role = "rx"    receive-only node:  captures and decodes one packet;
%                  it needs no settings about the message
%   role = "both"  loopback test, the same as the original single-SDR script
%
% For a TX node and an RX node on different computers, start the TX node
% first, then run the RX node while it is transmitting.
%
% Function files needed in the same folder:
%   qpskConfig, findSdrRadios, selectSdrRadio, setupSdrNode, releaseSdrNode,
%   createSdrTransmitter, createSdrReceiver, startTransmitter, runTransmitter,
%   captureSamples, receivePacket, buildPacketBits, payloadChecksum,
%   hexToBits, bitsToHex, makePreambleBits, dqpskModulate, pulseShapeTx,
%   detectPacket, correctFrequencyOffset, dqpskDemodulate

clear; clc;

%% ---------------- NODE SETTINGS ----------------
role       = "both";              % "tx", "rx" or "both"
hexMessage = "2e9bbe1209322102349567";      % sent by "tx" and "both" (1-255 hex characters)
txDuration = 10;                 % seconds a "tx" node transmits; Inf = until Ctrl+C
showPlots  = true;

x310Addresses = {};               % X310 IPs to probe if the search misses one, e.g. {'192.168.10.2'}

%% ---------------- Pick this node's radio ----------------
cfg = qpskConfig();
radios = findSdrRadios(x310Addresses);

fprintf("Radios found:\n");
for k = 1:numel(radios)
    fprintf("  %d) %s  %s\n", k, radios(k).Platform, radios(k).Address);
end

nodeRadio = selectSdrRadio(radios, 'any');
% Examples:
%   nodeRadio = selectSdrRadio(radios, 'X310');
%   nodeRadio = selectSdrRadio(radios, 'B210', 2);
%   "both" on two radios attached to this computer (TX first, RX second):
%   nodeRadio = [selectSdrRadio(radios, 'B210'), selectSdrRadio(radios, 'X310')];

fprintf("\nBaseband sample rate: %.3f MSample/s\n", cfg.sampleRate/1e6);
fprintf("Symbol rate: %.3f ksymbol/s\n", cfg.symbolRate/1e3);
fprintf("Raw bit rate: %.3f kbit/s\n", 2*cfg.symbolRate/1e3);

%% ---------------- Set up only what this role needs ----------------
sdr = setupSdrNode(cfg, nodeRadio, role);
fprintf("\nRole: %s\n", upper(sdr.role));
if ~isempty(sdr.txRadio), fprintf("  TX on %s %s\n", sdr.txRadio.Platform, sdr.txRadio.Address); end
if ~isempty(sdr.rxRadio), fprintf("  RX on %s %s\n", sdr.rxRadio.Platform, sdr.rxRadio.Address); end

%% ---------------- Run ----------------
switch sdr.role
    case "tx"
        % runTransmitter releases the radio when it returns or on Ctrl+C.
        if showPlots
            txBits = buildPacketBits(hexMessage, cfg);
            plotTxConstellation(dqpskModulate(txBits));
            drawnow;
        end
        tx = runTransmitter(cfg, sdr.tx, hexMessage, txDuration);

    case "rx"
        try
            [rxBuffer, capInfo] = captureSamples(cfg, sdr.rx);
        catch ME
            releaseSdrNode(sdr);
            rethrow(ME);
        end
        releaseSdrNode(sdr);
        fprintf("Captured %d complex samples in %d frames.\n", numel(rxBuffer), capInfo.captureFrames);

        rx = receivePacket(cfg, rxBuffer);
        printRxResult(rx);
        if showPlots, plotAllRx(cfg, rxBuffer, rx); end

    case "both"
        try
            tx = startTransmitter(cfg, sdr.tx, hexMessage);
            pause(0.10);                         % let the hardware and AGC settle
            [rxBuffer, capInfo] = captureSamples(cfg, sdr.rx);
        catch ME
            releaseSdrNode(sdr);
            rethrow(ME);
        end
        releaseSdrNode(sdr);                     % stops the repeated transmission
        fprintf("Captured %d complex samples in %d frames.\n", numel(rxBuffer), capInfo.captureFrames);

        rx = receivePacket(cfg, rxBuffer);
        printRxResult(rx);

        % Loopback only: the transmitted bits are known, so BER can be measured.
        if rx.valid && numel(rx.payloadBits) == numel(tx.payloadBits)
            bitErrors = sum(rx.payloadBits ~= tx.payloadBits);
            BER = bitErrors / numel(tx.payloadBits);
            fprintf("Transmitted message: %s\n", tx.hexMessage);
            fprintf("Bit errors: %d / %d   BER: %.6f\n", bitErrors, numel(tx.payloadBits), BER);
            if strcmp(rx.hexMessage, tx.hexMessage)
                fprintf("SUCCESS: Received message matches transmitted message.\n");
            else
                fprintf("WARNING: Received message does not match transmitted message.\n");
            end
        else
            BER = NaN;
            fprintf("WARNING: Received length does not match the transmitted message.\n");
        end

        if showPlots
            plotTxConstellation(tx.symbols);
            plotAllRx(cfg, rxBuffer, rx);
            if ~isnan(BER), plotBitComparison(tx.payloadBits, rx.payloadBits, BER); end
        end
end

%% ======================================================================
%                            LOCAL FUNCTIONS
%  ======================================================================
function printRxResult(rx)
    fprintf("\n--- Synchronization Results ---\n");
    fprintf("Best timing offset: %d samples\n", rx.sync.timingOffset);
    fprintf("Preamble metric: %.4f\n", rx.sync.metric);
    fprintf("Estimated packet start: sample %d of the RX capture\n", rx.sync.preambleStartSample);
    fprintf("Estimated residual frequency offset: %.2f Hz\n", rx.freqOffsetHz);

    fprintf("\n--- Reception Results ---\n");
    if ~rx.valid
        fprintf("FAILED: length field reads %d, which is not a valid message length.\n", rx.numHexChars);
        return;
    end
    fprintf("Length field: %d hex characters\n", rx.numHexChars);
    fprintf("Recovered message:   %s\n", rx.hexMessage);
    fprintf("Mean DQPSK decision distance: %.4f\n", mean(rx.decisionDistance));
    fprintf("Worst DQPSK decision distance: %.4f\n", max(rx.decisionDistance));
    if rx.checksumOK
        fprintf("Checksum OK.\n");
    else
        fprintf("CHECKSUM FAILED: the message contains errors.\n");
    end
end

function plotAllRx(cfg, rxBuffer, rx)
    plotRxDiagnostics(rxBuffer, cfg.sampleRate);
    plotMatchedFilter(rx.matched);
    plotSyncDiagnostics(rx.sync, rx.matched, cfg.samplesPerSymbol, rx.numPacketSymbols);
    plotRxConstellations(rx.packetSymbols, rx.packetCorrected, rx.payloadDiff);
end

function plotTxConstellation(dqpskSymbols)
    figure;
    plot(real(dqpskSymbols), imag(dqpskSymbols), 'o');
    grid on; axis equal;
    xlim([-1.5, 1.5]); ylim([-1.5, 1.5]);
    xlabel("In-phase"); ylabel("Quadrature");
    title("\pi/4-DQPSK Transmitted Symbols");
end

function plotRxDiagnostics(rxBuffer, sampleRate)
    figure("Name", "Received RF/Baseband Diagnostics");
    tiledlayout(2,2);

    nexttile;
    plot(real(rxBuffer(1:min(3000,end)))); hold on;
    plot(imag(rxBuffer(1:min(3000,end))));
    grid on; xlabel("Sample number"); ylabel("Amplitude");
    legend("I", "Q"); title("Received Complex Baseband Samples");

    nexttile;
    plot(real(rxBuffer(1:min(3000,end))), imag(rxBuffer(1:min(3000,end))), ".");
    grid on; axis equal;
    xlabel("In-phase"); ylabel("Quadrature"); title("Raw Received IQ Samples");

    nexttile;
    Nfft = 2^floor(log2(min(length(rxBuffer), 65536)));
    if Nfft < 2
        error("Not enough received samples to create an FFT diagnostic.");
    end
    RX = fftshift(fft(rxBuffer(1:Nfft), Nfft));
    fAxis = (-Nfft/2:Nfft/2-1) * (sampleRate/Nfft);
    plot(fAxis/1e3, 20*log10(abs(RX)/max(abs(RX)) + eps));
    grid on; xlabel("Frequency (kHz)"); ylabel("Magnitude (dB, normalized)");
    title("Received Spectrum"); xlim([-300 300]);

    nexttile;
    plot(abs(rxBuffer(1:min(5000,end))).^2);
    grid on; xlabel("Sample number"); ylabel("|r[n]|^2");
    title("Received Signal Power");
end

function plotMatchedFilter(rxMatched)
    figure("Name", "Matched Filter Output");
    tiledlayout(2,1);

    nexttile;
    plot(real(rxMatched(1:min(3000,end)))); hold on;
    plot(imag(rxMatched(1:min(3000,end))));
    grid on; xlabel("Sample number"); ylabel("Amplitude");
    legend("I", "Q"); title("Matched Filter Output");

    nexttile;
    plot(abs(rxMatched(1:min(5000,end))).^2);
    grid on; xlabel("Sample number"); ylabel("|y[n]|^2");
    title("Matched Filter Output Power");
end

function plotSyncDiagnostics(sync, rxMatched, samplesPerSymbol, numPacketSymbols)
    figure("Name", "DQPSK Packet Synchronization");
    tiledlayout(3,1);

    nexttile;
    stem(1:samplesPerSymbol, sync.timingMetrics, "filled");
    grid on; xlabel("Timing phase / sample offset");
    ylabel("Normalized preamble metric");
    title("Timing Recovery: Preamble Metric for Each Sampling Phase");

    nexttile;
    corrAxis = sync.timingOffset + ((1:length(sync.correlation))-1) * samplesPerSymbol;
    plot(corrAxis, sync.correlation, "LineWidth", 1.1); hold on;
    xline(sync.preambleStartSample, "r--", "Packet start", "LineWidth", 1.5);
    grid on; xlabel("Received sample number"); ylabel("Normalized correlation");
    title("Differential Preamble Correlation");

    nexttile;
    s0 = max(1, sync.preambleStartSample - 4*samplesPerSymbol);
    s1 = min(length(rxMatched), sync.preambleStartSample + (numPacketSymbols+5)*samplesPerSymbol);
    plot(s0:s1, abs(rxMatched(s0:s1)).^2); hold on;
    xline(sync.preambleStartSample, "r--", "Detected packet start", "LineWidth", 1.5);
    grid on; xlabel("Sample number"); ylabel("|Matched filter output|^2");
    title("Detected Packet Position");
end

function plotRxConstellations(rxPacketSymbols, rxPacketCorrected, rxPayloadDiff)
    idealPoints = exp(1j * (pi/4 + (0:3)*(pi/2)));

    figure("Name", "DQPSK Reception Diagnostics");
    tiledlayout(2,2);

    nexttile;
    plot(real(rxPacketSymbols), imag(rxPacketSymbols), "o");
    grid on; axis equal; xlabel("In-phase"); ylabel("Quadrature");
    title("Received Packet Symbols Before Frequency Correction");

    nexttile;
    plot(real(rxPacketCorrected), imag(rxPacketCorrected), "o");
    grid on; axis equal; xlabel("In-phase"); ylabel("Quadrature");
    title("Received Packet Symbols After Frequency Correction");

    nexttile;
    plot(real(rxPayloadDiff), imag(rxPayloadDiff), "o"); hold on;
    plot(real(idealPoints), imag(idealPoints), "rx", "MarkerSize", 12, "LineWidth", 2);
    grid on; axis equal; xlabel("Differential I"); ylabel("Differential Q");
    legend("Received differential symbols", "Ideal decisions", "Location", "best");
    title("Differential DQPSK Decision Constellation");

    nexttile;
    plot(unwrap(angle(rxPayloadDiff)), "o-"); hold on;
    yline(pi/4, "--"); yline(3*pi/4, "--"); yline(5*pi/4, "--"); yline(7*pi/4, "--");
    grid on; xlabel("Payload symbol index");
    ylabel("Differential phase increment (rad)");
    title("Received Differential Phase Increments");
end

function plotBitComparison(payloadBits, rxPayloadBits, BER)
    figure("Name", "Bit Comparison");
    tiledlayout(2,1);

    nexttile;
    stem(payloadBits, "filled"); ylim([-0.2 1.2]); grid on;
    xlabel("Bit index"); ylabel("Bit value"); title("Transmitted Payload Bits");

    nexttile;
    stem(rxPayloadBits, "filled"); ylim([-0.2 1.2]); grid on;
    xlabel("Bit index"); ylabel("Bit value");
    title(sprintf("Recovered Payload Bits: BER = %.6f", BER));
end
