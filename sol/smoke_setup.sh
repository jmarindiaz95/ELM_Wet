#!/bin/bash
# Step 1 of the E3SM smoke test (login node: creates the case and downloads its small input set).
# Standard E3SM 1-day single-point test case: 1x1_brazil grid, IELM compset (satellite phenology), 1 task.
# Usage:  bash /scratch/jmarindi/elm_work/ELM_Wet/sol/smoke_setup.sh   then   sbatch .../sol/smoke_build_run.sh
source /scratch/$USER/elm_work/ELM_Wet/sol/e3sm_env.sh
CASE=/scratch/$USER/elm_work/e3sm_cases/smoke_brazil
mkdir -p /scratch/$USER/elm_work/e3sm_cases /scratch/$USER/elm_work/e3sm_inputdata
rm -rf $CASE /scratch/$USER/elm_work/e3sm_runs/smoke_brazil
$E3SM_SRC/cime/scripts/create_newcase --case $CASE --res 1x1_brazil --compset IELM \
   --machine sol --compiler intel --mpilib impi --queue htc --walltime 01:00:00 || exit 1
cd $CASE
./xmlchange NTASKS=1,NTHRDS=1,ROOTPE=0
./xmlchange STOP_OPTION=ndays,STOP_N=1,DOUT_S=FALSE,PIO_TYPENAME=netcdf
./case.setup || exit 1
./check_input_data --download
./check_input_data && echo "== inputs complete; next: sbatch $E3SM_SRC/sol/smoke_build_run.sh"
