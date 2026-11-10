function [symbols, phaseIncrements] = dqpskModulate(bits)
% DQPSKMODULATE  pi/4-DQPSK modulation of a bit column.
%
%   [symbols, phaseIncrements] = dqpskModulate(bits)
%
%   bits            - vector of 0/1, even length
%   symbols         - complex unit-magnitude symbols (column)
%   phaseIncrements - phase change into each symbol, pi/4 + dibit*pi/2
%
% Dibit mapping: 00 -> pi/4, 01 -> 3pi/4, 10 -> 5pi/4, 11 -> 7pi/4.
% Each symbol's phase is the previous phase plus its increment.

    bits = bits(:);
    if mod(numel(bits), 2) ~= 0
        error("Packet bit count must be even for DQPSK.");
    end

    bitPairs = reshape(bits, 2, []).';
    dibits   = 2*bitPairs(:,1) + bitPairs(:,2);

    phaseIncrements = pi/4 + dibits*(pi/2);
    symbols = exp(1j * cumsum(phaseIncrements));
end
