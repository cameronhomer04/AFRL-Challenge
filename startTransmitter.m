function tx = startTransmitter(cfg, radioTx, hexMessage)
% STARTTRANSMITTER  Build the packet and start repeating it on the radio.
%
%   tx = startTransmitter(cfg, radioTx, hexMessage)
%
%   cfg        - settings from qpskConfig
%   radioTx    - comm.SDRuTransmitter (sdr.tx from setupSdrNode)
%   hexMessage - message to send
%
%   tx - struct: hexMessage, txBits, payloadBits, symbols, waveform
%
% Returns as soon as transmission starts; the radio keeps repeating the
% packet in the background until it is released (releaseSdrNode).
% For a transmit-only node, runTransmitter handles the waiting and release.

    [tx.txBits, tx.payloadBits, tx.hexMessage] = buildPacketBits(hexMessage, cfg);
    tx.symbols  = dqpskModulate(tx.txBits);
    tx.waveform = pulseShapeTx(tx.symbols, cfg);

    radioTx.transmitRepeat(tx.waveform);
end
