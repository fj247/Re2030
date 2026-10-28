function bds_capture_analyze(requestFile)
%BDS_CAPTURE_ANALYZE Analyze ONLY the first saved segment after capture ends.
r=jsondecode(fileread(requestFile));
g=jsondecode(fileread(fullfile(r.taskDirectory,'generated.json')));
out=fullfile(r.taskDirectory,'detector');
m=bds_capture_first_segment(g.metadataFile);
result=struct('overview','pending','presence','pending', ...
    'sourceFile',m.segments(1).fileName,'sourceSampleCount',m.numberComplexSamples, ...
    'sourceDurationSeconds',m.numberComplexSamples/m.sampleRateHz);
try
    summary=bds_analyze(m,0,m.numberComplexSamples, ...
        m.configuration.plotMaxBins,m.configuration.analysisFftLength);
    for component={'i','q'}
        label=component{1};
        fig=figure('Visible','off','Position',[80 80 1000 450]);
        ax=axes(fig);
        bds_plot_envelope(ax,summary.timeSeconds,summary.([label 'Min']), ...
            summary.([label 'Max']),upper(label));
        title(ax,sprintf('First segment: %s envelope (%.3f ms)',upper(label), ...
            1000*result.sourceDurationSeconds));
        publishFigure(fig,fullfile(out,[label '_envelope.png']));
    end
    fig=figure('Visible','off','Position',[80 80 1000 450]);
    plot(summary.frequencyHz/1e6,summary.psdDbWPerHz);grid on;
    xlabel('Baseband frequency (MHz)');ylabel('PSD (dBW/Hz)');
    title(sprintf('First segment: mean complex PSD (%.3f ms)',1000*result.sourceDurationSeconds));
    publishFigure(fig,fullfile(out,'mean_psd.png'));
    result.overview='saved';
catch err
    result.overview='failed'; result.overviewError=err.message;
end
if m.numberComplexSamples<20*round(m.sampleRateHz/1000)
    result.presence='insufficient_samples';
else
    try
        % Numeric evidence only; render independent figures below, no composite screenshot.
        options=struct('showFigure',false,'saveResults',false,'plotResults',false, ...
            'probeStartSeconds',0,'dwellMilliseconds',20);
        evidence=bds_validate_signal(m,options);
        a=evidence.probes{1};
        result.probeDurationSeconds=evidence.probeDurationSeconds;
        fig=figure('Visible','off','Position',[80 80 1000 550]);
        imagesc(a.delayChips,a.frequencyHz/1000,10*log10(max(a.scoreMap,realmin)));
        axis xy;colorbar;
        xlabel('Local code delay (chips, modulo 2046)');ylabel('Doppler hypothesis (kHz)');
        title(sprintf('First segment: PRN %d delay-Doppler search (20 ms)',a.prn));
        hold on;plot(a.codeDelayChips,a.dopplerHz/1000,'rx','MarkerSize',10,'LineWidth',2);
        publishFigure(fig,fullfile(out,'prn_search.png'));
        span=round(20*a.sampleRateHz/2.046e6); offsets=-span:span;
        indices=mod(a.codeDelaySamples+offsets,numel(a.delayChips))+1;
        fig=figure('Visible','off','Position',[80 80 1000 450]);
        plot(offsets*2.046e6/a.sampleRateHz,a.bestFrequencySlice(indices));
        hold on;yline(a.nominalThreshold,'r--');plot(0,a.peakScore,'ro');grid on;
        xlabel('Code-delay offset (chips)');ylabel('Normalized correlation power');
        title(sprintf('First segment: PRN %d local peak slice at %.0f Hz',a.prn,a.dopplerHz));
        publishFigure(fig,fullfile(out,'correlation.png'));
        result.presence=evidence.evidenceStatus;
        result.targetPrn=a.prn; result.peakScore=a.peakScore;
        result.nominalThreshold=a.nominalThreshold; result.peakRatio=a.peakToCompetitorRatio;
    catch err
        result.presence='failed';result.presenceError=err.message;
    end
end
bds_capture_json(fullfile(out,'analysis.json'),result);
close all;
end

function publishFigure(fig,destination)
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
% Render and publish atomically; the browser never reads an unfinished PNG.
tmp=[destination '.partial.png'];
set(fig,'PaperPositionMode','auto');
print(fig,tmp,'-dpng','-r120');
[ok,msg]=movefile(tmp,destination,'f');assert(ok,msg);
end
