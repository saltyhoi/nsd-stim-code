function design = generate_session_design_v3()

%% =========================
% SUBJECT INPUT
%% =========================
prompt = {'Subject ID'};
default_ans = {'213'};

box = inputdlg(prompt,'Generate session design',1,default_ans);

if isempty(box)
    return
end

subID = str2double(strtrim(box{1}));
rng(subID);

%% =========================
% SESSION PARAMETERS
%% =========================
p.runs = 34;
p.trials_per_run = 30;
p.total_trials = p.runs * p.trials_per_run;   % 1020

p.base_repeats = 3;
p.shared_mode = 'partial';

%% =========================
% LOAD SHARED INDEX POOL
%% =========================
S = load('nsd_expdesign.mat', 'sharedix');

if ~isfield(S, 'sharedix')
    error('nsd_expdesign.mat does not contain variable ''sharedix''.');
end

shared_pool = S.sharedix(:);

if isempty(shared_pool)
    error('sharedix is empty.');
end

if any(shared_pool < 1) || any(shared_pool > 73000)
    error('sharedix contains invalid indices.');
end

if numel(unique(shared_pool)) ~= numel(shared_pool)
    error('sharedix contains duplicates.');
end

%% =========================
% LOAD BASE INDICES (255)
%% =========================
base_idx = [ ...
46002 48617 32625 70335 5301 40575 56723 14528 27326 28068 ...
59079 14820 29021 66643 57838 53570 10046 31028 59023 64621 ...
15003 5285 13720 61748 69007 47290 14931 46480 12075 11725 ...
13613 60725 5583 25250 25581 40770 53891 61797 9722 59194 ...
41814 63081 61972 69130 33813 36623 69813 50114 71410 5204 ...
17463 6640 46160 10610 20702 53489 11689 6558 31964 4835 ...
51062 65639 66489 26435 34126 25318 9917 3626 30601 59595 ...
55107 48422 8843 50170 25693 37736 9027 12922 49076 4423 ...
26127 41482 64096 35798 64615 12495 12796 59585 55669 30407 ...
35986 68842 22967 11844 47687 56867 62209 42238 29660 18796 ...
3077 26292 60834 64295 19074 72510 22809 46661 12065 26243 ...
41056 20307 29568 69240 47614 70758 9462 22993 8465 11617 ...
50811 56314 48832 37221 8262 42473 52328 42642 56418 42166 ...
63449 9680 38494 42126 17794 28524 38978 43445 43619 43950 ...
37436 7039 72170 3687 70038 51788 61752 28303 39047 34238 ...
11521 24202 45213 43428 48260 66216 41097 72209 54812 60251 ...
37494 6489 43107 44971 17942 40909 39509 42697 60867 40920 ...
4930 71753 71232 25454 9048 47099 31801 53511 30856 59046 ...
52527 56454 59039 66278 50755 70095 31782 27878 39841 17238 ...
4058 56066 8387 20206 21194 38297 71450 25702 46036 8925 ...
39547 21601 15492 25287 4786 56042 11159 29837 16344 26163 ...
44844 65821 28024 55857 54698 47408 38641 19436 20633 28286 ...
21508 53727 30954 44736 28487 42563 38853 38060 36682 54683 ...
56269 22873 4436 17230 33131 72605 46460 54078 45837 28349 ...
28341 24846 43820 42781 68168 35790 61216 68471 20265 53370 ...
28189 65872 5338 50500 44339 ];

base_idx = base_idx(:);

if numel(base_idx) ~= 255
    error('Expected 255 base indices, got %d.', numel(base_idx));
end

%% =========================
% BUILD FINAL STIM LIST
%% =========================
tripled_idx = repmat(base_idx, p.base_repeats, 1);   % 765
n_needed = p.total_trials - numel(tripled_idx);      % 255

available_fill = setdiff(shared_pool, base_idx, 'stable');

if numel(available_fill) < n_needed
    error('Not enough unique shared images after excluding base_idx.');
end

fill_idx = available_fill(randperm(numel(available_fill), n_needed));
stim_list = [tripled_idx; fill_idx(:)];
stim_list = stim_list(randperm(numel(stim_list)));

