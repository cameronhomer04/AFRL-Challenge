function [block, overflowed] = captureBlock(radioRx, numFrames, maxFlushFrames)
% CAPTUREBLOCK  Capture one gap-free block of frames for the continuous receiver.
%
%   [block, overflowed] = captureBlock(radioRx, numFrames, maxFlushFrames)
%
%   radioRx        - comm.SDRuReceiver
%   numFrames      - frames per block
%   maxFlushFrames - 0 when the receiver is in burst mode (each burst is
%                    already gap-free). Otherwise, stale frames left in the
%                    radio's buffer while MATLAB was busy are read and thrown
%                    away first, until an overflow marks the gap or this many
%                    frames have been discarded.
%
%   block      - captured samples (double column)
%   overflowed - true if samples were dropped inside the block. The block is
%                still usable: the checksum catches a packet cut by the gap.

    % Throw away stale frames so the block starts with fresh, contiguous data.
    for k = 1:maxFlushFrames
        [~, ~, overflow] = radioRx();
        if overflow, break; end
    end

    frames = cell(numFrames, 1);
    overflowed = false;
    for k = 1:numFrames
        [rxFrame, dataLength, overflow] = radioRx();
        overflowed = overflowed || overflow;
        frames{k} = rxFrame(1:dataLength);
    end

    block = double(vertcat(frames{:}));
end
