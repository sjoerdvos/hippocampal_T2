#!/bin/bash

#
# Script to calculate global hippocampal T2 values from hippocampal segmentation on 3D-T1 images
# Input:
# -T1     - 3D T1 image used for hippocampal segmentation (REQUIRED)
# -seg_L  - Left hippocampal segmentation (REQUIRED)
# -seg_R  - Right hippocampal segmentation (REQUIRED)
# -T2map  - T2 map, in ms (REQUIRED)
# -out    - output directory (OPTIONAL - default is current PWD)
# -tmp    - temporary directory to store intermediate files (OPTIONAL - default is same a subfolder in out)
# -T2_thr - T2 value (in ms) used as cut-off to minimise CSF contamination (as detailed in GP Winston et al., ISMRM 2017)
# -vis    - give this input if you want to visualise the final segmentations over the T2 map
#
#
# -- BSD 3-Clause License --
# Copyright (c) 2017, University College London, United Kingdom
# Contributors: Sjoerd B. Vos & Gavin P. Winston
# Citation:     "Automated hippocampal T2 relaxometry". ISMRM, Honolulu, Hawaii, United States, 2017, p2421.
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 



# Specify which registration software you want to use:
# - FSL's flirt
# - NiftyReg, using scale factor point spread function resampling
reg_fsl=0
# Default interpolation from niftyreg is using scale factor point spread function resampling: http://link.springer.com/chapter/10.1007/978-3-319-24571-3_81
do_psf=1

# Set binarisation threshold
bin_thr=0.95
# Set default visualisation to off
do_vis=0


# Define and set up FSL: https://fsl.fmrib.ox.ac.uk/fsl/fslwiki
export FSLDIR=/usr2/mrtools/fsl-5.0.9
export PATH=${FSLDIR}/bin:${PATH}
export FSLOUTPUTTYPE=NIFTI_GZ
. ${FSLDIR}/etc/fslconf/fsl.sh

# Set path to NiftyReg: https://sourceforge.net/projects/niftyreg/
NIFTYREG_PATH=/data/p1502hippoT2/software/niftyreg-build/reg-apps

# Set upper threshold for T2 - any voxels with higher T2 will be removed to limit CSF-contamination
T2_CSF_thr=170


