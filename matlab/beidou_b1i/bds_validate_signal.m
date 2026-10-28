function [report,fig]=bds_validate_signal(metadataFile,overrides)
%BDS_VALIDATE_SIGNAL MANUAL, read-only I/Q presence verification (no NAV decode).
% report=bds_validate_signal(result.metadataFile)
% o=struct('targetPrn',12,'probeStartSeconds',[0 1 2],'noiseTrials',5);
% [report,fig]=bds_validate_signal(result.metadataFile,o)
% Reads raw files plus format, configured PRN and equivalent receive FIR ONLY.
% Does not read truth.mat, satellite position, true delay/Doppler, clock, NAV,
% configured C/N0, configured signal power, or simulation noise seed.
if nargin<2, overrides=struct(); end
o=bds_acquisition_options(overrides); m=bds_metadata(metadataFile); fs=m.sampleRateHz;
if isempty(o.targetPrn)
    assert(isfield(m,'configuration') && isfield(m.configuration,'prn'), ...
        'Specify targetPrn; no configured PRN available.');
    o.targetPrn=m.configuration.prn;
end
if isempty(o.controlPrn), o.controlPrn=6+mod(o.targetPrn-6+1,32); end
assert(o.targetPrn~=o.controlPrn,'Target and non-target control must use different PRNs.');
Nms=round(fs/1000); count=o.dwellMilliseconds*Nms;
assert(m.numberComplexSamples>=count, ...
    'Recording too short: need %.3f seconds or reduce dwellMilliseconds.',o.dwellMilliseconds/1000);
lastStart=m.numberComplexSamples-count;
if isempty(o.probeStartSeconds)
    starts=unique([0 floor(lastStart/2) lastStart]);
