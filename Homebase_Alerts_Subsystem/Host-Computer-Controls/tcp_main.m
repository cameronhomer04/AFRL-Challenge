%{
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           tcp_main.m
Author:         Cameron Homer
Date:           10/26/2026
Description:    Executable script for controlling the MATLAB server side
%}

function tcp_main()
    addpath(fullfile(pwd, '', 'Mesh_Network_Subsystem'))
    
    port = 5000;
    defaultScanningStruct = struct('status', "SCANNING", 'center_freq', 0.0, 'modulation', "NONE", 'node', 0);
    activeAlerts = defaultScanningStruct;
    
    function current = getAlerts()
        current = activeAlerts;
    end

    function setAlerts(newAlerts)
        activeAlerts = newAlerts;
    end

    try
        server = tcpserver("0.0.0.0", port);
        configureCallback(server, "byte", 1, @(src, evt) handleTcpClient(src, evt, @getAlerts, @setAlerts, defaultScanningStruct));
    catch err
        error('Failed to bind tcpserver on port %d: %s', port, err.message);
    end
        
    fprintf('====================================================\n');
    fprintf('  MATLAB Raw TCP Server listening on port %d...\n', port);
    fprintf('====================================================\n');
    fprintf('AVAILABLE TEST COMMANDS:\n');
    fprintf('  1. sdr             : Trigger USRP B210 RF loopback capture\n');
    fprintf('  2. <7-hex payload> : Manually inject a threat (e.g., 1100A0C)\n');
    fprintf('  3. reset           : Reset server back to SCANNING mode\n');
    fprintf('  4. status          : Display active alert JSON in terminal\n');
    fprintf('  5. exit            : Shutdown the server\n\n');

    while true
        drawnow;
        userInput = strtrim(input('Server Console >> ', 's'));
        
        if strcmpi(userInput, 'exit')
            fprintf('Shutting down server...\n');
            delete(server);
            break;
            
        elseif strcmpi(userInput, 'reset')
            activeAlerts = defaultScanningStruct;
            fprintf('--> STATE RESET: Cleared all alerts. System is in SCANNING mode.\n');
            broadcastState(server, activeAlerts);
            
        elseif strcmpi(userInput, 'status')
            fprintf('--> CURRENT JSON OUTPUT:\n%s\n', formatJsonArray(activeAlerts));
            
        elseif strcmpi(userInput, 'sdr')
            fprintf('--> Triggering USRP B210 RF Loopback Capture...\n');
            try
                hexPayload = runNodeFunctionVersion();
                
                if strlength(hexPayload) > 0
                    p = Payload(hexPayload);
                    if p.isValid
                        newAlert = p.toAlertStruct();
                        
                        if activeAlerts(1).node == 0 && strcmp(activeAlerts(1).status, "SCANNING")
                            activeAlerts = newAlert;
                        else
                            activeAlerts(end+1) = newAlert; %#ok<AGROW>
                        end
                        
                        fprintf('--> B210 RF ALERT CAPTURED & INJECTED! (Node %d | %.2f MHz | %s)\n', ...
                            p.sdrNode, p.centerFreq, p.modType);
                        
                        broadcastState(server, activeAlerts);
                    else
                        fprintf('--> B210 Payload Checksum Failed (%s).\n', hexPayload);
                    end
                else
                    fprintf('--> B210 RF Capture failed or returned empty payload.\n');
                end
            catch err
                fprintf('--> ERROR executing SDR capture: %s\n', err.message);
            end
            
        elseif ~isempty(userInput)
            try
                p = Payload(userInput);
                
                if p.isValid
                    newAlert = p.toAlertStruct();
                    
                    if activeAlerts(1).node == 0 && strcmp(activeAlerts(1).status, "SCANNING")
                        activeAlerts = newAlert;
                    else
                        activeAlerts(end+1) = newAlert; %#ok<AGROW>
                    end
                    
                    fprintf('--> CHECKSUM PASSED! Total Active Alerts: %d (Added Node %d | %.2f MHz | %s)\n', ...
                        length(activeAlerts), p.sdrNode, p.centerFreq, p.modType);
                    
                    broadcastState(server, activeAlerts);
                else
                    fprintf('--> CHECKSUM FAILED! Payload dropped.\n');
                end
            catch err
                fprintf('--> ERROR: Invalid command or payload format (%s)\n', err.message);
            end
        end
    end
end

%% Helper Function: Broadcasts JSON state string over TCP pipe
function broadcastState(server, alertState)
    if server.Connected
        jsonBody = formatJsonArray(alertState);
        write(server, uint8([jsonBody newline]));
    else
        fprintf('--> INFO: No mobile client connected to receive stream update.\n');
    end
end

%% Helper Function: Ensures standard JSON Array format []
function jsonStr = formatJsonArray(alertState)
    jsonStr = jsonencode(alertState);
    if ~startsWith(jsonStr, '[')
        jsonStr = sprintf('[%s]', jsonStr);
    end
end

%% TCP Callback Function: Handles inbound commands from mobile client
function handleTcpClient(src, ~, getAlertsFcn, setAlertsFcn, defaultScanningStruct)
    pause(0.01);
    
    bytesAvailable = src.NumBytesAvailable;
    if bytesAvailable > 0
        inboundBytes = read(src, bytesAvailable, "uint8");
        inboundText = strtrim(char(inboundBytes));
        
        if strcmp(inboundText, 'RESET')
            setAlertsFcn(defaultScanningStruct);
            fprintf('\n--> REMOTE RESET RECEIVED: Cleared alerts via Mobile App.\nServer Console >> ');
            broadcastState(src, defaultScanningStruct);
        else
            broadcastState(src, getAlertsFcn());
        end
    end
end