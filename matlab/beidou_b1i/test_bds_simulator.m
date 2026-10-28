function test_bds_simulator(includePlots)
if nargin<1, includePlots=true; end
%TEST_BDS_SIMULATOR Run in MATLAB R2024a; temporary small files.
root=tempname; mkdir(root); cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
c=bds_default_config(); c.txHardware.enabled=false; % Preserve original core reference tests.
% Exhaustive codebook: zero syndromes, systematic bits, distance >= 3.
book=false(2048,15);
for x=0:2047
    d=logical(mod(floor(x./2.^(10:-1:0)),2));
    b=bds_bch(d,'encode'); book(x+1,:)=b;
    assert(isequal(b(1:11),d)); assert(~any(bds_bch(b,'syndrome')));
end
assert(min(sum(book(2:end,:),2))==3);
for pos=1:15
    b=false(1,15); b(pos)=true; assert(any(bds_bch(b,'syndrome')));
end
% Known-vector PRN check; bit convention 0=+1, 1=-1.
p=bds_prn(12);
assert(isequal(char(double(p(1:64).')+'0'), ...
    '1010010010000111010000110010101101011001100111001011100001110010'));
assert(numel(p)==2046 && sum(p)==1024);
for id=6:37, assert(numel(bds_prn(id))==2046); end
% Every page of two superframes: decode wire bits without error correction.
s=bds_scene(c); nv=bds_nav(c,s,0,240);
assert(numel(nv.bits)==72000);
for k=1:240
    w=reshape(nv.bits((k-1)*300+(1:300)),30,10);
    assert(~any(bds_bch(w(16:30,1),'syndrome')));
    v=[w(1:15,1);w(16:26,1)];
    for j=2:10
        a=w(1:2:30,j); b=w(2:2:30,j);
        assert(~any(bds_bch(a,'syndrome')) && ~any(bds_bch(b,'syndrome')));
        v=[v;a(1:11);b(1:11)]; %#ok<AGROW>
    end
    assert(isequal(v,nv.information(:,k)));
    assert(val(v(1:11))==bin2dec('11100010010'));
    assert(val(v(16:18))==nv.frameId(k));
    assert(val(v(19:38))==mod(6*(k-1),604800));
    if nv.frameId(k)>=4, assert(val(v(40:46))==nv.page(k)); end
    if nv.frameId(k)==1
        assert(val(v(49:61))==c.bdtWeek);
        assert(val(v(62:78))*8==s.ephemeris.toc);
    elseif nv.frameId(k)==2
        assert(abs(val(v(191:222))*2^-19-s.ephemeris.sqrtA)<1e-9);
    end
end
% Navigation across week boundary.
nw=bds_nav(c,s,604794,3);
assert(isequal(nw.frameId.',[5 1 2]));
assert(val(nw.information(49:61,2))==c.bdtWeek+1);
% Physical scene: normal visibility and group/phase ionosphere sign.
g=bds_geometry(c,s,(0:0.02:1).');
assert(all(g.elevationDeg>5 & g.elevationDeg<=90));
assert(all(g.rangeM>2e7 & g.rangeM<4e7));
assert(all(abs(g.dopplerHz)<10000));
assert(all(g.ionosphereM>0 & g.troposphereM>0));
% End-to-end short noisy recording and block-size invariance.
c.durationSeconds=0.065; c.outputDirectory=root; c.outputName='a';
c.segmentSeconds=0.02; c.autoOverview=false;
c.blockSamples=32736; a=bds_generate(c);
c.outputName='b'; c.blockSamples=12345; c.segmentSeconds=0.017;
c.keepFullFile=false; b=bds_generate(c);
[xa,ma]=bds_read_iq(a.metadataFile,0,c.durationSeconds);
[xb,~]=bds_read_iq(b.metadataFile,0,c.durationSeconds);
assert(isequal(xa,xb),'Block size must not change recorded samples.');
assert(numel(xa)==round(c.durationSeconds*c.sampleRateHz));
info=dir(a.waveformFile); assert(info.bytes==numel(xa)*8);
assert(all(isfinite(xa)) && ~isreal(xa));
expected=ma.noiseDensityWPerHz*ma.equivalentTwoSidedNoiseBandwidthHz;
assert(abs(ma.measuredNoisePowerW/expected-1)<0.05);
assert(abs(ma.postFilterCn0DbHz-c.cn0DbHz)<2);
% Global reads and per-segment reads preserve exact original samples.
[xslice,~]=bds_read_iq(a.metadataFile,0.02,0.01);
n0=round(0.02*c.sampleRateHz); assert(isequal(xslice,xa(n0+(1:numel(xslice)))));
[seg,~]=bds_read_iq(a.metadataFile,0,0.01,2);
assert(isequal(seg,xa(n0+(1:numel(seg)))));
assert(numel(ma.segments)==4 && ma.segments(end).sampleCount==round(0.005*c.sampleRateHz));
assert(ma.verification.byteIdentical && isempty(b.waveformFile));
assert(~exist(fullfile(a.runDirectory,'INCOMPLETE.txt'),'file'));
% Same outputName starts a new run, never overwriting a previous run.
c.outputName='a'; c.keepFullFile=true;
again=bds_generate(c); assert(~strcmp(again.runDirectory,a.runDirectory));
assert(exist(a.waveformFile,'file')==2);
test_bds_storage(includePlots);
test_bds_acquisition(includePlots);
test_bds_tx_hardware(includePlots,false);
fprintf('PASS: signal core, continuous segmentation, exact full-file equality and analysis.\n');
end
function x=val(b), x=sum(double(b(:).').*2.^(numel(b)-1:-1:0)); end
