# fMRI Preprocessing Pipeline (NSD-style, Functional Space)

## Overview
This pipeline converts raw scanner data into analysis-ready functional data in a consistent coordinate system.

**Core workflow:**
DICOM → NIfTI → organize runs → align → register → mask → validate

**Goal:**
Produce clean, aligned 4D functional data where:
• all runs are consistent  
• anatomy and function are aligned  
• noisy/unreliable voxels are removed  

---

## Pipeline Summary (Conceptual)

| Step | Purpose |
|------|--------|
| Convert | DICOM → NIfTI |
| Organize | Sort functional runs |
| Align | Create stable reference (mean image) |
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

---

## Step-by-Step Pipeline

### 1. Copy Data from BIC Server

```bash
ssh sprague@bicdcm.bic.ucsb.edu
cd mri
ls
```

Find your study folder:
```bash
ls -ltr | grep study_2026XXXX_
```

Copy to compute server:
```bash
scp -r study_XXXX PSYCH-ADS\\dongwooklim@tcs-compute-1.psych.ucsb.edu:~/labshare/projects/nsd_3T_recognition/rawscans/
```

---

### 2. Convert DICOM → NIfTI

```bash
cd ~/labshare/projects/nsd_3T_recognition/rawscans/
cd study_20260311_101041.737000_11mar26_707540
```

Create output directory:
```bash
mkdir -p ~/labshare/projects/nsd_3T_recognition/sub044/anat01_orig
```

Convert:
```bash
dcm2niix_afni \
  -o ~/labshare/projects/nsd_3T_recognition/sub044/anat01_orig \
  -z y \
  -f %t_%p_%s \
  ./
```

---

### 3. Organize Functional Runs

```bash
mkdir -p ~/labshare/projects/nsd_3T_recognition/sub044/func
cd ~/labshare/projects/nsd_3T_recognition/sub044/func
```

---

### 4. Create Mean Functional Image

```bash
3dTstat -mean -prefix mean.nii.gz run*.nii.gz
```

---

### 5. Align Anatomy to Functional Space

```bash
# Align anatomical (T1) image to functional (EPI) space
# • This computes a transformation so the T1 matches the EPI geometry
# • Output will be an aligned anatomical volume (T1_al.nii.gz)

align_epi_anat.py \
-anat anat01_orig/T1.nii.gz \
-epi func/mean.nii.gz \
-anat2epi \
-epi_base 0 \
-suffix _al \
-volreg off \
-tshift off
```

---

### 6. Create Masks

```bash
3dAutomask -prefix brainmask.nii.gz mean.nii.gz
3dTstat -min -prefix minval.nii.gz run*.nii.gz
3dcalc -a minval.nii.gz -b brainmask.nii.gz -expr 'step(a)*b' -prefix valid.nii.gz
```
```bash
# Step 1: Create a brain mask from the mean functional image
# • Identifies voxels that likely belong to the brain
# • Output is a binary mask: 1 = brain, 0 = non-brain
# • Uses a relatively liberal threshold (keeps most cortex)
3dAutomask -prefix brainmask.nii.gz mean.nii.gz


# Step 2: Compute the minimum signal value for each voxel across all runs
# • For each voxel, find the lowest value it ever takes across time and runs
# • Voxels that drop to 0 (or near 0) likely indicate:
#     - signal dropout
#     - missing data due to motion or coverage issues
# • Output: a volume where each voxel = its minimum observed signal
3dTstat -min -prefix minval.nii.gz run*.nii.gz


# Step 3: Create a "valid voxel" mask based on signal presence AND brain location
# • step(a): returns 1 if voxel value > 0, otherwise 0
#     → marks voxels that ALWAYS had signal (never dropped to 0)
# • Multiply by brainmask (b):
#     → ensures voxel is inside the brain
# • Final mask keeps only voxels that:
#     (1) are in the brain AND
#     (2) have valid signal across all runs
# • Output is a binary mask: 1 = valid voxel, 0 = invalid
3dcalc -a minval.nii.gz -b brainmask.nii.gz -expr 'step(a)*b' -prefix valid.nii.gz
```


---

## Output Files

• run*.nii.gz → functional time series  
• mean.nii.gz → mean functional image  
• T1_to_func.nii.gz → aligned anatomy  
• brainmask.nii.gz → brain mask  
• valid.nii.gz → reliable voxels  

---

## Visual Quality Check

```bash
afni mean.nii.gz T1_to_func.nii.gz brainmask.nii.gz &
```

Check:
• alignment  
• mask coverage  
• motion artifacts  
• voxel quality  

---

## Final Output

Data is ready for:
• GLM modeling  
• decoding analyses  
• ROI analysis  

## Relation to NSD Preprocessing Pipeline

This pipeline follows the general philosophy of the Natural Scenes Dataset (NSD) preprocessing workflow (Allen et al., 2022; Kay et al., 2019), particularly in constructing functional-space outputs.

### Similarities
• Functional-space alignment: anatomical images are aligned to EPI space (`T1_to_func.nii.gz`)
• Liberal brain masking using AFNI (`3dAutomask`)
• Separation of:
  - anatomical mask (`brainmask.nii.gz`)
  - data validity mask (`valid.nii.gz`)
• Use of mean functional image (`mean.nii.gz`) as a stable reference

### Differences
• Single-resolution processing (NSD provides 1mm and 1.8mm outputs)
• Binary validity mask (NSD uses fractional validity across sessions)
• No signal dropout maps (`signaldropout.nii.gz`)
• No surface-based processing (FreeSurfer not included)

This pipeline can be considered a simplified “NSD-style” preprocessing workflow focused on functional-space analyses.


## References

Allen, E. J., et al. (2022). A massive 7T fMRI dataset to bridge cognitive neuroscience and artificial intelligence. *Nature Neuroscience*, 25, 116–126.

Kay, K. N., et al. (2019). A critical assessment of data quality and venous effects in submillimeter fMRI. *NeuroImage*, 189, 847–869.

NSD Dataset:
https://naturalscenesdataset.org/

NSD Data Manual:
https://cvnlab.slite.page/p/CT9Fwl4_hc/NSD-Data-Manual
