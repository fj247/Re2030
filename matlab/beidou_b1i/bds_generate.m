function result = bds_generate(cfg)
%BDS_GENERATE Single B1I/D1 received complex-envelope waveform to disk.
% Output: little-endian float32 I0,Q0,I1,Q1,... in sqrt(W), plus JSON/MAT.
% No specialized toolbox, SDR, receiver, network or RF transmission is used.
% Older saved configurations without a TX field retain the v3 ideal source.
if ~isfield(cfg,'txHardware')
    cfg.txHardware=bds_tx_hardware_profile(); cfg.txHardware.enabled=false;
end
cfg.txHardware=bds_tx_validate(cfg.txHardware,cfg.sampleRateHz,cfg.lowpassCutoffHz);
validateConfig(cfg);
controlled=isfield(cfg,'captureControl');
if controlled, captureCheckpoint(cfg,0,'initializing'); end
fs=cfg.sampleRateHz; fc=1561.098e6; chipRate=2.046e6;
N=round(cfg.durationSeconds*fs); assert(N>=1,'Duration contains no samples.');
assert(abs(N/fs-cfg.durationSeconds)<1e-9,'Duration must contain an integer number of samples.');
if ~exist(cfg.outputDirectory,'dir'), mkdir(cfg.outputDirectory); end
runDirectory=newRunDirectory(cfg.outputDirectory,cfg.outputName);
stem=fullfile(runDirectory,cfg.outputName);
metadataFile=[stem '.json']; truthFile=[stem '_truth.mat'];
marker=fullfile(runDirectory,'INCOMPLETE.txt');
writeText(marker,'Waveform generation/verification has not completed. Do not treat this run as complete.');
fprintf('B1I/D1 PRN %d, %.3f s, %.3f Msamples/s\n',cfg.prn,N/fs,fs/1e6);
fprintf('Run directory: %s\n',runDirectory);
fprintf('Waveform storage: %.3f GB (segments + optional full file).\n', ...
    8*N*(1+double(cfg.keepFullFile))/1e9);
scene=bds_scene(cfg); code=double(bds_prn(cfg.prn)).';
nh=double('00000100110101001110')-double('0');
% Hamming-windowed lowpass. DC gain=1; no Signal Processing Toolbox.
L=cfg.filterLength; D=(L-1)/2; ix=-D:D;
x=2*cfg.lowpassCutoffHz/fs*ix; si=ones(size(x));
z=(x~=0); si(z)=sin(pi*x(z))./(pi*x(z));
h=(2*cfg.lowpassCutoffHz/fs)*si.*(0.54-0.46*cos(2*pi*(0:L-1)/(L-1)));
h=h/sum(h);
% Include prehistory and tail so centered filtering produces no zero-start transient.
grid=(-cfg.geometryStepSeconds:cfg.geometryStepSeconds: ...
    N/fs+2*cfg.geometryStepSeconds).';
truth=bds_geometry(cfg,scene,grid);
if controlled, captureCheckpoint(cfg,0,'initializing'); end
first=6*floor(min(truth.codeTimeSow)/6)-6;
last=6*ceil(max(truth.codeTimeSow)/6)+6;
nav=bds_nav(cfg,scene,first,round((last-first)/6)+1);
codeMinusReceive=truth.codeTimeSow-(cfg.startSowSeconds+grid);
codePP=pchip(grid,codeMinusReceive); phasePP=pchip(grid,truth.phaseDelaySeconds);
rangePP=pchip(grid,truth.rangeM);
phase0=ppval(phasePP,0); range0=ppval(rangePP,0);
C=10^(cfg.signalPowerDbW/10); N0=C/10^(cfg.cn0DbHz/10);
if ~cfg.noiseEnabled, N0=0; end
sigma=sqrt(N0*fs/2); % Each real branch: variance N0*fs/2 before FIR
oldRng=rng; restoreRng=onCleanup(@()rng(oldRng)); %#ok<NASGU>
rng(cfg.randomSeed,'twister');
tx=[];
if cfg.txHardware.enabled
    firstQuery=(cfg.startSowSeconds-floor(cfg.startSowSeconds))-D/fs+ppval(codePP,-D/fs);
    tx=BdsTxSource(cfg,nav,code,firstQuery);
    fprintf('TX hardware: %s, internal %.3f MHz; phase-mask fit max error %.2f dB.\n', ...
        cfg.txHardware.name,tx.Design.internalSampleRateHz/1e6,tx.Design.phaseNoiseFit.maxFitErrorDb);
