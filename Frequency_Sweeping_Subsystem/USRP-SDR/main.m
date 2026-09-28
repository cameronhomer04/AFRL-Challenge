%{
Project:        AFRL Challenge
Subsystem:      Frequency Sweeping
File:           main.m
Author:         Cameron Homer
Date:           09/25/2026
Description:    Executable script for the frequency sweeping subsystem. This script will run the frequency sweeping receiver and the focused receiver in series.
%}

% Reminder of some useful USRP B210 values that I'm going to not use for but likely will for config on a final version of the subsystem
MIN_FREQ = 70e6;
MAX_FREQ = 6e9;
MAX_STEP_FREQ = 56e6;

% Configure USRP
START_FREQ = 900e6;                                     % We may want to eventually set this above the FM Broadcast range so we don't detect Broadcast Radio Signals (For now this may actually be useful for testing though)
END_FREQ = 930e6;                                       % Eventually this needs to be set to the higher end of the sweeping range probably something like MAX_FREQ-(STEP_FREQ/2)
STEP_FREQ = 5e6;                                        % This just needs to be some value below MAX_STEP_FREQ so we never skip any frequencies (may make sense to eventually have this be MAX_STEP_FREQ exactly)
MASTER_CLOCK_RATE = 10e6;                               % This should be fine between 10-61.44 MHz according to Gemini and is used to set our sampling rate
DECIMATION_FACTOR = 2;
SAMPLE_RATE = MASTER_CLOCK_RATE / DECIMATION_FACTOR;
GAIN = 45.0;                                            % There is no auto gain setting like in Python for the RTL so this probably needs to be a variable that gets fine tuned to some extent
SAMPLES_PER_FRAME = 65536;                              % Equivalent to setting the .read_samples(256 * 1024) in python script, setting to 65536 b/c that is what the FMSpectrum test file does
FOCUSED_TIME = 1.0;                                     % This is mostly going to be determined by how many spectrogram samples we need for our CNN when in the FOCUS state
POWER_THRESHOLD = 50.0;                                 % This is for the rudimentary peak detection module that I'm using at the moment. Ideally if this variable remains needed, Anusree determines what it should be

% Set testing flag
testing = true;

% Initialize USRP
USRP = comm.SDRuReceiver(...
    'Platform',             'B210', ...
    'SerialNum',            '3511EE2', ...
    'ChannelMapping',       1, ...
    'CenterFrequency',      START_FREQ, ...
    'MasterClockRate',      MASTER_CLOCK_RATE, ...
    'DecimationFactor',     DECIMATION_FACTOR, ...
    'SamplesPerFrame',      SAMPLES_PER_FRAME, ...
    'Gain',                 GAIN, ...
    'ReceiveAntennaPort',   'TX/RX');

% Initialize Spectrum Analyzer for validation
if testing
    sa = spectrumAnalyzer(...
        'SampleRate',       SAMPLE_RATE, ...
        'FrequencyOffset',  START_FREQ, ...
        'NumInputPorts',    1, ...
        'ShowLegend',       true, ...
        'Title',            'USRP B210 Sweeping & Focused State Machine');
end


% Execute frequency sweep & then do focused frequency generation for some time
state = "SWEEPING";
sweepingUp = true;
try
    while true
        switch state
            case "SWEEPING"
                [focusFreq, sweepingUp] = sweeping_rx(USRP, sweepingUp, START_FREQ, END_FREQ, STEP_FREQ, SAMPLE_RATE, POWER_THRESHOLD);

                if testing
                    sa.FrequencyOffset = USRP.CenterFrequency;
                    [iqdata, len, ~] = USRP();
                    if len > 0, sa(iqdata); end
                end

                if ~isnan(focusFreq)
                    fprintf('Peak Detected at %.2f MHz! Switching to FOCUSED.\n', focusFreq/1e6);
                    state = "FOCUSED";
                    USRP.CenterFrequency = focusFreq;
                    focusTimer = tic;
                end

            case "FOCUSED"
                focused_rx(USRP);           % For now, I am still using this function (but obviously it is stupid to) so if functionality doesn't change eventually this should just be here in one spot
                
                if testing
                    sa.FrequencyOffset = USRP.CenterFrequency;
                    [iqdata, len, ~] = USRP();
                    if len > 0, sa(iqdata); end
                end

                if toc(focusTimer) >= FOCUSED_TIME
                    fprintf('Focus time expired. Resuming SWEEPING...\n');
                    state = "SWEEPING";
                end
        end
    end
catch ME
    fprintf('Streaming stopped or error occurred: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('Error location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

release(USRP);

%{
% --- Create Spectrum Analyzer for Single-Channel Visual Verification ---
sa = spectrumAnalyzer(...
    'SampleRate',          SAMPLE_RATE, ...
    'CenterFrequency',     START_FREQ, ...
    'NumInputPorts',       1, ...
    'ChannelNames',        {'RF 0 (TX/RX)'}, ...
    'ShowLegend',          true, ...
    'Title',               sprintf('USRP B210 Signal Test @ %.1f MHz', DEFAULT_FREQ/1e6));

fprintf('Starting RF 0 (TX/RX) streaming test... Press Ctrl+C in Command Window to stop.\n');

% --- Streaming Verification Loop ---
try
    fprintf('Streaming started...\n');
    
    while true
        % Step 1: Read I/Q buffer from USRP B210 RF 0
        [iq_data, len, overrun] = USRP();
        
        if len > 0
            % Step 2: Display live PSD on Spectrum Analyzer
            sa(iq_data);
            
            % Step 3: Check for buffer overrun (dropped USB frames)
            if overrun
                warning('USB Buffer Overrun Detected! Consider reducing sample rate or frame size.');
            end
        end
    end

catch ME
    fprintf('Streaming stopped or error occurred: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('Error location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

% --- Cleanup Hardware Resources ---
release(USRP);
release(sa);
fprintf('USRP session released cleanly.\n');
%}