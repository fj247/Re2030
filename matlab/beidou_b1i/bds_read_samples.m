function iq=bds_read_samples(source,startSample,sampleCount)
%BDS_READ_SAMPLES Global zero-based complex sample range, bounded-memory read.
% Read indexed segment files and cross boundaries transparently; v1 reads its full file.
m=bds_metadata(source);
segmentRoot=m.sourceDirectory;
if isfield(m,'segmentDirectory'), segmentRoot=m.segmentDirectory; end
validateattributes(startSample,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(sampleCount,{'numeric'},{'scalar','integer','positive'});
assert(startSample+sampleCount<=m.numberComplexSamples,'Requested samples outside recording.');
if ~isfield(m,'segments')
    assert(isfield(m,'waveformFile') && ~isempty(m.waveformFile),'No waveform index.');
    iq=readFile(fullfile(m.sourceDirectory,m.waveformFile),startSample,sampleCount);
    return;
end
iq=complex(zeros(sampleCount,1,'single')); done=0;
firstSegment=floor(startSample/m.segmentSamples)+1;
lastSegment=floor((startSample+sampleCount-1)/m.segmentSamples)+1;
assert(lastSegment<=numel(m.segments),'Segment index too short.');
for k=firstSegment:lastSegment
    s=m.segments(k);
    lo=max(startSample,s.startSample);
    hi=min(startSample+sampleCount,s.startSample+s.sampleCount);
    if hi<=lo, continue; end
    part=readFile(fullfile(segmentRoot,s.fileName),lo-s.startSample,hi-lo);
    dst=lo-startSample+(1:numel(part)); iq(dst)=part; done=done+numel(part);
    if done==sampleCount, break; end
end
assert(done==sampleCount,'Segment index has gaps.');
end
function iq=readFile(path,offset,count)
fid=fopen(path,'r','ieee-le'); assert(fid>=0,'Cannot open %s',path);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
assert(fseek(fid,8*offset,'bof')==0,'Seek failed.');
[r,n]=fread(fid,[2 count],'single=>single'); assert(n==2*count,'Truncated waveform.');
iq=complex(r(1,:),r(2,:)).';
end