end
writer=BdsFileWriter(runDirectory,cfg.outputName,cfg,N);
cleanup=onCleanup(@()writer.abort());
stateS=complex(zeros(1,L-1)); stateW=stateS;
written=0; signalEnergy=0; noiseEnergy=0; lastProgress=-1;
for n0=-D:cfg.blockSamples:(N-1+D)
    if controlled && bds_capture_stop(cfg,written), break; end
    n=n0:min(n0+cfg.blockSamples-1,N-1+D); t=n/fs;
    svtime=cfg.startSowSeconds+t+ppval(codePP,t);
    chip=mod(floor(svtime*chipRate),2046)+1;
    nhidx=mod(floor(svtime*1000),20)+1;
    bitidx=floor((svtime-nav.firstSubframeSow)*50)+1;
    assert(all(bitidx>=1 & bitidx<=numel(nav.bits)),'NAV coverage error.');
    data=reshape(double(nav.bits(bitidx)),1,[]);
    bipolar=(1-2*code(chip)).*(1-2*nh(nhidx)).*(1-2*data);
    phase=cfg.initialCarrierPhaseRad-2*pi*fc*(ppval(phasePP,t)-phase0);
    amplitude=sqrt(C)*range0./ppval(rangePP,t);
    if cfg.txHardware.enabled
        query=(cfg.startSowSeconds-floor(cfg.startSowSeconds))+t+ppval(codePP,t);
        source=tx.sample(query);
        s=amplitude.*source.*exp(1i*phase);
    else
        s=amplitude.*bipolar.*exp(1i*phase);
    end
    if cfg.noiseEnabled
        r=randn(2,numel(n)); w=sigma*complex(r(1,:),r(2,:));
    else
        w=complex(zeros(size(n)));
    end
    [sf,stateS]=filter(h,1,s,stateS); [wf,stateW]=filter(h,1,w,stateW);
    % Causal FIR output at input index n represents centered time (n-D)/fs.
    keep=(n>=D & n<=N-1+D); a=sf(keep); b=wf(keep); iq=a+b;
    writer.write(iq);
    written=written+numel(iq);
    signalEnergy=signalEnergy+sum(abs(a).^2); noiseEnergy=noiseEnergy+sum(abs(b).^2);
    if controlled, captureCheckpoint(cfg,written,'generating'); end
    progress=floor(10*written/N);
    if progress>lastProgress
        fprintf('%.0f%% (%d / %d complex samples)\n',100*written/N,written,N);
        lastProgress=progress;
    end
end
if controlled
    captureCheckpoint(cfg,written,'finalizing');
    if written==0
        writer.abort();
        result=struct('runDirectory',runDirectory,'numberComplexSamples',0,'segmentCount',0,'bytes',0);
        return;
    end
    N=written; cfg.durationSeconds=N/fs; writer.finish(N);
else
    assert(written==N,'Sample-count mismatch.'); writer.finish();
end
clear cleanup;
meta.schema='bds-b1i-iq-v2'; meta.signal='BeiDou B1I / D1 / single synthetic MEO';
meta.provenance=scene.provenance;
meta.sampleRateHz=fs; meta.centerFrequencyHz=fc; meta.numberComplexSamples=N;
meta.durationSeconds=N/fs;
meta.waveformFile='';
if cfg.keepFullFile, meta.waveformFile=[cfg.outputName '.iq.f32']; end
meta.segmentSamples=round(cfg.segmentSeconds*fs);
meta.segmentSeconds=meta.segmentSamples/fs; meta.segments=writer.Records;
if controlled, meta.segmentDirectory=cfg.captureControl.detectorDirectory; end
meta.segmentIndexFile='segment_index.csv';
meta.segmentBoundaryPolicy='Split after float32 conversion; no padding, processing or state reset.';
meta.truthFile=[cfg.outputName '_truth.mat'];
meta.format='Little-endian float32 interleaved I0,Q0,I1,Q1,...; no header';
meta.iqUnits='sqrt(W), complex envelope convention E[abs(I+jQ)^2]=power in W';
meta.timeReference='Reception BDT week/SOW; output sample n is startSow+n/fs (n=0..N-1).';
meta.filterTiming='Centered equivalent filter; delay compensated using generated prehistory and tail.';
meta.configuration=cfg; meta.scene=scene;
meta.softwareVersion='4.0';
meta.txHardware=struct('enabled',logical(cfg.txHardware.enabled), ...
    'profileFile','tx_hardware_profile.json','designFile','tx_hardware_design.json');
