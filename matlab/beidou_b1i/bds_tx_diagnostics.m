function [r,fig]=bds_tx_diagnostics(source,showFigure)
%BDS_TX_DIAGNOSTICS Manual TX diagnostics, from a run JSON or config/profile.
% Numeric curves are computed from realized coefficients, NOT noisy I/Q.
% bds_tx_diagnostics(result.metadataFile); bds_tx_diagnostics(cfg,false);
if nargin<2, showFigure=true; end
folder='';
if ischar(source)||isstring(source)
    m=bds_metadata(source); p=m.configuration.txHardware;
    fs=m.sampleRateHz; cut=m.filterOneSidedCutoffHz; folder=m.sourceDirectory;
    d=jsondecode(fileread(fullfile(folder,m.txHardware.designFile)));
    if ~p.enabled, r=struct('enabled',false,'note','Ideal-source bypass; no TX curves.'); fig=[]; return; end
elseif isfield(source,'txHardware')
    p=source.txHardware; fs=source.sampleRateHz; cut=source.lowpassCutoffHz;
    d=bds_tx_design(p,fs,cut);
else
    p=source; fs=8.184e6; cut=2.8e6; d=bds_tx_design(p,fs,cut);
end
if ~p.enabled, r=struct('enabled',false,'note','Ideal-source bypass.'); fig=[]; return; end
span=min(max(12e6,0.75*fs),0.49*d.internalSampleRateHz);
f=linspace(-span,span,8193);
H=transfer(d.bwB,d.bwA,f,d.internalSampleRateHz).*transfer(d.responseFir,1,f,d.internalSampleRateHz);
phase=unwrap(angle(H)); gd=-gradient(phase)./(2*pi*gradient(f));
extra=transfer(d.responseFir,1,f,d.internalSampleRateHz);
extraGd=-gradient(unwrap(angle(extra)))./(2*pi*gradient(f));
inside=abs(f)<=p.response.referenceBandHz;
r=struct('enabled',true,'profile',p.name,'frequencyHz',f,'amplitudeDb',20*log10(max(abs(H),realmin)), ...
    'groupDelaySeconds',gd,'extraResponseAmplitudePpDb',max(20*log10(abs(extra(inside))))-min(20*log10(abs(extra(inside)))), ...
    'extraResponseGroupDelayPpSeconds',max(extraGd(inside))-min(extraGd(inside)), ...
    'configuration',p,'design',d,'evidenceScope','Model coefficient diagnostics; NOT hardware measurements, decoded NAV or certified ICD compliance.');
aa=transfer(d.antialiasFir,1,f,d.internalSampleRateHz);
stop=abs(f)>=fs/2;
r.antialiasAmplitudeDb=20*log10(max(abs(aa),realmin));
r.antialiasStopMaxDb=max(r.antialiasAmplitudeDb(stop));
u=linspace(0,2,1001); p2=p; p2.bandwidth.enabled=false; p2.response.enabled=false; p2.iqImbalance.enabled=false;
d2=d; d2.bwB=1; d2.bwA=1; d2.responseFir=1;
v=bds_tx_chain(u,p2,d2,[]);
r.paInputAmplitude=u; r.paOutputAmplitude=abs(v); r.paPhaseDeg=angle(v)*180/pi;
r.phaseNoise=d.phaseNoiseFit;
r.predictedReferencePaCompressionDb=10/p.pa.smoothness*log10(1+10^(-p.pa.smoothness*p.pa.inputBackoffDb/10));
fig=figure('Visible',onOff(showFigure),'Name','Equivalent TX hardware diagnostics','Color','w');
subplot(2,3,1); plot(f/1e6,r.amplitudeDb); grid on; xlabel('TX baseband frequency (MHz)'); ylabel('Gain (dB)'); title('Realized linear TX response');
subplot(2,3,2); plot(f/1e6,gd*1e9); grid on; xlabel('TX baseband frequency (MHz)'); ylabel('Group delay (ns)'); title('Causal delay; DC reference removed in waveform');
subplot(2,3,3); plot(u,abs(v),u,u,'--'); grid on; xlabel('Normalized input amplitude'); ylabel('Output amplitude'); title('PA AM/AM, before fixed power calibration');
subplot(2,3,4); plot(u,r.paPhaseDeg); grid on; xlabel('Normalized input amplitude'); ylabel('Phase (deg)'); title('PA AM/PM');
subplot(2,3,5); q=d.phaseNoiseFit;
semilogx(q.fitFrequencyHz,q.fitLevelDbcPerHz,'-',q.targetOffsetHz,q.targetLevelDbcPerHz,'o'); grid on;
xlabel('Offset (Hz)'); ylabel('SSB phase noise (dBc/Hz)'); title(sprintf('AR PSD fit, max %.2f dB error',q.maxFitErrorDb));
subplot(2,3,6); plot(f/1e6,r.antialiasAmplitudeDb); grid on; ylim([-140 5]); xlabel('Frequency (MHz)'); ylabel('AA gain (dB)'); title('Numerical anti-alias filter (not extra hardware)');
if ~isempty(folder)
    saveas(fig,fullfile(folder,'tx_hardware_diagnostics.png')); savefig(fig,fullfile(folder,'tx_hardware_diagnostics.fig'));
    save(fullfile(folder,'tx_hardware_diagnostics.mat'),'r','-v7');
end
end
function h=transfer(b,a,f,fs)
b=reshape(b,1,[]); a=reshape(a,1,[]); h=complex(zeros(size(f))); den=h;
for k=1:numel(b), h=h+b(k)*exp(-1i*2*pi*f/fs*(k-1)); end
for k=1:numel(a), den=den+a(k)*exp(-1i*2*pi*f/fs*(k-1)); end
h=h./den;
end
function s=onOff(v)
if v, s='on'; else, s='off'; end
end
