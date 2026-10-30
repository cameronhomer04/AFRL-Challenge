function txWaveform = pulseShapeTx(symbols, cfg)
% PULSESHAPETX  Upsample and RRC-filter DQPSK symbols for the USRP.
%
%   txWaveform = pulseShapeTx(symbols, cfg)
%
%   symbols    - complex symbol column from dqpskModulate
%   cfg        - settings from qpskConfig (uses rrcFilter, filterSpan,
%                samplesPerSymbol, txAmplitude)
%   txWaveform - complex single column, peak = cfg.txAmplitude

    % Zero tail lets the pulse-shaping filter settle after the packet.
    symbolsWithTail = [symbols(:); zeros(cfg.filterSpan, 1)];

    txWaveform = upfirdn(symbolsWithTail, cfg.rrcFilter, cfg.samplesPerSymbol, 1);

    % Normalise and leave headroom to avoid DAC clipping.
    txWaveform = cfg.txAmplitude * txWaveform ./ max(abs(txWaveform));

    % USRP transmission is most efficient with complex single-precision data.
    txWaveform = complex(single(txWaveform(:)));
end