txDesign=struct('enabled',false,'bypass','Original v3 ideal source path, no added resampling or calibration.');
if cfg.txHardware.enabled, txDesign=tx.Design; end
meta.txHardware.effectiveModules=struct();
for name={'bandwidth','response','pa','phaseNoise','spurs','iqImbalance','edgeAsymmetry','timingJitter'}
    meta.txHardware.effectiveModules.(name{1})=logical(cfg.txHardware.enabled && cfg.txHardware.(name{1}).enabled);
end
meta.txHardware.effectiveModules.ampm=logical(cfg.txHardware.enabled && cfg.txHardware.pa.enabled && cfg.txHardware.pa.ampmEnabled);
writeJson(fullfile(runDirectory,'tx_hardware_profile.json'),cfg.txHardware);
writeJson(fullfile(runDirectory,'tx_hardware_design.json'),txDesign);
meta.filterCoefficients=h; meta.filterOneSidedCutoffHz=cfg.lowpassCutoffHz;
meta.equivalentTwoSidedNoiseBandwidthHz=fs*sum(h.^2)/sum(h)^2;
meta.preFilterSignalPowerW=C;
meta.signalPowerReference='Nominal calibrated main component at TX-equivalent output before AA/RX and reference range; additional spurs are not included in configured C.'; meta.noiseDensityWPerHz=N0;
meta.cn0Convention='Configured C/N0 uses fixed calibrated main TX power before anti-alias/RX FIR; RX N0 unchanged. Post-filter signal power includes any spurs and TX/AA/RX loss.';
meta.measuredSignalPowerW=signalEnergy/N; meta.measuredNoisePowerW=noiseEnergy/N;
if N0>0
    meta.postFilterCn0DbHz=10*log10(meta.measuredSignalPowerW/N0);
else
    meta.postFilterCn0DbHz=[];
end
meta.modelLimits={'Single B1I public I component, not the entire RF band or B1Q'; ...
    'Hypothetical orbit/data, not actual C12 ephemeris or historical replay'; ...
    'Optional synthetic equivalent TX model; not measured spacecraft hardware or full composite payload'; ...
    'Finite-rate rectangular-chip approximation and explicit equivalent receive FIR'; ...
    'Open-sky direct path only; no multipath, scintillation or other satellites'; ...
    'Ionosphere uses zero-alpha 5 ns vertical model; troposphere uses zenith/sin(elevation)'; ...
    'No receiver clock, AGC, quantizer, acquisition, decoding or timing solution'};
meta.references={ ...
    'CSNO, BDS-SIS-ICD-B1I-3.0, Feb 2019, sections 4 and 5'; ...
    'https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf'; ...
    'https://www.mathworks.com/help/satcom/ug/gps-receiver-acquisition-and-tracking-using-ca-code.html'; ...
    'https://gnss-sdr.org/docs/sp-blocks/tracking/'};
meta.status='waveform_complete'; meta.overviewStatus='pending';
writeJson(metadataFile,meta);
writeIndex(fullfile(runDirectory,meta.segmentIndexFile),meta.segments);
fprintf('Verifying segment indices, sizes and optional full-file byte equality...\n');
meta.verification=bds_verify_files(metadataFile,cfg.verifyFullFile);
writeJson(metadataFile,meta);
if exist(marker,'file'), delete(marker); end
result=struct('runDirectory',runDirectory,'waveformFile',writer.FullPath, ...
    'metadataFile',metadataFile,'truthFile',truthFile,'segmentCount',numel(meta.segments), ...
    'numberComplexSamples',N,'bytes',8*N*(1+double(cfg.keepFullFile)));
if cfg.autoOverview
    try
        bds_overview(metadataFile,cfg.overviewVisible);
        meta.overviewStatus='saved'; result.overviewPng=fullfile(runDirectory,'overview.png');
    catch err
        meta.overviewStatus='failed'; meta.overviewError=err.message;
        writeText(fullfile(runDirectory,'overview_error.txt'),err.message);
        warning('BDS:OverviewFailed','Waveforms are saved, but overview failed: %s',err.message);
    end
else
    meta.overviewStatus='disabled';
