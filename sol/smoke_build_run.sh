#!/bin/bash
# Step 2 of the E3SM smoke test: build on a compute node, then submit the 1-day run.
# Usage:  sbatch smoke_build_run.sh <case name under e3sm_cases> (default qui_smoke)
# Check:  cat /scratch/jmarindi/elm_work/e3sm_cases/smoke_build.log
#SBATCH --job-name=e3sm_smoke_build
#SBATCH -p htc
#SBATCH -N 1
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -t 01:30:00
#SBATCH -o /scratch/jmarindi/elm_work/e3sm_cases/smoke_build.log
source /scratch/$USER/elm_work/ELM_Wet/sol/e3sm_env.sh
CNAME=${1:-qui_smoke}
cd /scratch/$USER/elm_work/e3sm_cases/$CNAME || { echo "ERROR: case $CNAME not found (run the setup script first)"; exit 1; }
echo "source: $(cd $E3SM_SRC && git log --oneline -1)"
if ./case.build; then
  echo "== BUILD OK $(date)"
  for v in $(env | grep -o '^SLURM_[A-Za-z_]*'); do unset $v; done
  ./case.submit
else
  echo "== BUILD FAILED"; L=$(ls -t /scratch/$USER/elm_work/e3sm_runs/$CNAME/bld/*.bldlog.* 2>/dev/null | head -1)
  echo "newest build log: $L"; [ -n "$L" ] && zcat -f $L | grep -a -i -m8 -B2 -A4 "error" | cut -c1-300
  exit 1
fi
