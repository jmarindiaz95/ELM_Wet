#!/bin/bash
# QUI ELM-Wet diagnostic: 10 years from a cold start in normal mode, monthly output, to find why the vegetation
# collapsed in year 4 of qui_wet_ad (GPP 1890 gC m-2 yr-1 in 2020, near 0 from 2021 with LAI 0.78 and BTRAN 1).
# PFT from the first argument: 4 (broadleaf evergreen tropical tree, default) or -1 (C3 grass, published ELM-Wet).
# Usage:  bash qui_wet_diag_setup.sh 4  -> case qui_wet_diag_pft4 ;  bash qui_wet_diag_setup.sh -1 -> qui_wet_diag_grass
# Same configuration as qui_wet_setup.sh plus: hummock column 150 mm above the hollow (humhol_ht as in
# ELM-SPRUCE), water level cycled 2018-2019 with the forcing (model years start at 2018, forcing aligned to 2018).
# About 1 min per model year; restarts every 25 years. Yearly output (gridcell and per column).
# Usage:  bash /scratch/jmarindi/elm_work/ELM_Wet/sol/qui_wet_ad_setup.sh   then   sbatch .../sol/smoke_build_run.sh qui_wet_ad
source /scratch/$USER/elm_work/ELM_Wet/sol/e3sm_env.sh
W=/scratch/$USER/elm_work
DIN=$W/e3sm_inputdata
SITE=1x1pt_PE-QFR
WPFT=${1:-4}
if [ "$WPFT" = "-1" ]; then CNAME=qui_wet_diag_grass; else CNAME=qui_wet_diag_pft$WPFT; fi
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
./xmlchange RUN_STARTDATE=2018-01-01,STOP_OPTION=nyears,STOP_N=10,REST_OPTION=nyears,REST_N=5,DOUT_S=FALSE,PIO_TYPENAME=netcdf
sed -i '/--exclusive/d' env_batch.xml
cat > user_nl_elm <<EON
 fsurdat = '$DIN/lnd/clm2/surfdata_map/surfdata_${SITE}_wet_simyr2000.nc'
 read_wetl_surf_wat_elev_from_surf = .true.
 wetl_pft = $WPFT
 wetl_col1_wt = 0.64
 wetl_col1_elev_offset = 150.
 wetl_elev_yr_first = 2018
 wetl_elev_yr_last = 2019
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
 hist_nhtfrq = 0, 0, 0
 hist_mfilt = 1, 1, 1
 hist_dov2xy = .true., .false., .false.
 hist_type1d_pertape = ' ', 'COLS', 'PFTS'
 hist_fincl2 = 'ZWT', 'H2OSFC', 'FINUNDATED', 'FCH4', 'CH4PROD', 'TOTSOMC', 'TOTVEGC', 'TOTLITC', 'QDRAI', 'QOVER', 'SMINN', 'SMIN_NO3', 'SMIN_NH4', 'SMIN_NO3_LEACHED', 'H2OSOI', 'TSOI', 'FPG'
 hist_fincl3 = 'GPP', 'NPP', 'TLAI', 'ELAI', 'BTRAN', 'LEAFC', 'LEAFN', 'FROOTC', 'DEADSTEMC', 'LIVESTEMC', 'HTOP', 'FPSN', 'CPOOL', 'NPOOL', 'LEAF_MR', 'AR'
EON
./preview_namelists || { echo "== preview_namelists FAILED"; exit 1; }
grep -E "wetl|paramfile|fsurdat|use_lch4|spinup_state" CaseDocs/lnd_in

./check_input_data --download
./check_input_data && echo "== inputs complete; next: sbatch $E3SM_SRC/sol/smoke_build_run.sh $CNAME"
