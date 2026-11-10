function tx = runTransmitter(cfg, radioTx, hexMessage, durationSeconds)
% RUNTRANSMITTER  Transmit-only node: repeat a packet for a set time.
%
%   tx = runTransmitter(cfg, radioTx, hexMessage, durationSeconds)
%
%   durationSeconds - how long to transmit. Inf (the default) transmits
%                     until you press Ctrl+C.
%
% The transmitter is released when this returns, including after Ctrl+C
% or an error, so the radio is never left transmitting.

    if nargin < 4 || isempty(durationSeconds)
        durationSeconds = Inf;
    end

    cleanup = onCleanup(@() release(radioTx)); %#ok<NASGU>  % runs on return or Ctrl+C

    tx = startTransmitter(cfg, radioTx, hexMessage);

    if isinf(durationSeconds)
        fprintf("Transmitting. Press Ctrl+C to stop.\n");
    else
        fprintf("Transmitting for %.1f s...\n", durationSeconds);
    end
    pause(durationSeconds);
    fprintf("Transmission stopped.\n");
end