end
writeJson(metadataFile,meta);
save(truthFile,'cfg','scene','truth','nav','h','meta','txDesign','-v7');
fprintf('Done: %d segments; metadata: %s\n',numel(meta.segments),metadataFile);
end
function directory=newRunDirectory(parent,name)
base=[name '_' datestr(now,'yyyymmdd_HHMMSS_FFF')]; directory=fullfile(parent,base); k=1;
while exist(directory,'dir') || exist(directory,'file')
    directory=fullfile(parent,sprintf('%s_%03d',base,k)); k=k+1;
end
[ok,msg]=mkdir(directory); assert(ok,msg);
end
function writeText(path,body)
fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write %s',path);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=unicode2native(char(body),'UTF-8');
count=fwrite(fid,bytes,'uint8'); assert(count==numel(bytes),'Incomplete text write.');
end
function writeJson(path,value)
writeText(path,jsonencode(value,'PrettyPrint',true));
end
function writeIndex(path,segments)
fid=fopen(path,'w'); assert(fid>=0); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'index,fileName,startSample,sampleCount,startSeconds,durationSeconds,bdtWeek,startSowSeconds,bytes\n');
for k=1:numel(segments)
    r=segments(k);
    fprintf(fid,'%d,%s,%.0f,%.0f,%.12f,%.12f,%d,%.12f,%.0f\n', ...
        r.index,r.fileName,r.startSample,r.sampleCount,r.startSeconds,r.durationSeconds, ...
        r.bdtWeek,r.startSowSeconds,r.bytes);
end
end
function validateConfig(c)
validateattributes(c.durationSeconds,{'numeric'},{'scalar','real','finite','positive','<=',3600});
validateattributes(c.segmentSeconds,{'numeric'},{'scalar','real','finite','positive'});
segmentSamples=round(c.segmentSeconds*c.sampleRateHz);
assert(segmentSamples>=1 && abs(segmentSamples/c.sampleRateHz-c.segmentSeconds)<1e-9, ...
    'Segment duration must contain an integer number of samples.');
validateattributes(c.plotMaxBins,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.analysisFftLength,{'numeric'},{'scalar','integer','>=',16});
for name={'keepFullFile','verifyFullFile','autoOverview','overviewVisible'}
    v=c.(name{1}); assert(isscalar(v) && (islogical(v) || isnumeric(v)) && ...
        isfinite(v) && (v==0 || v==1),'Expected a logical configuration flag.');
end
validateattributes(c.sampleRateHz,{'numeric'},{'scalar','real','finite','>=',8.184e6});
validateattributes(c.blockSamples,{'numeric'},{'scalar','integer','positive'});
validateattributes(c.prn,{'numeric'},{'scalar','integer','>=',6,'<=',37});
validateattributes(c.bdtWeek,{'numeric'},{'scalar','integer','>=',0,'<=',8191});
validateattributes(c.startSowSeconds,{'numeric'},{'scalar','real','finite','>=',0,'<',604800});
validateattributes(c.filterLength,{'numeric'},{'scalar','integer','>=',17});
assert(mod(c.filterLength,2)==1,'FIR length must be odd.');
assert(c.lowpassCutoffHz>2.046e6 && c.lowpassCutoffHz<c.sampleRateHz/2,'Invalid cutoff.');
validateattributes(c.geometryStepSeconds,{'numeric'},{'scalar','real','finite','positive','<=',0.1});
validateattributes(c.cn0DbHz,{'numeric'},{'scalar','real','finite'});
validateattributes(c.signalPowerDbW,{'numeric'},{'scalar','real','finite'});
assert(isequal(size(c.receiverLlaDegM),[1 3]) && all(isfinite(c.receiverLlaDegM)),'Invalid LLA.');
assert(abs(c.receiverLlaDegM(1))<90 && abs(c.receiverLlaDegM(2))<=180,'Invalid latitude/longitude.');
assert(c.zenithTroposphereM>=0 && c.ionosphereHeightM>0,'Invalid atmosphere.');
assert(c.prn==floor(c.prn),'Integer PRN required.');
assert(~isempty(regexp(c.outputName,'^[A-Za-z0-9_-]+$','once')),'Use a simple outputName.');
end

function captureCheckpoint(cfg,written,phase)
c=cfg.captureControl;
bds_capture_json(c.progressFile,struct('phase',phase,'sampleCount',written, ...
    'signalSeconds',written/cfg.sampleRateHz,'sampleRateHz',cfg.sampleRateHz));
if written==0 && bds_capture_stop(cfg,written)
    error('BDS:CaptureStoppedEmpty','Stopped before valid samples were generated.');
end
end
