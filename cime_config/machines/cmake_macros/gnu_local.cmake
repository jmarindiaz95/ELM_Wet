set(NETCDF_PATH "/opt/netcdf")
set(NETCDF_C_PATH "/opt/netcdf")
set(NETCDF_FORTRAN_PATH "/opt/netcdf")
set(HDF5_PATH "/usr")

execute_process(
  COMMAND /opt/netcdf/bin/nf-config --flibs
  OUTPUT_VARIABLE NETCDF_FORTRAN_LIBS
  OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY
)
string(APPEND SLIBS " ${NETCDF_FORTRAN_LIBS} -lblas -llapack")
