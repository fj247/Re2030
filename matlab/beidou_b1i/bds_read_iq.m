function [iq,meta]=bds_read_iq(metadataFile,startSeconds,durationSeconds,segmentIndex)
%BDS_READ_IQ Read global time range, or time relative to one selected segment.
% bds_read_iq(meta,1,0.02) -> 20 ms from global second 1.
% bds_read_iq(meta,0,0.02,3) -> first20 ms of segment 3.
if nargin<2, startSeconds=0; end
if nargin<3, durationSeconds=0.02; end
meta=bds_metadata(metadataFile); fs=meta.sampleRateHz;
validateattributes(startSeconds,{'numeric'},{'scalar','finite','nonnegative'});
validateattributes(durationSeconds,{'numeric'},{'scalar','finite','positive'});
base=0; available=meta.numberComplexSamples;
if nargin>=4
    validateattributes(segmentIndex,{'numeric'},{'scalar','integer','positive'});
    assert(isfield(meta,'segments') && segmentIndex<=numel(meta.segments),'Invalid segment index.');
    base=meta.segments(segmentIndex).startSample;
    available=meta.segments(segmentIndex).sampleCount;
end
n0=round(startSeconds*fs); n=min(round(durationSeconds*fs),available-n0);
assert(n>0,'Requested start is outside the selected recording/segment.');
iq=bds_read_samples(meta,base+n0,n);
end
