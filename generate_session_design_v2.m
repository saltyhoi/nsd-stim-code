function design = generate_session_design_v2()

%% =========================
% SUBJECT INPUT
%% =========================

prompt = {'Subject ID'};
default_ans = {'111'};

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

% lag constraints for realized schedule
p.easy_min_lag = 8;
p.easy_max_lag = 20;
p.hard_min_lag = 30;

% derive image counts from total number of trials
p.n_easy_images = round(p.easy_ratio * p.total_trials);   % number of easy-repeat images
p.n_hard_images = round(p.hard_ratio * p.total_trials);   % number of hard-repeat images

% total first-presented images:
% every trial is either:
%   1) a first presentation, or
%   2) a repeat of an easy image, or
%   3) a repeat of a hard image
%
% so first presentations = total trials - repeat trials
p.n_first_presentations = p.total_trials - p.n_easy_images - p.n_hard_images;

% among first-presented images, some are easy-repeat images and some are hard-repeat images
p.n_once_images = p.n_first_presentations - p.n_easy_images - p.n_hard_images;

% Safeguarding the number of trials for the experiment %
if p.n_first_presentations <= 0
    error('n_first_presentations must be positive.');
end

if p.n_once_images < 0
    error('n_once_images is negative. Reduce easy_ratio/hard_ratio.');
end

if p.n_first_presentations + p.n_easy_images + p.n_hard_images ~= p.total_trials
    error('Image design does not match total trials.');
end

if p.easy_max_lag >= p.trials_per_run
    error('easy_max_lag must be smaller than trials_per_run for within-run repeats.');
end


%% =========================
% SHARED IMAGE OPTION
%% =========================

p.shared_mode = 'partial';   % 'none' or 'partial'
% number of shared images if enabled


%% ===========================================================================
% GENERATE STIMULUS POOL
%% ===========================================================================

if strcmp(p.shared_mode,'none')

    stim_pool = randperm(73000);

elseif strcmp(p.shared_mode,'partial')
    % load shared image indices from local NSD design file (file from the NSD directory)
    S = load('nsd_expdesign.mat', 'sharedix');

    if ~isfield(S, 'sharedix')
        error('nsd_expdesign.mat does not contain variable ''sharedix''.');
    end

    shared_pool = S.sharedix(:)';   % force row vector

    if isempty(shared_pool)
        error('sharedix is empty.');
    end

    if any(shared_pool < 1) || any(shared_pool > 73000)
        error('sharedix contains invalid indices.');
    end

    if numel(unique(shared_pool)) ~= numel(shared_pool)
        error('sharedix contains duplicates.');
    end

    % subject-specific permutation of the shared pool
    rng(subID)
    stim_pool = shared_pool(randperm(numel(shared_pool))); % updating shared_pool so that across participants, it's randomly drawn from the sharedix
    
    if p.n_first_presentations > numel(stim_pool)
        error('Not enough shared images for this session.');
    end

else
    error('Invalid shared_mode option')
end

pool_idx = 1;


%% =========================
% SELECT IMAGE SETS FOR THIS SESSION
%% =========================
session_images = stim_pool(pool_idx : pool_idx + p.n_first_presentations - 1);
pool_idx = pool_idx + p.n_first_presentations;

perm_img = randperm(p.n_first_presentations);

easy_images = session_images(perm_img(1:p.n_easy_images));
hard_images = session_images(perm_img(p.n_easy_images+1 : p.n_easy_images+p.n_hard_images));
once_images = session_images(perm_img(p.n_easy_images+p.n_hard_images+1:end));

%% =========================
% INITIALIZE SCHEDULE MATRICES
%% =========================

stim_matrix = nan(p.runs, p.trials_per_run);           % actual stimulus ID per trial
stim_class_matrix = nan(p.runs, p.trials_per_run);     % 0=once, 1=easy, 2=hard
presentation_num_matrix = nan(p.runs, p.trials_per_run); % 1=first presentation, 2=repeat
first_global_matrix = nan(p.runs, p.trials_per_run);   % first presentation index for repeats
prev_global_matrix = nan(p.runs, p.trials_per_run);    % most recent previous presentation index

free_positions = cell(p.runs,1);
for r = 1:p.runs
    free_positions{r} = 1:p.trials_per_run;
end

