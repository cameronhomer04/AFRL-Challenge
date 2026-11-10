function frame = fhBuildSlotFrame(cfg, lay, slot, hexMessage)
% FHBUILDSLOTFRAME  One hop slot of samples, ready to send.
%
%   frame = fhBuildSlotFrame(cfg, lay, slot, hexMessage)
%
%   cfg        - settings from qpskConfig
%   lay        - layout from fhPacketLayout(cfg, fh, 12 + numel(hexMessage))
%   slot       - hop slot number (goes into every packet's header)
%   hexMessage - cleaned, upper-case message (char), without the header
%
%   frame - complex single column, lay.slotSamples long:
%     [ lead silence | packet 0 | gap | packet 1 | gap | ... | trail silence ]
%   Packet k carries [ fhHeaderBits(slot, k) as 12 hex chars | hexMessage ].

    frame = complex(zeros(lay.slotSamples, 1, 'single'));
    for k = 0:lay.pktsPerSlot-1
        hdrHex = bitsToHex(fhHeaderBits(slot, k));       % 12 hex characters
        bits = buildPacketBits([hdrHex, hexMessage], cfg);
        w = pulseShapeTx(dqpskModulate(bits), cfg);
        s0 = lay.leadSamples + k*lay.pktStep;
        frame(s0 + (1:numel(w))) = w;
    end
end
