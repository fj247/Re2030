function test_bds_capture_first_segment()
%TEST_BDS_CAPTURE_FIRST_SEGMENT Native MATLAB storage/range/graphics regression.
root=tempname;mkdir(root);cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
detector=fullfile(root,'detector');mkdir(detector);
cfg=bds_default_config();cfg.segmentSeconds=0.05;cfg.keepFullFile=false;
cfg.captureControl=struct('detectorDirectory',detector);
fs=cfg.sampleRateHz;N=round(.12*fs);part=round(.05*fs);
% Distinct later data makes accidental whole-run statistics observable.
x=complex(ones(N,1,'single'),zeros(N,1,'single'));x(part+1:end)=100+20i;
w=BdsFileWriter(root,'test',cfg,N);
% Cross storage boundaries inside write calls, like the generation block loop.
split=round(.037*fs);w.write(x(1:split));w.write(x(split+1:end));w.finish();
assert(numel(w.Records)==3);
assert(isequal([w.Records.sampleCount],[part part N-2*part]));
assert(sum([w.Records.bytes])==8*N);
assert(isempty(dir(fullfile(detector,'*.partial'))));
m=struct('sourceDirectory',root,'segmentDirectory',detector,'segments',w.Records, ...
    'numberComplexSamples',N,'segmentSamples',part,'sampleRateHz',fs,'configuration',cfg);
assert(isequal(bds_read_samples(m,0,N),x),'Segmentation changed the sample stream.');
first=bds_capture_first_segment(m);
assert(numel(first.segments)==1 && first.numberComplexSamples==part);
% Make later segments inaccessible: representative analysis must not open them.
movefile(fullfile(detector,w.Records(2).fileName),fullfile(root,'later.bin'));
stats=bds_analyze(first,0,first.numberComplexSamples,100,4096);
assert(stats.sampleCount==part && abs(stats.totalMeanPowerW-1)<1e-10);
rejected=false;
try
    bds_read_samples(first,part-1,2);
catch
    rejected=true;
end
assert(rejected,'First-segment view permitted reading beyond its boundary.');
% A <20 ms capture must still publish three separate overview figures.
short=m;short.numberComplexSamples=round(.01*fs);
short.segments=short.segments(1);short.segments.sampleCount=short.numberComplexSamples;
short.segments.durationSeconds=.01;short.segments.bytes=8*short.numberComplexSamples;
metadataFile=fullfile(root,'short.json');bds_capture_json(metadataFile,short);
bds_capture_json(fullfile(root,'generated.json'),struct('metadataFile',metadataFile));
requestFile=fullfile(root,'request.json');bds_capture_json(requestFile,struct('taskDirectory',root));
bds_capture_analyze(requestFile);
a=jsondecode(fileread(fullfile(detector,'analysis.json')));
assert(strcmp(a.overview,'saved') && strcmp(a.presence,'insufficient_samples'));
assert(a.sourceSampleCount==short.numberComplexSamples);
for name={'i_envelope.png','q_envelope.png','mean_psd.png'}
    info=imfinfo(fullfile(detector,name{1}));assert(info.Width>0 && info.Height>0);
end
assert(~exist(fullfile(detector,'prn_search.png'),'file'));
assert(~exist(fullfile(detector,'overview.png'),'file'));
fprintf('50 ms segmentation, continuous samples, first-segment bounds and short-capture figures passed.\n');
end
