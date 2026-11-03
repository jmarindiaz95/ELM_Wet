#!/bin/bash
# QUI smoke test, step 1 (login node): build the single-point inputs, create a 1-day case, download the few
# global files it still needs (parameters, snow optics, aerosol and topography streams).
# ELM satellite phenology (SP), tower forcing, no river model. Unmodified ELM-Wet code, no wetland landunit yet.
# Usage:  bash /scratch/jmarindi/elm_work/ELM_Wet/sol/qui_smoke_setup.sh   then   sbatch .../sol/smoke_build_run.sh qui_smoke
source /scratch/$USER/elm_work/ELM_Wet/sol/e3sm_env.sh
W=/scratch/$USER/elm_work
DIN=$W/e3sm_inputdata
SITE=1x1pt_PE-QFR
CASE=$W/e3sm_cases/qui_smoke
GSURF=$DIN/lnd/clm2/surfdata_map/surfdata_0.5x0.5_simyr2000_c200624.nc
FORC=$W/CLM_SPRUCE/inputdata/atm/datm7/CLM1PT_data/2x1pt_PE-QFR
[ -s $GSURF ] || { echo "ERROR: global surface file not downloaded yet: $GSURF"; exit 1; }
[ -f $FORC/2019-12.nc ] || { echo "ERROR: tower forcing not found in $FORC (git pull in CLM_SPRUCE?)"; exit 1; }
python3 -c "import netCDF4" || { echo "ERROR: python netCDF4 missing (mamba install into conda_perl)"; exit 1; }

python3 $E3SM_SRC/sol/make_qui_e3sm_inputs.py --surf $GSURF --forc $FORC --out $DIN || exit 1

rm -rf $CASE $W/e3sm_runs/qui_smoke
$E3SM_SRC/cime/scripts/create_newcase --case $CASE --res ELM_USRDAT \
   --compset 2000_DATM%1PT_ELM%SP_SICE_SOCN_SROF_SGLC_SWAV \
   --machine sol --compiler intel --mpilib impi --queue htc --walltime 01:00:00 || exit 1
cd $CASE
./xmlchange NTASKS=1,NTHRDS=1,ROOTPE=0
# Slurm account: CIME otherwise passes the placeholder 'PROJECT' to sbatch --account
ACCT=$(sacctmgr -nP show assoc user=$USER format=account | head -1)
[ -n "$ACCT" ] && ./xmlchange PROJECT=$ACCT && echo "== Slurm account: $ACCT"
./xmlchange ELM_USRDAT_NAME=$SITE
./xmlchange ATM_DOMAIN_PATH=$DIN/share/domains/domain.clm,LND_DOMAIN_PATH=$DIN/share/domains/domain.clm
./xmlchange ATM_DOMAIN_FILE=domain.lnd.$SITE.nc,LND_DOMAIN_FILE=domain.lnd.$SITE.nc
./xmlchange DATM_CLMNCEP_YR_START=2018,DATM_CLMNCEP_YR_END=2019,DATM_CLMNCEP_YR_ALIGN=2018
./xmlchange RUN_STARTDATE=2018-01-01,STOP_OPTION=ndays,STOP_N=1,DOUT_S=FALSE,PIO_TYPENAME=netcdf
cat > user_nl_elm <<EON
 fsurdat = '$DIN/lnd/clm2/surfdata_map/surfdata_${SITE}_simyr2000.nc'
 hist_nhtfrq = -24
 hist_mfilt = 1
EON
./case.setup || exit 1
./preview_namelists || { echo "== preview_namelists FAILED"; exit 1; }
echo "== datm streams:"; grep -h -A1 "streams" CaseDocs/datm_in | head -6
./check_input_data --download
./check_input_data && echo "== inputs complete; next: sbatch $E3SM_SRC/sol/smoke_build_run.sh qui_smoke"
