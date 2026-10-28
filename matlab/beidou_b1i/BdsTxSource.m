classdef BdsTxSource < handle
    %BDSTXSOURCE TX on uniform transmit-code clock; resampled at retarded times.
    % No propagated carrier, distance loss or receiver noise enters this class.
    properties (SetAccess=private)
        Design
    end
    properties (Access=private)
        P; Epoch; Code; Nav; HighNext; HighFs; MidFs; M; ChainState=[];
        AAState=[]; Buffer=[]; First; PN=[]; Jitter=[]; LastQuery=-Inf;
    end
    methods
        function o=BdsTxSource(cfg,nav,code,firstQuery)
            o.P=cfg.txHardware; o.Epoch=floor(cfg.startSowSeconds);
            o.Nav=nav; o.Code=code; o.Design=bds_tx_design(o.P,cfg.sampleRateHz,cfg.lowpassCutoffHz);
            o.HighFs=o.Design.internalSampleRateHz; o.MidFs=o.Design.intermediateSampleRateHz;
            o.M=o.Design.decimation;
            % Fixed power reference: eight PRN milliseconds, discard first four.
            count=round(0.008*o.HighFs); t=(0:count-1)/o.HighFs;
            cal=bds_tx_code(t,o.Epoch,o.HighFs,o.Code,o.Nav,o.P,[]);
            cal=bds_tx_chain(cal,o.P,o.Design,[]);
            power=mean(abs(cal(round(count/2)+1:end)).^2);
            assert(isfinite(power)&&power>0,'Invalid TX calibration power.');
            o.Design.amplitudeCalibration=1/sqrt(power);
            o.Design.calibrationPowerBeforeScalingW=power;
            advance=o.Design.totalReferenceDelaySeconds;
            warm=0.002; half=o.P.interpolationHalfLength;
            start=firstQuery+advance-warm-half/o.MidFs;
            block=o.P.internalBlockSamples;
            o.HighNext=floor(start*o.HighFs/block)*block;
            % Align the first generation block to the intermediate sampling grid.
            o.HighNext=o.HighNext-mod(o.HighNext,o.M);
            o.First=o.HighNext/o.M;
            start=o.HighNext/o.HighFs;
            if o.P.phaseNoise.enabled
                r=o.Design.phaseNoiseFit;
                o.PN=BdsTxGaussian(r.processSampleRateHz,r.arPole,r.componentVarianceRad2,o.P.seed,start);
            end
            if o.P.timingJitter.enabled
                j=o.P.timingJitter; fj=max(10000,32/j.correlationSeconds);
                o.Jitter=BdsTxGaussian(fj,exp(-1/(fj*j.correlationSeconds)), ...
                    j.rmsSeconds^2,o.P.seed+100,start);
            end
            o.Design.interpolation='Normalized 48-neighbor Blackman-windowed sinc by default, at 2x output rate; AA precedes interpolation.';
            o.Design.source='Uniform transmit-code clock, sample-cell averaged rectangular DAC; received query times include code propagation/clock/TGD.';
            o.Design.startupPolicy='2ms deterministic filter prehistory; random AR states initialized stationary; no zeros written to output.';
            o.Design.effectiveConfiguration=o.P;
        end
        function y=sample(o,t)
            t=reshape(t,1,[]); assert(all(diff(t)>0)&&t(1)>=o.LastQuery,'TX queries must increase.');
            o.LastQuery=t(end);
            q=(t+o.Design.totalReferenceDelaySeconds)*o.MidFs;
            K=o.P.interpolationHalfLength;
            lo=floor(min(q))-K+1; hi=floor(max(q))+K;
            assert(lo>=o.First,'Insufficient TX interpolation prehistory.');
            while o.First+numel(o.Buffer)-1<hi, o.generateBlock(); end
            y=complex(zeros(size(t))); norm=zeros(size(t)); base=floor(q);
            for j=-K+1:K
                n=base+j; u=q-n; w=ones(size(u)); k=u~=0;
                w(k)=sin(pi*u(k))./(pi*u(k));
                w=w.*(0.42+0.5*cos(pi*u/K)+0.08*cos(2*pi*u/K)); w(abs(u)>=K)=0;
                y=y+w.*o.Buffer(n-o.First+1); norm=norm+w;
            end
            y=y./norm;
            drop=max(0,lo-o.First-2); o.Buffer(1:drop)=[]; o.First=o.First+drop;
        end
    end
    methods (Access=private)
        function generateBlock(o)
            count=o.P.internalBlockSamples; n=o.HighNext+(0:count-1); t=n/o.HighFs;
            jitter=[]; if ~isempty(o.Jitter), jitter=o.Jitter.sample(t); end
            x=bds_tx_code(t,o.Epoch,o.HighFs,o.Code,o.Nav,o.P,jitter);
            [x,o.ChainState]=bds_tx_chain(x,o.P,o.Design,o.ChainState);
            x=x*o.Design.amplitudeCalibration;
            if ~isempty(o.PN), x=x.*exp(1i*o.PN.sample(t)); end
            if o.P.spurs.enabled
                for j=1:numel(o.P.spurs.offsetHz)
                    x=x+10^(o.P.spurs.levelDbc(j)/20)*exp(1i*(2*pi*o.P.spurs.offsetHz(j)*t+o.P.spurs.phaseRad(j)));
                end
            end
            if o.P.extraCarrierOffsetHz~=0, x=x.*exp(1i*2*pi*o.P.extraCarrierOffsetHz*t); end
            x=x*10^(-o.P.extraLossDb/20);
            [x,o.AAState]=bds_tx_fir(x,o.Design.antialiasFir,o.AAState);
            keep=mod(n,o.M)==0; o.Buffer=[o.Buffer x(keep)]; o.HighNext=o.HighNext+count;
        end
    end
end
