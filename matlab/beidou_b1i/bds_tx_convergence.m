function r=bds_tx_convergence()
%BDS_TX_CONVERGENCE Deterministic TX, 8x/16x versus 32x. About tens of ms.
% PN/jitter/spurs off: stochastic realizations and tone phase are not convergence.
% Other deterministic PA and response settings stay enabled for both A and B.
c=bds_default_config(); s=bds_scene(c); nav=bds_nav(c,s,228,8);
code=double(bds_prn(c.prn)).'; t=0.000123456+(0:32735)/c.sampleRateHz;
profiles={'transmitter_A','transmitter_B'}; factors=[8 16 32]; errors=zeros(2,2);
for j=1:2
    waves=cell(1,3);
    for k=1:3
        c.txHardware=bds_tx_hardware_profile(profiles{j}); c.txHardware.internalOversampling=factors(k);
        c.txHardware.phaseNoise.enabled=false; c.txHardware.spurs.enabled=false;
        tx=BdsTxSource(c,nav,code,t(1)); waves{k}=tx.sample(t);
    end
    for k=1:2
        errors(j,k)=norm(waves{k}-waves{3})/norm(waves{3});
    end
end
r=struct('profiles',{profiles},'factorsCompared',[8 16],'referenceFactor',32, ...
    'relativeRmsError',errors,'maxRelativeRmsError',max(errors(:)), ...
    'scope','Deterministic source convergence, fixed band; not full composite spacecraft validation.');
disp(r);
end
