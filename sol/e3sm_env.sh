# Source before any CIME command on Sol:  source /scratch/jmarindi/elm_work/ELM_Wet/sol/e3sm_env.sh
# Same compiler/MPI/NetCDF stack that builds CLM_SPRUCE; Perl with XML::LibXML from a conda env (system perl lacks it).
module purge
module load intel-oneapi-compilers-2022.1.0-gcc-11.2.0 intel-oneapi-mpi-2021.10.0-gcc-12.1.0 intel-oneapi-mkl-2022.1.0-aocc-3.1.0 netcdf-c-4.8.1-oneapi-2022.1.0 netcdf-fortran-4.5.3-oneapi-2022.1.0
export E3SM_SRC=/scratch/$USER/elm_work/ELM_Wet
# NetCDF from the Sol modules, fixed before anything else touches PATH (CIME reads these)
export NETCDF_C_PATH=$(dirname $(dirname $(which nc-config)))
export NETCDF_FORTRAN_PATH=$(dirname $(dirname $(which nf-config)))
# Only perl and python3 from the conda env: putting its whole bin/ on PATH exposes conda's own netCDF
# (nc-config, headers, libs), which PIO then builds against (_FillValue undefined with netCDF 4.9).
SHIM=/scratch/$USER/elm_work/conda_shim
mkdir -p $SHIM
for b in perl python3; do ln -sf /scratch/$USER/elm_work/conda_perl/bin/$b $SHIM/$b; done
export PATH=$SHIM:$PATH
export LD_LIBRARY_PATH=/scratch/$USER/clm_work/netcdf_merged_oneapi/lib:$LD_LIBRARY_PATH
export I_MPI_CC=icc I_MPI_CXX=icpc I_MPI_FC=ifort I_MPI_F90=ifort UCX_TLS=sm,tcp,self OMP_NUM_THREADS=1
perl -MXML::LibXML -e 1 2>/dev/null || echo "WARNING: perl XML::LibXML not found (conda_perl env missing?)"
case "$NETCDF_C_PATH" in *conda*) echo "WARNING: NETCDF_C_PATH points to conda: $NETCDF_C_PATH";; esac
