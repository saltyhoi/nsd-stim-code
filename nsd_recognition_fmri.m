clear; clc;

Screen('Preference','SkipSyncTests',1);
KbName('UnifyKeyNames');

%% =========================================================
% SUBJECT INPUT
%% =========================================================
prompt = {'Subject ID','Session','Run','Random Seed','Display (1=fMRI,2=behavior)','Eye tracking (1=yes,0=no)'};

default_ans = {'001','1','1',num2str(round(sum(100*clock))),'1','0'};

box = inputdlg(prompt,'Enter subject information',1,default_ans);
if isempty(box); return; end

p = struct();
t = struct();

p.SUBJECT = str2double(strtrim(box{1}));
p.SESSION = str2double(strtrim(box{2}));
p.RUN     = str2double(strtrim(box{3}));
p.RNDSEED = str2double(strtrim(box{4}));
p.DISPLAY = str2double(strtrim(box{5}));
p.EYE_TRACKING = str2double(strtrim(box{6}));
p.DEBUG = 1;   % 1 = fast testing, 0 = real experiment

rng(p.RNDSEED);


%% =========================================================
% KEYS
%% =========================================================
p.keyNew   = KbName('1!');
p.keyOld   = KbName('2@');
p.startKeys = [KbName('5%') KbName('5') KbName('t')]; % scanner trigger
p.escape   = KbName('ESCAPE');  % safe abort

% timing
if p.DEBUG
    p.stimDur = 0.3;   % fast testing
else
    p.stimDur = 3;     % real experiment
end
% p.stimDur = 3; % seconds

% Timing information 
if p.DEBUG
    p.start_wait = 0.5;
    p.end_wait   = 0.5;
else
    p.start_wait = 3.0;
    p.end_wait   = 10;
end
% p.start_wait  = 3.0; 
% p.end_wait    = 10; 


%% =========================================================
% PATHS
%% =========================================================
p.h5file = '../nsd_stimuli.hdf5';
p.dataset = '/imgBrick';

% output folder (optional)
p.dataDir = fullfile(pwd,'data');
if ~exist(p.dataDir,'dir'); mkdir(p.dataDir); end

if p.EYE_TRACKING
    p.et_fn = sprintf('S%03dR%02d',p.SUBJECT,p.RUN);
end

%% =========================================================
% CHECK FOR EXISTING DATA FILE
%% =========================================================

filename = sprintf('sub%03d_sess%02d_run%02d.mat', ...
    p.SUBJECT, p.SESSION, p.RUN);

outfile = fullfile(p.dataDir, filename);

if exist(outfile,'file')

    warning('Data file already exists:\n%s', outfile);

    choice = questdlg( ...
        sprintf('File already exists:\n\n%s\n\nContinue anyway?', filename), ...
        'Overwrite warning', ...
        'Stop experiment','Continue anyway','Stop experiment');

    if strcmp(choice,'Stop experiment')
        fprintf('Experiment stopped to prevent overwrite.\n');
        return
    end

end

%% =========================================================
% LOAD SESSION DESIGN + TRIM TO RUN
%% =========================================================
design_file = sprintf('session_design_sub%03d.mat', p.SUBJECT);

if ~exist(design_file,'file')
    error('Design file not found: %s', design_file);
end

S = load(design_file);
design = S.design;

fprintf('Loaded design file: %s\n', design_file);

% S = load('session_design.mat');     % contains "design"
% design = S.design;

p.trials_per_run = design.trials_per_run;

start_idx = (p.RUN-1)*p.trials_per_run + 1;
end_idx   = p.RUN*p.trials_per_run;

if start_idx < 1 || end_idx > numel(design.stim_list)
    error('Run %d is out of range for this session_design (start=%d, end=%d).', p.RUN, start_idx, end_idx);
end

p.KID73        = design.stim_list(start_idx:end_idx);
p.ITI          = design.ITI(start_idx:end_idx);
if p.DEBUG
    p.ITI(:) = 0.25;   % very short ITI for testing
end
p.ISOLD        = design.ISOLD(start_idx:end_idx);
p.MEMORYRECENT = design.MEMORYRECENT(start_idx:end_idx);
p.MEMORYFIRST  = design.MEMORYFIRST(start_idx:end_idx);

p.ntrials = numel(p.KID73);

if ~exist(p.h5file,'file')
    error('Cannot find stimulus file: %s', p.h5file);
end


%% =========================================================
% SCREEN SETUP
%% =========================================================

AssertOpenGL;

screen = max(Screen('Screens'));
p.bg_color = [127 127 127];
[p.window, p.rect] = Screen('OpenWindow',screen,p.bg_color);
Screen('BlendFunction', p.window, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);


