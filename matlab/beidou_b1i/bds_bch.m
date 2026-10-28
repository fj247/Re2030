function out = bds_bch(in, mode)
%BDS_BCH Systematic BCH(15,11,1), g(x)=x^4+x+1; MSB first.
% mode='encode': 11 information bits -> 15 bits.
% mode='syndrome': remainder of 15-bit received polynomial -> 4 bits.
b = logical(in(:).');
if strcmp(mode,'encode')
    assert(numel(b)==11, 'BCH input must have 11 bits.');
    d = [b false(1,4)];
elseif strcmp(mode,'syndrome')
    assert(numel(b)==15, 'BCH codeword must have 15 bits.');
    d = b;
else
    error('Unknown BCH mode.');
end
p = logical([1 0 0 1 1]);
for k=1:11
    if d(k), d(k:k+4) = xor(d(k:k+4),p); end
end
if strcmp(mode,'encode'), out = [b d(12:15)]; else, out = d(12:15); end
end
