function x = bds_tx_code(t,epoch,fs,code,nav,p,jitter)
%BDS_TX_CODE Cell-average DAC source with fractional falling edges.
% t is relative to epoch (BDT SOW). Integration of rectangular chips across
% each high-rate sample cell preserves sub-sample edge movement.
cr=2.046e6; base=round(epoch*cr); z=t*cr;
k=floor(z); b=(z+cr/(2*fs));
v0=value(base+k-1,code,nav); v1=value(base+k,code,nav); v2=value(base+k+1,code,nav);
e0=k; e1=k+1;
if p.edgeAsymmetry.enabled
    delta=p.edgeAsymmetry.fallingEdgeDelaySeconds*cr;
    e0=e0+delta*(v1<v0); e1=e1+delta*(v2<v1);
end
% Jitter is a residual digital-code timing process, not an additional carrier clock.
if ~isempty(jitter)
    e0=e0+jitter*cr; e1=e1+jitter*cr;
end
w0=min(1,max(0,(b-e0)*fs/cr)); w1=min(1,max(0,(b-e1)*fs/cr));
x=v0+(v1-v0).*w0+(v2-v1).*w1;
end
function v=value(k,code,nav)
% NAV, NH and PRN boundaries are integer chip boundaries in this signal.
chip=mod(k,2046)+1; nh=mod(floor(k/2046),20)+1;
bit=floor((k-round(nav.firstSubframeSow*2.046e6))/40920)+1;
assert(all(bit>=1 & bit<=numel(nav.bits)),'Insufficient NAV prehistory for TX filtering.');
secondary=1-2*(double('00000100110101001110')-double('0'));
v=reshape(1-2*double(code(chip)),1,[]).*secondary(nh).*reshape(1-2*double(nav.bits(bit)),1,[]);
end