%% =========================================================
% EYELINK INITIALIZATION
%% =========================================================
if p.EYE_TRACKING
    el = EyelinkInitDefaults(p.window);
    el.backgroundcolour = p.bg_color(1);
    el.calibrationtargetcolour = [255 0 0];
    EyelinkUpdateDefaults(el);
    Eyelink('Initialize','PsychEyelinkDispatchCallback');
    Eyelink('command','calibration_type=HV5');
    Eyelink('command','sample_rate=500');
    Eyelink('command','link_sample_data=LEFT,RIGHT,GAZE,AREA');
    Eyelink('command','file_event_filter = LEFT,RIGHT,FIXATION,SACCADE,BLINK,MESSAGE,BUTTON');
    Eyelink('command','file_sample_data = LEFT,RIGHT,GAZE,AREA,GAZERES,STATUS');
    Eyelink('command','screen_pixel_coords=%ld %ld %ld %ld',0,0,p.rect(3)-1,p.rect(4)-1);
    Eyelink('message','DISPLAY_COORDS %ld %ld %ld %ld',0,0,p.rect(3)-1,p.rect(4)-1);
    EyelinkDoTrackerSetup(el);
    Eyelink('openfile',p.et_fn);
end

HideCursor;
Priority(MaxPriority(p.window));

[p.xCenter,p.yCenter] = RectCenter(p.rect);

%% =========================================================
% INITIALIZE BEHAVIOR VARIABLES (ALL IN p)
%% =========================================================
if p.DISPLAY == 1     % fMRI BOLD
    p.scr_height = 39; % cm
    p.viewing_distance = 110; % cm
elseif p.DISPLAY == 2 % behavior
    p.scr_height = 30;
    p.viewing_distance = 52; % cm
end

%% =========================================================
% FIXATION PARAMETERS
%% =========================================================
p.ppd = 0.5*(p.rect(4)-p.rect(2)) / atan2d(p.scr_height/2, p.viewing_distance);
p.fix_size_out = 0.3;   % degrees 0.25
p.fix_size_in  = 0.075;   % degrees 0.05
% fprintf('PPD = %.2f\n', p.ppd);
% fprintf('Fix outer diameter px = %.2f\n', p.fix_size_out * p.ppd * 2);
p.center = [p.xCenter p.yCenter];

p.fix_pen      = 1;      % ring thickness (pixels)

% fixation parameters from Allen et al.
p.fix_diam_deg   = 0.2;               % total dot diameter
p.fix_diam_pix   = p.fix_diam_deg * p.ppd;
p.fix_border_pix = max(1, round(0.15 * p.fix_diam_pix));  % approximate black border
p.fix_color      = [255 0 0];
p.fix_alpha      = 127;               % ~50% opacity
p.fix_border_col = [0 0 0];


p.TRIAL = (1:p.ntrials)';

p.BUTTON = nan(p.ntrials,1);        % 1=new, 2=old
p.RT     = nan(p.ntrials,1);        % ms

p.ISOLDCURRENT = nan(p.ntrials,1);
p.ISCORRECT    = nan(p.ntrials,1);

p.CHANGEMIND  = zeros(p.ntrials,1);
p.TOTAL1      = 0;
p.TOTAL2      = 0;
p.MISSINGDATA = zeros(p.ntrials,1);

% optional timing logs (useful for fMRI)
t.trial_start = nan(p.ntrials,1);
t.stim_onset  = nan(p.ntrials,1);
t.trial_end   = nan(p.ntrials,1);

%% =========================================================
% ESTIMATED EXPERIMENT DURATION
%% =========================================================
p.trialDur = p.stimDur + p.ITI;      % duration of each trial
p.expt_dur = p.start_wait ...
           + sum(p.trialDur) ...
           + p.end_wait;
fprintf('Estimated run duration: %.2f seconds (%.2f minutes)\n', ...
        p.expt_dur, p.expt_dur/60);

% stimulus size (8.4 deg visual angle from Allen et al.,2021)
p.stim_deg = 8.4;                     % degrees of visual angle
p.stim_pix = round(p.stim_deg * p.ppd);
p.dstRect = CenterRectOnPoint([0 0 p.stim_pix p.stim_pix], ...
                           p.xCenter, p.yCenter);

%% =========================================================
% PRELOAD TEXTURES FOR THIS RUN (recommended for scanner timing)
%% =========================================================
p.tex = nan(p.ntrials,1);

