function [ch, freqHz, offsetHz] = fhHopSequence(cfg, slots, allowed)
% FHHOPSEQUENCE  Channel for each hop slot, worked out from the shared key.
%
%   [ch, freqHz, offsetHz] = fhHopSequence(cfg, slots)
%   [ch, freqHz, offsetHz] = fhHopSequence(cfg, slots, allowed)
%
%   cfg     - struct from fhConfig (uses cfg.key, cfg.nCh, cfg.freqs, cfg.offsets)
%   slots   - hop slot counter(s), whole numbers from 0, e.g. 0:99
%   allowed - (optional) channel numbers to hop over, e.g. after dropping
%             bad channels. Default: cfg.allowed if that field is set
%             (runNode_FH sets it from excludeChannels), otherwise 1:cfg.nCh
%
%   ch       - channel number for each slot (same size as slots)
%   freqHz   - absolute centre frequency of that channel (Hz)
%   offsetHz - offset of that channel from cfg.fc (Hz)
%
% Slots are grouped into frames of numel(allowed) slots. Each frame is a
% pseudo-random permutation of the allowed channels, so every channel is
% used exactly once per frame (a receiver parked on ANY channel hears the
% transmitter within one frame). The same channel is never used twice in
% a row, including across frame boundaries.
%
% The permutation depends only on the key and the frame number, so the
% transmitter and receiver get the same answer without exchanging anything,
% as long as they use the same allowed list.
% It uses a plain 32-bit LCG (no MATLAB random streams), so the same
% sequence can be rebuilt in C, Python or GNU Radio from this file.

    if nargin < 3 || isempty(allowed)
        if isfield(cfg, 'allowed') && ~isempty(cfg.allowed)
            allowed = cfg.allowed;
        else
            allowed = 1:cfg.nCh;
        end
    end
    allowed = allowed(:)';
    n = numel(allowed);
    if n < 2
        error('fhHopSequence:allowed', 'At least 2 channels are needed to hop.');
    end
    if any(slots(:) < 0 | slots(:) ~= round(slots(:)))
        error('fhHopSequence:slots', 'Slot numbers must be whole numbers from 0.');
    end

    ch = zeros(size(slots));
    if n == 2                                      % only one way to never repeat
        ch(:) = allowed(mod(slots(:), 2) + 1);
        freqHz   = reshape(cfg.freqs(ch),   size(ch));
        offsetHz = reshape(cfg.offsets(ch), size(ch));
        return;
    end
    frames = floor(slots / n);
    for f = unique(frames(:))'
        perm = framePerm(cfg.key, f, n);
        sel = (frames == f);
        ch(sel) = allowed(perm(mod(slots(sel), n) + 1));
    end

    freqHz   = reshape(cfg.freqs(ch),   size(ch));
    offsetHz = reshape(cfg.offsets(ch), size(ch));
end

% ----------------------------------------------------------------------
function perm = framePerm(key, f, n)
% Permutation for frame f, adjusted so it never starts with the channel
% that ended frame f-1.
    perm = shuffle(key, f, n);
    if f > 0
        prev = shuffle(key, f - 1, n);
        if perm(1) == prev(end)
            perm([1 2]) = perm([2 1]);
        end
    end
end

function perm = shuffle(key, f, n)
% Fisher-Yates shuffle of 1:n driven by a 32-bit LCG seeded from key and f.
% All arithmetic is exact in doubles (products stay below 2^53).
    M = 2^32;
    x = mod(key + mod(f, M) * 2654435761, M);      % mix key and frame number
    x = mod(x, M);
    for k = 1:4                                    % warm up the generator
        x = mod(1664525 * x + 1013904223, M);
    end
    perm = 1:n;
    for i = n:-1:2
        x = mod(1664525 * x + 1013904223, M);
        j = floor(x / M * i) + 1;                  % top bits -> 1..i
        perm([i j]) = perm([j i]);
    end
end
