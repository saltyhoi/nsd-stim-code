# fMRI Preprocessing Pipeline (Functional Space, Block-wise)

## Overview
This pipeline converts raw scanner data into analysis-ready functional data in a consistent coordinate system.

**Core workflow:**  
DICOM → NIfTI → organize → bias correction → distortion correction → motion correction → align → register → mask → validate  

**Goal:**  
Produce clean, aligned 4D functional data where:
- all runs are geometrically consistent
- anatomy and function are aligned
- distortion and motion artifacts are corrected
- noisy/unreliable voxels are removed  

---

## Key Design Principles

• Distortion correction is applied **per acquisition block (AP/PA pairs)**  
• Motion correction is applied **within each run**  
• Alignment uses **mean EPI after correction (NOT raw mean, NOT SE target)**  

---

## Acquisition Structure (Important)

Data are collected in repeating blocks:

(AP1, PA1) → run01, run02  
(AP2, PA2) → run03, run04  
(AP3, PA3) → run05, run06  

Each AP/PA pair is used to correct the two runs that follow.

---

## Pipeline Summary (Conceptual)

| Step | Purpose |
|------|--------|
| Convert | DICOM → NIfTI |
| Organize | Sort functional runs |
| Bias Correct | Fix coil intensity inhomogeneity |
| Distortion Correct | Remove EPI warping (AP/PA) |
| Motion Correct | Align volumes within runs |
| Reference | Create mean corrected EPI |
| Register | Align anatomy to functional |
| Mask | Remove non-brain + noisy voxels |
| Validate | Ensure data integrity |

---

## Directory Structure

```
nsd_3T_recognition/
├── rawscans/
│   └── study_XXXX/
├── sub044/
│   ├── anat01_orig/
│   └── func/
```

## Later implementation
```Bash
SUBJ=sub044
BASE=~/labshare/projects/nsd_3T_recognition/${SUBJ}

align_epi_anat.py \
-anat ${BASE}/anat01_orig/T1.nii.gz \
-epi ${BASE}/func/mean_epi_ref.nii.gz \
...
```

---

## Step-by-Step Pipeline

### 1. Copy Data from BIC Server
```
ssh sprague@bicdcm.bic.ucsb.edu  
cd mri  
ls  
```
Find your study folder:  
```Bash
ls -ltr | grep study_2026XXXX_
```
Copy to compute server:  
```Bash
scp -r study_XXXX PSYCH-ADS\\dongwooklim@tcs-compute-1.psych.ucsb.edu:~/labshare/projects/nsd_3T_recognition/rawscans/
```

---
### 2. Convert DICOM → NIfTI ⚠️
```Bash
cd ~/labshare/projects/nsd_3T_recognition/rawscans/  
cd study_XXXX  
```
Create ouput directory:
```Bash
mkdir -p ~/labshare/projects/nsd_3T_recognition/sub044/anat01_orig  
```
Convert:
```Bash
dcm2niix_afni \
  -o ~/labshare/projects/nsd_3T_recognition/sub044/anat01_orig \
  -z y \
  -f %t_%p_%s \
  ./
```

---
### 3. Organize Functional Runs ⚠️
```Bash
mkdir -p ~/labshare/projects/nsd_3T_recognition/sub044/func  
cd ~/labshare/projects/nsd_3T_recognition/sub044/func  
```
3b. Rename and Prepare Inputs

OPTIONAL: Manually

Copy bias field scans
```commandline
cp ../anat01_orig/*BIAS_HeadCoil*.nii.gz head_receive_field.nii.gz
cp ../anat01_orig/*BIAS_BodyCoil*.nii.gz body_receive_field.nii.gz
```
Rename distortion (AP/PA) pairs (Example)
```commandline
cp ../anat01_orig/*SE_DISTORTION_AP_11.nii.gz blip_for1.nii.gz
cp ../anat01_orig/*SE_DISTORTION_PA_12.nii.gz blip_rev1.nii.gz

cp ../anat01_orig/*SE_DISTORTION_AP_13.nii.gz blip_for2.nii.gz
cp ../anat01_orig/*SE_DISTORTION_PA_15.nii.gz blip_rev2.nii.gz
```

