function [y,state] = bds_tx_chain(x,p,d,state)
%BDS_TX_CHAIN Deterministic equivalent TX; normalized voltage, no receiver noise.
if nargin<4 || isempty(state)
    state.bw=zeros(1,max(numel(d.bwA),numel(d.bwB))-1);
    state.response=zeros(1,numel(d.responseFir)-1);
end
[y,state.bw]=filter(d.bwB,d.bwA,x,state.bw);
if p.iqImbalance.enabled
    g=10^(p.iqImbalance.amplitudeDb/40); ph=p.iqImbalance.phaseDeg*pi/180;
    I=g*real(y); Q=imag(y)/g;
    y=complex(I-Q*sin(ph),Q*cos(ph));
end
if p.pa.enabled
    r=abs(y); sat=10^(p.pa.inputBackoffDb/20)*d.referenceInputAmplitude;
    comp=(1+(r/sat).^(2*p.pa.smoothness)).^(-1/(2*p.pa.smoothness));
    phase=zeros(size(r));
    if p.pa.ampmEnabled
        q=(r/d.referenceInputAmplitude).^2;
        phase=(p.pa.ampmAtReferenceDeg*pi/180)*2*q./(1+q);
    end
    y=y.*comp.*exp(1i*phase);
end
[y,state.response]=bds_tx_fir(y,d.responseFir,state.response);
end