%% ===========================================================================
% PLACE EASY REPEATS (WITHIN RUN)
%% ===========================================================================
% distribute easy-repeat images across runs as evenly as possible
base_easy_per_run = floor(p.n_easy_images / p.runs);
extra_easy = mod(p.n_easy_images, p.runs);

easy_per_run = base_easy_per_run * ones(1, p.runs);
if extra_easy > 0
    extra_runs = randperm(p.runs, extra_easy);
    easy_per_run(extra_runs) = easy_per_run(extra_runs) + 1;
end

easy_order = randperm(numel(easy_images));
easy_cursor = 1;

for r = 1:p.runs
    n_this_run = easy_per_run(r);

    for k = 1:n_this_run
        stim = easy_images(easy_order(easy_cursor));
        easy_cursor = easy_cursor + 1;

        placed = false;
        for attempt = 1:1000
            free = free_positions{r};

            if numel(free) < 2
                break
            end

            t1 = free(randi(numel(free)));
            valid_t2 = free(free > t1 & (free - t1) >= p.easy_min_lag & (free - t1) <= p.easy_max_lag);

            if isempty(valid_t2)
                continue
            end

            t2 = valid_t2(randi(numel(valid_t2)));

            stim_matrix(r,t1) = stim;
            stim_matrix(r,t2) = stim;

            stim_class_matrix(r,t1) = 1;
            stim_class_matrix(r,t2) = 1;

            presentation_num_matrix(r,t1) = 1;
            presentation_num_matrix(r,t2) = 2;

            g1 = sub2global(r, t1, p.trials_per_run);
            g2 = sub2global(r, t2, p.trials_per_run);

            first_global_matrix(r,t2) = g1;
            prev_global_matrix(r,t2) = g1;

            free_positions{r}(free_positions{r} == t1) = [];
            free_positions{r}(free_positions{r} == t2) = [];

            placed = true;
            break
        end

        if ~placed
            error('Could not place easy repeat image within run %d under lag constraints.', r);
        end
    end
end

%% ===========================================================================
% PLACE HARD REPEATS (ACROSS RUNS)
%% ===========================================================================
hard_order = randperm(numel(hard_images));

for i = 1:numel(hard_images)
    stim = hard_images(hard_order(i));

    placed = false;
    for attempt = 1:5000
        candidate_runs = find(cellfun(@numel, free_positions) > 0);

        if numel(candidate_runs) < 2
            break
        end

        r1 = candidate_runs(randi(numel(candidate_runs)));
        r2 = candidate_runs(randi(numel(candidate_runs)));
        while r2 == r1
            r2 = candidate_runs(randi(numel(candidate_runs)));
        end

        t1 = free_positions{r1}(randi(numel(free_positions{r1})));
        t2 = free_positions{r2}(randi(numel(free_positions{r2})));

        g1 = sub2global(r1, t1, p.trials_per_run);
        g2 = sub2global(r2, t2, p.trials_per_run);

        % Convert (run_idx, trial_idx) into a single global trial index.
        % Assumes each run has the same number of trials (trials_per_run).
        % Example: run 3, trial 5 with 100 trials/run → global index = 205.
        % Useful for flattening multi-run data into one continuous trial sequence.

        if g1 < g2
            rf = r1; tf = t1; rr = r2; tr = t2;
            gf = g1; gr = g2;
        else
            rf = r2; tf = t2; rr = r1; tr = t1;
            gf = g2; gr = g1;
        end

        if (gr - gf) < p.hard_min_lag
            continue
        end

        stim_matrix(rf,tf) = stim;
        stim_matrix(rr,tr) = stim;

        stim_class_matrix(rf,tf) = 2;
        stim_class_matrix(rr,tr) = 2;

        presentation_num_matrix(rf,tf) = 1;
        presentation_num_matrix(rr,tr) = 2;

        first_global_matrix(rr,tr) = gf;
        prev_global_matrix(rr,tr) = gf;

        free_positions{rf}(free_positions{rf} == tf) = [];
        free_positions{rr}(free_positions{rr} == tr) = [];

        placed = true;
        break
    end

    if ~placed
        error('Could not place hard repeat image across runs under lag constraints.');
    end
end


%% =========================
% FILL REMAINING SLOTS WITH ONCE-ONLY IMAGES
%% =========================

once_order = randperm(numel(once_images));
once_cursor = 1;

