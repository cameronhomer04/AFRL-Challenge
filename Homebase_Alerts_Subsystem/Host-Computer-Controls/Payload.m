%{
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           main.m
Author:         Cameron Homer
Date:           10/18/2026
Description:    Class for handling payload decoding and validity
%}

classdef Payload
    properties
        payload uint32 = 0
        sdrNode uint8 = 0
        modType string = "NONE"
        centerFreq double = 0.0
        checksum uint8 = 0
        isValid logical = false
    end

    methods
        function obj = Payload(rawPayload)
            if isstring(rawPayload) || ischar(rawPayload)
                obj.payload = uint32(hex2dec(rawPayload));
            else
                obj.payload = uint32(rawPayload);
            end
            % sdrNode is just the integer value of the first hex val
            obj.sdrNode = uint8(bitshift(bitand(obj.payload, hex2dec('F000000')), -24));
            % modType is the decoded string from the integer value of the
            % second hex val
            obj.modType = obj.decodeMod(uint8(bitshift(bitand(obj.payload, hex2dec('0F00000')), -20)));
            % centerFreq is the decoded double from the integer value of
            % the third-sixth hex val
            obj.centerFreq = obj.decodeFreq(uint16(bitshift(bitand(obj.payload, hex2dec('00FFFF0')), -4)));
            % Extract checksum
            obj.checksum = uint8(bitand(obj.payload, hex2dec('000000F')));
            % Determine payload validity
            obj.isValid = obj.validate();
        end

        function alertStruct = toAlertStruct(obj)
            alertStruct = struct(...
                'status', "ALERT", ...
                'center_freq', obj.centerFreq, ...
                'modulation', obj.modType, ...
                'node', double(obj.sdrNode) ...
            );
        end
    end

    methods (Access = private)
        function modStr = decodeMod(~, encodedMod)
            % Simple hard coded function to set our modType based on the
            % hex value received
            mods = ["FM", "QAM", "BPSK"];
            if encodedMod >= 0 && encodedMod < length(mods)
                modStr = mods(encodedMod + 1);
            else
                modStr = "UNKNOWN";
            end
        end
        
        % Simple function to decode our actually centerFreq value based on
        % the hex val received
        function freqMHz = decodeFreq(~, unshiftedFreq)
            freqMHz = 70 + (unshiftedFreq * .1);
        end

        % Simple function to validate our checksum
        function valid = validate(obj)
            sumHexDigits = bitand(bitshift(obj.payload, -24), 15) + ...
                           bitand(bitshift(obj.payload, -20), 15) + ...
                           bitand(bitshift(obj.payload, -16), 15) + ...
                           bitand(bitshift(obj.payload, -12), 15) + ...
                           bitand(bitshift(obj.payload, -8), 15) + ...
                           bitand(bitshift(obj.payload, -4), 15);

            calculatedChecksum = uint8(mod(sumHexDigits, 16));
            valid = (calculatedChecksum == obj.checksum);
        end
    end
end