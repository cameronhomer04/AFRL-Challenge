function [offsetHz, retuned] = fhTune(radio, cfg, ch)
% FHTUNE  Point a USRP transmitter or receiver at hop channel ch.
%
%   [offsetHz, retuned] = fhTune(radio, cfg, ch)
%
%   radio - comm.SDRuTransmitter or comm.SDRuReceiver object
%   cfg   - struct from fhConfig
%   ch    - channel number (e.g. from fhHopSequence)
%
%   'lo' mode     : sets radio.CenterFrequency to the channel centre and
%                   returns offsetHz = 0 (nothing to shift digitally).
%   'digital' mode: leaves the radio at cfg.fc and returns the channel's
%                   offset from fc. Shift the baseband by that amount with
%                   fhFreqShift (transmit) or fhSelectChannel (receive).
%
%   retuned - true if the LO was actually changed. The LO is only touched
%             when the frequency changes, because every retune briefly
%             interrupts the RF chain (a few ms on B210/X310).
%
% CenterFrequency is a tunable property, so this works between step() calls
% without releasing the object. Use it right before step() of the first
% frame of each hop:
%
%   ch = fhHopSequence(cfg, slot);
%   off = fhTune(tx, cfg, ch);
%   underrun = tx(myWaveform);

    if ch < 1 || ch > cfg.nCh || ch ~= round(ch)
        error('fhTune:ch', 'Channel must be a whole number from 1 to %d.', cfg.nCh);
    end

    retuned = false;
    if strcmp(cfg.mode, 'lo')
        target = cfg.freqs(ch);
        offsetHz = 0;
    else
        target = cfg.fc;
        offsetHz = cfg.offsets(ch);
    end

    if isempty(radio)                % allows dry runs without a radio
        return;
    end
    if abs(radio.CenterFrequency - target) > 0.5
        radio.CenterFrequency = target;
        retuned = true;
    end
end
