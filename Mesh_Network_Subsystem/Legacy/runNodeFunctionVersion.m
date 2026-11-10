% Function used for testing the mobile application using the B210
% Created: 11/1/2026
% "Authored": Cameron Homer (really this is just stolen from Grant)

function hexResult = runNodeFunctionVersion()
    clear rx;
    clear tx;
    hexResult = "";
    role       = "rx";              % "tx", "rx" or "both"
    hexMessage = "1100A0C";           % Sent by "tx" and "both" (1-255 hex characters)
    txDuration = 10;                  % Seconds a "tx" node transmits; Inf = until Ctrl+C
    
    x310Addresses = {};               % X310 IPs to probe if search misses one
    sdr = struct('tx', [], 'rx', []); % Initialize empty sdr struct for finally block safety
   
        %% ---------------- Pick this node's radio ----------------
        cfg = qpskConfig();
        radios = findSdrRadios(x310Addresses);
        
        fprintf("Radios found:\n");
        for k = 1:numel(radios)
            fprintf("  %d) %s  %s\n", k, radios(k).Platform, radios(k).Address);
        end
        
        nodeRadio = selectSdrRadio(radios, 'any');
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
                hexResult = rx.hexMessage;
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