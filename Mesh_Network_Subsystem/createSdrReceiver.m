function radioRx = createSdrReceiver(cfg, radio)
% CREATESDRRECEIVER  Receiver object for a B210 or an X310.
%
%   radioRx = createSdrReceiver(cfg, radio)
%
%   cfg   - settings from qpskConfig
%   radio - one element from findSdrRadios / selectSdrRadio
%           (fields Platform and Address). Can be the same radio as the
%           transmitter (loopback) or a different one.
%
% Uses the clock, gain and channel settings in cfg.platforms.<Platform>,
% and SerialNum (B210) or IPAddress (X310) to address the radio.

    p = cfg.platforms.(radio.Platform);

    radioRx = comm.SDRuReceiver( ...
        'Platform',         radio.Platform, ...
        addressProperty(radio), radio.Address, ...
        'CenterFrequency',  cfg.centerFrequency, ...
        'MasterClockRate',  p.masterClockRate, ...
        'DecimationFactor', p.decimFactor, ...
        'Gain',             p.rxGain, ...
        'SamplesPerFrame',  cfg.samplesPerFrame, ...
        'OutputDataType',   'double', ...
        'ChannelMapping',   p.rxChannel);
end

function name = addressProperty(radio)
    if strcmp(radio.Platform, 'B210')
        name = 'SerialNum';                 % USB radio
    else
        name = 'IPAddress';                 % networked radio (X310)
    end
end
