function report=test_bds_tx_hardware(includePlots,includeConvergence)
%TEST_BDS_TX_HARDWARE Run in MATLAB R2024a. Does not run a classifier.
if nargin<1, includePlots=true; end
if nargin<2, includeConvergence=false; end
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
c=bds_default_config(); c.durationSeconds=0.04; c.outputDirectory=root;
c.autoOverview=false; c.segmentSeconds=0.013; c.outputName='hardware_A';
p=c.txHardware; file=fullfile(root,'profile.json'); bds_tx_save_profile(file,p);
loaded=bds_tx_load_profile(file); assert(isequaln(loaded,p),'Profile round-trip changed values.');
% Unknown fields and invalid parameters must reject.
bad=p; bad.pa.smoothness=0; rejected=false;
try, bds_tx_validate(bad,c.sampleRateHz,c.lowpassCutoffHz); catch, rejected=true; end
assert(rejected); bad=p; bad.unknown=true; rejected=false;
try, bds_tx_save_profile(fullfile(root,'bad.json'),bad); catch, rejected=true; end
assert(rejected);
% Deterministic source and random processes cannot reset at output boundaries.
c.blockSamples=32736; a=bds_generate(c); xa=bds_read_samples(a.metadataFile,0,round(c.durationSeconds*c.sampleRateHz));
c.blockSamples=12345; c.segmentSeconds=0.017; c.keepFullFile=false;
c.outputName='hardware_A_different_storage'; b=bds_generate(c);
xb=bds_read_samples(b.metadataFile,0,numel(xa));
assert(isequal(xa,xb),'Receive block/storage changes altered hardware waveform.');
c.txHardware=bds_tx_hardware_profile('transmitter_B'); c.outputName='hardware_B';
bb=bds_generate(c); xbb=bds_read_samples(bb.metadataFile,0,numel(xa));
assert(norm(double(xa)-double(xbb))>0,'A/B unexpectedly identical.');
% Same receiver noise across profiles: weak TX differences are not noise labels.
ma=bds_metadata(a.metadataFile); mb=bds_metadata(bb.metadataFile);
assert(abs(ma.measuredNoisePowerW-mb.measuredNoisePowerW)<1e-25);
% Ideal master bypass ignores valid per-module settings and internal factor.
c.txHardware=p; c.txHardware.enabled=false; c.outputName='ideal'; ia=bds_generate(c);
c.txHardware=bds_tx_hardware_profile('transmitter_B'); c.txHardware.enabled=false;
c.txHardware.internalOversampling=16; c.outputName='ideal_other_profile'; ib=bds_generate(c);
assert(isequal(bds_read_samples(ia.metadataFile,0,numel(xa)),bds_read_samples(ib.metadataFile,0,numel(xa))));
% Complete saved IQ, blind target search, wrong PRN and independent noise controls.
o=struct('dopplerMinHz',-1000,'dopplerMaxHz',1000,'noiseTrials',3, ...
    'plotResults',false,'saveResults',false,'showFigure',false);
ea=bds_validate_signal(a.metadataFile,o); eb=bds_validate_signal(bb.metadataFile,o);
assert(all(ea.targetDetected)&&all(eb.targetDetected),'TX signal structure not recovered.');
assert(~ea.otherPrnDetected&&~eb.otherPrnDetected&&ea.noiseDetectionCount==0&&eb.noiseDetectionCount==0);
% Streaming random process equivalence on split queries (not same seed = new HW).
f=10000; t=(0:9999)/f; z1=BdsTxGaussian(f,0.99,1,17,0); y=z1.sample(t);
z2=BdsTxGaussian(f,0.99,1,17,0); yy=[z2.sample(t(1:3333)) z2.sample(t(3334:end))]; assert(isequal(y,yy));
% Fractional source-edge change exists even below one high-rate sample period.
s=bds_scene(c); nv=bds_nav(c,s,228,8); code=double(bds_prn(c.prn)).';
ph=bds_tx_hardware_profile(); ph.edgeAsymmetry.enabled=false;
t=(0:20000)/65.472e6; y=bds_tx_code(t,240,65.472e6,code,nv,ph,[]);
ph.edgeAsymmetry.enabled=true; ph.edgeAsymmetry.fallingEdgeDelaySeconds=1e-9;
yy=bds_tx_code(t,240,65.472e6,code,nv,ph,[]); assert(any(y~=yy));
% Optional blocks: each finite and changes the equivalent source under excitation.
d=bds_tx_design(p,c.sampleRateHz,c.lowpassCutoffHz); sig=complex(cos(0:0.01:100),sin(0:0.01:100));
p0=p; p0.iqImbalance.enabled=false; y=bds_tx_chain(sig,p0,d,[]);
p0.iqImbalance.enabled=true; yy=bds_tx_chain(sig,p0,d,[]); assert(all(isfinite(yy))&&norm(y-yy)>0);
report=struct('passed',true,'convergence',[],'phaseMaskFitErrorDb',d.phaseNoiseFit.maxFitErrorDb);
if includeConvergence
    report.convergence=bds_tx_convergence();
    assert(report.convergence.maxRelativeRmsError<0.01,'Internal sampling convergence exceeds 1 percent.');
end
if includePlots
    [r,fig]=bds_tx_diagnostics(a.metadataFile,false); close(fig);
    assert(r.antialiasStopMaxDb<-50,'Insufficient AA stop-band rejection.');
end
fprintf('PASS: TX profiles, continuous stream, bypass, fractional edges, random process and A/B saved-IQ structure.\n');
end
