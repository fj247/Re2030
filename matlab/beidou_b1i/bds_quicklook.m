function [fig,stats]=bds_quicklook(metadataFile,segmentIndex,startSeconds,durationSeconds)
%BDS_QUICKLOOK MANUAL only: full selected segment I, Q and complex mean PSD.
% bds_quicklook(meta,3)                 -> ALL of segment 3
% bds_quicklook(meta,3,0.1,0.0001)      -> 100 us from 0.1 s within segment 3
% Legacy v1 single-file metadata also supported (segmentIndex must be 1).
if nargin<2, segmentIndex=1; end
if nargin<3, startSeconds=0; end
m=bds_metadata(metadataFile); fs=m.sampleRateHz;
validateattributes(segmentIndex,{'numeric'},{'scalar','integer','positive'});
validateattributes(startSeconds,{'numeric'},{'scalar','finite','nonnegative'});
if isfield(m,'segments')
    assert(segmentIndex<=numel(m.segments),'Segment does not exist.');
    base=m.segments(segmentIndex).startSample; available=m.segments(segmentIndex).sampleCount;
else
    assert(segmentIndex==1,'Legacy metadata has only one file.');
    base=0; available=m.numberComplexSamples;
end
n0=round(startSeconds*fs); assert(n0<available,'Start outside selected segment.');
if nargin<4
    count=available-n0;
else
    validateattributes(durationSeconds,{'numeric'},{'scalar','finite','positive'});
    count=min(round(durationSeconds*fs),available-n0);
end
assert(count>0); maxBins=2000; nfft=4096;
if isfield(m.configuration,'plotMaxBins'), maxBins=m.configuration.plotMaxBins; end
if isfield(m.configuration,'analysisFftLength'), nfft=m.configuration.analysisFftLength; end
fprintf('Analyzing all %d selected complex samples (%.6f s).\n',count,count/fs);
stats=bds_analyze(m,base+n0,count,maxBins,nfft);
fig=figure('Name',sprintf('B1I segment %06d: complete selected interval',segmentIndex), ...
    'Position',[100 100 1100 850]);
a=subplot(3,1,1); plotTime(a,stats,'i',fs);
title(a,sprintf('Segment %06d | I | %.6f s analyzed',segmentIndex,count/fs));
a=subplot(3,1,2); plotTime(a,stats,'q',fs); title(a,'Q component');
a=subplot(3,1,3); plot(a,stats.frequencyHz/1e6,stats.psdDbWPerHz); grid(a,'on');
xlabel(a,'Baseband frequency (MHz)'); ylabel(a,'PSD (dBW/Hz)');
title(a,'Complex I+jQ: mean PSD using the entire selected interval');
end
function plotTime(ax,s,which,fs)
% For a sufficiently small interval, show actual point-by-point samples via
% the min=max one-sample bins. Longer intervals show all-bin extrema.
if strcmp(which,'i'), lo=s.iMin; hi=s.iMax; label='I';
else, lo=s.qMin; hi=s.qMax; label='Q'; end
if all(s.binSampleCount==1)
    plot(ax,(0:s.sampleCount-1)/fs,lo*1e9); grid(ax,'on');
    xlabel(ax,'Time from selected start (s)'); ylabel(ax,[label ' (n sqrt(W))']);
else
    bds_plot_envelope(ax,s.timeSeconds,lo,hi,label);
end
end
