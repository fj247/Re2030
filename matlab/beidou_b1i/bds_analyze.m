function stats=bds_analyze(source,startSample,sampleCount,maxBins,nfft)
%BDS_ANALYZE Stream ALL requested samples into envelopes, powers and mean PSD.
% Fixed nonoverlapping Hamming windows. The final partial FFT is normalized
% using only the actual window coefficients; FFT padding never changes files.
m=bds_metadata(source);
if nargin<2, startSample=0; end
if nargin<3, sampleCount=m.numberComplexSamples-startSample; end
if nargin<4, maxBins=2000; end
if nargin<5, nfft=4096; end
validateattributes(maxBins,{'numeric'},{'scalar','integer','positive'});
validateattributes(nfft,{'numeric'},{'scalar','integer','>=',16});
assert(sampleCount>=1 && startSample>=0 && startSample+sampleCount<=m.numberComplexSamples);
fs=m.sampleRateHz; binSize=ceil(sampleCount/maxBins); nb=ceil(sampleCount/binSize);
stats.startSample=startSample; stats.sampleCount=sampleCount; stats.sampleRateHz=fs;
stats.timeSeconds=zeros(nb,1); stats.binStartSample=zeros(nb,1); stats.binSampleCount=zeros(nb,1);
stats.iMin=zeros(nb,1); stats.iMax=zeros(nb,1); stats.qMin=zeros(nb,1); stats.qMax=zeros(nb,1);
stats.meanPowerW=zeros(nb,1);
w=0.54-0.46*cos(2*pi*(0:nfft-1)'/(nfft-1));
fftSum=zeros(nfft,1); energy=0; frames=0; carry=complex(zeros(0,1));
maxChunk=262144;
for k=1:nb
    binStart=(k-1)*binSize; count=min(binSize,sampleCount-binStart);
    stats.binStartSample(k)=startSample+binStart;
    stats.binSampleCount(k)=count;
    stats.timeSeconds(k)=(binStart+(count-1)/2)/fs;
    imin=inf; imax=-inf; qmin=inf; qmax=-inf; power=0;
    for offset=0:maxChunk:count-1
        take=min(maxChunk,count-offset);
        x=double(bds_read_samples(m,startSample+binStart+offset,take));
        imin=min(imin,min(real(x))); imax=max(imax,max(real(x)));
        qmin=min(qmin,min(imag(x))); qmax=max(qmax,max(imag(x)));
        power=power+sum(abs(x).^2);
        buffer=[carry;x]; nf=floor(numel(buffer)/nfft);
        if nf>0
            windows=reshape(buffer(1:nf*nfft),nfft,nf);
            y=fft(bsxfun(@times,windows,w),nfft,1);
            fftSum=fftSum+sum(abs(y).^2,2);
            energy=energy+nf*sum(w.^2); frames=frames+nf;
        end
        carry=buffer(nf*nfft+1:end);
    end
    stats.iMin(k)=imin; stats.iMax(k)=imax; stats.qMin(k)=qmin; stats.qMax(k)=qmax;
    stats.meanPowerW(k)=power/count;
end
if ~isempty(carry)
    wc=w(1:numel(carry)); y=fft(carry.*wc,nfft);
    fftSum=fftSum+abs(y).^2; energy=energy+sum(wc.^2); frames=frames+1;
end
stats.frequencyHz=(-floor(nfft/2):ceil(nfft/2)-1)'*fs/nfft;
stats.psdWPerHz=fftshift(fftSum)/(fs*energy);
stats.psdDbWPerHz=10*log10(max(stats.psdWPerHz,realmin));
stats.totalMeanPowerW=sum(stats.meanPowerW.*stats.binSampleCount)/sampleCount;
stats.spectrumWindows=frames; stats.fftLength=nfft;
stats.description='All samples; min/max display bins; power includes signal+noise; Hamming mean PSD.';
end
