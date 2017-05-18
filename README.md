# hippocampal_T2
Automated hippocampal T2 relaxometry using hippocampal segmentation and T2 map (PAPER REFERENCE)

Script to calculate global hippocampal T2 values from hippocampal segmentation on 3D-T1 images

Input:
-T1     - 3D T1 image used for hippocampal segmentation (REQUIRED)
-seg_L  - Left hippocampal segmentation (REQUIRED)
-seg_R  - Right hippocampal segmentation (REQUIRED)
-T2map  - T2 map, in ms (REQUIRED)
-out    - output directory (OPTIONAL - default is current PWD)
-tmp    - temporary directory to store intermediate files (OPTIONAL - default is same a subfolder in out)
-T2_thr - T2 value (in ms) used as cut-off to minimise CSF contamination (as detailed in GP Winston et al., ISMRM 2017)
-vis    - give this input if you want to visualise the final segmentations over the T2 map

In the script, reg_fsl is set to the default of 0 which means that NiftyReg will be used for the registration (https://sourceforge.net/projects/niftyreg/). This is the version that was used for the paper.

If the prefer to only use FSL, then reg_fsl can be set to 1 and FSL will be used for the registrations. This is however different to the paper and may produce different results.
