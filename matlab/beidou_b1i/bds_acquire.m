function a=bds_acquire(iq,sampleRateHz,prn,overrides)
%BDS_ACQUIRE Blind code-delay/Doppler PCPS search from complex I/Q only.
% No metadata, ephemeris, true delay/carrier or navigation truth is read.
% For NH/data transition robustness, independently correlate the two 0.5-ms
% halves of every one-ms input block, then noncoherently sum squared magnitudes.
% This mitigates, but does not eliminate, a transition inside a half-block.
% Median-background Gamma/Bonferroni threshold is a NOMINAL approximation.
if nargin<4, overrides=struct(); end
o=bds_acquisition_options(overrides);
validateattributes(sampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(prn,{'numeric'},{'scalar','integer','>=',6,'<=',37});
N=round(sampleRateHz/1000); H=N/2; M=o.dwellMilliseconds;
assert(N>=2046 && mod(N,2)==0 && abs(N/sampleRateHz-0.001)<1e-12, ...
    'Acquisition requires an even integer sample count per 1 ms.');
assert(isvector(iq) && numel(iq)>=M*N,'Not enough I/Q for configured dwell.');
x=double(iq(1:M*N)); x=x(:);
assert(all(isfinite(x)),'I/Q contains NaN or Inf.');
x=reshape(x,N,M); t=(0:N-1)'/sampleRateHz;
code=1-2*double(bds_prn(prn));
chipIndex=mod(floor((0:N-1)'*2.046e6/sampleRateHz),2046)+1;
replica=code(chipIndex); codeFft=conj(fft(replica));
freqs=(o.dopplerMinHz:o.dopplerStepHz:o.dopplerMaxHz).';
raw=zeros(numel(freqs),N);
for k=1:numel(freqs)
    z=bsxfun(@times,x,exp(-1i*2*pi*freqs(k)*t));
    z1=z; z1(H+1:end,:)=0;
    z2=z; z2(1:H,:)=0;
    r1=ifft(bsxfun(@times,fft(z1,[],1),codeFft),[],1);
    r2=ifft(bsxfun(@times,fft(z2,[],1),codeFft),[],1);
    raw(k,:)=sum(abs(r1).^2+abs(r2).^2,2).';
end
shape=2*M;
% If cells were independent Gamma(shape,scale), this converts their median
% into an estimated mean; colored noise and overlapping hypotheses violate
% exact assumptions. State this explicitly in the report and plots.
medianToMean=gammaincinv(0.5,shape)/shape;
background=median(raw(:))/medianToMean;
if background>0, score=raw/background; else, score=zeros(size(raw)); end
q=1-o.nominalSearchPfa/numel(raw);
assert(q<1,'Search too large for threshold floating-point resolution.');
threshold=gammaincinv(q,shape)/shape;
[peak,linear]=max(score(:)); [fi,ci]=ind2sub(size(score),linear);
guard=ceil(o.guardChips*sampleRateHz/2.046e6);
other=score; excluded=mod((ci-1)+(-guard:guard),N)+1;
other(:,excluded)=0; competitor=max(other(:));
if peak>0, ratio=peak/max(competitor,realmin); else, ratio=0; end
a.prn=prn; a.sampleRateHz=sampleRateHz; a.samplesUsed=M*N;
a.durationSeconds=M/1000; a.halfBlockSeconds=0.0005;
a.dopplerHz=freqs(fi); a.codeDelaySamples=ci-1;
a.codeDelaySeconds=(ci-1)/sampleRateHz; a.codeDelayChips=(ci-1)*2.046e6/sampleRateHz;
a.peakScore=peak; a.nominalThreshold=threshold;
a.peakToCompetitorRatio=ratio; a.minimumPeakRatio=o.minimumPeakRatio;
a.detected=peak>=threshold && ratio>=o.minimumPeakRatio;
a.atDopplerBoundary=(fi==1 || fi==numel(freqs));
a.backgroundEstimate=background; a.inputMeanPowerW=mean(abs(x(:)).^2);
a.frequencyHz=freqs; a.delayChips=(0:N-1)*2.046e6/sampleRateHz;
a.scoreMap=score; a.bestFrequencySlice=score(fi,:);
a.nominalSearchPfa=o.nominalSearchPfa;
a.thresholdNote=['Nominal Gamma(shape=2*M), median-background, Bonferroni reference; ' ...
    'colored-noise/cell dependencies and background estimation mean actual Pfa is NOT certified.'];
a.delayNote='Local code delay modulo 1 ms, not a navigation subframe boundary or absolute propagation time.';
end
