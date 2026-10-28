function test_bds_capture_stop()
%TEST_BDS_CAPTURE_STOP No waveform generation or filesystem size refresh needed.
root=tempname;mkdir(root);cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
cfg.captureControl=struct('stopFile',fullfile(root,'STOP'), ...
    'limitFile',fullfile(root,'limit.json'),'maxBytes',16);
assert(~bds_capture_stop(cfg,0));
assert(~bds_capture_stop(cfg,1));
% Deliberately no I/Q files exist: successful-write count alone is authoritative.
[stop,reason]=bds_capture_stop(cfg,2);
assert(stop && strcmp(reason,'storage_limit'));
limit=jsondecode(fileread(cfg.captureControl.limitFile));
assert(limit.sampleCount==2 && limit.bytes==16);
f=fopen(cfg.captureControl.stopFile,'w');assert(f>=0);fclose(f);
[stop,reason]=bds_capture_stop(cfg,0);
assert(stop && strcmp(reason,'requested'));
delete(cfg.captureControl.stopFile);
cfg.captureControl.serviceLeaseFile=fullfile(root,'LEASE');
[stop,reason]=bds_capture_stop(cfg,0);
assert(stop && strcmp(reason,'service_interrupted'));
f=fopen(cfg.captureControl.serviceLeaseFile,'w');assert(f>=0);fclose(f);
assert(~bds_capture_stop(cfg,0));
fprintf('Capture stop ledger and service-lease checks passed.\n');
end
