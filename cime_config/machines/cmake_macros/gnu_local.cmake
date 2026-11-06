set(NETCDF_PATH "/usr")
set(NETCDF_C_PATH "/usr")
set(NETCDF_FORTRAN_PATH "/usr")
set(HDF5_PATH "/usr")

execute_process(
  COMMAND /usr/bin/nf-config --flibs
  OUTPUT_VARIABLE NETCDF_FORTRAN_LIBS
  OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY
)
string(APPEND SLIBS " ${NETCDF_FORTRAN_LIBS} -lblas -llapack")