for i = 1:p.ntrials
    kid = p.KID73(i);

    % imgBrick is stored as 3 x 425 x 425 x 73000 in your file
    img = h5read(p.h5file,p.dataset,[1 1 1 kid],[3 425 425 1]);
    img = permute(img,[3 2 1]);   % -> 425 x 425 x 3
    img = uint8(img);

    p.tex(i) = Screen('MakeTexture',p.window,img);
end

%% =========================================================
% WAIT FOR SCANNER TRIGGER (and allow ESC to abort & save)
%% =========================================================

DrawFormattedText(p.window,'Waiting for scanner trigger (5)\n(ESC to abort)','center','center',[255 255 255]);
Screen('Flip',p.window);

KbReleaseWait;
while 1
    [keyIsDown, secs, keyCode] = KbCheck(-1);  % IMPORTANT: -1
    if keyIsDown
        if keyCode(p.escape)
            t.abort_time = secs;
            safe_abort_and_save(p,t);
            return
        end
        if any(keyCode(p.startKeys))
            break
        end
    end
end

t.experiment_start = GetSecs;

%% =========================================================
% START EYELINK RECORDING
%% =========================================================
if p.EYE_TRACKING
    Eyelink('StartRecording');
    WaitSecs(0.05);
    Eyelink('Command','record_status_message "RUN STARTED"');
    Eyelink('Message','xDAT %i',101);
end

%% ==========================================
% START WAIT
%% ==========================================
wait_start = GetSecs;
while GetSecs - wait_start < p.start_wait
    Screen('FillRect',p.window,p.bg_color);
    drawFixation(p.window,p);
    Screen('Flip',p.window);
end

%% =========================================================
% TRIAL LOOP
%% =========================================================

for trial = 1:p.ntrials

    t.trial_start(trial) = GetSecs;

    Screen('FillRect', p.window, p.bg_color);
    Screen('DrawTexture', p.window, p.tex(trial), [], p.dstRect);
    drawFixation(p.window, p);
    
    t.stim_onset(trial) = Screen('Flip', p.window);
    if p.EYE_TRACKING
        Eyelink('Message','xDAT %i',1);
        Eyelink('command','record_status_message "Trial %d of %d"',trial,p.ntrials);
    end
    stim_onset = t.stim_onset(trial);

    responded = 0;

    while GetSecs - stim_onset < p.stimDur

        [resp, secs] = checkForResp([p.keyNew p.keyOld], p.escape);

        if resp == -1
            t.abort_time = secs;
            safe_abort_and_save(p,t);
            return
        end

        if resp ~= 0
            % resp is a keycode; map to button
            if resp == p.keyNew
                button = 1;
                p.TOTAL1 = p.TOTAL1 + 1;
            elseif resp == p.keyOld
                button = 2;
                p.TOTAL2 = p.TOTAL2 + 1;
            else
                button = NaN;
            end

            if ~isnan(button)
                if responded == 1
                    p.CHANGEMIND(trial) = 1;
                end

                p.BUTTON(trial) = button;
                p.RT(trial) = (secs - stim_onset)*1000; % ms
                responded = 1;
            end
        end
    end

    if p.EYE_TRACKING
        Eyelink('Message','xDAT %i',2);
    end
    
    % classify response
    if ~isnan(p.BUTTON(trial))
        p.ISOLDCURRENT(trial) = (p.BUTTON(trial) == 2);
        p.ISCORRECT(trial)    = (p.ISOLD(trial) == p.ISOLDCURRENT(trial));
    else
        p.MISSINGDATA(trial)  = 1;
    end

    % ITI with fixation
    Screen('FillRect',p.window,p.bg_color);
    drawFixation(p.window,p);
    Screen('Flip',p.window);

    iti_start = GetSecs;
    while GetSecs - iti_start < p.ITI(trial)
        [resp, secs] = checkForResp([], p.escape);
        if resp == -1
            t.abort_time = secs;
            safe_abort_and_save(p,t);
            return
        end
    end

    t.trial_end(trial) = GetSecs;
end

Screen('Flip',p.window);
wait_start = GetSecs;

while GetSecs - wait_start < p.end_wait
    Screen('FillRect',p.window,p.bg_color);
    drawFixation(p.window,p);
    Screen('Flip',p.window);
end

DrawFormattedText(p.window,'Run finished\n\nPress SPACE to exit','center','center',[255 255 255]);
Screen('Flip',p.window);

resp = 0;
while resp == 0
    [resp, ~] = checkForResp(KbName('space'), p.escape);

    if resp == -1
        safe_abort_and_save(p,t);
        return
    end
end
fprintf('SPACE pressed: run finished normally\n');


