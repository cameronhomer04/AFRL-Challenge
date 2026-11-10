function bits = makePreambleBits(numBits)
% MAKEPREAMBLEBITS  Deterministic pseudo-random preamble from a 7-bit LFSR.
%
%   bits = makePreambleBits(numBits)
%
% numBits must be even because DQPSK carries 2 bits per symbol.
% Every node generates the same preamble, so the receiver knows it in advance.

    if mod(numBits, 2) ~= 0
        error("Preamble length must be even for DQPSK.");
    end

    state = logical([1 0 0 0 0 0 1]);     % initial LFSR state
    bits = zeros(numBits, 1);

    for k = 1:numBits
        bits(k) = state(7);
        feedback = xor(state(7), state(6));   % PRBS-style feedback taps
        state = [feedback state(1:6)];
    end
end
