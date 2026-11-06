#!/bin/bash
# QUI smoke test, local Docker setup: build the single-point inputs and create a one-day case.
# Usage from the Mac host:
#   docker run -it --rm -v "$PWD:/work" elm-local bash
#   bash /work/ELM_Wet/sol/qui_smoke_setup.sh
# Then build and run inside the same container:
#   cd /work/cases/qui_smoke && ./case.build && ./case.submit

set -euo pipefail
export USER=${USER:-root}

W=/work
E3SM_SRC=$W/ELM_Wet
DIN=$W/inputs/scratch/jmarindi/elm_work/e3sm_inputdata
SITE=1x1pt_PE-QFR
CASE=$W/cases/qui_smoke
GSURF=$DIN/lnd/clm2/surfdata_map/surfdata_0.5x0.5_simyr2000_c200624.nc
WETSURF=$DIN/lnd/clm2/surfdata_map/surfdata_${SITE}_wet_simyr2000.nc
FORC=$W/CLM_SPRUCE/inputdata/atm/datm7/CLM1PT_data/2x1pt_PE-QFR

[ -d "$E3SM_SRC/cime" ] || { echo "ERROR: ELM_Wet source not found at $E3SM_SRC"; exit 1; }
[ -f "$FORC/2019-12.nc" ] || { echo "ERROR: tower forcing not found in $FORC"; exit 1; }
python3 -c "import netCDF4" || { echo "ERROR: python netCDF4 missing; rebuild the elm-local image"; exit 1; }

# Prefer the original global source. The staged local inputs also include the exact QUI cell used to create the
# wetland file; make_qui_e3sm_inputs.py can turn that 1x1 file back into the non-wetland SP smoke-test surface.
if [ -s "$GSURF" ]; then
  SURF_SOURCE=$GSURF
elif [ -s "$WETSURF" ]; then
  SURF_SOURCE=$WETSURF
  echo "== global surface file absent; rebuilding the SP surface from staged QUI cell $WETSURF"
else
  echo "ERROR: neither the global surface file nor the staged QUI surface file exists"
  exit 1
fi

python3 "$E3SM_SRC/sol/make_qui_e3sm_inputs.py" --surf "$SURF_SOURCE" --forc "$FORC" --out "$DIN"

rm -rf "$CASE" "$W/runs/qui_smoke"
"$E3SM_SRC/cime/scripts/create_newcase" --case "$CASE" --res ELM_USRDAT \
  --compset 2000_DATM%1PT_ELM%SP_SICE_SOCN_SROF_SGLC_SWAV \
  --machine local --compiler gnu --mpilib mpich

cd "$CASE"
./xmlchange NTASKS=1,NTHRDS=1,ROOTPE=0
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
cat > user_nl_datm <<EOD
 taxmode = 'cycle', 'cycle', 'cycle'
EOD

./case.setup
./preview_namelists
grep -q "taxmode *= *'cycle'" CaseDocs/datm_in || {
  echo "ERROR: datm taxmode is not cycle"
  grep -i taxmode CaseDocs/datm_in
  exit 1
}
echo "== datm streams:"
grep -h -A1 "streams" CaseDocs/datm_in | head -6
if ! ./check_input_data; then
  echo "== downloading only the inputs reported missing for this ELM_USRDAT case"
  ./check_input_data --download
fi
./check_input_data
echo "== inputs complete; next: cd $CASE && ./case.build && ./case.submit"
