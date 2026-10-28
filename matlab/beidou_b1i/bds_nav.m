function nav = bds_nav(cfg, scene, firstSubframeSow, numberSubframes)
%BDS_NAV Build actual D1 words, BCH parity and interleaving (ICD 3.0 sec. 5).
% Information is packed in logical word positions BEFORE parity/interleaving.
% Word 1: 26 information bits; words 2:10: 22 information bits each.
assert(mod(firstSubframeSow,6)==0);
nav.bits=false(300*numberSubframes,1);
nav.information=false(224,numberSubframes);
nav.subframeSow=zeros(numberSubframes,1);
nav.frameId=zeros(numberSubframes,1); nav.page=zeros(numberSubframes,1);
e=scene.ephemeris;
for k=1:numberSubframes
    absSow=firstSubframeSow+6*(k-1); sow=mod(absSow,604800);
    wn=mod(cfg.bdtWeek+floor(absSow/604800),8192);
    sf=mod(floor(sow/6),5)+1;
    page=mod(floor(sow/30),24)+1;
    % First 38 information bits: preamble 11, reserved 4, ID 3, SOW 20.
    v=[ub(bin2dec('11100010010'),11) false(1,4) ub(sf,3) ub(sow,20)];
    switch sf
        case 1
            v=[v ub(0,1) ub(e.AODC,5) ub(e.URAI,4) ub(wn,13) ...
                num(e.toc,17,8,false) num(e.TGD1,10,1e-10,true) ...
                num(e.TGD2,10,1e-10,true) ...
                num(e.alpha(1),8,2^-30,true) num(e.alpha(2),8,2^-27,true) ...
                num(e.alpha(3),8,2^-24,true) num(e.alpha(4),8,2^-24,true) ...
                num(e.beta(1),8,2^11,true) num(e.beta(2),8,2^14,true) ...
                num(e.beta(3),8,2^16,true) num(e.beta(4),8,2^16,true) ...
                num(e.a2,11,2^-66,true) num(e.a0,24,2^-33,true) ...
                num(e.a1,22,2^-50,true) ub(e.AODE,5)];
        case 2
            toe=round(e.toe/8); tb=ub(toe,17);
            v=[v num(e.deltaN,16,pi*2^-43,true) num(e.Cuc,18,2^-31,true) ...
                num(e.M0,32,pi*2^-31,true) num(e.e,32,2^-33,false) ...
                num(e.Cus,18,2^-31,true) num(e.Crc,18,2^-6,true) ...
                num(e.Crs,18,2^-6,true) num(e.sqrtA,32,2^-19,false) tb(1:2)];
        case 3
            tb=ub(round(e.toe/8),17);
            v=[v tb(3:17) num(e.i0,32,pi*2^-31,true) ...
                num(e.Cic,18,2^-31,true) num(e.OmegaDot,24,pi*2^-43,true) ...
                num(e.Cis,18,2^-31,true) num(e.IDOT,14,pi*2^-43,true) ...
                num(e.Omega0,32,pi*2^-31,true) num(e.omega,32,pi*2^-31,true) false];
        otherwise
            v=[v false ub(page,7)];
            if sf==4 || page<=6
                if sf==4, id=page; else, id=24+page; end
                a=scene.almanac(id);
                v=[v num(a.sqrtA,24,2^-11,false) num(a.a1,11,2^-38,true) ...
                    num(a.a0,11,2^-20,true) num(a.Omega0,24,pi*2^-23,true) ...
                    num(a.e,17,2^-21,false) num(a.deltaI,16,pi*2^-19,true) ...
                    num(a.toa,8,4096,false) num(a.OmegaDot,17,pi*2^-38,true) ...
                    num(a.omega,24,pi*2^-23,true) num(a.M0,24,pi*2^-23,true) ...
                    ub(0,2)]; % AmEpID=00: no expanded almanacs
            elseif page==7
                v=[v false(1,19*9) false(1,7)]; % all synthetic legacy SVs healthy
            elseif page==8
                v=[v false(1,11*9) ub(mod(wn,256),8) ...
                    num(scene.almanac(1).toa,8,4096,false) false(1,63)];
            elseif page==9
                % Reserved 30, then offsets GPS/Galileo/GLO (all synthetic zero).
                v=[v false(1,30) num(0,14,1e-10,true) num(0,16,1e-10,true) ...
                    num(0,14,1e-10,true) num(0,16,1e-10,true) ...
                    num(0,14,1e-10,true) num(0,16,1e-10,true) false(1,58)];
            elseif page==10
                u=scene.utc;
                v=[v num(u.deltaLS,8,1,true) num(u.deltaLSF,8,1,true) ...
                    ub(u.WNLSF,8) num(u.A0,32,2^-30,true) ...
                    num(u.A1,24,2^-50,true) ub(u.DN,8) false(1,90)];
            else
                v=[v false(1,178)]; % AmEpID != 11: pages 11..24 reserved
            end
    end
    assert(numel(v)==224,'D1 information allocation must total 224 bits.');
    words=false(30,10);
    words(:,1)=[v(1:15) bds_bch(v(16:26),'encode')].';
    for w=2:10
        d=v(27+(w-2)*22:48+(w-2)*22);
        c1=bds_bch(d(1:11),'encode'); c2=bds_bch(d(12:22),'encode');
        words(1:2:30,w)=c1; words(2:2:30,w)=c2;
    end
    nav.bits((k-1)*300+(1:300))=words(:);
    nav.information(:,k)=v.'; nav.subframeSow(k)=absSow;
    nav.frameId(k)=sf; nav.page(k)=page;
end
nav.firstSubframeSow=firstSubframeSow;
nav.bitRateHz=50;
end
function b=num(x,n,lsb,signed)
z=round(x/lsb);
if signed, assert(z>=-2^(n-1) && z<2^(n-1),'Signed field overflow.');
else, assert(z>=0 && z<2^n,'Unsigned field overflow.'); end
b=ub(mod(z,2^n),n);
end
function b=ub(x,n)
assert(x==floor(x) && x>=0 && x<2^n,'Unsigned bit field overflow.');
b=logical(mod(floor(x./2.^(n-1:-1:0)),2));
end
