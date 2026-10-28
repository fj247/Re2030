function test_bds_capture_worker()
%TEST_BDS_CAPTURE_WORKER Same native worker accepts two jobs without restarting.
cfg=bds_default_config();
bds_tx_design(cfg.txHardware,cfg.sampleRateHz,cfg.lowpassCutoffHz);
root=tempname;mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
lease=fullfile(root,'LEASE');touch(lease);
for k=1:2
    job=fullfile(root,sprintf('job%d',k));mkdir(job);mkdir(fullfile(job,'detector'));
    touch(fullfile(job,'STOP'));
    bds_capture_json(fullfile(job,'request.json'),struct('taskDirectory',job,'maxBytes',1024^3));
end
nextJob=1;started=tic;
driver=timer('ExecutionMode','fixedSpacing','Period',.1,'TimerFcn',@drive);
timerCleanup=onCleanup(@()deleteTimer(driver)); %#ok<NASGU>
start(driver);
bds_capture_worker(root,'generation');
assert(nextJob==3,'Worker did not complete both commands.');
for k=1:2
    job=fullfile(root,sprintf('job%d',k));
    generated=jsondecode(fileread(fullfile(job,'generated.json')));assert(generated.empty);
    done=jsondecode(fileread(fullfile(root,sprintf('test%d.json',k))));assert(done.exitCode==0);
    assert(isempty(dir(fullfile(job,'detector','*.f32'))));
end
fprintf('Persistent worker readiness, two commands, no pre-attack IQ, and shutdown passed.\n');
    function drive(~,~)
        touch(lease);
        if toc(started)>180
            touch(fullfile(root,'SHUTDOWN'));return;
        end
        if ~exist(fullfile(root,'ready.json'),'file'),return;end
        if nextJob>1 && ~exist(fullfile(root,sprintf('test%d.json',nextJob-1)),'file'),return;end
        if nextJob==3
            touch(fullfile(root,'SHUTDOWN'));return;
        end
        job=fullfile(root,sprintf('job%d',nextJob));
        bds_capture_json(fullfile(root,'command.json'),struct('id',sprintf('test%d',nextJob), ...
            'entry','bds_capture_entry','requestFile',fullfile(job,'request.json'), ...
            'logFile',fullfile(job,'generation.log')));
        nextJob=nextJob+1;
    end
end
function touch(path)
fid=fopen(path,'w');assert(fid>=0);fclose(fid);
end
function deleteTimer(driver)
stop(driver);delete(driver);
end