# Check inputs
if [ $# -eq 0 ] ; then
  correct_input=0

else
  correct_input=1

  # Remove the first argument (this shell's name)
  i=0
  for var in "$@"
  do
    args[$i]=$var
    let i=$i+1
  done

  # Loop over arguments to find all options
  args=("$@")
  i=0
  while [ $i -lt $# ]
  do
    if [ ${args[i]} = "-T1" ] ; then
      let i=$i+1
      T1_img=${args[i]}
    elif [ ${args[i]} = "-T2map" ] ; then
      let i=$i+1
      T2_map=${args[i]}
    elif [ ${args[i]} = "-seg_L" ] ; then
      let i=$i+1
      hippo_l=${args[i]}
    elif [ ${args[i]} = "-seg_R" ] ; then
      let i=$i+1
      hippo_r=${args[i]}
    elif [ ${args[i]} = "-out" ] ; then
      let i=$i+1
      out_dir=${args[i]}
    elif [ ${args[i]} = "-tmp" ] ; then
      let i=$i+1
      tmp_dir=${args[i]}
    elif [ ${args[i]} = "-T2_thr" ] ; then
      let i=$i+1
      T2_CSF_thr=${args[i]}
    elif [ ${args[i]} = "-vis" ] ; then
      do_vis=1
    fi
    let i=$i+1
  done

  # Check if user gave all required inputs
  if ( [ -z ${T1_img} ] || [ -z ${T2_map} ] || [ -z ${hippo_l} ] || [ -z ${hippo_r} ] ) ; then
    echo ""
    echo "Not all required inputs are set..."
    correct_input=0
  fi
  # Check if all required inputs exist
  if ( [ ! -f ${T1_img} ] || [ ! -f ${T2_map} ] || [ ! -f ${hippo_l} ] || [ ! -f ${hippo_r} ] ) ; then
    echo ""
    echo "Not all input files exist..."
    correct_input=0
  fi

fi

if [ ${correct_input} -eq 0 ] ; then
  echo ""
  echo "Please see the following options for proper use:"
  echo "-T1:    Subject's T1 MPRAGE scan (REQUIRED)"
  echo "-T2map: Subject's T2 map (REQUIRED)"
  echo "-seg_L: Left hippocampal segmentation - matching the -T1 input (REQUIRED)"
  echo "-seg_R: Right hippocampal segmentation - matching the -T1 input (REQUIRED)"
  echo "-out:   Directory where output will be saved (OPTIONAL - default is PWD)"
  echo "-tmp:   Temporary directory where calculations will be saved (OPTIONAL - default is within output directory)"
  echo "-vis:   Give this input flag if you want to visualise the final segmentations over the T2 map (OPTIONAL)"
  echo ""
  echo "e.g., hippoT2_FSL.sh -T1 my_T1.niii.gz -T2map my_T2map.nii.gz -seg_L my_left_segmentation.nii.gz -seg_R my_right_segmentation.nii.gz"
  echo ""
  exit 1
fi


##########  Define required settings  ##########

# Ensure all input files are absolute file paths
if [[ ${T1_img} != /* ]] ; then  T1_img="${PWD}/${T1_img}"; fi
if [[ ${T2_map} != /* ]] ; then  T2_map="${PWD}/${T2_map}"; fi
if [[ ${hippo_l} != /* ]] ; then  hippo_l="${PWD}/${hippo_l}"; fi
if [[ ${hippo_r} != /* ]] ; then  hippo_r="${PWD}/${hippo_r}"; fi

# Check if user gave output directory
if [ -z ${out_dir} ]; then
  out_dir=${PWD}
fi
# Ensure it's absolute path
if [[ ${out_dir} == "." ]] ; then  out_dir=${PWD}; fi
if [[ ${out_dir} != /* ]] ; then  out_dir="${PWD}/${out_dir}"; fi

# Check if user gave tmp directory
if [ -z ${tmp_dir} ]; then
  tmp_dir="${out_dir}/tmp"
else
  # Ensure it's absolute path
  if [[ ${tmp_dir} == "." ]] ; then  tmp_dir=${PWD}; fi
  if [[ ${tmp_dir} != /* ]] ; then  tmp_dir="${PWD}/${tmp_dir}"; fi
fi

# Define output file
output_file="${out_dir}/Hippocampal_T2.txt"

# Create tmp dir if it doesn't exist and go there
if [ ! -d ${tmp_dir} ] ; then
  mkdir ${tmp_dir}
fi
cd ${tmp_dir}



##########  Get hipposegs to 2D T2 map  ##########
echo -e "\nSTEP 1 - Registering T1 scan to T2 map..."

# Do bet on T1 to get brain mask
bet_name="T1_bet"
bet $T1_img $bet_name -m
brain_mask=`find ./${bet_name}*mask* -maxdepth 1 -type f -printf %f -quit`
bet_name=`find ./${bet_name}.n* -maxdepth 1 -type f -printf %f -quit`
# Erode bet_mask once
fslmaths ${brain_mask} -kernel 3D -ero ${brain_mask}

# Register rigidly (6 dof)
if [ ${reg_fsl} -eq 1 ] ; then
  flirt -in ${bet_name} -ref ${T2_map} -omat transformT1-2-T2 -dof 6 -cost normmi -searchcost normmi
else
  ${NIFTYREG_PATH}/reg_aladin -target ${T2_map} -source ${bet_name} -rigOnly -aff transformT1-2-T2 -voff
fi

# apply transformation to the hippocampal segmentations to get them in T2 space
hippo_l_T2="hippo_l_T2.nii.gz"
hippo_r_T2="hippo_r_T2.nii.gz"
if [ ${reg_fsl} -eq 1 ] ; then
  flirt -in ${hippo_l} -ref ${T2_map} -init transformT1-2-T2 -applyxfm -out ${hippo_l_T2}
  flirt -in ${hippo_r} -ref ${T2_map} -init transformT1-2-T2 -applyxfm -out ${hippo_r_T2}
else
  if [ ${do_psf} -eq 1 ] ; then
    ${NIFTYREG_PATH}/reg_resample -target ${T2_map} -source ${hippo_l} -aff transformT1-2-T2 -result ${hippo_l_T2} -voff -psf
    ${NIFTYREG_PATH}/reg_resample -target ${T2_map} -source ${hippo_r} -aff transformT1-2-T2 -result ${hippo_r_T2} -voff -psf
  else
    ${NIFTYREG_PATH}/reg_resample -target ${T2_map} -source ${hippo_l} -aff transformT1-2-T2 -result ${hippo_l_T2} -voff
    ${NIFTYREG_PATH}/reg_resample -target ${T2_map} -source ${hippo_r} -aff transformT1-2-T2 -result ${hippo_r_T2} -voff
  fi
fi


##########  Minimise CSF contamination  ##########
echo -e "\nSTEP 2 - Minimising CSF contamination..."

# Apply binarisation to interpolated binary seg
fslmaths ${hippo_l_T2} -thr ${bin_thr} -bin ${hippo_l_T2}
fslmaths ${hippo_r_T2} -thr ${bin_thr} -bin ${hippo_r_T2}

# Erode mask by one voxel, only in-plane
hippo_l_T2_ero="hippo_l_T2_eroded.nii.gz"
hippo_r_T2_ero="hippo_r_T2_eroded.nii.gz"
fslmaths ${hippo_l_T2} -kernel 2D -ero ${hippo_l_T2_ero}
fslmaths ${hippo_r_T2} -kernel 2D -ero ${hippo_r_T2_ero}

# Mask out anything with a T2 value higher than threshold defined above
fslmaths ${T2_map} -uthr ${T2_CSF_thr} -bin ${tmp_dir}/low_T2.nii.gz
fslmaths ${hippo_l_T2_ero} -mul ${tmp_dir}/low_T2.nii.gz ${hippo_l_T2_ero}
fslmaths ${hippo_r_T2_ero} -mul ${tmp_dir}/low_T2.nii.gz ${hippo_r_T2_ero}

# multiply T2 map with mask & remove NaN
T2_l=${tmp_dir}/hippo_l_T2_masked.nii.gz
T2_r=${tmp_dir}/hippo_r_T2_masked.nii.gz
fslmaths ${hippo_l_T2_ero} -mul ${T2_map} -nan ${T2_l}
fslmaths ${hippo_r_T2_ero} -mul ${T2_map} -nan ${T2_r}



##########  Generating statistics  ##########
echo -e "\nSTEP 3 - Generating statistics..."

# Get average T2 values
meanT2_L=`fslstats ${T2_l} -M`
meanT2_R=`fslstats ${T2_r} -M`

# Get ratio L/R and round to 1 decimal
T2_L_div_R=`echo "(1000*${meanT2_L}/${meanT2_R})*0.1" | bc`
T2_R_div_L=`echo "(1000*${meanT2_R}/${meanT2_L})*0.1" | bc`

# Round to 1 decimal
meanT2_L=`echo "(1000*${meanT2_L}/100)*0.1" | bc`
meanT2_R=`echo "(1000*${meanT2_R}/100)*0.1" | bc`

# Get volume of T2 mask L&R
T2vol_L=`fslstats ${T2_l} -V | awk '{print $2}'`
T2vol_R=`fslstats ${T2_r} -V | awk '{print $2}'`
# Get volume of binary HC segmentation in T2 space L&R
HCvol_L=`fslstats ${hippo_l_T2} -V | awk '{print $2}'`
HCvol_R=`fslstats ${hippo_r_T2} -V | awk '{print $2}'`
# Get volume percentage sampled, rounded to 1 decimal
L_sampled=`echo "(1000*${T2vol_L}/${HCvol_L})*0.1" | bc`
R_sampled=`echo "(1000*${T2vol_R}/${HCvol_R})*0.1" | bc`


# Create output file anew
rm -f ${output_file}
touch ${output_file}

# Write to file
echo "Files used for hippocampal T2 calculation [`date`]:" >> ${output_file}
echo "T1 image: ${T1_img}" >> ${output_file}
echo "T2 map:   ${T2_map}" >> ${output_file}
echo "Hippocampal segmentation left: ${hippo_l}" >> ${output_file}
echo "Hippocampal segmentation right: ${hippo_r}" >> ${output_file}
echo >> ${output_file}
if [ ${reg_fsl} -eq 1 ] ; then
  flirt_vers=`flirt -version`
  echo "Registration performed using FSL ${flirt_vers}" >> ${output_file}
else
  nr_vers=`${NIFTYREG_PATH}/reg_aladin --version`
  echo "Registration performed using NiftyReg (git hash: ${nr_vers})" >> ${output_file}
fi
echo >> ${output_file}
echo -e "R hippocampal T2\t${meanT2_R} ms (sampling ${R_sampled}% of hippocampal volume)" >> ${output_file}
echo -e "L hippocampal T2\t${meanT2_L} ms (sampling ${L_sampled}% of hippocampal volume)" >> ${output_file}
echo >> ${output_file}
echo -e "R:L T2 ratio\t\t${T2_R_div_L} percent" >> ${output_file}
echo -e "L:R T2 ratio\t\t${T2_L_div_R} percent" >> ${output_file}
#echo >> ${output_file}
#echo -e "Normal range based on 50 healthy controls" >> ${output_file}
#echo -e "Normal T2 range: 108.5-123.8 ms, mean+/-1.96sd, 95% confidence interval (106.1-126.2 ms for 99%)" >> ${output_file}


# Display T2 values on terminal
echo
echo "=========================================================================================="
cat ${output_file}
echo "=========================================================================================="


# Copy the segmentations in T2 space to main dir
T2_L_seg=`basename ${T2_map} | sed s/.nii/_mask_L.nii/`
T2_R_seg=`basename ${T2_map} | sed s/.nii/_mask_R.nii/`
mv ${hippo_l_T2_ero} ${out_dir}/${T2_L_seg}
mv ${hippo_r_T2_ero} ${out_dir}/${T2_R_seg}

# Go to output directory
cd ${out_dir}

# Remove unwanted tmp files
rm -r ${tmp_dir}


# View segmentations over T2 map
if [ ${do_vis} -eq 1 ] ; then
  fslview -m single ${T2_map} -b 0,300 ${T2_L_seg} -l Red -t 0.5 ${T2_R_seg} -l Red -t 0.5 &
fi


# End of hippocampal_T2.sh