%% =========================================================
% STOP EYELINK RECORDING + SAVE EDF
%% =========================================================
if p.EYE_TRACKING
    Eyelink('Message','xDAT %i',0);   % experiment end
    Eyelink('StopRecording');
    Eyelink('CloseFile');

    try
        Eyelink('ReceiveFile',[p.et_fn '.edf'], fullfile(p.dataDir,[p.et_fn '.edf']));
    catch
        fprintf('Problem receiving EDF file.\n');
    end

    Eyelink('ShutDown');
end

t.experiment_end = GetSecs;
%% =========================================================
% SAVE DATA
%% =========================================================

filename = sprintf('sub%03d_sess%02d_run%02d.mat',p.SUBJECT,p.SESSION,p.RUN);
outfile = fullfile(p.dataDir, filename);
save(outfile,'p','t');

% cleanup textures
Screen('Close',p.tex(~isnan(p.tex)));

Screen('CloseAll');
ShowCursor;
Priority(0);





%% =========================================================
% LOCAL FUNCTIONS (keep at bottom of script)
%% =========================================================

function safe_abort_and_save(p,t)
    if ~isfield(p,'dataDir') || isempty(p.dataDir)
        p.dataDir = pwd;
    end
    if ~exist(p.dataDir,'dir'); mkdir(p.dataDir); end

    filename = sprintf('sub%03d_sess%02d_run%02d_ABORTED.mat',p.SUBJECT,p.SESSION,p.RUN);
    outfile = fullfile(p.dataDir, filename);

    %% ===============================
    % STOP EYELINK SAFELY
    %% ===============================
    if isfield(p,'EYE_TRACKING') && p.EYE_TRACKING

        try
            Eyelink('StopRecording');
        catch
        end

        try
            Eyelink('CloseFile');
        catch
        end

        try
            Eyelink('ReceiveFile',[p.et_fn '.edf'], ...
                fullfile(p.dataDir,[p.et_fn '_ABORTED.edf']));
        catch
            fprintf('Could not retrieve EDF file.\n');
        end

        try
            Eyelink('ShutDown');
        catch
        end
    end

    % close any open textures if present
    if isfield(p,'tex') && ~isempty(p.tex)
        try
            Screen('Close',p.tex(~isnan(p.tex)));
        catch
        end
    end

    save(outfile,'p','t');     % SAVE BEHAVIOR DATA

    Screen('CloseAll');     % CLOSE SCREEN
    ShowCursor;
    Priority(0);

    fprintf('ESC pressed: saved %s\n', outfile);
end

function [resp, ts] = checkForResp(possResp, escapeKey)
    resp = 0;
    ts = NaN;

    [keyIsDown, secs, keyCode] = KbCheck(-1);

    if ~keyIsDown
        return
    end

    keysPressed = find(keyCode);

    % ESC has priority
    if any(keysPressed == escapeKey)
        resp = -1;
        ts = secs;
        return
    end

    if nargin >= 1 && ~isempty(possResp)
        if any(keysPressed == possResp)
            resp = keysPressed(1);
            ts = secs;
        end
    end
end

function drawFixation(w, p)
    % Draw a multi-layer fixation point as described
    % % Outer dot (thicker, fix_color)
    % Screen('DrawDots', w, [0;0], p.fix_size_out * p.ppd * 2 + p.fix_pen, p.fix_color, p.center, 2);
    % % Inner dot (background color, slightly smaller)
    % Screen('DrawDots', w, [0;0], p.fix_size_out * p.ppd * 2 - p.fix_pen, p.bg_color, p.center, 2);
    % % Innermost dot (fix_color, smaller)
    % Screen('DrawDots', w, [0;0], p.fix_size_in * p.ppd * 2, p.fix_color, p.center, 2);

    % % Outer dot (thicker, fix_color)
    % Screen('DrawDots', w, [0;0], p.fix_size_out * p.ppd, p.fix_color * 0.8, p.center, 3);
    % % Inner dot (background color, slightly smaller)
    % Screen('DrawDots', w, [0;0], p.fix_size_out * p.ppd * 0.9, p.bg_color, p.center, 3);
    % % Innermost dot (fix_color, smaller)
    % Screen('DrawDots', w, [0;0], p.fix_size_in * p.ppd , p.fix_color * 0.8, p.center, 3);


    % Semi-transparent red fixation dot with black border.
    % PTB alpha blending must be enabled in the main script.

    outerDiam = p.fix_diam_pix;
    innerDiam = max(1, outerDiam - 2*p.fix_border_pix);

    % black border
    Screen('DrawDots', w, [0;0], outerDiam, p.fix_border_col, p.center, 2);

    % red center with 50% opacity
    Screen('DrawDots', w, [0;0], innerDiam, [p.fix_color p.fix_alpha], p.center, 2);
end