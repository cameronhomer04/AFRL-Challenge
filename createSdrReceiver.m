function radioRx = createSdrReceiver(cfg, radio, burstFrames)
% CREATESDRRECEIVER  Receiver object for a B210 or an X310.
%
%   radioRx = createSdrReceiver(cfg, radio)
%   radioRx = createSdrReceiver(cfg, radio, burstFrames)
%
%   cfg         - settings from qpskConfig
%   radio       - one element from findSdrRadios / selectSdrRadio
%                 (fields Platform and Address). Can be the same radio as
%                 the transmitter (loopback) or a different one.
%   burstFrames - (optional) turn on burst mode: every group of this many
%                 frames is captured with no gaps, even if MATLAB is busy
%                 between groups. Used by the continuous receiver. 0 or
%                 omitted = normal streaming.
%
% Uses the clock, gain and channel settings in cfg.platforms.<Platform>,
% and SerialNum (B210) or IPAddress (X310) to address the radio.

    if nargin < 3, burstFrames = 0; end
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

    if burstFrames > 0
        radioRx.EnableBurstMode  = true;
        radioRx.NumFramesInBurst = burstFrames;
    end
end

function name = addressProperty(radio)
    if strcmp(radio.Platform, 'B210')
        name = 'SerialNum';                 % USB radio
    else
        name = 'IPAddress';                 % networked radio (X310)
    end
end
