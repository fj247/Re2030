classdef BdsTxGaussian < handle
    %BDSTXGAUSSIAN Stationary AR mixture on its own clock; fixed random blocks.
    properties (Access=private)
        Fs; Pole; Variance; Streams; States; Buffer; First; Next; Chunk=4096;
    end
    methods
        function o=BdsTxGaussian(fs,pole,variance,seed,startTime)
            o.Fs=fs; o.Pole=pole(:).'; o.Variance=variance(:).';
            o.First=floor(startTime*fs)-2; o.Next=o.First; o.Buffer=[];
            for j=1:numel(pole)
                o.Streams{j}=RandStream('mt19937ar','Seed',mod(seed+37*j,2^32-1));
                % Gaussian stationary initial state; filter's zi = a*x_previous.
                o.States(j)=pole(j)*sqrt(variance(j))*randn(o.Streams{j},1);
            end
        end
        function y=sample(o,t)
            t=reshape(t,1,[]); if isempty(t), y=t; return; end
            q=t*o.Fs; lo=floor(min(q)); hi=floor(max(q))+1;
            assert(lo>=o.First,'TX random process called backwards.');
            while o.Next<=hi
                z=zeros(1,o.Chunk);
                for j=1:numel(o.Pole)
                    if o.Variance(j)==0, continue; end
                    a=o.Pole(j); sd=sqrt(o.Variance(j)*(-expm1(2*log(a))));
                    [v,o.States(j)]=filter(sd,[1 -a],randn(o.Streams{j},1,o.Chunk),o.States(j));
                    z=z+v;
                end
                o.Buffer=[o.Buffer z]; o.Next=o.Next+o.Chunk;
            end
            k=floor(q)-o.First+1; frac=q-floor(q);
            y=(1-frac).*o.Buffer(k)+frac.*o.Buffer(k+1);
            drop=max(0,lo-o.First-2); o.Buffer(1:drop)=[]; o.First=o.First+drop;
        end
    end
end
