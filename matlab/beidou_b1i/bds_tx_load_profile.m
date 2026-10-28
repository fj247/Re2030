function p = bds_tx_load_profile(file)
%BDS_TX_LOAD_PROFILE Load complete v1 profile; reject unsupported fields/version.
p=jsondecode(fileread(file));
% JSON has no row-vector distinction.
for n={'offsetHz','historicalLevelDbcPerHz','cornerHz'}
    p.phaseNoise.(n{1})=reshape(p.phaseNoise.(n{1}),1,[]);
end
for n={'offsetHz','levelDbc','phaseRad'}, p.spurs.(n{1})=reshape(p.spurs.(n{1}),1,[]); end
bds_tx_validate(p,8.184e6,2.8e6);
end