%% =========================
% RESHAPE INTO RUNS
%% =========================
stim_matrix = reshape(stim_list, p.trials_per_run, p.runs)';

%% =========================
% DERIVE TRIAL-WISE OUTPUTS
%% =========================
STIMCLASS = zeros(p.total_trials,1);         % 0=once/filler, 1=repeated-set
PRESENTATIONNUM = nan(p.total_trials,1);     % 1,2,3 for repeated-set; 1 for filler
FIRSTGLOBAL = nan(p.total_trials,1);
PREVGLOBAL = nan(p.total_trials,1);

for t = 1:p.total_trials
    this_stim = stim_list(t);
    prev = find(stim_list(1:t-1) == this_stim);

    if ismember(this_stim, base_idx)
        STIMCLASS(t) = 1;
        PRESENTATIONNUM(t) = numel(prev) + 1;
    else
        STIMCLASS(t) = 0;
        PRESENTATIONNUM(t) = 1;
    end

    if ~isempty(prev)
        FIRSTGLOBAL(t) = prev(1);
        PREVGLOBAL(t) = prev(end);
    end
end

RUN_INDEX = ceil((1:p.total_trials)' / p.trials_per_run);
TRIAL_IN_RUN = mod((1:p.total_trials)' - 1, p.trials_per_run) + 1;

ISOLD = PRESENTATIONNUM > 1;
REPEATTYPE = zeros(p.total_trials,1);
REPEATTYPE(ISOLD) = 1;

%% =========================
% COMPUTE MEMORY VARIABLES
%% =========================
MEMORYRECENT = nan(p.total_trials,1);
MEMORYFIRST  = nan(p.total_trials,1);

for t = 1:p.total_trials
    prev = find(stim_list(1:t-1) == stim_list(t));
    if ~isempty(prev)
        MEMORYRECENT(t) = t - prev(end);
        MEMORYFIRST(t)  = t - prev(1);
    end
end

%% =========================
% IMAGE GROUPS
%% =========================
once_images = fill_idx(:);
easy_images = base_idx(:);
hard_images = [];

%% =========================
% VERIFY
%% =========================
if any(isnan(stim_list))
    error('Some trial slots were not filled.');
end

for i = 1:numel(base_idx)
    if sum(stim_list == base_idx(i)) ~= 3
        error('Base index %d does not appear exactly 3 times.', base_idx(i));
    end
end

for i = 1:numel(fill_idx)
    if sum(stim_list == fill_idx(i)) ~= 1
        error('Filler index %d does not appear exactly once.', fill_idx(i));
    end
end

%% =========================
% GENERATE ITIs
%% =========================
ITI_pool = 4:8;

n_iti_types = numel(ITI_pool);
base_count = floor(p.trials_per_run / n_iti_types);
remainder = mod(p.trials_per_run, n_iti_types);

iti_counts = base_count * ones(1, n_iti_types);
iti_counts(1:remainder) = iti_counts(1:remainder) + 1;

ITI_template_per_run = [];
for i = 1:n_iti_types
    ITI_template_per_run = [ITI_template_per_run, repmat(ITI_pool(i), 1, iti_counts(i))];
end

if numel(ITI_template_per_run) ~= p.trials_per_run
    error('ITI template length does not match p.trials_per_run.');
end

ITI_counts_per_run = iti_counts;
ITI_matrix = nan(p.runs, p.trials_per_run);

for r = 1:p.runs
    ITI_matrix(r,:) = ITI_template_per_run(randperm(p.trials_per_run));
end

ITI = reshape(ITI_matrix', [], 1);
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
image_ids_all = [once_images(:); easy_images(:)];
image_class_all = [zeros(numel(once_images),1); ones(numel(easy_images),1)];
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

design.STIMCLASS = STIMCLASS;
design.PRESENTATIONNUM = PRESENTATIONNUM;
design.REPEATTYPE = REPEATTYPE;
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
fprintf('Distinct first-presented images: %d\n', numel(unique(stim_list)));
fprintf('Once-only images: %d\n', numel(design.once_images));
fprintf('Easy-repeat images: %d\n', numel(design.easy_images));
fprintf('Hard-repeat images: %d\n', numel(design.hard_images));
fprintf('ITI total per run: %d sec\n', design.ITI_run_sums(1));

end