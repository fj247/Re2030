function bds_capture_analyze(requestFile)
%BDS_CAPTURE_ANALYZE Export numeric charts from the first CLOSED segment only.
r=jsondecode(fileread(requestFile));
if isfield(r,'metadataFile')
    source=r.metadataFile;
else
    g=jsondecode(fileread(fullfile(r.taskDirectory,'generated.json')));source=g.metadataFile;
end
out=fullfile(r.taskDirectory,'detector');
m=bds_capture_first_segment(source);
result=struct('overview','pending','spectrum','pending','presence','pending', ...
    'search','pending','correlation','pending','sourceFile',m.segments(1).fileName, ...
    'sourceSampleCount',m.numberComplexSamples, ...
    'sourceDurationSeconds',m.numberComplexSamples/m.sampleRateHz);
reportFile=fullfile(out,'analysis.json');
bds_capture_json(reportFile,result);
try
    summary=bds_analyze(m,0,m.numberComplexSamples,1,m.configuration.analysisFftLength);
    chart=struct('schema','wireless-chart-v1','kind','spectrum', ...
        'frequencyMHz',summary.frequencyHz/1e6,'powerDbWPerHz',summary.psdDbWPerHz);
    bds_capture_json(fullfile(out,'mean_psd.json'),chart);
    result.overview='saved';result.spectrum='saved';
catch err
    result.overview='failed';result.spectrum='failed';result.overviewError=err.message;
end
% Publish spectrum and its status while PRN search is still running.
bds_capture_json(reportFile,result);
if m.numberComplexSamples<20*round(m.sampleRateHz/1000)
    result.presence='insufficient_samples';
    result.search='insufficient_samples';result.correlation='insufficient_samples';
else
    try
        options=struct('showFigure',false,'saveResults',false,'plotResults',false, ...
            'probeStartSeconds',0,'dwellMilliseconds',20);
        evidence=bds_validate_signal(m,options);
        a=evidence.probes{1};
        result.probeDurationSeconds=evidence.probeDurationSeconds;
        % Max-pool only for display: retain a narrow peak within each delay bin.
        % Full-resolution best-frequency slice and exact peak coordinates are separate.
        columns=min(512,numel(a.delayChips));edges=round(linspace(0,numel(a.delayChips),columns+1));
        score=zeros(size(a.scoreMap,1),columns);delay=zeros(1,columns);
        for k=1:columns
            idx=edges(k)+1:edges(k+1);
            score(:,k)=max(a.scoreMap(:,idx),[],2);
            delay(k)=mean(a.delayChips(idx));
        end
        chart=struct('schema','wireless-chart-v1','kind','search', ...
            'delayChips',delay,'frequencyKHz',a.frequencyHz/1000, ...
            'scoreDb',10*log10(max(score,realmin)), ...
            'peakDelayChips',a.codeDelayChips,'peakFrequencyKHz',a.dopplerHz/1000, ...
            'prn',a.prn,'displayReduction','Max correlation power per code-delay bin');
        bds_capture_json(fullfile(out,'prn_search.json'),chart);
        result.search='saved';bds_capture_json(reportFile,result);
        span=round(20*a.sampleRateHz/2.046e6);offsets=-span:span;
        indices=mod(a.codeDelaySamples+offsets,numel(a.delayChips))+1;
        chart=struct('schema','wireless-chart-v1','kind','correlation', ...
            'offsetChips',offsets*2.046e6/a.sampleRateHz, ...
            'power',a.bestFrequencySlice(indices),'threshold',a.nominalThreshold, ...
            'peakScore',a.peakScore,'dopplerHz',a.dopplerHz,'prn',a.prn);
        bds_capture_json(fullfile(out,'correlation.json'),chart);
        result.correlation='saved';result.presence=evidence.evidenceStatus;
        result.targetPrn=a.prn;result.peakScore=a.peakScore;
        result.nominalThreshold=a.nominalThreshold;result.peakRatio=a.peakToCompetitorRatio;
    catch err
        result.presence='failed';result.presenceError=err.message;
        if ~strcmp(result.search,'saved'),result.search='failed';end
        if ~strcmp(result.correlation,'saved'),result.correlation='failed';end
    end
end
bds_capture_json(reportFile,result);
end
