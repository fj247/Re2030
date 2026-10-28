function test_bds_capture_control()
%TEST_BDS_CAPTURE_CONTROL Run on the user's MATLAB R2024a. No graphics required.
sourceDirectory=fileparts(mfilename('fullpath'));
assert(strcmpi(fileparts(which('bds_generate')),sourceDirectory), ...
    'Another bds_generate shadows the integrated version; check MATLAB path.');
fprintf('Capture source: %s\n',which('bds_generate'));
root=tempname;mkdir(root);cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
job=fullfile(root,'job');mkdir(job);mkdir(fullfile(job,'detector'));
cfg=bds_default_config();cfg.durationSeconds=0.2;cfg.keepFullFile=false;
cfg.verifyFullFile=false;cfg.autoOverview=false;cfg.overviewVisible=false;
cfg.outputDirectory=fullfile(job,'private');
cfg.captureControl=struct('stopFile',fullfile(job,'STOP'), ...
 'progressFile',fullfile(job,'progress.json'),'limitFile',fullfile(job,'limit.json'), ...
 'detectorDirectory',fullfile(job,'detector'),'maxBytes',1, ...
 'firstSegmentFile',fullfile(job,'first_segment.json'));
test_bds_capture_stop();
result=bds_generate(cfg);
assert(result.numberComplexSamples>0 && result.numberComplexSamples<round(.2*cfg.sampleRateHz), ...
    'Capacity stop did not shorten the recording.');
assert(result.numberComplexSamples==cfg.blockSamples-(cfg.filterLength-1), ...
    'A one-byte budget should stop after the first output block.');
meta=bds_metadata(result.metadataFile);
assert(meta.verification.structuralPassed);
first=jsondecode(fileread(fullfile(job,'first_segment.json')));
assert(first.numberComplexSamples==result.numberComplexSamples);
assert(exist(fullfile(job,'detector',first.segments(1).fileName),'file')~=0);
assert(isempty(meta.waveformFile));assert(numel(meta.segments)==1);
segment=fullfile(job,'detector','segment_000001.iq.f32');
d=dir(segment);assert(d.bytes==8*result.numberComplexSamples);
assert(isempty(dir(fullfile(job,'detector','*.partial'))));
x=bds_read_samples(result.metadataFile,0,min(100,result.numberComplexSamples));
assert(all(isfinite(x)));assert(exist(fullfile(job,'limit.json'),'file')~=0);
% Stop before initialization is a valid empty outcome, not a truncated success.
job2=fullfile(root,'empty');mkdir(job2);mkdir(fullfile(job2,'detector'));
f=fopen(fullfile(job2,'STOP'),'w');fclose(f);
r=struct('taskDirectory',job2,'maxBytes',1024^3);
bds_capture_json(fullfile(job2,'request.json'),r);
bds_capture_entry(fullfile(job2,'request.json'));
g=jsondecode(fileread(fullfile(job2,'generated.json')));assert(g.empty);
fprintf('Capture stop/finalize contract passed.\n');
end