else
    starts=unique(round(o.probeStartSeconds(:).'*fs));
    assert(all(starts<=lastStart),'A probe extends beyond the recording.');
end
report.schema='bds-b1i-presence-v1'; report.options=o;
report.sourceDirectory=m.sourceDirectory; report.sampleRateHz=fs;
report.probeDurationSeconds=o.dwellMilliseconds/1000;
report.probes=cell(1,numel(starts)); report.targetDetected=false(1,numel(starts));
report.metadataUse=['Format and configured PRN; receive-FIR coefficients for synthetic controls. ' ...
    'No true code/carrier timing, ephemeris, NAV, C/N0 or truth.mat used.'];
firstInput=[];
for k=1:numel(starts)
    fprintf('Acquiring PRN %d from saved I/Q at %.6f s (%d samples)...\n', ...
        o.targetPrn,starts(k)/fs,count);
    x=bds_read_samples(m,starts(k),count);
    a=bds_acquire(x,fs,o.targetPrn,o);
    a.startSample=starts(k); a.startSeconds=starts(k)/fs;
    a.recordCodeEpochPhaseSeconds=mod(a.startSeconds+a.codeDelaySeconds,0.001);
    report.probes{k}=a; report.targetDetected(k)=a.detected;
    if k==1, firstInput=x; end
    fprintf('  peak=%.3f, nominal threshold=%.3f, ratio=%.2f, Doppler=%.0f Hz, detected=%d\n', ...
        a.peakScore,a.nominalThreshold,a.peakToCompetitorRatio,a.dopplerHz,a.detected);
end
fprintf('Other-PRN control: PRN %d on the SAME first I/Q window...\n',o.controlPrn);
report.otherPrn=compact(bds_acquire(firstInput,fs,o.controlPrn,o));
if isfield(m,'filterCoefficients') && ~isempty(m.filterCoefficients)
    h=double(m.filterCoefficients(:));
    assert(all(isfinite(h)) && sum(abs(h))>0,'Invalid receive FIR metadata.');
    report.noiseModel='Independent complex Gaussian noise, same known receive FIR, same measured window power.';
else
    h=1;
    report.noiseModel='Independent white complex Gaussian control; receive FIR unavailable, spectral match not guaranteed.';
end
power=mean(abs(double(firstInput)).^2);
previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(o.controlSeed,'twister'); report.noiseControls=cell(1,o.noiseTrials);
for k=1:o.noiseTrials
    fprintf('Synthetic noise-only control %d/%d...\n',k,o.noiseTrials);
    warm=numel(h)-1; z=randn(2,count+warm);
    noise=filter(h,1,complex(z(1,:),z(2,:)));
    noise=noise(warm+1:end).';
    noise=noise*sqrt(power/max(mean(abs(noise).^2),realmin));
    report.noiseControls{k}=compact(bds_acquire(noise,fs,o.targetPrn,o));
end
report.noiseDetectionCount=sum(cellfun(@(x)x.detected,report.noiseControls));
report.otherPrnDetected=report.otherPrn.detected;
report.boundaryCandidateCount=sum(cellfun(@(x)x.atDopplerBoundary,report.probes));
if all(report.targetDetected) && ~report.otherPrnDetected && report.noiseDetectionCount==0 ...
        && report.boundaryCandidateCount==0
    report.evidenceStatus='supported_in_tested_windows';
    report.statement='Matching target-PRN structure is supported in tested I/Q windows by this diagnostic search.';
else
    report.evidenceStatus='inconclusive';
    report.statement=['Detection and controls do not meet all diagnostic criteria. This is not proof ' ...
        'that the signal is absent; inspect search range, duration, SNR and control results.'];
end
report.limits={ ...
    'Detects a matching PRN structure, NOT decoded NAV correctness or transmitter identity'; ...
    'Local delay is modulo 1 ms, not absolute propagation time or a frame boundary'; ...
    'Selected short windows only; not proof of continuous reception between probes'; ...
    'Nominal Gamma/median threshold assumptions are approximate; actual Pfa is NOT certified'; ...
    'A few synthetic noise trials are diagnostic controls, not a false-alarm calibration'; ...
    'Non-target-PRN control presumes the single-satellite simulated scene'; ...
    'No acquisition resampling; requires an even integer sample count per millisecond'};
report.references={ ...
    'https://gnss-sdr.org/docs/sp-blocks/acquisition/'; ...
    'https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf'};
report.outputDirectory=''; report.plotStatus='not_requested';
if o.saveResults
    if isempty(o.outputDirectory), parent=m.sourceDirectory; else, parent=char(o.outputDirectory); end
    if ~exist(parent,'dir'), mkdir(parent); end
    base=['signal_validation_' datestr(now,'yyyymmdd_HHMMSS_FFF')];
    destination=fullfile(parent,base); k=1;
    while exist(destination,'dir') || exist(destination,'file')
        destination=fullfile(parent,sprintf('%s_%03d',base,k)); k=k+1;
    end
    [ok,msg]=mkdir(destination); assert(ok,msg); report.outputDirectory=destination;
end
fig=[];
% Save numerical evidence before graphics so a rendering failure loses no results.
if o.saveResults, saveReport(report); end
if o.plotResults && (o.showFigure || o.saveResults)
    try
        fig=bds_plot_acquisition(report,o.showFigure);
        if o.saveResults
            set(fig,'PaperPositionMode','auto');
            print(fig,fullfile(report.outputDirectory,'signal_presence.png'),'-dpng','-r150');
            savefig(fig,fullfile(report.outputDirectory,'signal_presence.fig'));
            report.plotStatus='saved';
        else
            report.plotStatus='rendered';
        end
    catch err
        report.plotStatus='failed'; report.plotError=err.message;
        warning('BDS:PresencePlotFailed','Numerical verification completed; plot failed: %s',err.message);
        if o.saveResults, saveReport(report); end
    end
end
if o.saveResults, saveReport(report); end
fprintf('\nEvidence status: %s\n%s\n',report.evidenceStatus,report.statement);
fprintf('Target windows: %d/%d; other-PRN detected: %d; noise controls detected: %d/%d.\n', ...
    sum(report.targetDetected),numel(starts),report.otherPrnDetected,report.noiseDetectionCount,o.noiseTrials);
fprintf('This result does not verify navigation frames or certify a false-alarm rate.\n');
if o.saveResults, fprintf('Evidence saved to: %s\n',report.outputDirectory); end
end
function a=compact(a)
a=rmfield(a,{'scoreMap','bestFrequencySlice','frequencyHz','delayChips'});
end
function saveReport(report)
save(fullfile(report.outputDirectory,'signal_presence.mat'),'report','-v7');
summary=report;
for k=1:numel(summary.probes), summary.probes{k}=compact(summary.probes{k}); end
fid=fopen(fullfile(report.outputDirectory,'signal_presence.json'),'w','n','UTF-8'); assert(fid>=0);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
b=unicode2native(jsonencode(summary,'PrettyPrint',true),'UTF-8');
assert(fwrite(fid,b,'uint8')==numel(b),'Incomplete evidence JSON write.');
end
