function report=bds_verify_files(metadataFile,compareFull)
%BDS_VERIFY_FILES Verify indices, exact byte counts, and optional full-file equality.
% compareFull=true rereads and compares bytes, without loading complete files.
if nargin<2, compareFull=true; end
m=bds_metadata(metadataFile); assert(isfield(m,'segments'),'Requires v2 segments.');
segmentRoot=m.sourceDirectory;
if isfield(m,'segmentDirectory'), segmentRoot=m.segmentDirectory; end
expectedStart=0; checkedBytes=0;
for k=1:numel(m.segments)
    s=m.segments(k);
    assert(s.index==k && s.startSample==expectedStart,'Out-of-order or noncontiguous index.');
    assert(s.sampleCount>0 && s.sampleCount==floor(s.sampleCount),'Invalid segment size.');
    if k<numel(m.segments)
        assert(s.sampleCount==m.segmentSamples,'Non-final segment is short.');
    else
        assert(s.sampleCount<=m.segmentSamples,'Final segment too long.');
    end
    d=dir(fullfile(segmentRoot,s.fileName));
    assert(numel(d)==1 && d.bytes==8*s.sampleCount,'Segment file-size mismatch.');
    assert(s.bytes==d.bytes,'Index bytes mismatch.');
    expectedStart=expectedStart+s.sampleCount; checkedBytes=checkedBytes+d.bytes;
end
assert(expectedStart==m.numberComplexSamples,'Total sample count mismatch.');
report=struct('structuralPassed',true,'segmentCount',numel(m.segments), ...
    'numberComplexSamples',expectedStart,'segmentBytes',checkedBytes, ...
    'fullFileCompared',false,'byteIdentical',[]);
if isempty(m.waveformFile), return; end
fullPath=fullfile(m.sourceDirectory,m.waveformFile); d=dir(fullPath);
assert(numel(d)==1 && d.bytes==checkedBytes,'Full file-size mismatch.');
if ~compareFull, return; end
fid=fopen(fullPath,'r'); assert(fid>=0); cf=onCleanup(@()fclose(fid)); %#ok<NASGU>
for k=1:numel(m.segments)
    sid=fopen(fullfile(segmentRoot,m.segments(k).fileName),'r'); assert(sid>=0);
    cs=onCleanup(@()fclose(sid)); remaining=m.segments(k).bytes;
    while remaining>0
        take=min(remaining,1048576);
        a=fread(fid,take,'*uint8'); b=fread(sid,take,'*uint8');
        assert(numel(a)==take && isequal(a,b),'Full/segment byte mismatch in segment %d.',k);
        remaining=remaining-take;
    end
    clear cs;
end
report.fullFileCompared=true; report.byteIdentical=true;
end
