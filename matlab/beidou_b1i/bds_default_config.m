function cfg = bds_default_config()
%BDS_DEFAULT_CONFIG Normal, single-satellite B1I/D1 simulation; base MATLAB.
% All scene values are synthetic, NOT a recording or the real orbit of C12.
cfg.durationSeconds = 60;
cfg.segmentSeconds = 1;             % Storage boundary only; no waveform reset
cfg.keepFullFile = true;             % Also retain the continuous full recording
cfg.verifyFullFile = true;           % Reread full/segments and compare bytes
cfg.autoOverview = true;             % Plot and save after generation
cfg.overviewVisible = true;          % false: save without opening a window
cfg.plotMaxBins = 2000;              % Display envelope bins, NOT data decimation
cfg.analysisFftLength = 4096;         % Whole-record streaming averaged PSD
cfg.sampleRateHz = 8.184e6;           % 4 samples/chip
cfg.blockSamples = 163680;          % 20 ms; may change independently of frames
cfg.prn = 12;                      % Supported D1 codes: 6:37
cfg.bdtWeek = 1000;                 % Synthetic BDT week, not UTC
cfg.startSowSeconds = 240;          % Reception BDT seconds-of-week
cfg.cn0DbHz = 45;                   % Pre-filter C/N0, engineering assumption
cfg.signalPowerDbW = -158;          % Pre-filter power, engineering assumption
cfg.noiseEnabled = true;
cfg.randomSeed = 20261023;
cfg.receiverLlaDegM = [32.06, 118.79, 50]; % Fictional reference antenna
cfg.zenithTroposphereM = 2.3;        % Simple dry+wet effective zenith model
cfg.ionosphereHeightM = 375e3;
cfg.geometryStepSeconds = 0.02;
cfg.initialCarrierPhaseRad = 0.3;
cfg.filterLength = 65;              % Odd, symmetric Hamming-windowed FIR
cfg.lowpassCutoffHz = 2.8e6;        % One-sided cutoff; about 5.6 MHz total
cfg.txHardware = bds_tx_hardware_profile('transmitter_A'); % v4: enabled by default
cfg.outputDirectory = fullfile(pwd, 'bds_output');
cfg.outputName = 'b1i_single_normal';
% Every run gets a new unique subdirectory; existing runs are never overwritten.
end
