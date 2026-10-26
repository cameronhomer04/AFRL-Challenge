%{
Project:        AFRL Challenge
Subsystem:      Homebase Alerts
File:           http_main.m
Author:         Cameron Homer
Date:           10/18/2026
Description:    Executable script for controlling the MATLAB server side (Legacy)
%}

function http_main()
    port = 5000;
    defaultScanningStruct = struct('status', "SCANNING", 'center_freq', 0.0, 'modulation', "NONE", 'node', 0);
    activeAlerts = defaultScanningStruct;
    function current = getAlerts()
        current = activeAlerts;
    end
    try
        server = tcpserver("0.0.0.0", port);
        configureCallback(server, "byte", 1, @(src, evt) handleHttpClient(src, evt, @getAlerts));
    catch err
        error('Failed to bind tcpserver on port %d: %s', port, err.message);
    end
    
    fprintf('====================================================\n');
    fprintf('  MATLAB HTTP Server listening on port %d...\n', port);
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
    
        elseif strcmpi(userInput, 'status')
            fprintf('--> CURRENT JSON OUTPUT:\n%s\n', jsonencode(activeAlerts));
    
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
                else
                    fprintf('--> CHECKSUM FAILED! Payload dropped.\n');
                end
            catch err
                fprintf('--> ERROR: Invalid command or payload format (%s)\n', err.message);
            end
        end
    end
end

function handleHttpClient(src, ~, getAlertsFcn)
    pause(0.01);
    
    bytesAvailable = src.NumBytesAvailable;
    if bytesAvailable > 0
        read(src, bytesAvailable, "uint8");
        currentAlerts = getAlertsFcn();
        jsonBody = jsonencode(currentAlerts);
        if ~startsWith(jsonBody, '[')
            jsonBody = sprintf('[%s]', jsonBody);
        end
    
        httpResponse = sprintf([...
            'HTTP/1.1 200 OK\r\n' ...
            'Content-Type: application/json; charset=utf-8\r\n' ...
            'Content-Length: %d\r\n' ...
            'Access-Control-Allow-Origin: *\r\n' ...
            'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n' ...
            'Access-Control-Allow-Headers: *\r\n' ...
            'Connection: close\r\n\r\n' ...
            '%s'], length(jsonBody), jsonBody);
    
        write(src, uint8(httpResponse));
    end
end