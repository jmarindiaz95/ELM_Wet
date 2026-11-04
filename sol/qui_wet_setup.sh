#!/bin/bash
# QUI ELM-Wet wetland test, step 1 (login node). 1-year cold start, BGC mode (CN + CH4), wetland landunit 100%,
# daily tower water level read from the surface file, both wetland columns broadleaf evergreen tropical tree,
# column weights 0.64 / 0.36. Checks that the wetland code, the new namelist options and the water level
# forcing run at QUI; it is not a spinup.
# Usage:  bash /scratch/jmarindi/elm_work/ELM_Wet/sol/qui_wet_setup.sh   then   sbatch .../sol/smoke_build_run.sh qui_wet
source /scratch/$USER/elm_work/ELM_Wet/sol/e3sm_env.sh
W=/scratch/$USER/elm_work
DIN=$W/e3sm_inputdata
SITE=1x1pt_PE-QFR
CNAME=qui_wet
CASE=$W/e3sm_cases/$CNAME
GSURF=$DIN/lnd/clm2/surfdata_map/surfdata_0.5x0.5_simyr2000_c200624.nc
FSRC=$W/CLM_SPRUCE/inputdata/atm/datm7/CLM1PT_data/2x1pt_PE-QFR
WTD=$FSRC/source/PE-QFR_forcing_input_2018-2019.csv.gz
[ -s $GSURF ] || { echo "ERROR: missing $GSURF"; exit 1; }
[ -f $WTD ] || { echo "ERROR: missing $WTD (git pull in CLM_SPRUCE?)"; exit 1; }

python3 $E3SM_SRC/sol/make_qui_e3sm_inputs.py --surf $GSURF --forc $FSRC --out $DIN --wtd $WTD || exit 1

rm -rf $CASE $W/e3sm_runs/$CNAME
$E3SM_SRC/cime/scripts/create_newcase --case $CASE --res ELM_USRDAT \
   --compset 2000_DATM%1PT_ELM%BGC_SICE_SOCN_SROF_SGLC_SWAV \
   --machine sol --compiler intel --mpilib impi --queue htc --walltime 02:00:00 || exit 1
cd $CASE
./xmlchange NTASKS=1,NTHRDS=1,ROOTPE=0
ACCT=$(sacctmgr -nP show assoc user=$USER format=account | head -1)
[ -n "$ACCT" ] && ./xmlchange PROJECT=$ACCT
./xmlchange ELM_USRDAT_NAME=$SITE
./xmlchange ATM_DOMAIN_PATH=$DIN/share/domains/domain.clm,LND_DOMAIN_PATH=$DIN/share/domains/domain.clm
./xmlchange ATM_DOMAIN_FILE=domain.lnd.$SITE.nc,LND_DOMAIN_FILE=domain.lnd.$SITE.nc
./xmlchange DATM_CLMNCEP_YR_START=2018,DATM_CLMNCEP_YR_END=2019,DATM_CLMNCEP_YR_ALIGN=2018
./xmlchange RUN_STARTDATE=2018-01-01,STOP_OPTION=nyears,STOP_N=1,DOUT_S=FALSE,PIO_TYPENAME=netcdf
sed -i '/--exclusive/d' env_batch.xml
cat > user_nl_elm <<EON
 fsurdat = '$DIN/lnd/clm2/surfdata_map/surfdata_${SITE}_wet_simyr2000.nc'
 read_wetl_surf_wat_elev_from_surf = .true.
 wetl_pft = 4
 wetl_col1_wt = 0.64
EON
./case.setup || exit 1
./preview_namelists || { echo "== preview_namelists FAILED"; exit 1; }
./check_input_data --download                     # default parameter file and BGC streams (ndep, fire)
PDEF=$(grep -E "^ *paramfile" CaseDocs/lnd_in | sed "s/.*= *'\(.*\)'.*/\1/")
PWET=$DIN/lnd/clm2/paramdata/clm_params_elmwet_qui.nc
echo "== default parameter file: $PDEF"
python3 $E3SM_SRC/sol/make_wet_params.py $PDEF $PWET || exit 1
cat >> user_nl_elm <<EON
 paramfile = '$PWET'
 hist_nhtfrq = 0, -24
 hist_mfilt = 1, 365
 hist_dov2xy = .true., .false.
 hist_type1d_pertape = ' ', 'COLS'
 hist_fincl2 = 'ZWT', 'H2OSFC', 'FINUNDATED', 'FCH4', 'CH4PROD', 'TSOI_10CM', 'QOVER', 'QDRAI'
EON
./preview_namelists || { echo "== preview_namelists FAILED"; exit 1; }
grep -E "wetl|paramfile|fsurdat|use_lch4" CaseDocs/lnd_in
./check_input_data --download
./check_input_data && echo "== inputs complete; next: sbatch $E3SM_SRC/sol/smoke_build_run.sh $CNAME"
