"""Independent TX numerical reference; does NOT execute MATLAB.
Requires NumPy/SciPy. No deliverable IQ recording is generated.
"""
import json
from pathlib import Path
import numpy as np
from scipy.signal import lfilter, fftconvolve, freqz, welch
FS=8.184e6

def prn():
    a=b=int('01010101010',2); out=[]
    for _ in range(2046):
        out.append((a^(b>>8)^(b>>5))&1)
        fa=sum((a>>j)&1 for j in [0,1,2,3,4,10])%2
        fb=sum((b>>j)&1 for j in [0,2,3,6,7,8,9,10])%2
        a=(a>>1)|(fa<<10); b=(b>>1)|(fb<<10)
    return 1-2*np.array(out)
CODE=prn(); NH=1-2*np.array(list(map(int,'00000100110101001110')))
def value(k):
    # Alternating 50bps fixture NAV, independent of real ephemeris fields.
    return CODE[k%2046]*NH[(k//2046)%20]*(1-2*((k//40920)%2))
def dac(t,fhi,delta=0):
    z=t*2.046e6; k=np.floor(z).astype('int64'); b=z+2.046e6/(2*fhi)
    p,c,n=value(k-1),value(k),value(k+1)
    e0=k+delta*2.046e6*(c<p); e1=k+1+delta*2.046e6*(n<c)
    return p+(c-p)*np.clip((b-e0)*fhi/2.046e6,0,1)+(n-c)*np.clip((b-e1)*fhi/2.046e6,0,1)
def design(factor,profile):
    fhi=FS*factor; K=np.tan(np.pi*8e6/fhi); den=1+np.sqrt(2)*K+K*K
    bb=K*K/den*np.array([1,2,1]); aa=np.array([1,2*(K*K-1)/den,(1-np.sqrt(2)*K+K*K)/den])
    # Scale FIR length in seconds for a fair higher-sampling comparison.
    L=2*round(128*factor/8)+1
    f=np.fft.fftfreq(L,1/fhi); B=2.046e6; taper=np.exp(-(f/(2*B))**8)
    pp,gd=(.05,1e-9) if profile=='A' else (.04,.8e-9)
    H=10**((pp/2*np.cos(np.pi*f/B)*taper)/20)*np.exp(-1j*gd*B*np.sin(np.pi*f/B)*taper)
    h=np.fft.fftshift(np.fft.ifft(H)).real*np.blackman(L); h/=h.sum()
    length=2*int(np.ceil(6*fhi/(FS/2-2.8e6)/2))+1
    n=np.arange(length)-(length-1)/2; cutoff=(2.8e6+FS/2)/2
    ha=2*cutoff/fhi*np.sinc(2*cutoff/fhi*n)*np.blackman(length); ha/=ha.sum()
    delay=np.sqrt(2)/(2*K)/fhi+np.dot(np.arange(L),h)/fhi+(length-1)/(2*fhi)
    return bb,aa,h,ha,delay

def chain(x,bb,aa,h,profile):
    x=lfilter(bb,aa,x); ibo,deg=(6,1) if profile=='A' else (7,.8)
    r=abs(x); sat=10**(ibo/20)
    x=x/(1+(r/sat)**4)**.25*np.exp(1j*np.deg2rad(deg)*2*r*r/(1+r*r))
    return fftconvolve(x,h)[:len(x)]
def render(factor,profile,query):
    fhi=FS*factor; bb,aa,h,ha,delay=design(factor,profile)
    tc=np.arange(round(.008*fhi))/fhi; cal=chain(dac(tc,fhi),bb,aa,h,profile)
    gain=1/np.sqrt(np.mean(abs(cal[len(cal)//2:])**2))
    first=int(np.floor((query[0]+delay-.002)*fhi/(factor/2))*(factor/2))
    last=int(np.ceil((query[-1]+delay+.0001)*fhi)); n=np.arange(first,last)
    x=chain(dac(n/fhi,fhi),bb,aa,h,profile)*gain
    x=fftconvolve(x,ha)[:len(x)]; sel=n%(factor//2)==0; x=x[sel]; firstmid=n[sel][0]//(factor//2)
    q=(query+delay)*FS*2; base=np.floor(q).astype('int64'); y=np.zeros(len(q),complex); norm=np.zeros(len(q)); K=24
    for j in range(-K+1,K+1):
        u=q-(base+j); w=np.sinc(u)*(.42+.5*np.cos(np.pi*u/K)+.08*np.cos(2*np.pi*u/K));w[abs(u)>=K]=0
        y+=w*x[base+j-firstmid];norm+=w
    return y/norm

def phasefit(margin=10):
    fp=1048576.; corners=np.logspace(0,5.5,12); a=np.exp(-2*np.pi*corners/fp)
    f=np.logspace(1,5,101); levels=np.interp(np.log10(f),np.arange(1,6),np.array([-60,-75,-80,-85,-95])-margin)
    target=2*10**(levels/10)
    S=(2/fp)*(1-a*a)/((1-a)**2+2*a*(1-np.cos(2*np.pi*f[:,None]/fp)))
    S*=np.sinc(f[:,None]/fp)**4
    A=S/target[:,None];scale=np.linalg.norm(A,axis=0);B=A/scale
    coef=np.zeros(len(a)); residual=np.ones(len(f))
    for _ in range(1000):
        for j in range(len(a)):
            old=coef[j];coef[j]=max(0,old+B[:,j]@residual); residual-=B[:,j]*(coef[j]-old)
    variance=coef/scale; error=np.max(abs(10*np.log10((S@variance)/target)))
    return error,float(np.sqrt(variance.sum())),a,variance

def verify():
    r={'scope':'Independent numerical checks, MATLAB NOT executed','matlab_executed':False}
    err,rms,a,v=phasefit(); assert err<3,(err,rms)
    r['phase_noise_max_fit_error_db']=float(err);r['phase_noise_rms_rad']=rms
    bb,aa,h,ha,delay=design(8,'A'); f=np.linspace(0,12e6,20001)
    _,A=freqz(ha,worN=2*np.pi*f/(FS*8))
    stop=float(20*np.log10(max(abs(A[f>=FS/2])))); assert stop<-50,stop
    r['aa_stop_max_db']=stop;r['tx_and_aa_reference_delay_seconds']=delay
    _,R=freqz(h,worN=2*np.pi*f/(FS*8)); band=f<=2.046e6
    gd=-np.gradient(np.unwrap(np.angle(R)),2*np.pi*f)
    r['extra_amplitude_pp_db']=float(np.ptp(20*np.log10(abs(R[band]))))
    r['extra_group_delay_pp_ns']=float(np.ptp(gd[band])*1e9)
    query=.000123456+np.arange(32736)/FS
    result={}
    for profile in ['A','B']:
        waves=[render(k,profile,query) for k in [8,16,32]]
        errors=[float(np.linalg.norm(w-waves[-1])/np.linalg.norm(waves[-1])) for w in waves[:2]]
        assert max(errors)<.01,errors
        result[profile]={'8x_vs_32x_relative_rms':errors[0],'16x_vs_32x_relative_rms':errors[1]}
    r['convergence']=result
    t=np.arange(20000)/(FS*8); diff=np.linalg.norm(dac(t,FS*8)-dac(t,FS*8,1e-9));assert diff>0
    r['fractional_1ns_edge_change_norm']=float(diff)
    # End-to-end hardware fixture + independent PN + weak spur, propagation phase,
    # receiver noise/FIR, then blind PRN acquisition (no injected delay supplied).
    from check_acquisition_reference import acq
    D=32; N=round(.02*FS); t=np.arange(-D,N+D)/FS
    query=(1+1730/1561098000)*t-.00042375
    n=np.arange(-D,D+1); hr=2*2.8e6/FS*np.sinc(2*2.8e6/FS*n)*np.hamming(65);hr/=hr.sum()
    rng=np.random.default_rng(428); noise=np.sqrt(FS/(2*10**4.5))*(rng.normal(size=len(t))+1j*rng.normal(size=len(t)))
    clean_noise=lfilter(hr,[1],noise)[64:]; fixtures={}
    for prof in ['A','B']:
        signal=render(8,prof,query)
        er,rr,ap,vp=phasefit(10 if prof=='A' else 12)
        pn=np.zeros(len(t)); rp=np.random.default_rng(919)
        # Generate the same AR PSD at RF output sample rate for this independent fixture.
        for pole,var in zip(ap,vp):
            corner=-np.log(pole)*1048576/(2*np.pi); ar=np.exp(-2*np.pi*corner/FS)
            part,_=lfilter([np.sqrt(var*(1-ar*ar))],[1,-ar],rp.normal(size=len(t)),zi=[ar*np.sqrt(var)*rp.normal()]);pn+=part
        level=-70 if prof=='A' else -74
        signal=(signal*np.exp(1j*pn)+10**(level/20)*np.exp(1j*(2*np.pi*8e5*query+.7)))*np.exp(2j*np.pi*1730*t)
        received=lfilter(hr,[1],signal+noise)[64:]
        target=acq(received,FS,12); wrong=acq(received,FS,13); null=acq(clean_noise,FS,12)
        assert target['detected'] and not wrong['detected'] and not null['detected']
        assert abs(target['fd']-1730)<=500
        fixtures[prof]={'target':target,'wrong_prn':wrong,'noise':null}
    r['hardware_acquisition_fixtures']=fixtures
    # Independent overlap-save check, including blocks shorter than FIR memory.
    rng=np.random.default_rng(91); x=rng.normal(size=12345)+1j*rng.normal(size=12345)
    expected=lfilter(ha,[1],x); state=np.zeros(len(ha)-1,complex); actual=[]
    for start in range(0,len(x),137):
        z=np.r_[state,x[start:start+137]]; N=2**int(np.ceil(np.log2(len(z)+len(ha)-1)))
        y=np.fft.ifft(np.fft.fft(z,N)*np.fft.fft(ha,N));actual.extend(y[len(ha)-1:len(z)]);state=z[-len(ha)+1:]
    error=np.max(abs(expected-np.array(actual)));assert error<1e-12;r['streaming_fir_max_error']=float(error)
    r['status']='PASS';print(json.dumps(r,indent=2,default=lambda x:x.item() if isinstance(x,np.generic) else str(x)));return r
if __name__=='__main__':
    r=verify();Path(__file__).with_name('tx_reference_results.json').write_text(json.dumps(r,indent=2,default=lambda x:x.item() if isinstance(x,np.generic) else str(x))+'\n')
