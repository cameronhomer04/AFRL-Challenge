function cfg = fhConfig(fc, nCh, varargin)
% FHCONFIG  Frequency-hopping settings shared by the transmitter and receiver.
%
%   cfg = fhConfig(fc, nCh)
%   cfg = fhConfig(fc, nCh, 'Name', value, ...)
%
%   fc  - centre frequency of operation (Hz), e.g. 915e6
%   nCh - number of hop channels. The band (default 25 MHz) is split into
%         nCh equal channels centred on fc. An EVEN number is recommended:
%         with an odd number one channel sits exactly on fc, where a
%         wideband receiver tuned to fc sees its own LO leakage (DC spike).
%
%   Name-value options (defaults in brackets):
%     'Bandwidth'     total hopping bandwidth in Hz                [25e6]
%     'Dwell'         time spent on each channel (s)               [0.05]
%     'Key'           shared hop key, whole number 0..2^32-1       [12345]
%     'Mode'          'lo'      : retune the radio LO every hop    ['lo']
%                                 (low sample rate, works on B210 and X310)
%                     'digital' : LO stays at fc, the waveform is shifted
%                                 digitally to the channel (fast hops, but
%                                 the radio must stream >= ~1.25 x Bandwidth)
%     'TxRadio'       'B210' or 'X310' (picks valid sample rates)  ['B210']
%     'RxRadio'       'B210' or 'X310'                             ['X310']
%     'RollOff'       RRC roll-off of the QPSK signal              [0.35]
%     'GuardFraction' part of each channel left empty as guard     [0.2]
%     'SamplesPerSymbol' samples per symbol in 'lo' mode           [4]
%
%   cfg (struct):
%     fc, nCh, bandwidth, spacing         - band layout (Hz)
%     offsets, freqs                      - 1-by-nCh channel centres:
%                                           offset from fc, absolute (Hz)
%     edges                               - [low high] of the whole band (Hz)
%     dwell, key, mode
%     symbolRate, sps, rollOff, occupiedBw - QPSK settings that fit a channel
%     tx.MasterClockRate, tx.InterpolationFactor, tx.SampleRate
%     rx.MasterClockRate, rx.DecimationFactor,    rx.SampleRate
%           tx: sample rate for the transmitter in the chosen mode
%           rx: wideband rate for a monitor receiver at fc that sees the
%               whole band (used by fhDetectHops / fhSelectChannel)
%
% The transmitter and receiver must call fhConfig with the SAME fc, nCh,
% Bandwidth, Key and Dwell, otherwise they hop to different channels.
%
% Example:
%   cfg = fhConfig(915e6, 20);           % 20 channels x 1.25 MHz, 902.5-927.5 MHz
%   [ch, f] = fhHopSequence(cfg, 0:9);   % first 10 hops

    p = inputParser;
    p.FunctionName = 'fhConfig';
    addParameter(p, 'Bandwidth', 25e6);
    addParameter(p, 'Dwell', 0.05);
    addParameter(p, 'Key', 12345);
    addParameter(p, 'Mode', 'lo');
    addParameter(p, 'TxRadio', 'B210');
    addParameter(p, 'RxRadio', 'X310');
    addParameter(p, 'RollOff', 0.35);
    addParameter(p, 'GuardFraction', 0.2);
    addParameter(p, 'SamplesPerSymbol', 4);
    parse(p, varargin{:});
    o = p.Results;

    % ---- Checks ----
    if ~isscalar(nCh) || nCh < 2 || nCh ~= round(nCh)
        error('fhConfig:nCh', 'nCh must be a whole number of 2 or more.');
    end
    if ~isscalar(fc) || fc <= 0
        error('fhConfig:fc', 'fc must be a positive frequency in Hz.');
    end
    if o.Bandwidth <= 0
        error('fhConfig:bw', 'Bandwidth must be positive.');
    end
    if o.Key < 0 || o.Key >= 2^32 || o.Key ~= round(o.Key)
        error('fhConfig:key', 'Key must be a whole number from 0 to 2^32-1.');
    end
    if o.Dwell <= 0
        error('fhConfig:dwell', 'Dwell must be positive (seconds).');
    end
    if o.GuardFraction < 0 || o.GuardFraction >= 1
        error('fhConfig:guard', 'GuardFraction must be from 0 to just under 1.');
    end
    mode = lower(char(o.Mode));
    if ~any(strcmp(mode, {'lo', 'digital'}))
        error('fhConfig:mode', 'Mode must be ''lo'' or ''digital''.');
    end

    cfg.fc        = fc;
    cfg.nCh       = nCh;
    cfg.bandwidth = o.Bandwidth;
    cfg.spacing   = o.Bandwidth / nCh;
    cfg.offsets   = ((1:nCh) - (nCh + 1)/2) * cfg.spacing;   % channel centres from fc
    cfg.freqs     = fc + cfg.offsets;
    cfg.edges     = fc + [-1 1] * o.Bandwidth/2;
    cfg.dwell     = o.Dwell;
    cfg.key       = o.Key;
    cfg.mode      = mode;
    cfg.rollOff   = o.RollOff;
    cfg.guardFraction = o.GuardFraction;

    if cfg.spacing < 25e3
        warning('fhConfig:narrow', ['Channels are only %.1f kHz wide: the symbol ' ...
                'rate will be very low. Use fewer channels.'], cfg.spacing/1e3);
    end
    if mod(nCh, 2) == 1
        warning('fhConfig:odd', ['nCh is odd, so channel %d is centred on fc and ' ...
                'overlaps the LO leakage of a receiver tuned to fc. An even nCh avoids this.'], ...
                (nCh + 1)/2);
    end
    checkTuningRange(cfg.edges, o.TxRadio, 'TxRadio');
    checkTuningRange(cfg.edges, o.RxRadio, 'RxRadio');

    % ---- Sample rates ----
    % The QPSK signal must fit inside one channel minus the guard:
    %   symbolRate * (1 + rollOff) <= spacing * (1 - guardFraction)
    maxSymRate = cfg.spacing * (1 - o.GuardFraction) / (1 + o.RollOff);

    % Wideband rate for a receiver at fc that watches the whole band
    [cfg.rx.MasterClockRate, cfg.rx.DecimationFactor, cfg.rx.SampleRate] = ...
        radioRate(o.RxRadio, 1.25 * o.Bandwidth);

    if strcmp(mode, 'lo')
        % Transmitter only needs to cover one channel
        [mcr, f, fs] = radioRate(o.TxRadio, o.SamplesPerSymbol * maxSymRate);
    else
        % Transmitter must cover the whole band to shift digitally
        [mcr, f, fs] = radioRate(o.TxRadio, 1.25 * o.Bandwidth);
    end
    cfg.tx.MasterClockRate     = mcr;
    cfg.tx.InterpolationFactor = f;
    cfg.tx.SampleRate          = fs;

    % Whole number of samples per symbol, symbol rate inside the channel
    cfg.sps        = ceil(fs / maxSymRate);
    cfg.symbolRate = fs / cfg.sps;
    cfg.occupiedBw = cfg.symbolRate * (1 + o.RollOff);

    if strcmp(mode, 'digital') && fs > 20e6
        warning('fhConfig:rate', ['Digital mode streams %.1f MS/s to the transmitter. ' ...
                'MATLAB may not keep up (underruns). ''lo'' mode needs only %.2f MS/s.'], ...
                fs/1e6, o.SamplesPerSymbol * maxSymRate / 1e6);
    end
