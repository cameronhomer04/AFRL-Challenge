% Continuous Beacon Generator for Sweeping Verification
tx = comm.SDRuTransmitter(...
    'Platform',             'B210', ...
    'SerialNum',            '3511EE2', ...
    'ChannelMapping',       2, ...             % RF 1
    'CenterFrequency',      915e6, ...         % Target test frequency
    'MasterClockRate',      10e6, ...
    'InterpolationFactor',  2, ...            % 5 MSPS
    'Gain',                 20);

% 2. Generate continuous Complex Baseband Waveform (100 kHz tone)
fs = 10e6 / 2;                                % 5 MSPS
t = (0:4095)' / fs;
tx_wave = complex(cos(2*pi*100e3*t), sin(2*pi*100e3*t));

fprintf('Transmitting 915 MHz beacon on RF 1... Press Ctrl+C to stop.\n');

try
    while true
        % Calling tx(tx_wave) sends the buffer down to the FPGA/AD9361 for RF output
        tx(tx_wave); 
    end
catch ME
    fprintf('Transmission stopped: %s\n', ME.message);
end

release(tx);