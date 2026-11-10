function txStats = fhRunTransmitter(cfg, fh, radioTx, hexMessages, opts)
% FHRUNTRANSMITTER  Frequency-hopping transmit node: pi/4-DQPSK packets,
% a new channel every dwell, until stopped.
%
%   txStats = fhRunTransmitter(cfg, fh, radioTx, hexMessages, opts)
%
%   cfg         - settings from qpskConfig (the modem)
%   fh          - struct from fhConfig plus slotGuard / pktGap (see runNode_FH)
%   radioTx     - comm.SDRuTransmitter (sdr.tx from setupSdrNode)
%   hexMessages - one message, or several to take turns: "DEAD" or ["DEAD","BEEF"]
%                 Each can be up to cfg.maxHexChars - 12 hex characters
%                 (12 characters go to the hop header).
%   opts        - struct, any field may be left out:
%       duration        seconds to transmit; Inf = until Stop / Ctrl+C (default)
%       messageInterval seconds on each message before the next (default 5)
%       showDisplay     small window with a Stop button (default true)
%       statusEvery     print a status line every this many slots (default 20)
%
%   txStats - slots sent, underruns, packets per slot, time on air
%
% Each slot is one frame of dwell x sampleRate samples:
%   [ lead silence | packet 0 | gap | packet 1 | gap | ... | trail silence ]
% Every packet's message is  [ 12-hex-char hop header | your message ].
% The header carries the slot number, the packet number in the slot and a
% CRC-8 (fhHeaderBits), so a receiver can join the hop sequence at any time.
% The radio streams the frames (not transmitRepeat), so the slot timing is
% set by the radio's sample clock. The transmitter is released on return,
% including after Ctrl+C.

    if nargin < 5, opts = struct(); end
    opts = fillDefaults(opts);

    % ---- Messages and their slot layouts ----
    messages = cellstr(hexMessages);
    nMsg = numel(messages);
    layouts = cell(nMsg, 1);
    for m = 1:nMsg
        [~, messages{m}] = hexToBits(messages{m});          % clean, upper case
        if numel(messages{m}) + 12 > cfg.maxHexChars
            error('Message %d is %d hex characters; with the 12-character hop header the maximum is %d.', ...
                  m, numel(messages{m}), cfg.maxHexChars - 12);
        end
        layouts{m} = fhPacketLayout(cfg, fh, 12 + numel(messages{m}));
    end

    cleanup = onCleanup(@() release(radioTx)); %#ok<NASGU>  % runs on return, error or Ctrl+C

    fs = cfg.sampleRate;
    lay = layouts{1};
    fprintf('\nHopping transmitter: %d packets per %.0f ms slot (%.2f ms each), %.0f ms guard.\n', ...
            lay.pktsPerSlot, 1e3*fh.dwell, 1e3*lay.pktSamples/fs, ...
            1e3*(lay.leadSamples + lay.trailSamples)/fs);

    display = [];
    if opts.showDisplay
        display = createTxDisplay();
        fprintf('Transmitting. Press Stop in the window (or Ctrl+C) to end.\n');
    else
        fprintf('Transmitting. Press Ctrl+C to end.\n');
    end

    slot = 0;
    nUnder = 0;
    msgIndex = 1;
    lastSwitch = tic;
    runTimer = tic;
    fprintf('[%7.1f s] Message: %s\n', 0, messages{msgIndex});

    while toc(runTimer) < opts.duration
        % ---- Next message when it is time (no restart needed) ----
        if nMsg > 1 && toc(lastSwitch) >= opts.messageInterval
            msgIndex = mod(msgIndex, nMsg) + 1;
            lastSwitch = tic;
            fprintf('[%7.1f s] Message: %s\n', toc(runTimer), messages{msgIndex});
        end
        msg = messages{msgIndex};
        lay = layouts{msgIndex};

        % ---- Build this slot's frame ----
        frame = fhBuildSlotFrame(cfg, lay, slot, msg);

        % ---- Hop and send ----
        [ch, fHz] = fhHopSequence(fh, slot);
        fhTune(radioTx, fh, ch);                             % retunes the LO
        nUnder = nUnder + double(radioTx(complex(frame)));   % keep it complex (see fhRunLoopback)

        if mod(slot, opts.statusEvery) == 0
            fprintf('[%7.1f s] slot %6d  ch %3d  %.3f MHz  underruns %d\n', ...
                    toc(runTimer), slot, ch, fHz/1e6, nUnder);
        end
        if ~isempty(display)
            if ~isgraphics(display.fig) || display.stopButton.Value
                break;                                       % Stop pressed / window closed
            end
            display.text.String = sprintf(['On air: %s\nslot %d   channel %d   %.3f MHz\n' ...
                '%.1f s elapsed   underruns %d'], msg, slot, ch, fHz/1e6, toc(runTimer), nUnder);
            drawnow limitrate;
        end
        slot = slot + 1;
    end

    txStats.slots        = slot;
    txStats.underruns    = nUnder;
    txStats.pktsPerSlot  = lay.pktsPerSlot;
    txStats.layout       = lay;
    txStats.secondsOnAir = toc(runTimer);
    fprintf('\nTransmission stopped: %d hops in %.1f s, %d underruns.\n', ...
            slot, txStats.secondsOnAir, nUnder);
    if nUnder > 0
        fprintf('  Underruns leave gaps on air. Close other programs, turn off showDisplay,\n');
        fprintf('  or use a longer dwell.\n');
    end
end

% ======================================================================
function d = createTxDisplay()
    d.fig = figure('Name', 'Hopping DQPSK Transmitter', 'NumberTitle', 'off', ...
                   'MenuBar', 'none', 'Position', [100 100 460 160]);
    d.text = uicontrol(d.fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03 0.05 0.75 0.85], 'HorizontalAlignment', 'left', ...
        'FontSize', 10, 'String', 'Starting...');
    d.stopButton = uicontrol(d.fig, 'Style', 'togglebutton', 'String', 'Stop', ...
        'Units', 'normalized', 'Position', [0.80 0.60 0.17 0.30], 'FontWeight', 'bold');
    drawnow;
end

function opts = fillDefaults(opts)
    defaults = struct('duration', Inf, 'messageInterval', 5, 'showDisplay', true, ...
                      'statusEvery', 20);
    names = fieldnames(defaults);
    for k = 1:numel(names)
        if ~isfield(opts, names{k}) || isempty(opts.(names{k}))
            opts.(names{k}) = defaults.(names{k});
        end
    end
end
