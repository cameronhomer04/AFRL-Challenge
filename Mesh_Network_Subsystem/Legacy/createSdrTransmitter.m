function radioTx = createSdrTransmitter(cfg, radio)
% CREATESDRTRANSMITTER  Transmitter object for a B210 or an X310.
%
%   radioTx = createSdrTransmitter(cfg, radio)
%
%   cfg   - settings from qpskConfig
%   radio - one element from findSdrRadios / selectSdrRadio
%           (fields Platform and Address)
%
% Uses the clock, gain and channel settings in cfg.platforms.<Platform>,
% and SerialNum (B210) or IPAddress (X310) to address the radio.

    p = cfg.platforms.(radio.Platform);

    radioTx = comm.SDRuTransmitter( ...
        'Platform',            radio.Platform, ...
        addressProperty(radio), radio.Address, ...
        'CenterFrequency',     cfg.centerFrequency, ...
        'MasterClockRate',     p.masterClockRate, ...
        'InterpolationFactor', p.interpFactor, ...
        'Gain',                p.txGain, ...
        'ChannelMapping',      p.txChannel);
end

function name = addressProperty(radio)
    if strcmp(radio.Platform, 'B210')
        name = 'SerialNum';                 % USB radio
    else
        name = 'IPAddress';                 % networked radio (X310)
    end
end