Rename EPI runs (Example):
```commandline
cp ../anat01_orig/*mbepi*_PA_9.nii.gz run01.nii.gz
cp ../anat01_orig/*mbepi*_PA_10.nii.gz run02.nii.gz
```
Note: Scanner-generated filenames are not used directly in the pipeline.  
All inputs must be renamed to standardized names (`runXX`, `blip_forX`, `blip_revX`, etc.) before preprocessing.


MUCH EASIER WAY: AUTOMATED
```commandline
cat > prepare_inputs.sh <<'EOF'
#!/bin/bash
set -euo pipefail

SRC="../anat01_orig"

# bias fields
cp "$SRC"/*BIAS_HeadCoil*.nii.gz head_receive_field.nii.gz
cp "$SRC"/*BIAS_BodyCoil*.nii.gz body_receive_field.nii.gz

# T1: pick the first MPRAGE by acquisition order
t1file=$(ls "$SRC"/*T1_MPRAGE*.nii.gz | sort -V | head -n 1)
cp "$t1file" T1.nii.gz

# rename only REAL EPI runs (exclude 1-volume junk)
i=1
for f in $(ls "$SRC"/*mbepi*.nii.gz | sort -V); do
  nv=$(3dinfo -nv "$f")
  if [[ "$nv" -gt 1 ]]; then
    cp "$f" "$(printf 'run%02d.nii.gz' "$i")"
    i=$((i+1))
  fi
done

# rename AP distortion scans in acquisition order
i=1
for f in $(ls "$SRC"/*SE_DISTORTION_AP*.nii.gz | sort -V); do
  cp "$f" "$(printf 'blip_for%d.nii.gz' "$i")"
  i=$((i+1))
done

# rename PA distortion scans in acquisition order
i=1
for f in $(ls "$SRC"/*SE_DISTORTION_PA*.nii.gz | sort -V); do
  cp "$f" "$(printf 'blip_rev%d.nii.gz' "$i")"
  i=$((i+1))
done

echo
echo "Created:"
ls -1 run*.nii.gz blip_for*.nii.gz blip_rev*.nii.gz head_receive_field.nii.gz body_receive_field.nii.gz T1.nii.gz
EOF
```
Run:
```commandline
chmod +x prepare_inputs.sh
./prepare_inputs.sh
```

---

### 4. Bias Correction
Apply to all runs and AP/PA images.
```Bash
#cd $DATAROOT/$EXPTDIR/$SUBJ/$SESS
cd ~/labshare/projects/nsd_3T_recognition/sub044/func

FUNCPREFIX=run
BLIPPREFIX=blip_

# Create a mask from the head receive field image
3dAutomask -prefix head_mask.nii.gz -clfrac 0.3 -overwrite head_receive_field.nii.gz

# Compute masked bias field: head / body
3dcalc \
  -a head_receive_field.nii.gz \
  -b body_receive_field.nii.gz \
  -c head_mask.nii.gz \
  -prefix bias_field_masked.nii.gz \
  -expr '((a*c)/(b*c))'

# Smooth the bias field
3dBlurToFWHM \
  -input bias_field_masked.nii.gz \
  -prefix bias_field_blur15.nii.gz \
  -FWHM 15 \
  -mask head_mask.nii.gz \
  -overwrite

# Resample bias field into functional space using first EPI volume as reference
3dAllineate \
  -1Dmatrix_save bias2func.1D \
  -source body_receive_field.nii.gz \
  -base run01.nii*[0] \
  -master BASE \
  -prefix body_receive_field_al.nii.gz

3dAllineate \
  -1Dmatrix_apply bias2func.1D \
  -source bias_field_blur15.nii.gz \
  -base run01.nii*[0] \
  -master BASE \
  -prefix bias_al.nii.gz \
  -overwrite

3dAllineate \
  -1Dmatrix_apply bias2func.1D \
  -source head_mask.nii.gz \
  -base run01.nii*[0] \
  -master BASE \
  -prefix mask_al.nii.gz \
  -overwrite

# Make lists of EPI runs and blip images
rm -f ./bc_func_list.txt
for FUNC in ${FUNCPREFIX}*.nii*; do
  printf "%s\n" $FUNC | cut -f -1 -d . >> ./bc_func_list.txt
done

rm -f ./bc_blip_list.txt
for BLIP in ${BLIPPREFIX}*.nii*; do
  printf "%s\n" $BLIP | cut -f -1 -d . >> ./bc_blip_list.txt
done

# Apply bias correction to EPI runs
CORES=$(cat ./bc_func_list.txt | wc -l)
cat ./bc_func_list.txt | parallel -P $CORES \
3dcalc -a {}.nii* -b bias_al.nii.gz -c mask_al.nii.gz \
-prefix {}_bc.nii.gz -expr "'c*(a/b)'" -overwrite

# Apply bias correction to AP/PA distortion images
CORES=$(cat ./bc_blip_list.txt | wc -l)
cat ./bc_blip_list.txt | parallel -P $CORES \
3dcalc -a {}.nii* -b bias_al.nii.gz -c mask_al.nii.gz \
-prefix {}_bc.nii.gz -expr "'c*(a/b)'" -overwrite
```

