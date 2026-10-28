function p = bds_tx_validate(p,fs,rxCutoff)
%BDS_TX_VALIDATE Strict complete profile; no silently ignored unknown fields.
ref=bds_tx_hardware_profile(); checkFields(p,ref,'txHardware');
assert(strcmp(p.schema,ref.schema) && strcmp(p.modelVersion,ref.modelVersion),'Unsupported TX profile version.');
assert(ischar(p.name) || (isstring(p.name)&&isscalar(p.name)),'Invalid profile name.');
flag(p.enabled); scalar(p.internalOversampling,2,32,true); assert(mod(p.internalOversampling,2)==0,'Oversampling must be even.');
scalar(p.internalBlockSamples,1024,1048576,true); scalar(p.interpolationHalfLength,8,128,true);
scalar(p.seed,0,2^32-100,true); scalar(p.extraCarrierOffsetHz,-1e4,1e4,false); scalar(p.extraLossDb,0,100,false);
for k={'bandwidth','response','pa','phaseNoise','spurs','iqImbalance','edgeAsymmetry','timingJitter'}
    flag(p.(k{1}).enabled);
end
assert(p.bandwidth.order==2,'Only the documented second-order Butterworth is implemented.');
scalar(p.bandwidth.cutoffHz,0,fs*p.internalOversampling/2,false); assert(p.bandwidth.cutoffHz>0 && p.bandwidth.cutoffHz<fs*p.internalOversampling/2);
scalar(p.response.amplitudeRipplePpDb,0,3,false); scalar(p.response.groupDelayRipplePpSeconds,0,100e-9,false);
scalar(p.response.referenceBandHz,1,fs/2,false); scalar(p.response.firLength,33,4097,true); assert(mod(p.response.firLength,2)==1);
assert(strcmp(p.pa.model,'Rapp')); flag(p.pa.ampmEnabled); scalar(p.pa.smoothness,0.5,20,false);
scalar(p.pa.inputBackoffDb,0,30,false); scalar(p.pa.ampmAtReferenceDeg,-30,30,false);
v=p.phaseNoise; assert(isvector(v.offsetHz)&&numel(v.offsetHz)>=2&&all(isfinite(v.offsetHz))&&all(v.offsetHz>0)&&all(diff(v.offsetHz)>0));
assert(isvector(v.historicalLevelDbcPerHz)&&numel(v.historicalLevelDbcPerHz)==numel(v.offsetHz)&&all(isfinite(v.historicalLevelDbcPerHz))&&all(v.historicalLevelDbcPerHz<0));
scalar(v.marginDb,0,60,false); scalar(v.processSampleRateHz,1,fs*p.internalOversampling,false);
assert(max(v.offsetHz)<v.processSampleRateHz/2,'Phase-noise process Nyquist must exceed every spectral point.');
assert(isvector(v.cornerHz)&&all(isfinite(v.cornerHz))&&all(v.cornerHz>0)&&all(v.cornerHz<v.processSampleRateHz/2)&&all(diff(v.cornerHz)>0));
v=p.spurs; assert(isvector(v.offsetHz)&&isvector(v.levelDbc)&&isvector(v.phaseRad)&&numel(v.offsetHz)==numel(v.levelDbc)&&numel(v.offsetHz)==numel(v.phaseRad));
assert(all(isfinite([v.offsetHz(:);v.levelDbc(:);v.phaseRad(:)]))&&all(abs(v.offsetHz)<fs*p.internalOversampling/2)&&all(v.levelDbc<=-30));
scalar(p.iqImbalance.amplitudeDb,-3,3,false); scalar(p.iqImbalance.phaseDeg,-10,10,false);
scalar(p.edgeAsymmetry.fallingEdgeDelaySeconds,-20e-9,20e-9,false);
scalar(p.timingJitter.rmsSeconds,0,2e-9,false); scalar(p.timingJitter.correlationSeconds,1e-5,1,false);
assert(fs>=8.184e6 && rxCutoff>0 && rxCutoff<fs/2,'Invalid receive band.');
end
function checkFields(a,b,path)
assert(isstruct(a)&&isscalar(a),'Expected scalar structure: %s',path);
assert(isequal(sort(fieldnames(a)),sort(fieldnames(b))),'Missing/unknown fields in %s. Load a complete profile first.',path);
n=fieldnames(b);
for k=1:numel(n)
    if isstruct(b.(n{k})), checkFields(a.(n{k}),b.(n{k}),[path '.' n{k}]); end
end
end
function scalar(x,lo,hi,integer)
assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x>=lo&&x<=hi,'Invalid TX numeric parameter.');
if integer, assert(x==floor(x),'Expected integer TX parameter.'); end
end
function flag(x)
assert((isnumeric(x)||islogical(x))&&isscalar(x)&&isreal(x)&&isfinite(x)&&(x==0||x==1),'Invalid TX logical flag.');
end
