function fig=bds_plot_acquisition(report,visible)
%BDS_PLOT_ACQUISITION Correlation search/slice, controls and repeated detections.
% This is a code-delay/Doppler correlation map, NOT a time-frequency spectrogram.
if nargin<2, visible=true; end
if visible, vis='on'; else, vis='off'; end
a=report.probes{1};
fig=figure('Name','B1I signal-presence evidence','Visible',vis,'Position',[80 80 1250 900]);
ax=subplot(2,2,1);
imagesc(ax,a.delayChips,a.frequencyHz/1000,10*log10(max(a.scoreMap,realmin)));
axis(ax,'xy'); colorbar(ax); xlabel(ax,'Local code delay (chips, modulo 2046)');
ylabel(ax,'Doppler hypothesis (kHz)');
title(ax,sprintf('PRN %d | %.3f s probe | normalized correlation (dB)',a.prn,a.startSeconds));
hold(ax,'on'); plot(ax,a.codeDelayChips,a.dopplerHz/1000,'rx','MarkerSize',10,'LineWidth',2); hold(ax,'off');
ax=subplot(2,2,2);
span=round(20*a.sampleRateHz/2.046e6); offsets=-span:span;
indices=mod(a.codeDelaySamples+offsets,numel(a.delayChips))+1;
relativeChips=offsets*2.046e6/a.sampleRateHz;
plot(ax,relativeChips,a.bestFrequencySlice(indices)); hold(ax,'on');
yline(ax,a.nominalThreshold,'r--','Nominal threshold');
plot(ax,0,a.peakScore,'ro'); hold(ax,'off'); grid(ax,'on');
xlabel(ax,'Code-delay offset from candidate (chips, circular zoom)'); ylabel(ax,'Normalized correlation power');
title(ax,{sprintf('Slice at %.0f Hz | candidate %.2f chips',a.dopplerHz,a.codeDelayChips), ...
    sprintf('Peak ratio %.2f | detected=%d',a.peakToCompetitorRatio,a.detected)});
ax=subplot(2,2,3); labels={}; peaks=[]; limits=[];
for k=1:numel(report.probes)
    labels{end+1}=sprintf('Target%d',k); %#ok<AGROW>
    peaks(end+1)=report.probes{k}.peakScore; limits(end+1)=report.probes{k}.nominalThreshold; %#ok<AGROW>
end
labels{end+1}=sprintf('Other PRN%d',report.otherPrn.prn);
peaks(end+1)=report.otherPrn.peakScore; limits(end+1)=report.otherPrn.nominalThreshold;
for k=1:numel(report.noiseControls)
    labels{end+1}=sprintf('Noise%d',k); %#ok<AGROW>
    peaks(end+1)=report.noiseControls{k}.peakScore; %#ok<AGROW>
    limits(end+1)=report.noiseControls{k}.nominalThreshold; %#ok<AGROW>
end
bar(ax,peaks); hold(ax,'on'); plot(ax,1:numel(peaks),limits,'r--o'); hold(ax,'off');
set(ax,'XTick',1:numel(peaks),'XTickLabel',labels); xtickangle(ax,30); grid(ax,'on');
ylabel(ax,'Peak normalized correlation power');
title(ax,'Same search rule; detection also requires peak-ratio test');
ax=subplot(2,2,4); times=zeros(1,numel(report.probes)); phase=times; freq=times;
for k=1:numel(report.probes)
    p=report.probes{k}; times(k)=p.startSeconds;
    phase(k)=p.recordCodeEpochPhaseSeconds*1e6; freq(k)=p.dopplerHz;
end
yyaxis(ax,'left'); plot(ax,times,phase,'o-'); ylabel(ax,'Record-relative code epoch (us, modulo 1000)');
yyaxis(ax,'right'); plot(ax,times,freq,'s-'); ylabel(ax,'Coarse Doppler (Hz)');
xlabel(ax,'Probe start time in recording (s)'); grid(ax,'on');
title(ax,sprintf('%s | %d/%d windows detected', ...
    strrep(report.evidenceStatus,'_',' '),sum(report.targetDetected),numel(report.probes)));
end
