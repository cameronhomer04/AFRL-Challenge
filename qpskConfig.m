function cfg = qpskConfig()
% QPSKCONFIG  Radio and pi/4-DQPSK settings shared by every node.
%
%   cfg = qpskConfig()
%
% Modulation settings are the same on every radio so any node can talk to
% any other. Clock, gain and channel settings differ by hardware, so they
% live in cfg.platforms.<B210 | X310>. Every platform must give the same
% baseband sample rate (symbolRate x samplesPerSymbol); this is checked here.

    % ---- Shared radio settings ----
    cfg.centerFrequency = 2.4e9;
    cfg.samplesPerFrame = 4096;

    % ---- Modulation (identical on every node) ----
    cfg.symbolRate       = 100e3;
    cfg.samplesPerSymbol = 8;           % oversampling factor
    cfg.rolloff          = 0.35;        % root-raised-cosine roll-off
    cfg.filterSpan       = 10;          % RRC filter length in symbols
    cfg.preambleLength   = 128;         % preamble bits (must be even)
    cfg.txAmplitude      = 0.70;        % headroom to avoid DAC clipping

    % ---- Packet layout (used by runNode / buildPacketBits / receivePacket) ----
    %   [ preamble | length (hex chars) | payload | checksum ]
    cfg.lengthFieldBits = 8;            % so payloads of 1-255 hex characters
    cfg.checksumBits    = 8;            % XOR of the payload bytes
    cfg.maxHexChars     = 2^cfg.lengthFieldBits - 1;
    cfg.maxPacketSymbols = (cfg.preambleLength + cfg.lengthFieldBits + ...
                            4*cfg.maxHexChars + cfg.checksumBits) / 2;

    % ---- Per-platform settings ----
    % B210 (USB, found by serial number). 32 MHz / 40 = 800 kS/s.
    cfg.platforms.B210 = struct( ...
        'masterClockRate', 32e6, ...
        'interpFactor',    40, ...
        'decimFactor',     40, ...
        'txGain',          50, ...      % dB, B210 range about 0-89.75
        'rxGain',          30, ...
        'txChannel',       1, ...
        'rxChannel',       2);

    % X310 (Ethernet, found by IP address). 200 MHz / 250 = 800 kS/s.
    % Gains are on the daughterboard's scale (UBX/SBX about 0-31.5 dB);
    % tune them on the bench. Channel 1 = daughterboard slot A, 2 = slot B.
    cfg.platforms.X310 = struct( ...
        'masterClockRate', 200e6, ...
        'interpFactor',    250, ...
        'decimFactor',     250, ...
        'txGain',          15, ...
        'rxGain',          20, ...
        'txChannel',       1, ...
        'rxChannel',       2);

    % ---- Derived values ----
    cfg.sampleRate = cfg.symbolRate * cfg.samplesPerSymbol;   % baseband, all radios
    cfg.rrcFilter  = rcosdesign(cfg.rolloff, cfg.filterSpan, ...
                                cfg.samplesPerSymbol, "sqrt");

    % ---- Sanity checks ----
    if cfg.sampleRate <= 0 || cfg.samplesPerFrame <= 0
        error("Sample rate and frame size must be positive.");
    end
    if mod(cfg.preambleLength, 2) ~= 0 || mod(cfg.lengthFieldBits, 2) ~= 0 ...
            || mod(cfg.checksumBits, 2) ~= 0
        error("Preamble, length field and checksum must each have an even number of bits.");
    end

    names = fieldnames(cfg.platforms);
    for k = 1:numel(names)
        p = cfg.platforms.(names{k});
        txRate = p.masterClockRate / p.interpFactor;
        rxRate = p.masterClockRate / p.decimFactor;
        if abs(txRate - cfg.sampleRate) > 1 || abs(rxRate - cfg.sampleRate) > 1
            error(['Sample-rate mismatch on %s.\n' ...
                   'TX rate: %.0f, RX rate: %.0f, required: %.0f samples/s'], ...
                   names{k}, txRate, rxRate, cfg.sampleRate);
        end
    end
end
