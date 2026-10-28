function bds_capture_analyze(requestFile)
%BDS_CAPTURE_ANALYZE Read saved IQ; export detector-facing numeric evidence only.
r=jsondecode(fileread(requestFile));
g=jsondecode(fileread(fullfile(r.taskDirectory,'generated.json')));
out=fullfile(r.taskDirectory,'detector');
result=struct('overview','pending','presence','pending');
try
    [fig,summary]=bds_overview(g.metadataFile,false);
    publishImage(fullfile(fileparts(g.metadataFile),'overview.png'),fullfile(out,'overview.png'));
    close(fig); result.overview='saved';
catch err
    result.overview='failed'; result.overviewError=err.message;
end
m=bds_metadata(g.metadataFile);
if m.numberComplexSamples/m.sampleRateHz<0.020
    result.presence='insufficient_samples';
else
    try
        options=struct('showFigure',false,'saveResults',false);
        [evidence,fig]=bds_validate_signal(g.metadataFile,options);
        imagePath=fullfile(fileparts(g.metadataFile),'capture_presence.png');
        print(fig,imagePath,'-dpng','-r120');close(fig);
        publishImage(imagePath,fullfile(out,'presence.png'));
        a=evidence.probes{1};
        span=round(20*a.sampleRateHz/2.046e6); offsets=-span:span;
        indices=mod(a.codeDelaySamples+offsets,numel(a.delayChips))+1;
        fig=figure('Visible','off');
        plot(offsets*2.046e6/a.sampleRateHz,a.bestFrequencySlice(indices));
        hold on;yline(a.nominalThreshold,'r--');plot(0,a.peakScore,'ro');grid on;
        xlabel('Code-delay offset (chips)');ylabel('Normalized correlation power');
        title('Target PRN correlation peak - local slice');
        imagePath=fullfile(fileparts(g.metadataFile),'capture_correlation.png');
        print(fig,imagePath,'-dpng','-r120');close(fig);
        publishImage(imagePath,fullfile(out,'correlation.png'));
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

function publishImage(source,destination)
tmp=[destination '.partial'];
[ok,msg]=copyfile(source,tmp);assert(ok,msg);
[ok,msg]=movefile(tmp,destination,'f');assert(ok,msg);
end
