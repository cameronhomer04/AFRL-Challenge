function [st, ch, slotNow] = fhRxFollow(st, cfg, slot, pktIdx, pktsPerSlot, tNow)
% FHRXFOLLOW  Keep a hop-following receiver on the transmitter's channel.
%
%   st = fhRxFollow([], cfg)                       % start (acquiring)
%   [st, ch] = fhRxFollow(st, cfg)                 % no packet this frame
%   [st, ch] = fhRxFollow(st, cfg, slot)           % packet with good header
%   [st, ch] = fhRxFollow(st, cfg, slot, pktIdx, pktsPerSlot)
%
%   st          - follower state, carried from call to call
%   cfg         - struct from fhConfig (same Key and Dwell as the transmitter)
%   slot        - slot number from fhReadHeader ([] if nothing was decoded)
%   pktIdx      - packet number inside the slot (from fhReadHeader), optional
%   pktsPerSlot - packets the transmitter sends per slot, optional; with
%                 pktIdx it tells the follower how far into the slot it is
%   tNow        - (optional) current time in s, for simulation; by default
%                 the follower uses its own tic/toc clock
%
%   ch      - channel to listen on now: pass it to fhTune(rx, cfg, ch)
%   slotNow - slot the follower thinks the transmitter is on (NaN if lost)
%
% How it works
%   Acquiring: park on one channel (st.parkCh, default the first channel of
%   the sequence). Every channel comes up once per frame of nCh slots, so
%   the transmitter is heard within nCh x dwell seconds.
%   Locked: each good header gives the slot number and roughly where in the
%   slot it was sent. From then on the follower predicts the current slot
%   from elapsed time and tunes to fhHopSequence(cfg, slotNow).
%   Lost: after st.lostAfter slots with no good header it goes back to
%   acquiring.
%
% Typical receive loop:
%   st = fhRxFollow([], cfg);
%   while running
%       fhTune(rx, cfg, st.ch);
%       samples = rx();
%       [bits, found] = myQpskReceiver(samples);      % your existing code
%       if found
%           [slot, k, ok] = fhReadHeader(bits);
%           if ok, st = fhRxFollow(st, cfg, slot, k, pktsPerSlot); continue; end
%       end
%       st = fhRxFollow(st, cfg);                       % nothing decoded
%   end

    if nargin < 3, slot = []; end
    if nargin < 4 || isempty(pktIdx), pktIdx = 0; end
    if nargin < 5 || isempty(pktsPerSlot), pktsPerSlot = 1; end

    % ---- Start ----
    if isempty(st)
        st.t0        = tic;
        st.locked    = false;
        st.parkCh    = fhHopSequence(cfg, 0);
        st.lostAfter = 3;          % slots without a header before giving up
        st.refSlot   = NaN;        % slot of the last good header
        st.refStart  = NaN;        % estimated time that slot began (s)
        st.lastHeard = NaN;        % time of the last good header (s)
        st.ch        = st.parkCh;
        st.nHeaders  = 0;
        ch = st.ch; slotNow = NaN;
        return;
    end

    if nargin < 6 || isempty(tNow)
        tNow = toc(st.t0);
    end

    % ---- A good header: lock to it ----
    if ~isempty(slot)
        st.locked    = true;
        st.refSlot   = slot;
        st.refStart  = tNow - (pktIdx + 0.5) / pktsPerSlot * cfg.dwell;
        st.lastHeard = tNow;
        st.nHeaders  = st.nHeaders + 1;
    end

    % ---- Predict the current slot ----
    if st.locked
        slotNow = st.refSlot + floor((tNow - st.refStart) / cfg.dwell);
        if (tNow - st.lastHeard) > st.lostAfter * cfg.dwell
            st.locked = false;                 % lost: back to acquiring
        end
    end

    if st.locked
        st.ch = fhHopSequence(cfg, slotNow);
    else
        slotNow = NaN;
        st.ch = st.parkCh;
    end
    ch = st.ch;
end