end

% ----------------------------------------------------------------------
function checkTuningRange(edges, radio, name)
% Rough RF range check. X310 range depends on the daughterboard (UBX-160:
% 10 MHz - 6 GHz); the B210 covers 70 MHz - 6 GHz.
    switch upper(char(radio))
        case 'B210', lim = [70e6 6e9];
        case 'X310', lim = [10e6 6e9];
        otherwise
            error('fhConfig:radio', '%s must be ''B210'' or ''X310''.', name);
    end
    if edges(1) < lim(1) || edges(2) > lim(2)
        error('fhConfig:range', ['Band %.3f-%.3f MHz is outside the %s range ' ...
              '(%.0f MHz - %.0f GHz).'], edges/1e6, upper(char(radio)), lim(1)/1e6, lim(2)/1e9);
    end
end

function [mcr, factor, fs] = radioRate(radio, fsMin)
% Pick a master clock rate and integer interpolation/decimation factor so
% that fs = mcr/factor is the smallest valid rate at or above fsMin.
% Factors are limited to 1, 2, 3, even 4-128 and multiples of 4 up to 256,
% which the MATLAB USRP support package accepts on both radios.
    factors = [1 2 3 4:2:128 132:4:256];
    switch upper(char(radio))
        case 'X310'
            best = inf;
            for m = [200e6 184.32e6]
                fsAll = m ./ factors;
                ok = find(fsAll >= fsMin);
                if isempty(ok), continue; end
                [v, k] = min(fsAll(ok));
                if v < best
                    best = v; mcr = m; factor = factors(ok(k));
                end
            end
            if isinf(best)
                error('fhConfig:rate', 'X310 cannot reach %.1f MS/s.', fsMin/1e6);
            end
            fs = mcr / factor;
        case 'B210'
            mcrRange = [5e6 56e6];
            fs = ceil(fsMin / 1e5) * 1e5;            % round up to 100 kHz
            fs = max(fs, 20e3);                      % lowest rate the clock allows
            if fs > mcrRange(2)
                error('fhConfig:rate', ['B210 cannot reach %.1f MS/s. Reduce the ' ...
                      'bandwidth or use the X310 for this role.'], fsMin/1e6);
            end
            % Largest factor that keeps the clock in range (more oversampling)
            ok = factors(fs * factors <= mcrRange(2) & fs * factors >= mcrRange(1));
            factor = max(ok);
            mcr = fs * factor;
    end
end
