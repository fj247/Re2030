"""Independent Python PCPS numerical reference; does NOT execute MATLAB.
Requires NumPy/SciPy. Tests known parameters only in fixtures, never as search inputs.
"""
from pathlib import Path
import json
import numpy as np
from scipy.signal import lfilter
from scipy.special import gammaincinv
from scipy.fft import fft,ifft

def code(prn):
 pairs=[(1,3),(1,4),(1,5),(1,6),(1,8),(1,9),(1,10),(1,11),(2,7),(3,4),(3,5),(3,6),(3,8),(3,9),(3,10),(3,11),(4,5),(4,6),(4,8),(4,9),(4,10),(4,11),(5,6),(5,8),(5,9),(5,10),(5,11),(6,8),(6,9),(6,10),(6,11),(8,9),(8,10),(8,11),(9,10),(9,11),(10,11)]
 g1=g2=int('01010101010',2);out=[]
 for k in range(2046):
  out.append((g1^ (g2>>(11-pairs[prn-1][0]))^(g2>>(11-pairs[prn-1][1])))&1)
  f1=sum((g1>>j)&1 for j in [0,1,2,3,4,10])%2;f2=sum((g2>>j)&1 for j in [0,2,3,6,7,8,9,10])%2
  g1=(g1>>1)|(f1<<10);g2=(g2>>1)|(f2<<10)
 return 1-2*np.array(out)
def acq(x,fs,prn,ms=20,freqs=np.arange(-10000,10001,500)):
 n=round(fs/1000);h=n//2
 c=code(prn)[np.floor(np.arange(n)*2046000/fs).astype(int)]
 cf=np.conj(fft(c)); x=x[:ms*n].reshape(ms,n)
 out=[]
 for f in freqs:
  y=x*np.exp(-2j*np.pi*f*np.arange(n)/fs)
  z1=y.copy();z1[:,h:]=0
  z2=y.copy();z2[:,:h]=0
  a=ifft(fft(z1,axis=1)*cf,axis=1);b=ifft(fft(z2,axis=1)*cf,axis=1)
  out.append(np.sum(abs(a)**2+abs(b)**2,axis=0))
 out=np.array(out);K=2*ms;bg=np.median(out)/(gammaincinv(K,.5)/K); out=out/bg
 fi,ci=np.unravel_index(np.argmax(out),out.shape)
 other=out.copy();guard=int(np.ceil(2*fs/2046000));other[:,(ci+np.arange(-guard,guard+1))%n]=0
 threshold=gammaincinv(K,1-1e-3/out.size)/K
 peak=out[fi,ci];ratio=peak/max(other.max(),1e-100)
 return dict(prn=prn,peak=float(peak),ratio=float(ratio),threshold=float(threshold),delay=ci,fd=int(freqs[fi]),detected=bool(peak>=threshold and ratio>=1.4))


def fixture(fs=8184000, ms=20, prn=12, delay=.00042375, fd=1730, seed=428):
    n=round(fs*ms/1000); d=32
    ix=np.arange(-d,d+1)
    h=2*2.8e6/fs*np.sinc(2*2.8e6/fs*ix)*np.hamming(65);h/=h.sum()
    t=np.arange(-d,n+d)/fs
    sv=(1+fd/1561098000)*t-delay
    nh=1-2*np.array(list(map(int,'00000100110101001110')))
    s=code(prn)[np.floor(sv*2046000).astype(int)%2046]
    s=s*nh[np.floor(sv*1000).astype(int)%20]
    s=s*(1-2*(np.floor(sv*50).astype(int)%2))*np.exp(2j*np.pi*fd*t)
    rng=np.random.default_rng(seed)
    w=np.sqrt(fs/(2*10**4.5))*(rng.normal(size=len(t))+1j*rng.normal(size=len(t)))
    return lfilter(h,[1],s+w)[64:],lfilter(h,[1],w)[64:]


def serial(x):
    return {k:(v.item() if isinstance(v,np.generic) else v) for k,v in x.items()}


if __name__=='__main__':
    fs=8184000
    cases=[dict(prn=12,delay=.00042375,fd=1730,seed=428),
           dict(prn=12,delay=.00024975,fd=-3400,seed=512),
           dict(prn=17,delay=.00074975,fd=2650,seed=987)]
    results=[]
    for c in cases:
        x,w=fixture(**c)
        a=acq(x,fs,c['prn']);wrong=acq(x,fs,c['prn']+1);null=acq(w,fs,c['prn'])
        assert a['detected'] and not wrong['detected'] and not null['detected']
        assert abs(a['delay']-round(c['delay']*fs))<=2
        assert abs(a['fd']-c['fd'])<=500
        results.append(dict(fixture=c,target=serial(a),other_prn=serial(wrong),noise=serial(null)))
    scaled=acq(x*1e-7,fs,c['prn'])
    assert abs(scaled['peak']-a['peak'])<1e-10
    noise_results=[]
    for seed in range(100,110):
        _,w=fixture(seed=seed)
        r=acq(w,fs,12)
        assert not r['detected']
        noise_results.append(serial(r))
    out={'status':'PASS: independent acquisition reference, not MATLAB execution',
         'matlab_executed':False,'fixtures':results,'independent_noise_trials':10,
         'noise_detections':sum(r['detected'] for r in noise_results),
         'maximum_noise_peak_score':max(r['peak'] for r in noise_results),
         'amplitude_scaling_invariant':True,
         'warning':'Finite diagnostics do not certify actual false alarm probability.'}
    Path(__file__).with_name('acquisition_reference_results.json').write_text(
        json.dumps(out,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(out,indent=2))
