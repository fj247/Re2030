function code = bds_prn(prn)
%BDS_PRN B1I Gold code, ICD 3.0 section 4.3, Table 4-1.
% Stage numbering is left-to-right 1..11; output G1 stage 11.
% Return 0/1 bits. BPSK mapping is 0=>+1, 1=>-1 (constant pi ambiguity).
validateattributes(prn, {'numeric'}, {'scalar','integer','>=',6,'<=',37});
taps = [1 3;1 4;1 5;1 6;1 8;1 9;1 10;1 11;2 7;3 4;3 5;3 6; ...
    3 8;3 9;3 10;3 11;4 5;4 6;4 8;4 9;4 10;4 11;5 6;5 8;5 9; ...
    5 10;5 11;6 8;6 9;6 10;6 11;8 9;8 10;8 11;9 10;9 11;10 11];
g1 = [0 1 0 1 0 1 0 1 0 1 0]; g2 = g1;
code = false(2046,1);
for k=1:2046
    code(k) = mod(g1(11)+sum(g2(taps(prn,:))),2);
    f1 = mod(sum(g1([1 7 8 9 10 11])),2);
    f2 = mod(sum(g2([1 2 3 4 5 8 9 11])),2);
    g1 = [f1 g1(1:10)]; g2 = [f2 g2(1:10)];
end
end
