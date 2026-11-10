function sdr = setupSdrNode(cfg, radio, role)
% SETUPSDRNODE  Create only the radio objects a node's role needs.
%
%   sdr = setupSdrNode(cfg, radio, role)
%
%   cfg   - settings from qpskConfig
%   radio - one element from findSdrRadios / selectSdrRadio. For role
%           "both" you may pass two, [txRadio, rxRadio], to transmit on
%           one radio and receive on another attached to the same computer.
%   role  - "tx"   transmit only (no receiver is created)
%           "rx"   receive only  (no transmitter is created)
%           "both" transmit and receive (loopback test, later a relay)
%
%   sdr   - struct with fields
%       role     the role, lower case
%       txRadio  radio used to transmit ([] if none)
%       rxRadio  radio used to receive  ([] if none)
%       tx       comm.SDRuTransmitter, or [] when not needed
%       rx       comm.SDRuReceiver,    or [] when not needed
%
% Release with releaseSdrNode(sdr) when finished.

    role = lower(string(role));
    if numel(radio) > 2 || (numel(radio) == 2 && role ~= "both")
        error('Pass one radio, or two ([txRadio, rxRadio]) for role "both".');
    end

    sdr.role    = role;
    sdr.txRadio = [];
    sdr.rxRadio = [];
    sdr.tx      = [];
    sdr.rx      = [];

    switch role
        case "tx"
            sdr.txRadio = radio(1);
        case "rx"
            sdr.rxRadio = radio(1);
        case "both"
            sdr.txRadio = radio(1);
            sdr.rxRadio = radio(end);       % same radio unless two were given
        otherwise
            error('Unknown role "%s". Use "tx", "rx" or "both".', role);
    end

    if ~isempty(sdr.txRadio)
        sdr.tx = createSdrTransmitter(cfg, sdr.txRadio);
    end
    if ~isempty(sdr.rxRadio)
        sdr.rx = createSdrReceiver(cfg, sdr.rxRadio);
    end
end