for r = 1:p.runs
    free = free_positions{r};

    for j = 1:numel(free)
        t = free(j);
        stim = once_images(once_order(once_cursor));
        once_cursor = once_cursor + 1;

        stim_matrix(r,t) = stim;
        stim_class_matrix(r,t) = 0;
        presentation_num_matrix(r,t) = 1;
    end
end

%% =========================
% FLATTEN TO TRIAL VECTORS
%% =========================

stim_list = reshape(stim_matrix', [], 1);
STIMCLASS = reshape(stim_class_matrix', [], 1);
PRESENTATIONNUM = reshape(presentation_num_matrix', [], 1);
FIRSTGLOBAL = reshape(first_global_matrix', [], 1);
PREVGLOBAL = reshape(prev_global_matrix', [], 1);

RUN_INDEX = ceil((1:p.total_trials)' / p.trials_per_run);
TRIAL_IN_RUN = mod((1:p.total_trials)' - 1, p.trials_per_run) + 1;

ISOLD = PRESENTATIONNUM == 2;
REPEATTYPE = zeros(p.total_trials,1);
REPEATTYPE(ISOLD & STIMCLASS == 1) = 1;
REPEATTYPE(ISOLD & STIMCLASS == 2) = 2;


%% =========================
% COMPUTE MEMORY VARIABLES FROM REALIZED SCHEDULE
%% =========================

MEMORYRECENT = nan(p.total_trials,1);
MEMORYFIRST  = nan(p.total_trials,1);

for t = 1:p.total_trials
    prev = find(stim_list(1:t-1) == stim_list(t));

    if ~isempty(prev)
        MEMORYRECENT(t) = t - prev(end);
        MEMORYFIRST(t)  = t - prev(1);

        if isnan(PREVGLOBAL(t))
            PREVGLOBAL(t) = prev(end);
        end
        if isnan(FIRSTGLOBAL(t))
            FIRSTGLOBAL(t) = prev(1);
        end
    end
end

%% =========================
% VERIFY REALIZED STIMULUS SCHEDULE
%% =========================

if any(isnan(stim_list))
    error('Some trial slots were not filled.');
end

u = unique(stim_list);
counts = zeros(numel(u),1);
for i = 1:numel(u)
    counts(i) = sum(stim_list == u(i));
end

if any(counts > 2)
    error('Some images appear more than twice.');
end

% easy images must appear exactly twice within the same run
for i = 1:numel(easy_images)
    pos = find(stim_list == easy_images(i));
    if numel(pos) ~= 2
        error('An easy image does not appear exactly twice.');
    end
    rpos = ceil(pos / p.trials_per_run);
    if rpos(1) ~= rpos(2)
        error('An easy image repeat is not within run.');
    end
    if (pos(2) - pos(1)) < p.easy_min_lag || (pos(2) - pos(1)) > p.easy_max_lag
        error('An easy image violates easy lag constraints.');
    end
end

% hard images must appear exactly twice across different runs
for i = 1:numel(hard_images)
    pos = find(stim_list == hard_images(i));
    if numel(pos) ~= 2
        error('A hard image does not appear exactly twice.');
    end
    rpos = ceil(pos / p.trials_per_run);
    if rpos(1) == rpos(2)
        error('A hard image repeat is not across runs.');
    end
    if (pos(2) - pos(1)) < p.hard_min_lag
        error('A hard image violates hard lag constraints.');
    end
end

if numel(once_images) ~= p.n_once_images
    error('Once-only image count mismatch.');
end
if numel(easy_images) ~= p.n_easy_images
    error('Easy image count mismatch.');
end
if numel(hard_images) ~= p.n_hard_images
    error('Hard image count mismatch.');
end


%% ===========================================================================
% GENERATE ITIs
%% ===========================================================================

ITI_pool = 4:8;

n_iti_types = numel(ITI_pool);
base_count = floor(p.trials_per_run / n_iti_types);
remainder = mod(p.trials_per_run, n_iti_types);

% Start with equal base counts
iti_counts = base_count * ones(1, n_iti_types);

% Distribute the leftover trials
% Example: if remainder = 2, first two ITIs get +1
iti_counts(1:remainder) = iti_counts(1:remainder) + 1;

% Build per-run ITI template
ITI_template_per_run = [];

for i = 1:n_iti_types
    ITI_template_per_run = [ITI_template_per_run, repmat(ITI_pool(i), 1, iti_counts(i))];
end

% Safety check
if numel(ITI_template_per_run) ~= p.trials_per_run
    error('ITI template length does not match p.trials_per_run.');
end

ITI_counts_per_run = iti_counts;

%% =========================
% GENERATE ITIs
% randomized integers, same total duration per run
%% =========================
ITI_matrix = nan(p.runs, p.trials_per_run);

for r = 1:p.runs
    ITI_matrix(r,:) = ITI_template_per_run(randperm(p.trials_per_run));
end

ITI = reshape(ITI_matrix', [], 1);
% ITI = ITI_pool(randi(length(ITI_pool),p.total_trials,1));

%% =========================
% VERIFY ITI PROPERTIES
%% =========================

ITI_run_sums = sum(ITI_matrix, 2);

if numel(unique(ITI_run_sums)) ~= 1
    error('ITI run totals are not identical.');
end

for r = 1:p.runs
    for i = 1:numel(ITI_pool)
        actual_count = sum(ITI_matrix(r,:) == ITI_pool(i));
        if actual_count ~= ITI_counts_per_run(i)
            error('Run %d has incorrect count for ITI=%d.', r, ITI_pool(i));
        end
    end
end

%% =========================
% IMAGE-LEVEL AUDIT TABLES
%% =========================

image_ids_all = [once_images(:); easy_images(:); hard_images(:)];
image_class_all = [zeros(numel(once_images),1); ones(numel(easy_images),1); 2*ones(numel(hard_images),1)];
image_first_global = nan(numel(image_ids_all),1);
image_second_global = nan(numel(image_ids_all),1);
image_n_presented = zeros(numel(image_ids_all),1);

for i = 1:numel(image_ids_all)
    pos = find(stim_list == image_ids_all(i));
    image_n_presented(i) = numel(pos);
    if ~isempty(pos)
        image_first_global(i) = pos(1);
    end
    if numel(pos) >= 2
        image_second_global(i) = pos(2);
    end
end

%% =========================
% STORE DESIGN
%% =========================

design.stim_matrix = stim_matrix;
design.stim_list = stim_list;

design.STIMCLASS = STIMCLASS;                 % 0=once, 1=easy, 2=hard
design.PRESENTATIONNUM = PRESENTATIONNUM;     % 1=first, 2=repeat
design.REPEATTYPE = REPEATTYPE;               % 0=new, 1=easy repeat trial, 2=hard repeat trial
design.ISOLD = ISOLD;

design.FIRSTGLOBAL = FIRSTGLOBAL;
design.PREVGLOBAL = PREVGLOBAL;
design.MEMORYRECENT = MEMORYRECENT;
design.MEMORYFIRST = MEMORYFIRST;

design.RUN_INDEX = RUN_INDEX;
design.TRIAL_IN_RUN = TRIAL_IN_RUN;

design.once_images = once_images(:);
design.easy_images = easy_images(:);
design.hard_images = hard_images(:);

design.image_ids_all = image_ids_all;
design.image_class_all = image_class_all;
design.image_first_global = image_first_global;
design.image_second_global = image_second_global;
design.image_n_presented = image_n_presented;


design.ITI = ITI;
design.ITI_matrix = ITI_matrix;
design.ITI_run_sums = ITI_run_sums;
design.ITI_pool = ITI_pool;
design.ITI_counts_per_run = ITI_counts_per_run;

design.runs = p.runs;
design.trials_per_run = p.trials_per_run;
design.total_trials = p.total_trials;
design.subject = subID;
design.shared_mode = p.shared_mode;

design.params = p;


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

fprintf('Session design saved: %s\n', filename);
fprintf('Total trials: %d\n', design.total_trials);
fprintf('Distinct first-presented images: %d\n', p.n_first_presentations);
fprintf('Once-only images: %d\n', numel(design.once_images));
fprintf('Easy-repeat images: %d\n', numel(design.easy_images));
fprintf('Hard-repeat images: %d\n', numel(design.hard_images));
fprintf('ITI total per run: %d sec\n', design.ITI_run_sums(1));

end

function g = sub2global(run_idx, trial_idx, trials_per_run)
    g = (run_idx - 1) * trials_per_run + trial_idx;
end