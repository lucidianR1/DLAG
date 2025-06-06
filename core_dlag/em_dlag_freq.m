function [estParams,seq,LL,Xspec,iterTime,D,gams_across,gams_within,nus_across,nus_within,err_status,msg] ...
          = em_dlag_freq(currentParams,seq,varargin)
%
% [estParams,seq,LL,Xspec,iterTime,D,gams_across,gams_within,nus_across,nus_within,err_status,msg] ...
%     = em_dlag_freq(currentParams,seq,...)
%
% Description: Fit DLAG model parameters using an approximate EM algorithm
%              in the frequency domain.
%
% Arguments:
%
%     Required:
%
%     currentParams -- Structure containing DLAG model parameters at which EM
%                      algorithm is initialized. Contains the fields
% 
%                    covType -- string; type of GP covariance (e.g., 'rbf')
%                    gamma_across -- (1 x xDim_across) array; GP timescales
%                                    in ms are given by 'stepSize ./ sqrt(gamma)'                                                    
%                    eps_across   -- (1 x xDim_across) GP noise variances
%                    gamma_within -- (1 x numGroups) cell array; 
%                                    GP timescales for each group
%                    eps_within   -- (1 x numGroups) cell array;
%                                    GP noise variances for each group
%                    if covType == 'sg'
%                        nu_across -- (1 x xDim_across) array; center
%                                     frequencies for spectral Gaussians;
%                                     convert to 1/time via 
%                                     nu_across./binWidth 
%                        nu_within -- (1 x numGroups) cell array; 
%                                     center frequencies for each group
%                    d            -- (yDim x 1) array; observation mean
%                    C            -- (yDim x (numGroups*xDim)) array;
%                                    mapping between low- and high-d spaces
%                    R            -- (yDim x yDim) array; observation noise
%                                    covariance 
%                    DelayMatrix  -- (numGroups x xDim_across) array;
%                                    delays from across-group latents to 
%                                    observed variables. NOTE: Delays are
%                                    reported as (real-valued) number of
%                                    time-steps.
%                    xDim_across  -- int; number of across-group latent 
%                                    variables
%                    xDim_within  -- (1 x numGroups) array; number of
%                                    within-group latents in each group
%                    yDims        -- (1 x numGroups) array; 
%                                    dimensionalities of each observed group
%     seq      -- data structure, whose nth entry (corresponding to
%                 the nth trial) has fields
%                     trialId         -- unique trial identifier
%                     T (1 x 1)       -- number of timesteps
%                     yfft (yDim x T) -- unitary FFT of the neural data
%
%     Optional:
%
%     maxIters  -- int; number of EM iterations to run (default: 1e6)
%     tolLL     -- float; stopping criterion #1 for EM (based on LL) 
%                  (default: 1e-8)
%     tolParam  -- float; stopping criterion #2 for EM (based on delays and
%                  timescales; i.e., if across-group delays and timescales 
%                  stop changing, stop training.) (default: -Inf)
%     freqLL    -- int; data likelihood is computed every freqLL EM iterations.
%                  freqLL = 1 means that data likelihood is computed every
%                  iteration. (default: 10)
%     freqParam -- int; store intermediate values for delays and timescales
%                  and check for convergence every freqParam EM iterations 
%                  (default: 100)
%     verbose   -- logical; specifies whether to display status messages
%                  (default: true)
%     maxDelayFrac -- float in range [0,1]; Constrain estimated delays to
%                  be no more than a certain fraction of the trial length.
%                  (default: 0.5)
%     minVarFrac -- float; Set private variance floor, for entries of
%                  observation noise covariance matrix. (default: 0.01)
%     maxTauFrac -- float in range [0,1]; Constrain estimated timescales to
%                   be no more than a certain fraction of the trial 
%                   length. (default: 1.0)
%     parallelize -- logical; Here, this setting just determines which 
%                    status messages will be printed. (default: false)
%     learnDelays -- logical; If set to false, then delays will remain
%                  fixed at their initial value throughout training. 
%                  (default: true)
%     learnObs  -- logical; If set to false, then observation parameters
%                  will remain fixed at their initial value throughout 
%                  training. (default: true)
%     trackedParams -- structure containing the tracked parameters from a
%                      previous fitting attempt, with the intention of 
%                      starting where that attempt left off. See LL,
%                      iterTime, D, gams_across, gams_within, nus_across,
%                      and nus_within below.
%
% Outputs:
%
%     estParams -- Structure containing DLAG model parameters returned by 
%                  EM algorithm (same format as currentParams)
%     seq       -- data structure with new fields (these fields are added
%                  to existing fields in the seq input argument)
%                  xsm   -- ((numGroups*xDim) x T) array; posterior mean 
%                           at each timepoint
%     Xspec     -- data structure whose jth entry, corresponding
%                  to a group of trials of the same length, has fields
%                      T       -- int; number of time steps for this
%                                 trial group
%                      Sx_post -- (xDim x xDim x T) array; posterior 
%                                 spectrum at each frequency
%                      NOTE: For DLAG, posterior covariance/spectra of X 
%                            are the same for trials of the same length.
%     NOTE: The outputs below track progress throughout the fitting
%           procedure. They can be useful in debugging, if fitting produces
%           unintuitive estimates, convergence seems slow, etc.
%     LL        -- (1 x numIters) array; data log likelihood after each EM
%                  iteration
%     iterTime  -- (1 x numIters) array; computation time for each EM
%                  iteration
%     D         -- (1 x numIters) cell array; the estimated delay matrix
%                  after each EM iteration.
%     gams_across -- (1 x numIters) cell arry; estimated gamma_across after
%                    each EM iteration.
%     gams_within -- (1 x numGroups) cell arry;
%                    gams_within(i) -- (1 x numIters) cell array; estimated
%                                      gamma_within for group i after each 
%                                      EM iteration.
%     nus_across -- (1 x numIters) cell arry; estimated nu_across after
%                    each EM iteration.
%     nus_within -- (1 x numGroups) cell arry;
%                    nu_within(i) -- (1 x numIters) cell array; estimated
%                                      nu_within for group i after each 
%                                      EM iteration.
%     err_status -- int; 1 if data likelihood decreased during fitting. 0
%                   otherwise.
%     msg        -- string; A message indicating why fitting was stopped 
%                   (for both error and non-error cases).
%
% Authors:
%     Evren Gokcen    egokcen@cmu.edu
%
% Revision history:
%     18 Jul 2023 -- Initial full revision.
           
