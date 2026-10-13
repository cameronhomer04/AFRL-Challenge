function iq = capture_IQ()
%% ---- User settings ----
serialNum   = '3511EE2';    % skips findsdru
fc          = 2.4e9;        % center frequency (Hz)
masterClock = 20e6;         % Hz
decim       = 4;            % fs = masterClock/decim = 2.5 MS/s (lower = safer)
gain        = 30;           % dB; lower it if the clip check below warns
numSamps    = 1e6;          % samples to keep
frameLen    = 50000;        % samples per frame (bigger = fewer calls = fewer overflows)
useBurst    = true;         % set false if burst mode still overflows; lost samples
                            % are then counted and reported instead of aborting
dropSamps   = 1000;         % startup transient to discard
outFile     = 'capture.mat';
doPlot      = true;

fs        = masterClock/decim;                 % 10 MS/s
numFrames = ceil((numSamps + dropSamps)/frameLen);

%% ---- Create the receiver and guarantee it gets released ----
rx = comm.SDRuReceiver( ...
    'Platform',         'B210', ...
    'SerialNum',        serialNum, ...
    'CenterFrequency',  fc, ...
    'MasterClockRate',  masterClock, ...
    'DecimationFactor', decim, ...
    'Gain',             gain, ...
    'SamplesPerFrame',  frameLen, ...
    'OutputDataType',   'double');
if useBurst
    rx.EnableBurstMode  = true;
    rx.NumFramesInBurst = numFrames;
end
cleanupObj = onCleanup(@() safeRelease(rx)); 

%% ---- Capture ----
buf  = complex(zeros(numFrames*frameLen, 1));
idx  = 0;
lost = 0;
maxCalls = numFrames*20;      % guard against an endless loop
calls = 0;

while idx < numFrames*frameLen && calls < maxCalls
    calls = calls + 1;
    [data, len, lostSamps] = rx();
    if len > 0
        buf(idx+(1:len)) = data(1:len);
        idx = idx + len;
    end
    lost = lost + lostSamps;
end

if idx < numFrames*frameLen
    warning('capture_IQ:short', 'Only %d of %d samples received.', idx, numFrames*frameLen);
end

%% ---- Post-process ----
iq = buf(1:idx);
iq = iq(dropSamps+1:end);
if numel(iq) > numSamps
    iq = iq(1:numSamps);
end

fprintf('Captured %d samples at %.2f MS/s, %d lost samples\n', numel(iq), fs/1e6, lost);
if lost > 0
    warning('capture_IQ:lost', 'Samples were lost. Lower the sample rate (raise decim).');
end

peak = max(abs(iq));
fprintf('Peak magnitude: %.3f, mean power: %.3e\n', peak, mean(abs(iq).^2));
if peak > 0.9
    warning('capture_IQ:clip', 'Signal near full scale (clipping likely). Lower the gain.');
end

save(outFile, 'iq', 'fs', 'fc');
fprintf('Saved to %s\n', outFile);

%% ---- Quick look ----
if doPlot
    figure;
    pspectrum(iq, fs, 'FrequencyLimits', [-fs/2 fs/2]);
    title(sprintf('Baseband spectrum (center %.3f GHz)', fc/1e9));
end
end

function safeRelease(obj)
% Release without throwing, so cleanup never masks the original error.
try
    release(obj);
catch
end
end
