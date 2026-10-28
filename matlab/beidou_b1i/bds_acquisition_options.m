function o=bds_acquisition_options(overrides)
%BDS_ACQUISITION_OPTIONS Manual signal-presence verification settings.
o.targetPrn=[];                   % Empty: use configured identity, NOT truth timing
o.controlPrn=[];                  % Empty: next supported PRN (single-satellite scene)
o.dwellMilliseconds=20;          % 20 one-ms blocks, each split into two halves
o.dopplerMinHz=-10000; o.dopplerMaxHz=10000; o.dopplerStepHz=500;
o.nominalSearchPfa=1e-3;           % Approximate Gaussian/Gamma reference, NOT certified Pfa
o.minimumPeakRatio=1.4;          % Peak / strongest non-guard code-delay competitor
o.guardChips=2;
o.probeStartSeconds=[];           % Empty: beginning, middle, end of recording
o.noiseTrials=3;                 % Diagnostic controls, NOT a Pfa calibration campaign
o.controlSeed=20261025;
o.plotResults=true; o.showFigure=true; o.saveResults=true;
o.outputDirectory='';            % Empty: new subdirectory beside run metadata
if nargin>=1
    assert(isstruct(overrides) && isscalar(overrides),'Options must be a scalar struct.');
    names=fieldnames(overrides);
    for k=1:numel(names)
        assert(isfield(o,names{k}),'Unknown acquisition option: %s',names{k});
        o.(names{k})=overrides.(names{k});
    end
end
validateattributes(o.dwellMilliseconds,{'numeric'},{'scalar','integer','>=',2,'<=',100});
validateattributes(o.dopplerMinHz,{'numeric'},{'scalar','real','finite'});
validateattributes(o.dopplerMaxHz,{'numeric'},{'scalar','real','finite','>',o.dopplerMinHz});
validateattributes(o.dopplerStepHz,{'numeric'},{'scalar','real','finite','positive'});
assert(o.dopplerStepHz<=o.dopplerMaxHz-o.dopplerMinHz,'Doppler step exceeds search span.');
validateattributes(o.nominalSearchPfa,{'numeric'},{'scalar','real','finite','>',0,'<',0.1});
validateattributes(o.minimumPeakRatio,{'numeric'},{'scalar','real','finite','>',1});
validateattributes(o.guardChips,{'numeric'},{'scalar','real','finite','positive','<',100});
validateattributes(o.noiseTrials,{'numeric'},{'scalar','integer','>=',1,'<=',100});
validateattributes(o.controlSeed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
for prn={o.targetPrn,o.controlPrn}
    if ~isempty(prn{1}), validateattributes(prn{1},{'numeric'},{'scalar','integer','>=',6,'<=',37}); end
end
if ~isempty(o.probeStartSeconds)
    validateattributes(o.probeStartSeconds,{'numeric'},{'vector','real','finite','nonnegative'});
end
for name={'plotResults','showFigure','saveResults'}
    v=o.(name{1}); assert(isscalar(v) && (v==0 || v==1),'Logical option expected.');
end
end
