function bds_tx_save_profile(file,p)
%BDS_TX_SAVE_PROFILE Save a complete validated profile as UTF-8 JSON.
bds_tx_validate(p,8.184e6,2.8e6);
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0,'Cannot open profile output.');
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
b=unicode2native(jsonencode(p,'PrettyPrint',true),'UTF-8'); assert(fwrite(fid,b,'uint8')==numel(b));
end
