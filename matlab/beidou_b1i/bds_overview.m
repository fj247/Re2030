function [fig,summary]=bds_overview(metadataFile,visible)
%BDS_OVERVIEW Scan whole run, plot, and save PNG/FIG/MAT beside full file.
% No spectrogram/time-frequency matrix is computed or saved.
m=bds_metadata(metadataFile);
if nargin<2, visible=m.configuration.overviewVisible; end
maxBins=m.configuration.plotMaxBins; nfft=m.configuration.analysisFftLength;
fprintf('Building whole-run overview using all %d complex samples...\n',m.numberComplexSamples);
summary=bds_analyze(m,0,m.numberComplexSamples,maxBins,nfft);
lengthSamples=min(m.numberComplexSamples,round(0.2*m.sampleRateHz));
starts=unique([0 floor((m.numberComplexSamples-lengthSamples)/2) ...
    m.numberComplexSamples-lengthSamples]);
summary.representativeStartSamples=starts;
summary.representativePsdWPerHz=zeros(nfft,numel(starts));
for k=1:numel(starts)
    s=bds_analyze(m,starts(k),lengthSamples,1,nfft);
    summary.representativePsdWPerHz(:,k)=s.psdWPerHz;
end
if visible, vis='on'; else, vis='off'; end
fig=figure('Name','B1I whole-run overview','Visible',vis,'Position',[80 80 1200 950]);
a=subplot(3,2,1); bds_plot_envelope(a,summary.timeSeconds,summary.iMin,summary.iMax,'I');
title(a,'Whole-run I amplitude range');
a=subplot(3,2,2); bds_plot_envelope(a,summary.timeSeconds,summary.qMin,summary.qMax,'Q');
title(a,'Whole-run Q amplitude range');
a=subplot(3,2,3); plot(a,summary.timeSeconds,10*log10(max(summary.meanPowerW,realmin)));
grid(a,'on'); xlabel(a,'Time from run start (s)'); ylabel(a,'Total power (dBW)');
title(a,'Received signal + noise: time-bin mean power');
a=subplot(3,2,4); plot(a,summary.frequencyHz/1e6,summary.psdDbWPerHz);
grid(a,'on'); xlabel(a,'Baseband frequency (MHz)'); ylabel(a,'PSD (dBW/Hz)');
title(a,'Whole-run mean complex PSD');
a=subplot(3,2,[5 6]); labels=cell(1,numel(starts)); hold(a,'on');
for k=1:numel(starts)
    plot(a,summary.frequencyHz/1e6,10*log10(max(summary.representativePsdWPerHz(:,k),realmin)));
    labels{k}=sprintf('%.3f to %.3f s',starts(k)/m.sampleRateHz, ...
        (starts(k)+lengthSamples)/m.sampleRateHz);
end
hold(a,'off'); grid(a,'on'); legend(a,labels,'Location','best');
xlabel(a,'Baseband frequency (MHz)'); ylabel(a,'PSD (dBW/Hz)');
title(a,'Representative time intervals: spectrum comparison (not a spectrogram)');
base=fullfile(m.sourceDirectory,'overview');
set(fig,'PaperPositionMode','auto');
print(fig,[base '.png'],'-dpng','-r150'); savefig(fig,[base '.fig']);
save([base '_stats.mat'],'summary','-v7');
fprintf('Overview saved: %s.png / .fig / _stats.mat\n',base);
end
