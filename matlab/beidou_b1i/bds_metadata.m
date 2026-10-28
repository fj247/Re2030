function meta=bds_metadata(source)
%BDS_METADATA Load run JSON once, or reuse an already loaded structure.
if isstruct(source)
    meta=source;
    assert(isfield(meta,'sourceDirectory'),'Loaded metadata needs sourceDirectory.');
else
    source=char(source);
    meta=jsondecode(fileread(source));
    [ok,info]=fileattrib(source); assert(ok,'Cannot resolve metadata path.');
    meta.sourceDirectory=fileparts(info.Name);
end
end
