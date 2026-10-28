function bds_capture_json(path,value)
%BDS_CAPTURE_JSON Atomic small status write for the Python controller.
tmp=[path '.tmp'];
f=fopen(tmp,'w','n','UTF-8'); assert(f>=0,'Cannot write task status.');
c=onCleanup(@()fclose(f));
b=unicode2native(jsonencode(value,'PrettyPrint',true),'UTF-8');
assert(fwrite(f,b,'uint8')==numel(b),'Incomplete task status write.');
clear c;
ok=false;msg='Cannot publish task status.';
for attempt=1:5
    [ok,msg]=movefile(tmp,path,'f');
    if ok, break; end
    pause(0.02); % Windows readers/antivirus may briefly hold the destination.
end
assert(ok,msg);
end
