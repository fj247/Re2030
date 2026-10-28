function s = bds_scene(cfg)
%BDS_SCENE Quantized, synthetic MEO broadcast ephemeris and almanacs.
% All physical propagation uses the SAME quantized values put into the NAV.
we=7.292115e-5;
e.sqrtA = q(sqrt(27906000),2^-19); e.e=q(0.005,2^-33);
e.i0=q(55*pi/180,pi*2^-31); e.omega=q(0.25,pi*2^-31);
e.M0=q(0.45,pi*2^-31); e.toe=floor(cfg.startSowSeconds/8)*8; e.toc=e.toe;
e.deltaN=q(0,pi*2^-43); e.OmegaDot=q(-2.5e-9,pi*2^-43);
e.IDOT=0; e.Cuc=0; e.Cus=0; e.Crc=0; e.Crs=0; e.Cic=0; e.Cis=0;
% Place this hypothetical orbit above the reference antenna, not a real C12 orbit.
E=e.M0; for k=1:12, E=e.M0+e.e*sin(E); end
u=atan2(sqrt(1-e.e^2)*sin(E),cos(E)-e.e)+e.omega;
node=cfg.receiverLlaDegM(2)*pi/180-atan2(sin(u)*cos(e.i0),cos(u));
e.Omega0=q(wrap(node+we*e.toe),pi*2^-31);
e.a0=q(2e-6,2^-33); e.a1=q(1e-12,2^-50); e.a2=0;
e.TGD1=q(2e-9,1e-10); e.TGD2=0;
e.alpha=zeros(1,4); e.beta=[q(72000,2^11),0,0,0];
e.URAI=0; e.AODE=0; e.AODC=0;
s.ephemeris=e;
% Legacy almanac set, AmEpID=00 (expanded pages 11..24 stay reserved).
% This background data does NOT cause additional satellite waveforms.
for id=1:30
    a.toa=floor(e.toe/4096)*4096;
    if id<=5, sma=42164000; inc=0; else, sma=27906000; inc=55*pi/180; end
    a.sqrtA=q(sqrt(sma),2^-11); a.e=q(e.e,2^-21);
    a.omega=q(e.omega,pi*2^-23);
    a.M0=q(wrap(e.M0+sqrt(3.986004418e14/(e.sqrtA^2)^3)*(a.toa-e.toe) ...
        +(id-cfg.prn)*0.4),pi*2^-23);
    a.Omega0=q(wrap(e.Omega0+e.OmegaDot*(a.toa-e.toe) ...
        +(id-cfg.prn)*0.3),pi*2^-23);
    a.deltaI=q(inc-(id>5)*0.3*pi,pi*2^-19);
    a.OmegaDot=q(e.OmegaDot,pi*2^-38); a.a0=q(e.a0,2^-20); a.a1=q(e.a1,2^-38);
    s.almanac(id)=a;
end
s.utc = struct('A0',0,'A1',0,'deltaLS',4,'deltaLSF',4, ...
    'WNLSF',mod(cfg.bdtWeek,256),'DN',6);
s.timeDescription='Synthetic BDT week/SOW. UTC offsets are assumed scenario data, not live service data.';
s.provenance='Synthetic, quantized broadcast parameters; not RINEX and not a historical replay.';
end
function y=q(x,l), y=round(x/l)*l; end
function y=wrap(x), y=mod(x+pi,2*pi)-pi; end
