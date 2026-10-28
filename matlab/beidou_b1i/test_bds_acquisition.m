function test_bds_acquisition(includePlots)
%TEST_BDS_ACQUISITION Known-signal/noise controls and saved-I/Q blind search.
% This test fixture knows its injected parameters; the detector does NOT.
if nargin<1, includePlots=true; end
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
fs=8.184e6; duration=0.04; N=round(duration*fs); D=32;
ix=-D:D; cutoff=2.8e6; z=2*cutoff/fs*ix; si=ones(size(z));
a=z~=0; si(a)=sin(pi*z(a))./(pi*z(a));
h=(2*cutoff/fs)*si.*(0.54-0.46*cos(2*pi*(0:64)/64)); h=h/sum(h);
t=(-D:N-1+D)'/fs; delay=0.00042375; fd=1730;
sv=(1+fd/1561.098e6)*t-delay;
code=1-2*double(bds_prn(12)); nh=1-2*(double('00000100110101001110')-double('0'));
s=code(mod(floor(sv*2.046e6),2046)+1).*reshape(nh(mod(floor(sv*1000),20)+1),[],1);
s=s.*(1-2*mod(floor(sv*50),2)).*exp(1i*2*pi*fd*t);
old=rng; restore=onCleanup(@()rng(old)); %#ok<NASGU>
rng(428,'twister'); r=randn(numel(t),2);
noise=sqrt(fs/(2*10^(45/10)))*complex(r(:,1),r(:,2));
y=filter(h,1,s+noise); y=y(2*D+1:end);
n=filter(h,1,noise); n=n(2*D+1:end);
o=bds_acquisition_options(struct('dopplerMinHz',-4000,'dopplerMaxHz',4000, ...
    'noiseTrials',2,'showFigure',false,'plotResults',includePlots));
a=bds_acquire(y,fs,12,o); other=bds_acquire(y,fs,13,o);
assert(a.detected && ~other.detected,'Known PRN / other-PRN control failed.');
assert(abs(a.codeDelaySamples-round(delay*fs))<=2,'Wrong code-delay estimate.');
assert(abs(a.dopplerHz-fd)<=o.dopplerStepHz,'Wrong Doppler estimate.');
z=bds_acquire(complex(zeros(size(n))),fs,12,o); assert(~z.detected && z.peakScore==0);
null=bds_acquire(n,fs,12,o); assert(~null.detected,'Noise-only fixture falsely detected.');
% Route the waveform through the SAME storage writer as simulation, and supply
% intentionally unusable timing/truth metadata: validation must not read it.
c=bds_default_config(); c.outputDirectory=root; c.segmentSeconds=0.01;
c.keepFullFile=false; w=BdsFileWriter(root,'fixture',c,N);
cw=onCleanup(@()w.abort());
for k=1:12345:N, w.write(y(k:min(k+12344,N))); end
w.finish(); clear cw;
m.schema='bds-b1i-iq-v2'; m.numberComplexSamples=N; m.sampleRateHz=fs;
m.durationSeconds=duration; m.waveformFile=''; m.segmentSamples=round(0.01*fs); m.segments=w.Records;
m.configuration=struct('prn',12,'startSowSeconds','MUST NOT USE','cn0DbHz','MUST NOT USE', ...
    'signalPowerDbW','MUST NOT USE','randomSeed','MUST NOT USE');
m.scene='MUST NOT USE'; m.truthFile='this_file_must_not_be_opened.mat'; m.filterCoefficients=h;
p=fullfile(root,'fixture.json'); fid=fopen(p,'w'); assert(fid>=0);
fwrite(fid,jsonencode(m),'char'); fclose(fid);
o.probeStartSeconds=[0 0.01 0.02];
[r,fig]=bds_validate_signal(p,o);
if ~isempty(fig), fc=onCleanup(@()close(fig)); end %#ok<NASGU>
assert(all(r.targetDetected) && ~r.otherPrnDetected && r.noiseDetectionCount==0);
assert(strcmp(r.evidenceStatus,'supported_in_tested_windows'));
assert(exist(fullfile(r.outputDirectory,'signal_presence.json'),'file')==2);
assert(exist(fullfile(r.outputDirectory,'signal_presence.mat'),'file')==2);
if includePlots
    assert(strcmp(r.plotStatus,'saved'));
    assert(exist(fullfile(r.outputDirectory,'signal_presence.png'),'file')==2);
    assert(exist(fullfile(r.outputDirectory,'signal_presence.fig'),'file')==2);
end
fprintf('PASS: acquisition, delay/Doppler, non-target/noise controls and saved-file blind verification.\n');
end
