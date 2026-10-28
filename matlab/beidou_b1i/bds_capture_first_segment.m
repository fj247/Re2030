function m=bds_capture_first_segment(source)
%BDS_CAPTURE_FIRST_SEGMENT Bound every downstream read to the first saved segment.
m=bds_metadata(source);
assert(isfield(m,'segments') && ~isempty(m.segments),'No saved segment to analyze.');
s=m.segments(1);
assert(s.startSample==0 && s.sampleCount>0,'Invalid first segment.');
m.segments=s;
m.numberComplexSamples=s.sampleCount;
end