Verify the number of runs
```commandline
ls run*_bc.nii.gz | wc -l
ls blip_for*_bc.nii.gz | wc -l
ls blip_rev*_bc.nii.gz | wc -l
```
Check the run lengths:
```commandline
3dinfo -nv run*.nii.gz
```
Check the distortion files:
```commandline
3dinfo -nv blip_for*.nii.gz blip_rev*.nii.gz
```

---

### 5. Distortion + Motion Correction (Block-wise) ⚠️

(AP_k, PA_k) → runA, runB  

Outputs: run*_mcuw.nii.gz

5a. Create the block-mapping ```.txt``` file
```Bash
cat > distortion_blocks.txt <<'EOF'
1,01,02
2,03,04
3,05,06
4,07,08
5,09,10
EOF
```
5b. Optional: Create a script (if not already created)
```Bash
cat > run_block_preproc.sh <<'EOF'
#!/bin/bash
set -euo pipefail

BLOCKFILE="${1:-distortion_blocks.txt}"

if [[ ! -f "$BLOCKFILE" ]]; then
  echo "Block file not found: $BLOCKFILE"
  exit 1
fi

while IFS=',' read -r PAIR STARTRUN ENDRUN; do
  [[ -z "$PAIR" ]] && continue

  BLOCK=$(printf "block%02d" "$PAIR")
  AP=$(printf "blip_for%s_bc.nii.gz" "$PAIR")
  PA=$(printf "blip_rev%s_bc.nii.gz" "$PAIR")

  RUNS=()
  for r in $(seq $((10#$STARTRUN)) $((10#$ENDRUN))); do
    RUNS+=("$(printf "run%02d_bc.nii.gz" "$r")")
  done

  echo "======================================="
  echo "Processing $BLOCK"
  echo "AP: $AP"
  echo "PA: $PA"
  echo "RUNS: ${RUNS[*]}"
  echo "======================================="

  [[ -f "$AP" ]] || { echo "Missing $AP"; exit 1; }
  [[ -f "$PA" ]] || { echo "Missing $PA"; exit 1; }
  for f in "${RUNS[@]}"; do
    [[ -f "$f" ]] || { echo "Missing $f"; exit 1; }
  done

  afni_proc.py \
    -subj_id "${BLOCK}" \
    -dsets "${RUNS[@]}" \
    -blocks volreg \
    -volreg_align_to MIN_OUTLIER \
    -blip_forward_dset "$AP" \
    -blip_reverse_dset "$PA" \
    -blip_opts_qw -noXdis -noZdis \
    -script "proc_${BLOCK}.tcsh" \
    -out_dir "${BLOCK}.results"

  tcsh -xef "proc_${BLOCK}.tcsh" | tee "output_${BLOCK}.txt"

  cp "${BLOCK}.results/dfile_rall.1D" "motion_${BLOCK}.1D"

  IDX=1
  for r in $(seq $((10#$STARTRUN)) $((10#$ENDRUN))); do
    OUTRUN=$(printf "run%02d_mcuw.nii.gz" "$r")
    INRUN=$(printf "pb02.%s.r%02d.volreg+orig" "$BLOCK" "$IDX")
    3dcopy "${BLOCK}.results/${INRUN}" "$OUTRUN"
    IDX=$((IDX+1))
  done

done < "$BLOCKFILE"
EOF
```
Make it executable:
```Bash
chmod +x run_block_preproc.sh
```
5c. Now Run it:
- Each AP/PA pair is applied only to the runs within its block; distortion correction is not shared across blocks.
```Bash
./run_block_preproc.sh distortion_blocks.txt
```

