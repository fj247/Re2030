classdef BdsFileWriter < handle
    %BDSFILEWRITER Route one continuous stream to full and segmented files.
    % Does not filter, normalize, pad, or reinitialize waveform state.
    properties (SetAccess=private)
        Records
        Written = 0
        FullPath = ''
    end
    properties (Access=private)
        Directory
        Stem
        SegmentSamples
        ExpectedSamples
        Fs
        Week
        Sow
        FullFid = -1
        SegmentFid = -1
        FullPartial = ''
        SegmentPartial = ''
        SegmentPath = ''
        SegmentCount = 0
        SegmentIndex = 0
        SegmentStart = 0
        Finished = false
        DetectorDirectory = ''
    end
    methods
        function obj=BdsFileWriter(directory,stem,cfg,totalSamples)
            obj.Directory=directory; obj.Stem=stem;
            if isfield(cfg,'captureControl')
                obj.DetectorDirectory=cfg.captureControl.detectorDirectory;
                if ~exist(obj.DetectorDirectory,'dir'), mkdir(obj.DetectorDirectory); end
            end
            obj.SegmentSamples=round(cfg.segmentSeconds*cfg.sampleRateHz);
            obj.ExpectedSamples=totalSamples; obj.Fs=cfg.sampleRateHz;
            obj.Week=cfg.bdtWeek; obj.Sow=cfg.startSowSeconds;
            obj.Records=struct('index',{},'fileName',{},'startSample',{}, ...
                'sampleCount',{},'startSeconds',{},'durationSeconds',{}, ...
                'bdtWeek',{},'startSowSeconds',{},'bytes',{});
            if cfg.keepFullFile
                obj.FullPath=fullfile(directory,[stem '.iq.f32']);
                obj.FullPartial=[obj.FullPath '.partial'];
                obj.FullFid=fopen(obj.FullPartial,'w','ieee-le');
                assert(obj.FullFid>=0,'Cannot open full waveform file.');
            end
        end
        function write(obj,iq)
            assert(~obj.Finished,'Writer already finished.');
            assert(obj.Written+numel(iq)<=obj.ExpectedSamples,'Too many samples.');
            % Convert ONCE so both destinations receive identical float32 bytes.
            payload=[single(real(iq(:).'));single(imag(iq(:).'))];
            if obj.FullFid>=0
                count=fwrite(obj.FullFid,payload,'single');
                assert(count==numel(payload),'Incomplete full-file write.');
            end
            offset=0;
            while offset<numel(iq)
                if obj.SegmentFid<0, obj.openSegment(); end
                take=min(numel(iq)-offset,obj.SegmentSamples-obj.SegmentCount);
                count=fwrite(obj.SegmentFid,payload(:,offset+(1:take)),'single');
                assert(count==2*take,'Incomplete segment write.');
                obj.SegmentCount=obj.SegmentCount+take;
                obj.Written=obj.Written+take; offset=offset+take;
                if obj.SegmentCount==obj.SegmentSamples, obj.closeSegment(); end
            end
        end
        function finish(obj,actualSamples)
            if nargin>1
                assert(actualSamples==obj.Written && actualSamples<=obj.ExpectedSamples,'Invalid actual sample count.');
                obj.ExpectedSamples=actualSamples;
            end
            assert(obj.Written==obj.ExpectedSamples,'Written sample count mismatch.');
            if obj.SegmentFid>=0, obj.closeSegment(); end
            if obj.FullFid>=0
                fclose(obj.FullFid); obj.FullFid=-1;
                [ok,msg]=movefile(obj.FullPartial,obj.FullPath); assert(ok,msg);
            end
            obj.Finished=true;
        end
        function abort(obj)
            % Close only owned live handles. Incomplete files retain .partial.
            if obj.FullFid>=0, fclose(obj.FullFid); obj.FullFid=-1; end
            if obj.SegmentFid>=0, fclose(obj.SegmentFid); obj.SegmentFid=-1; end
        end
        function delete(obj), obj.abort(); end
    end
    methods (Access=private)
        function openSegment(obj)
            obj.SegmentIndex=obj.SegmentIndex+1;
            obj.SegmentCount=0; obj.SegmentStart=obj.Written;
            name=sprintf('segment_%06d.iq.f32',obj.SegmentIndex);
            obj.SegmentPath=fullfile(obj.Directory,name);
            if ~isempty(obj.DetectorDirectory), obj.SegmentPath=fullfile(obj.DetectorDirectory,name); end
            obj.SegmentPartial=[obj.SegmentPath '.partial'];
            obj.SegmentFid=fopen(obj.SegmentPartial,'w','ieee-le');
            assert(obj.SegmentFid>=0,'Cannot open segment.');
        end
        function closeSegment(obj)
            fclose(obj.SegmentFid); obj.SegmentFid=-1;
            [ok,msg]=movefile(obj.SegmentPartial,obj.SegmentPath); assert(ok,msg);
            sow=obj.Sow+obj.SegmentStart/obj.Fs;
            [~,name,ext]=fileparts(obj.SegmentPath);
            r.index=obj.SegmentIndex; r.fileName=[name ext];
            r.startSample=obj.SegmentStart; r.sampleCount=obj.SegmentCount;
            r.startSeconds=obj.SegmentStart/obj.Fs; r.durationSeconds=obj.SegmentCount/obj.Fs;
            r.bdtWeek=obj.Week+floor(sow/604800); r.startSowSeconds=mod(sow,604800);
            r.bytes=8*obj.SegmentCount;
            obj.Records(end+1)=r;
        end
    end
end
