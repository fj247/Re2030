function bds_capture_worker(directory,role)
%BDS_CAPTURE_WORKER Warm once; no waveform is generated until a command arrives.
fprintf('MATLAB version: %s\n',version);
fprintf('Capture source: %s\n',which('bds_generate'));
fprintf('Worker role: %s\n',role);
cfg=bds_default_config();
if strcmp(role,'generation')
    % Reusable deterministic coefficients only. No TX sample state or IQ files.
    bds_tx_design(cfg.txHardware,cfg.sampleRateHz,cfg.lowpassCutoffHz);
    bds_prn(cfg.prn);
else
    fft(zeros(round(cfg.sampleRateHz/1000),1));
    gammaincinv(.5,40);
end
bds_capture_json(fullfile(directory,'ready.json'),struct('ready',true));
commandFile=fullfile(directory,'command.json');
leaseFile=fullfile(directory,'LEASE');
while ~exist(fullfile(directory,'SHUTDOWN'),'file')
    lease=dir(leaseFile);
    if isempty(lease) || (now-lease.datenum)*86400>30, break; end
    if ~exist(commandFile,'file'), pause(.05);continue; end
    command=jsondecode(fileread(commandFile));delete(commandFile);
    code=0;
    try
        diary(command.logFile);diary on;
        r=jsondecode(fileread(command.requestFile));
        if strcmp(command.entry,'bds_capture_entry')
            phase='generation';
        elseif strcmp(command.entry,'bds_capture_analyze')
            phase='analysis';
        else
            error('BDS:WorkerCommand','Unknown capture command.');
        end
        bds_capture_json(fullfile(r.taskDirectory,[phase '_entered.json']),struct('entered',true));
        feval(command.entry,command.requestFile);
    catch err
        code=1;
        fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
    end
    diary off;
    bds_capture_json(fullfile(directory,[command.id '.json']),struct('exitCode',code));
end
end
