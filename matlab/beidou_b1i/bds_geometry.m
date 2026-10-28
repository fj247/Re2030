function g = bds_geometry(cfg, scene, relativeSeconds)
%BDS_GEOMETRY Retarded-time MEO orbit, earth rotation, clock and atmosphere.
% Scalar-column truth grid. Values refer to reception BDT = startSow + t.
c=299792458; fc=1561.098e6; we=7.292115e-5;
ll=cfg.receiverLlaDegM; lat=ll(1)*pi/180; lon=ll(2)*pi/180;
a=6378137; f=1/298.257222101; ee=f*(2-f); N=a/sqrt(1-ee*sin(lat)^2);
rx=[(N+ll(3))*cos(lat)*cos(lon);(N+ll(3))*cos(lat)*sin(lon); ...
    (N*(1-ee)+ll(3))*sin(lat)];
Renu=[-sin(lon) cos(lon) 0; -sin(lat)*cos(lon) -sin(lat)*sin(lon) cos(lat); ...
    cos(lat)*cos(lon) cos(lat)*sin(lon) sin(lat)];
t=relativeSeconds(:); m=numel(t);
g.relativeSeconds=t; g.rangeM=zeros(m,1); g.elevationDeg=zeros(m,1);
g.azimuthDeg=zeros(m,1); g.clockSeconds=zeros(m,1);
g.codeTimeSow=zeros(m,1); g.phaseDelaySeconds=zeros(m,1);
g.ionosphereM=zeros(m,1); g.troposphereM=zeros(m,1);
for k=1:m
    tr=cfg.startSowSeconds+t(k); tau=0.08;
    for iter=1:7
        [pos,E]=orbit(scene.ephemeris,tr-tau);
        ang=we*tau;
        % Rotate transmit ECEF coordinates into the reception ECEF frame.
        rot=[cos(ang) sin(ang) 0;-sin(ang) cos(ang) 0;0 0 1];
        delta=rot*pos-rx; rho=norm(delta); tau=rho/c;
    end
    enu=Renu*delta; el=atan2(enu(3),hypot(enu(1),enu(2)));
    az=mod(atan2(enu(1),enu(2)),2*pi);
    if el<5*pi/180, error('Satellite below 5 degrees: shorten duration or modify scene.'); end
    % BDS single-layer obliquity factor. alpha=0 -> 5 ns vertical night baseline.
    % beta is still broadcast; zero alpha makes local-time cosine term zero.
    map=1/sqrt(1-(6378000/(6378000+cfg.ionosphereHeightM)*cos(el))^2);
    I=c*5e-9*map; T=cfg.zenithTroposphereM/sin(el);
    e=scene.ephemeris; dt=wrapweek(tr-tau-e.toc);
    relat=-2*sqrt(3.986004418e14)/c^2*e.e*e.sqrtA*sin(E);
    clk=e.a0+e.a1*dt+e.a2*dt^2+relat;
    g.rangeM(k)=rho; g.elevationDeg(k)=el*180/pi; g.azimuthDeg(k)=az*180/pi;
    g.clockSeconds(k)=clk; g.ionosphereM(k)=I; g.troposphereM(k)=T;
    g.codeTimeSow(k)=tr-(rho+I+T)/c+clk-e.TGD1;
    % Ionosphere delays the envelope but ADVANCES carrier phase.
    g.phaseDelaySeconds(k)=(rho+T-I)/c-clk;
end
if m>=3
    g.dopplerHz=-fc*gradient(g.phaseDelaySeconds,t);
else
    g.dopplerHz=nan(m,1);
end
g.receiverEcefM=rx;
end
function [pos,E]=orbit(e,t)
mu=3.986004418e14; we=7.292115e-5;
tk=wrapweek(t-e.toe); A=e.sqrtA^2;
M=e.M0+(sqrt(mu/A^3)+e.deltaN)*tk; E=M;
for iter=1:12, E=E-(E-e.e*sin(E)-M)/(1-e.e*cos(E)); end
v=atan2(sqrt(1-e.e^2)*sin(E),cos(E)-e.e); phi=v+e.omega;
u=phi+e.Cus*sin(2*phi)+e.Cuc*cos(2*phi);
r=A*(1-e.e*cos(E))+e.Crs*sin(2*phi)+e.Crc*cos(2*phi);
i=e.i0+e.IDOT*tk+e.Cis*sin(2*phi)+e.Cic*cos(2*phi);
O=e.Omega0+(e.OmegaDot-we)*tk-we*e.toe;
x=r*cos(u); y=r*sin(u);
pos=[x*cos(O)-y*cos(i)*sin(O);x*sin(O)+y*cos(i)*cos(O);y*sin(i)];
end
function t=wrapweek(t), t=mod(t+302400,604800)-302400; end
