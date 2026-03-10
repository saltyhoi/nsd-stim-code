function design = generate_session_design()

%% =========================
% SUBJECT INPUT
%% =========================

prompt = {'Subject ID'};
default_ans = {'001'};

box = inputdlg(prompt,'Generate session design',1,default_ans);

if isempty(box)
    return
end

subID = str2double(strtrim(box{1}));

rng(subID);   % reproducible sequence


%% =========================
% SESSION PARAMETERS
%% =========================

p.runs = 15;
p.trials_per_run = 30;
p.total_trials = p.runs * p.trials_per_run;

% repeat proportions
p.easy_ratio = 0.10;
p.hard_ratio = 0.10;

% lag constraints
p.easy_min_lag = 8;
p.easy_max_lag = 20;
p.hard_min_lag = 30;


%% =========================
% SHARED IMAGE OPTION
%% =========================

p.shared_mode = 'partial';   % 'none' or 'partial'

% number of shared images if enabled
p.shared_count = 80;


%% =========================
% GENERATE STIMULUS POOL
%% =========================

if strcmp(p.shared_mode,'none')

    stim_pool = randperm(73000);

elseif strcmp(p.shared_mode,'partial')

    % shared pool (same across subjects)
    rng(999)
    shared_pool = randperm(73000,p.shared_count);

    % subject-specific pool
    rng(subID)
    subject_pool = setdiff(randperm(73000),shared_pool);

    stim_pool = [shared_pool subject_pool];

else
    error('Invalid shared_mode option')
end

pool_idx = 1;


%% =========================
% GENERATE REPEAT TYPES
%% =========================

repeat_type = zeros(p.total_trials,1);

n_easy = round(p.easy_ratio * p.total_trials);
n_hard = round(p.hard_ratio * p.total_trials);

idx = randperm(p.total_trials);

repeat_type(idx(1:n_easy)) = 1;
repeat_type(idx(n_easy+1:n_easy+n_hard)) = 2;


%% =========================
% BUILD STIMULUS SEQUENCE
%% =========================

stim_list = zeros(p.total_trials,1);
seen = [];

for t = 1:p.total_trials

    % new trial
    if repeat_type(t)==0 || isempty(seen)

        stim = stim_pool(pool_idx);
        pool_idx = pool_idx + 1;

        stim_list(t) = stim;
        seen = [seen stim];

    else

        candidates = [];

        for s = 1:length(seen)

            prev = find(stim_list(1:t-1)==seen(s));

            if isempty(prev)
                continue
            end

            lag = t - prev(end);

            if repeat_type(t)==1
                if lag >= p.easy_min_lag && lag <= p.easy_max_lag
                    candidates(end+1) = seen(s);
                end
            end

            if repeat_type(t)==2
                if lag >= p.hard_min_lag
                    candidates(end+1) = seen(s);
                end
            end

        end

        % fallback if no candidate found
        if isempty(candidates)

            stim = stim_pool(pool_idx);
            pool_idx = pool_idx + 1;

            seen = [seen stim];

        else

            stim = candidates(randi(numel(candidates)));

        end

        stim_list(t) = stim;

    end

end


%% =========================
% COMPUTE MEMORY VARIABLES
%% =========================

MEMORYRECENT = nan(p.total_trials,1);
MEMORYFIRST  = nan(p.total_trials,1);

for t = 1:p.total_trials

    prev = find(stim_list(1:t-1)==stim_list(t));

    if ~isempty(prev)
        MEMORYRECENT(t) = t - prev(end);
        MEMORYFIRST(t)  = t - prev(1);
    end

end


%% =========================
% GENERATE ITIs
%% =========================

ITI_pool = 4:8;
ITI = ITI_pool(randi(length(ITI_pool),p.total_trials,1));


%% =========================
% STORE DESIGN
%% =========================

design.stim_list = stim_list;

design.REPEATTYPE = repeat_type;
design.ISOLD = repeat_type > 0;

design.MEMORYRECENT = MEMORYRECENT;
design.MEMORYFIRST = MEMORYFIRST;

design.ITI = ITI;

design.runs = p.runs;
design.trials_per_run = p.trials_per_run;

design.subject = subID;
design.shared_mode = p.shared_mode;


%% =========================
% CHECK IF DESIGN EXISTS
%% =========================

filename = sprintf('session_design_sub%03d.mat',subID);

if exist(filename,'file')

    warning('Design file already exists:\n%s', filename);

    choice = questdlg( ...
        sprintf('Design already exists:\n\n%s\n\nDo you want to overwrite it?', filename), ...
        'Overwrite warning', ...
        'Stop','Overwrite','Stop');

    if strcmp(choice,'Stop')
        fprintf('Design generation stopped to prevent overwrite.\n');
        return
    end

end


%% =========================
% SAVE DESIGN
%% =========================

save(filename,'design');

fprintf('Session design saved: %s\n',filename);

end