%{
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           tcp_main.m
Author:         Cameron Homer
Date:           10/26/2026
Description:    Executable script for controlling the MATLAB server side
%}

function tcp_main()
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
    fprintf('  1. <7-hex payload> : Decode and inject a threat (e.g., 1100A0C)\n');
    fprintf('  2. reset           : Reset server back to SCANNING mode\n');
    fprintf('  3. status          : Display active alert JSON in terminal\n');
    fprintf('  4. exit            : Shutdown the server\n\n');

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
                    
                    % Instantly push updated state to connected mobile client
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
    % Only attempt to write if a TCP client is actively connected
    if server.Connected
        jsonBody = formatJsonArray(alertState);
        write(server, uint8([jsonBody newline]));
    else
        fprintf('--> INFO: No client connected to receive stream update.\n');
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
        
        % Process out-of-band RESET command from Flutter app
        if strcmp(inboundText, 'RESET')
            setAlertsFcn(defaultScanningStruct);
            fprintf('\n--> REMOTE RESET RECEIVED: Cleared alerts via Mobile App.\nServer Console >> ');
            broadcastState(src, defaultScanningStruct);
        else
            % If client requests state explicitly upon connection, push current state back
            broadcastState(src, getAlertsFcn());
        end
    end
end