---

### 6. Create Mean Corrected EPI Reference
```Bash
3dTstat -mean -prefix mean_epi_ref.nii.gz run*_mcuw.nii.gz
```

---

### 7. Align Anatomy to Functional Space
```Bash
align_epi_anat.py \
-anat T1.nii.gz \
-epi mean_epi_ref.nii.gz \
-anat2epi \
-epi_base 0 \
-giant_move \
-suffix _al \
-volreg off \
-tshift off
```
output:
```commandline
T1_al+orig
```
```commandline
3dcopy T1_al+orig T1_to_func.nii.gz
```
output:
```bash
T1_to_func.nii.gz
```
---

### 8. Create Masks
**Brain Mask:**

Step 1: Create a brain mask from the mean functional image 
- Identifies voxels that likely belong to the brain
- Output is a binary mask: 1 = brain, 0 = non-brain
- Uses a relatively liberal threshold (keeps most cortex)
```Bash
3dAutomask -prefix brainmask.nii.gz mean_epi_ref.nii.gz
```

**Valid Voxel Mask:**

Step 2: Compute the minimum signal value for each voxel across all runs
- For each voxel, find the lowest value it ever takes across time and runs
- Voxels that drop to 0 (or near 0) likely indicate:
  - signal dropout
  - missing data due to motion or coverage issues
- Output: a volume where each voxel = its minimum observed signal


Step 3: Create a "valid voxel" mask based on signal presence AND brain location
- step(a): returns 1 if voxel value > 0, otherwise 0
  - → marks voxels that ALWAYS had signal (never dropped to 0)
- Multiply by brainmask (b):
  - → ensures voxel is inside the brain
- Final mask keeps only voxels that:
  - (1) are in the brain AND
  - (2) have valid signal across all runs
- Output is a binary mask: 1 = valid voxel, 0 = invalid
```Bash
3dTcat -prefix all_runs_mcuw.nii.gz run*_mcuw.nii.gz
3dTstat -min -prefix minval.nii.gz all_runs_mcuw.nii.gz
```
```
3dcalc -a minval.nii.gz -b brainmask.nii.gz \
-expr 'step(a)*b' \
-prefix valid.nii.gz
```
```commandline
rm -f all_runs_mcuw.nii.gz
```
 

---

## Output Files

- run*_mcuw.nii.gz → corrected functional runs
- mean_epi_ref.nii.gz → alignment reference
- T1_to_func.nii.gz → aligned anatomy
- brainmask.nii.gz → brain mask
- valid.nii.gz → reliable voxels
- motion.1D → motion parameters

---
## Visual Quality Check
```Bash
afni mean_epi_ref.nii.gz T1_to_func.nii.gz brainmask.nii.gz &
```
```commandline
afni mean_epi_ref.nii.gz T1_to_func.nii.gz valid.nii.gz &
```
---
## Final Output
Data is ready for:
- GLM modeling
- decoding analyses
- ROI analysis