% Optional arguments
maxIters      = 1e6;
tolLL         = 1e-8;
tolParam      = -Inf;
freqLL        = 10;
freqParam     = 100;
verbose       = true;
maxDelayFrac  = 0.5;
minVarFrac    = 0.01;
maxTauFrac    = 1.0;
parallelize   = false;
learnDelays   = true;
learnObs      = true;
trackedParams = {};
extra_opts    = assignopts(who,varargin);

% Initialize other variables
yDims         = currentParams.yDims;
yDim          = sum(yDims);
xDim_across   = currentParams.xDim_across;
xDim_within   = currentParams.xDim_within;
numGroups     = length(yDims);

% Convert variance fraction to actual variance
varFloor = minVarFrac * diag(cov([seq.y]'));
                         
% Make sure groups are valid
assert(yDim == sum(yDims));
assert(length(yDims) == length(xDim_within));

% Make sure initial delays are within specified constraints
% Convert maxDelayFrac to units of "time steps", the same units as in
% DelayMatrix
currentParams.maxDelay = maxDelayFrac*min([seq.T]);
maxDelay = currentParams.maxDelay;                          

% If delays are outside the range (minDelay,maxDelay), then replace them
% with a random number in [0,1].
currentParams.DelayMatrix(currentParams.DelayMatrix >= maxDelay) = rand;
currentParams.DelayMatrix(currentParams.DelayMatrix <= -maxDelay) = rand;

% Convert maxTauFrac to unitless quantity 'gamma'
minGamma = 1/(maxTauFrac*min([seq.T]))^2;

if isempty(trackedParams)
    % Start convergence tracking fresh
    LL = [];                 % (Pseudo) log-likelihood at each iteration
    LLi = -inf;              % Initial (pseudo) log-likelihood
    iterTime = [];           % Time it takes to complete each iteration
    deltaD_i = inf;          % Initial change in delays between iterations
    deltaGam_across_i = inf; % Initial change in across-group timescales 
                             % between iterations
    D = {currentParams.DelayMatrix}; % Estimated delays each iteration
    % Within- and across-group timescales each iteration
    gams_across = {currentParams.gamma_across};
    for groupIdx = 1:numGroups
        gams_within{groupIdx} = {currentParams.gamma_within{groupIdx}};
    end
    % Within- and across-group center frequencies each iteration
    if isequal(currentParams.covType, 'sg')
        nus_across = {currentParams.nu_across};
        for groupIdx = 1:numGroups
            nus_within{groupIdx} = {currentParams.nu_within{groupIdx}};
        end
    else
        nus_across = [];
        nus_within = cell(1,numGroups);
    end
    startIter = 1; % Initial value for EM loop index
else
    % Start convergence tracking based on where a previous attempt left
    % off.
    LL            = trackedParams.LL;          % (Pseudo) log-likelihood at each iteration
    LLi           = trackedParams.LL(end);     % Most recent (pseudo) log-likelihood
    LLbase        = trackedParams.LL(2);       % Base (psuedo) log-likelihood
    iterTime      = trackedParams.iterTime;    % Time it takes to complete each iteration
    D             = trackedParams.D;           % Estimated delays each iteration
    gams_across   = trackedParams.gams_across; % Estimated across-group timescales each iteration
    gams_within   = trackedParams.gams_within; % Estimated within-group timescales each iteration
    if isequal(currentParams.covType, 'sg')
        nus_across   = trackedParams.nus_across; % Estimated across-group center frequencies each iteration
        nus_within   = trackedParams.nus_within; % Estimated within-group center frequencies each iteration 
    else
        nus_across = [];
        nus_within = cell(1,numGroups);
    end
    if xDim_across > 0
        deltaD_i = max(abs(D{end}(:) - D{end-1}(:)));
        deltaGam_across_i = max(abs(gams_across{end} - gams_across{end-1}));
    else
        deltaD_i = NaN;
        deltaGam_across_i = NaN;
    end
    startIter = length(LL) + 1; % Initial value for EM loop index
end


% Track error if data likelihood decreases
err_status = 0;

% Begin EM iterations
for i =  startIter:maxIters
    
    if verbose && ~parallelize
        fprintf('EM iteration %3d of %d ', i, maxIters);
    end
    
    % Determine when to actually compute the log-likelihood
    if (rem(i, freqLL) == 0) || (i<=2) || (i == maxIters)
        getLL = true;
    else
        getLL = false;
    end
    
    
    %% === E STEP ===
    
    if ~isnan(LLi)
        LLold   = LLi;
    end                                         
    tic; % For tracking the computation time of each iteration    
    [seq,LLi,Xspec] = exactInferenceWithLL_freq(seq, currentParams, ...
                                                'getLL', getLL);   
                                    
    LL = [LL LLi];
    
    %% === M STEP ===
    if learnObs
        % Learn C,d,R     
        res = learnObsParams_dlag_freq(seq, currentParams, Xspec, 'varFloor', varFloor);
        currentParams.C = res.C;
        currentParams.d = res.d;
        currentParams.R = res.R;
    end
    
    % Learn GP kernel params and delays
    if currentParams.notes.learnKernelParams
        % Across- and within-group GP kernel parameters can be learned
        % independently, so it's convenient to separate them here.
        [seqAcross, XspecAcross, seqWithin, XspecWithin] ...
            = partitionLatents_freq(seq, Xspec, xDim_across, xDim_within);
        for n = 1:length(seq)
            seqAcross(n).yfft = seq(n).yfft;
        end
        tempParams = currentParams;
        % Don't try to learn GP parameters when xDim_across is 0
        if xDim_across > 0
            % Across-group parameters
            tempParams.xDim = xDim_across;
            tempParams.gamma = currentParams.gamma_across;
            tempParams.eps = currentParams.eps_across;
            if isequal(currentParams.covType, 'sg')
                tempParams.nu = currentParams.nu_across; 
            end
            % learnGPparams_pluDelays performs gradient descent to learn kernel
            % parameters WITH delays
            res = learnGPparams_plusDelays_freq(seqAcross, XspecAcross, tempParams, ...
                                                'learnDelays', learnDelays, extra_opts{:});
            switch currentParams.covType
                case 'rbf'
                    currentParams.gamma_across = res.gamma; 
                    if numGroups > 1
                        currentParams.DelayMatrix = res.DelayMatrix;
                    end
                    if (rem(i, freqParam) == 0) || (i == maxIters)
                        % Store current delays and timescales and compute
                        % change since last computation
                        D = [D {currentParams.DelayMatrix}];
                        gams_across = [gams_across {currentParams.gamma_across}];
                        deltaD_i = max(abs(D{end}(:) - D{end-1}(:)));
                        deltaGam_across_i = max(abs(gams_across{end} - gams_across{end-1}));
                    else
                        deltaD_i = NaN;
                        deltaGam_across_i = NaN;
                    end
        
                case 'sg'
                    currentParams.gamma_across = res.gamma; 
                    currentParams.nu_across = abs(res.nu); % Keep center frequency positive, for interpretability
                    if learnDelays
                        % Only update delays if desired. Otherwise, they will
                        % remain fixed at their initial value.
                        currentParams.DelayMatrix = res.DelayMatrix;
                    end
                    if (rem(i, freqParam) == 0) || (i == maxIters)
                        % Store current delays, timescales, and frequencies
                        % and compute change since last computation
                        D = [D {currentParams.DelayMatrix}];
                        gams_across = [gams_across {currentParams.gamma_across}];
                        nus_across = [nus_across {currentParams.nu_across}];
                        deltaD_i = max(abs(D{end}(:) - D{end-1}(:)));
                        deltaGam_across_i = max(abs(gams_across{end} - gams_across{end-1}));
                    else
                        deltaD_i = NaN;
                        deltaGam_across_i = NaN;
                    end
        
            end
        
            % NOTE: Learning GP noise variance is currently unsupported.
            if currentParams.notes.learnGPNoise
                currentParams.eps_across = res.eps;
            end
        end
        
        % Within-group parameters
        for groupIdx = 1:numGroups
            % Don't try to learn GP parameters when xDim_within is 0
            if xDim_within(groupIdx) > 0
                tempParams.gamma = currentParams.gamma_within{groupIdx};
                tempParams.eps = currentParams.eps_within{groupIdx};
                if isequal(currentParams.covType, 'sg')
                    tempParams.nu = currentParams.nu_within{groupIdx}; 
                end
                % learnGPparams performs gradient descent to learn kernel
                % parameters WITHOUT delays.
                res = learnGPparams_freq(seqWithin{groupIdx}, ...
                                         XspecWithin{groupIdx}, ...
                                         tempParams, ...
                                         extra_opts{:});
                switch currentParams.covType
                    case 'rbf'
                        currentParams.gamma_within{groupIdx} = res.gamma;  
                        if (rem(i, freqParam) == 0) || (i == maxIters)
                            % Store current timescales
                            % We won't track the change since last computation
                            % for the within-group case, for now.
                            gams_within{groupIdx} = [gams_within{groupIdx} {res.gamma}];
                        end
                        
                    case 'sg'
                        currentParams.gamma_within{groupIdx} = res.gamma;
                        currentParams.nu_within{groupIdx} = abs(res.nu); % Keep center frequency positive, for interpretability
                        if (rem(i, freqParam) == 0) || (i == maxIters)
                            % Store current timescales
                            % We won't track the change since last computation
                            % for the within-group case, for now.
                            gams_within{groupIdx} = [gams_within{groupIdx} {res.gamma}];
                            nus_within{groupIdx} = [nus_within{groupIdx} {res.nu}];
                        end

                end

                % NOTE: Learning GP noise variance is currently unsupported.
                if currentParams.notes.learnGPNoise
                    currentParams.eps_within{groupIdx} = res.eps;
                end
            end
        end
    end  
    tEnd    = toc;
    iterTime = [iterTime tEnd];  % Finish tracking EM iteration time
    
    % Display the most recent likelihood that was evaluated
    if verbose && ~parallelize
        if getLL
            fprintf('       lik %f\r', LLi);
        else
            fprintf('\r');
        end
    end
    % Verify that likelihood is growing monotonically
    if i<=2
        LLbase = LLi;
    end
    if (LLi < LLold)
        err_status = 1;
        msg = [];
        % msg = sprintf('Error: Data likelihood decreased from %g to %g on iteration %d\n',...
        %               LLold, LLi, i);
        % break;
    elseif ((LLi-LLbase) < (1+tolLL)*(LLold-LLbase))
        % Stopping criterion #1: log-likelihood not changing
        msg = sprintf('LL has converged');
        break;
    elseif (deltaD_i < tolParam) && (deltaGam_across_i < tolParam) && (learnDelays)
        % Stopping criterion #2: Across-group delays AND timescales not changing
        % Don't use parameter changes as a convergence criterion if not
        % learning delays.
        msg = sprintf('Across-group delays and timescales have converged');
        break;
    end

end

if ~err_status
    if length(LL) < maxIters
        msg = sprintf('%s after %d EM iterations.', msg, length(LL));
    else
        msg = sprintf('Fitting stopped after maxIters (%d) was reached.', maxIters);
    end
    
end

if verbose && ~parallelize
    fprintf('%s\n', msg);
end
    
estParams = currentParams;
