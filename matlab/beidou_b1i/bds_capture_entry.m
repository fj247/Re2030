function bds_capture_entry(requestFile)
%BDS_CAPTURE_ENTRY Cooperative capture; private model data never enters detector index.
r=jsondecode(fileread(requestFile));
try
    cfg=bds_default_config();
    % Plan only the bounded storage horizon; do not precompute an unrelated hour.
    cfg.durationSeconds=min(60,ceil(r.maxBytes/(8*cfg.sampleRateHz))+1);
    cfg.segmentSeconds=0.05; % Storage boundary only; waveform state stays continuous.
    cfg.keepFullFile=false; cfg.verifyFullFile=false;
    cfg.autoOverview=false; cfg.overviewVisible=false;
    cfg.outputDirectory=fullfile(r.taskDirectory,'private');
    cfg.outputName='attacker_b1i';
    cfg.captureControl=struct('stopFile',fullfile(r.taskDirectory,'STOP'), ...
        'progressFile',fullfile(r.taskDirectory,'progress.json'), ...
        'limitFile',fullfile(r.taskDirectory,'limit.json'), ...
        'detectorDirectory',fullfile(r.taskDirectory,'detector'),'maxBytes',r.maxBytes);
    if exist(cfg.captureControl.stopFile,'file')
        bds_capture_json(fullfile(r.taskDirectory,'generated.json'),struct('empty',true)); return;
    end
    result=bds_generate(cfg);
    if result.numberComplexSamples==0
        bds_capture_json(fullfile(r.taskDirectory,'generated.json'),struct('empty',true)); return;
    end
    bds_capture_json(fullfile(r.taskDirectory,'generated.json'), ...
        struct('empty',false,'metadataFile',result.metadataFile));
catch err
    if strcmp(err.identifier,'BDS:CaptureStoppedEmpty')
        bds_capture_json(fullfile(r.taskDirectory,'generated.json'),struct('empty',true));
    else
        bds_capture_json(fullfile(r.taskDirectory,'generation_error.json'),struct('message',err.message));
        rethrow(err);
    end
end
end
