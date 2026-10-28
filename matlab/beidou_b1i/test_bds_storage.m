function test_bds_storage(includePlots)
%TEST_BDS_STORAGE Deterministic fixtures: arbitrary boundaries, tail, PSD, plots.
if nargin<1, includePlots=true; end
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
c=bds_default_config(); c.sampleRateHz=1024; c.segmentSeconds=1000/1024;
c.analysisFftLength=256; c.plotMaxBins=32; c.overviewVisible=false;
N=10003; n=(0:N-1)';
x=complex(single(0.7*cos(2*pi*64*n/c.sampleRateHz)), ...
    single(0.7*sin(2*pi*64*n/c.sampleRateHz)));
w=BdsFileWriter(root,'fixture',c,N); cw=onCleanup(@()w.abort());
for start=1:1377:N, w.write(x(start:min(start+1376,N))); end
w.finish(); clear cw;
m.schema='bds-b1i-iq-v2'; m.numberComplexSamples=N; m.sampleRateHz=c.sampleRateHz;
m.durationSeconds=N/c.sampleRateHz; m.segmentSamples=1000; m.segments=w.Records;
m.waveformFile='fixture.iq.f32'; m.configuration=c;
p=fullfile(root,'fixture.json'); writeJson(p,m);
report=bds_verify_files(p,true); assert(report.byteIdentical);
assert(numel(m.segments)==11 && m.segments(end).sampleCount==3);
assert(isequal(bds_read_samples(p,0,N),x));
assert(isequal(bds_read_samples(p,991,25),x(992:1016)));
% Global mean/pointwise extrema must include every sample, including tail.
s=bds_analyze(p,0,N,32,256);
assert(sum(s.binSampleCount)==N);
assert(abs(s.totalMeanPowerW-mean(abs(double(x)).^2))<1e-12);
for k=1:numel(s.binSampleCount)
    at=s.binStartSample(k)+(1:s.binSampleCount(k));
    assert(s.iMin(k)==min(real(double(x(at)))) && s.iMax(k)==max(real(double(x(at)))));
    assert(s.qMin(k)==min(imag(double(x(at)))) && s.qMax(k)==max(imag(double(x(at)))));
end
% Positive-frequency complex tone must peak at +64 Hz, not its mirror.
[~,peak]=max(s.psdWPerHz); assert(s.frequencyHz(peak)==64);
df=c.sampleRateHz/256;
assert(abs(sum(s.psdWPerHz)*df-0.49)<1e-5);
% Deliberately change a sample in the full file: byte comparison MUST reject.
fid=fopen(w.FullPath,'r+'); assert(fid>=0);
fseek(fid,104,'bof'); original=fread(fid,1,'*uint8');
fseek(fid,104,'bof'); fwrite(fid,bitxor(original,uint8(1)),'uint8'); fclose(fid);
rejected=false; try, bds_verify_files(p,true); catch, rejected=true; end
assert(rejected,'Byte verifier missed a corrupted full file.');
% A different full-file size is rejected too.
fid=fopen(w.FullPath,'a'); fwrite(fid,uint8(0),'uint8'); fclose(fid);
rejected=false; try, bds_verify_files(p,false); catch, rejected=true; end
assert(rejected,'Size verifier missed an extra byte.');
% Segment reads stay valid even with the intentionally damaged full file.
assert(isequal(bds_read_samples(p,0,N),x));
if includePlots
    previous=get(groot,'defaultFigureVisible');
    set(groot,'defaultFigureVisible','off'); restore=onCleanup(@()set(groot,'defaultFigureVisible',previous)); %#ok<NASGU>
    [f,t]=bds_quicklook(p,1); fc=onCleanup(@()close(f));
    assert(t.sampleCount==1000 && numel(findall(f,'Type','axes'))==3); clear fc;
    [f,t]=bds_overview(p,false); fc=onCleanup(@()close(f));
    assert(t.sampleCount==N && numel(findall(f,'Type','axes'))==5);
    for suffix={'.png','.fig','_stats.mat'}
        d=dir(fullfile(root,['overview' suffix{1}])); assert(numel(d)==1 && d.bytes>0);
    end
    clear fc;
end
fprintf('PASS: nonaligned segmentation, 3-sample tail, corruption detection, whole-file stats/PSD');
if includePlots, fprintf(', I/Q and overview graphics'); end
fprintf('.\n');
end
function writeJson(path,value)
fid=fopen(path,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value),'char');
end
