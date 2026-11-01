function releaseSdrNode(sdr)
% RELEASESDRNODE  Stop and release whichever radio objects a node created.
%
%   releaseSdrNode(sdr)
%
% Safe to call more than once. Releasing the transmitter also stops a
% transmitRepeat that is still running.

    if ~isempty(sdr.tx), release(sdr.tx); end
    if ~isempty(sdr.rx), release(sdr.rx); end
end
