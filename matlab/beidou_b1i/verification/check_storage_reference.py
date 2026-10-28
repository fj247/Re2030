"""Independent streaming/storage/PSD invariant checks, NOT MATLAB execution."""
from pathlib import Path
import json
import tempfile
import numpy as np


def check_split(n, segment_size, block_size):
    x = np.column_stack((np.arange(n, dtype=np.float32), -np.arange(n, dtype=np.float32)))
    expected = x.astype('<f4').tobytes()
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        records = []
        current = None
        used = 0
        written = 0
        with (root / 'full').open('wb') as full:
            for offset in range(0, n, block_size):
                data = x[offset:offset+block_size].astype('<f4')
                full.write(data.tobytes())
                pos = 0
                while pos < len(data):
                    if current is None:
                        path = root / f'segment_{len(records)+1:06d}'
                        current = path.open('wb')
                        records.append({'path': path, 'start': written, 'count': 0})
                        used = 0
                    take = min(len(data)-pos, segment_size-used)
                    current.write(data[pos:pos+take].tobytes())
                    pos += take
                    used += take
                    written += take
                    records[-1]['count'] += take
                    if used == segment_size:
                        current.close()
                        current = None
        if current is not None:
            current.close()
        assert written == n
        reconstructed = b''.join(r['path'].read_bytes() for r in records)
        assert reconstructed == (root/'full').read_bytes() == expected
        assert sum(r['count'] for r in records) == n
        assert all(r['path'].stat().st_size == 8*r['count'] for r in records)
        assert all(r['count'] == segment_size for r in records[:-1])
        assert records[-1]['count'] == (n-1) % segment_size + 1
        assert all(b['start'] == a['start']+a['count'] for a,b in zip(records,records[1:]))
        # A one-byte corruption must cease to match the concatenated stream.
        bad = bytearray(expected)
        bad[len(bad)//2] ^= 1
        assert reconstructed != bytes(bad)
    return len(records)


def check_analysis():
    fs, n, nfft = 1024, 10003, 256
    t = np.arange(n)
    x = (0.7*np.exp(2j*np.pi*64*t/fs)).astype(np.complex64).astype(np.complex128)
    count = int(np.ceil(n/32))
    power, covered = 0.0, 0
    for offset in range(0,n,count):
        z=x[offset:offset+count]
        power += np.sum(abs(z)**2)
        covered += len(z)
    assert covered == n
    assert abs(power/n-np.mean(abs(x)**2)) < 1e-12
    w=np.hamming(nfft)
    accumulated=np.zeros(nfft)
    energy=0.0
    for offset in range(0,n,nfft):
        z=x[offset:offset+nfft]
        win=w[:len(z)]
        accumulated += abs(np.fft.fft(z*win,nfft))**2
        energy += np.sum(win**2)
    psd=np.fft.fftshift(accumulated)/(fs*energy)
    f=np.fft.fftshift(np.fft.fftfreq(nfft,1/fs))
    assert f[np.argmax(psd)] == 64
    assert abs(np.sum(psd)*(fs/nfft)-0.49) < 1e-5
    return {'samples_covered':covered, 'peak_frequency_Hz':float(f[np.argmax(psd)]),
            'integrated_psd_W':float(np.sum(psd)*(fs/nfft))}


if __name__ == '__main__':
    cases=[(10003,1000,1377),(2000,1000,333),(7,1000,2),(1001,1000,1001),
           (10003,997,31),(19,1,7)]
    counts=[check_split(*case) for case in cases]
    result={'status':'PASS: independent reference invariants, not MATLAB execution',
            'matlab_executed':False,'storage_cases':len(cases),
            'segment_counts':counts,'analysis':check_analysis()}
    print(json.dumps(result,indent=2))
    Path(__file__).with_name('storage_reference_results.json').write_text(
        json.dumps(result,indent=2)+'\n',encoding='utf-8')
