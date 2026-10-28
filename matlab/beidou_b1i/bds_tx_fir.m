function [y,state]=bds_tx_fir(x,h,state)
%BDS_TX_FIR Causal FIR via FFT overlap-save; state is previous input samples.
L=numel(h);
if nargin<3 || isempty(state), state=zeros(1,L-1); end
if L==1, y=h*x; state=[]; return; end
z=[state reshape(x,1,[])]; nf=2^nextpow2(numel(z)+L-1);
v=ifft(fft(z,nf).*fft(h,nf)); y=v(L:L+numel(x)-1);
if isreal(x)&&isreal(state)&&isreal(h), y=real(y); end
state=z(end-L+2:end);
end
