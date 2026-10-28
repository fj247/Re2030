function d = bds_tx_design(p,fs,rxCutoff)
%BDS_TX_DESIGN Realized coefficients, causal delay reference and PSD fit.
persistent cachedParameters cachedFs cachedCutoff cachedDesign
p=bds_tx_validate(p,fs,rxCutoff);
if ~isempty(cachedDesign) && isequal(p,cachedParameters) && isequal(fs,cachedFs) && isequal(rxCutoff,cachedCutoff)
    d=cachedDesign;return;
end
fhi=fs*p.internalOversampling;
d.effectiveModules=struct();
for name={'bandwidth','response','pa','phaseNoise','spurs','iqImbalance','edgeAsymmetry','timingJitter'}
    d.effectiveModules.(name{1})=logical(p.enabled && p.(name{1}).enabled);
end
d.effectiveModules.ampm=logical(p.enabled && p.pa.enabled && p.pa.ampmEnabled);
d.references={ ...
    'CSNO ICD 2.0, Dec 2013, 4.2.4/4.2.7: historical PN mask and bandwidth, not current per-SV measurements'; ...
    'https://gge.ext.unb.ca/Resources/beidou_icd_english_ver2.0.pdf'; ...
    'CSNO B1I ICD 3.0, Feb 2019, 4.2: current model signal definition, PLL-conditioned phase requirement'; ...
    'https://en.beidou.gov.cn/SYSTEMS/ICD/201902/P020190227702348791891.pdf'; ...
    'Chen et al., Astronomical Research and Technology 19(5),447-457,2022,Table3: spur levels, not tone positions or device distributions'; ...
    'https://html.rhhz.net/Jwk_twyjyjs/html/20220506.htm'; ...
    'https://www.mathworks.com/help/comm/ref/comm.memorylessnonlinearity-system-object.html'; ...
    'https://www.mathworks.com/help/comm/ref/comm.phasenoise-system-object.html'};
d.internalSampleRateHz=fhi; d.intermediateSampleRateHz=2*fs;
d.decimation=p.internalOversampling/2;
d.bwB=1; d.bwA=1; bwDelay=0;
if p.bandwidth.enabled
    K=tan(pi*p.bandwidth.cutoffHz/fhi); den=1+sqrt(2)*K+K^2;
    d.bwB=K^2/den*[1 2 1]; d.bwA=[1 2*(K^2-1)/den (1-sqrt(2)*K+K^2)/den];
    bwDelay=sqrt(2)/(2*K)/fhi;
end
d.responseFir=1; responseDelay=0;
if p.response.enabled
    % firLength is specified at 65.472 MHz: keep physical support as fs changes.
    N=2*round((p.response.firLength-1)/2*fhi/65.472e6)+1; D=(N-1)/2;
    f=(0:N-1)*fhi/N; f(f>fhi/2)=f(f>fhi/2)-fhi;
    B=p.response.referenceBandHz;
    % Smooth even amplitude and odd phase. sin integral gives cosine GD ripple.
    taper=exp(-(f/(2*B)).^8);
    ampDb=(p.response.amplitudeRipplePpDb/2)*cos(pi*f/B).*taper;
    ph=-p.response.groupDelayRipplePpSeconds*B*sin(pi*f/B).*taper;
    target=10.^(ampDb/20).*exp(1i*ph);
    h=real(fftshift(ifft(target))); win=0.42-0.5*cos(2*pi*(0:N-1)/(N-1))+0.08*cos(4*pi*(0:N-1)/(N-1));
    h=h.*win; h=h/sum(h); d.responseFir=h;
    responseDelay=sum((0:N-1).*h)/fhi;
    d.responseNominalDelaySamples=D;
end
% Before interpolation/decimation: pass receive useful band; stop at output Nyquist.
transition=fs/2-rxCutoff; len=2*ceil(6*fhi/transition/2)+1;
d.antialiasFir=lowpassFir(len,(rxCutoff+fs/2)/2,fhi);
aaDelay=(len-1)/(2*fhi);
d.hardwareReferenceDelaySeconds=bwDelay+responseDelay;
d.totalReferenceDelaySeconds=d.hardwareReferenceDelaySeconds+aaDelay;
d.delayPolicy='Remove DC group delay of linear TX/AA filters by evaluating advanced TX time; retain waveform deformation. NAV TGD is not added again.';
d.phaseNoiseFit=phaseFit(p.phaseNoise);
d.referenceInputAmplitude=1;
d.amplitudeCalibration=1; % Filled by source constructor, fixed for the entire run.
d.referencePolicy='Normalize main deterministic TX output power using fixed 8ms PRN calibration BEFORE anti-alias/RX; no per-block normalization. Excludes PN/spurs.';
cachedParameters=p;cachedFs=fs;cachedCutoff=rxCutoff;cachedDesign=d;
end
function h=lowpassFir(L,cut,fs)
n=-(L-1)/2:(L-1)/2; z=2*cut/fs*n; s=ones(size(z)); k=z~=0; s(k)=sin(pi*z(k))./(pi*z(k));
w=0.42-0.5*cos(2*pi*(0:L-1)/(L-1))+0.08*cos(4*pi*(0:L-1)/(L-1));
h=2*cut/fs*s.*w; h=h/sum(h);
end
function r=phaseFit(p)
f=logspace(log10(p.offsetHz(1)),log10(p.offsetHz(end)),101).';
level=interp1(log10(p.offsetHz),p.historicalLevelDbcPerHz-p.marginDb,log10(f),'linear');
target=2*10.^(level/10); fp=p.processSampleRateHz;
a=exp(-2*pi*p.cornerHz(:).'/fp);
% Unit-variance AR(1) one-sided PSD, plus linear-interpolator sinc^4 response.
w=2*pi*f/fp;
S=(2/fp)*(1-a.^2)./((1-a).^2+2*a.*(1-cos(w)));
z=f/fp; si=sin(pi*z)./(pi*z); S=S.*si.^4;
A=S./target; scale=sqrt(sum(A.^2,1)); B=A./scale;
coef=zeros(numel(a),1); residual=ones(size(f));
for iteration=1:1000
    for j=1:numel(a)
        old=coef(j); coef(j)=max(0,old+B(:,j)'*residual);
        residual=residual-B(:,j)*(coef(j)-old);
    end
end
variance=coef./scale(:);
fit=S*variance;
r=struct('processSampleRateHz',fp,'cornerHz',p.cornerHz,'arPole',a, ...
    'componentVarianceRad2',variance(:).','targetOffsetHz',p.offsetHz, ...
    'targetLevelDbcPerHz',p.historicalLevelDbcPerHz-p.marginDb, ...
    'fitFrequencyHz',f(:).','fitLevelDbcPerHz',10*log10(fit(:).'/2), ...
    'maxFitErrorDb',max(abs(10*log10(fit./target))), ...
    'rmsPhaseRad',sqrt(sum(variance)), ...
    'method','Stationary independent AR(1) mixture, nonnegative relative-PSD fit; linear interpolation. Not an exact mask generator or PLL certificate.', ...
    'extension','Actual low/high frequency extension follows fitted Lorentzian mixture, bandlimited at process Nyquist; no extrapolation asserted beyond this model.');
end
