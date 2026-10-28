% RUN_BDS_SIMULATION MATLAB R2024a, no specialized toolbox required.
clear; clc;
addpath(fileparts(mfilename('fullpath')));
cfg=bds_default_config();
% Default profile A; choose B BEFORE calling bds_generate:
% cfg.txHardware=bds_tx_hardware_profile('transmitter_B');
% cfg.txHardware.enabled=false; % Original ideal TX path
cfg.durationSeconds=60;             % Try 5 or 10 for an initial run
cfg.segmentSeconds=1;               % Last segment keeps its actual length
cfg.keepFullFile=true;              % Segments AND one identical full recording
cfg.autoOverview=true;              % Automatically plot/save the whole-run overview
cfg.outputDirectory=fullfile(fileparts(mfilename('fullpath')),'bds_output');
result=bds_generate(cfg);
disp(result);
% Manual only: choose a complete segment or zoom into original samples.
% bds_quicklook(result.metadataFile,1)
% bds_quicklook(result.metadataFile,2,0.1,0.0001)
% [iq,meta]=bds_read_iq(result.metadataFile,0,0.02,2);

% Manual, independent signal-presence evidence from saved raw I/Q:
% evidence=bds_validate_signal(result.metadataFile);

% Manual hardware model diagnostics (not RF fingerprint classification):
% bds_tx_diagnostics(result.metadataFile);
