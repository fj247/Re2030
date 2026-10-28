function [stop,reason]=bds_capture_stop(cfg,written)
%BDS_CAPTURE_STOP Use the successful-write ledger, not open-file directory sizes.
% Windows may report stale sizes while .partial handles remain open. Each
% complex float32 sample consumes exactly eight bytes in the detector stream.
c=cfg.captureControl;
stop=exist(c.stopFile,'file')~=0;
reason='';
if stop
    reason='requested';
elseif 8*written>=c.maxBytes
    stop=true;reason='storage_limit';
    bds_capture_json(c.limitFile,struct('reason',reason, ...
        'sampleCount',written,'bytes',8*written));
end
end
