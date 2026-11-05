module WetlandSurfWatElevation

  !-----------------------------------------------------------------------
  ! !DESCRIPTION:
  ! CLM Satelitte Phenology model (SP) ecosystem dynamics (phenology, vegetation).
  ! Allow some subroutines to be used by the CLM Carbon Nitrogen model (CLMCN)
  ! so that DryDeposition code can get estimates of LAI differences between months.
  !
  ! !USES:
  use shr_strdata_mod , only : shr_strdata_type, shr_strdata_create
  use shr_strdata_mod , only : shr_strdata_print, shr_strdata_advance
  use shr_kind_mod    , only : r8 => shr_kind_r8
  use shr_kind_mod    , only : CL => shr_kind_CL
  use shr_kind_mod    , only : CX => shr_kind_CXX
  use shr_log_mod     , only : errMsg => shr_log_errMsg
  use decompMod       , only : bounds_type
  use abortutils      , only : endrun
  use elm_varctl      , only : iulog, scmlat,scmlon,single_column
  use elm_varcon      , only : grlnd
  use controlMod      , only : NLFilename
  use decompMod       , only : gsmap_lnd_gdc2glo
  use domainMod       , only : ldomain
  use fileutils       , only : getavu, relavu
  use VegetationType       , only : veg_pp
  use WaterstateType  , only : waterstate_type
  use perf_mod        , only : t_startf, t_stopf
  use spmdMod         , only : masterproc
  use spmdMod         , only : mpicom, comp_id
  use mct_mod
  use ncdio_pio   
  use topounit_varcon , only : max_topounits
  use GridcellType    , only : grc_pp
  use ColumnDataType    , only : column_water_state
  !
  ! !PUBLIC TYPES:
  implicit none
  save
  !
  ! !PUBLIC MEMBER FUNCTIONS:
  public :: interpDailyWetSurfWatElev       ! interpolate monthly vegetation data
  !
  ! !PRIVATE MEMBER FUNCTIONS:
  private :: readDailyWetSurfWatElev  ! read monthly vegetation data for two months
  !
  ! !PRIVATE TYPES:

  !-----------------------------------------------------------------------

contains

  !-----------------------------------------------------------------------
  subroutine interpDailyWetSurfWatElev (bounds, col_ws)
    !
    ! !DESCRIPTION:
    ! Determine if 2 new months of data are to be read.
    !
    ! !USES:
    use elm_varctl      , only : fsurdat
    use clm_time_manager, only : get_curr_date, get_step_size, get_nstep,get_curr_calday
    !
    ! !ARGUMENTS:
    type(bounds_type), intent(in) :: bounds
    type(column_water_state), intent(inout) :: col_ws
    !
    ! !LOCAL VARIABLES:
    !real(r8):: dtime       ! land model time step (sec)

    !-----------------------------------------------------------------------
    
    !dtime = get_step_size()

    call readDailyWetSurfWatElev (bounds, fsurdat, col_ws)

  end subroutine interpDailyWetSurfWatElev
  
  !-----------------------------------------------------------------------
  
  subroutine readDailyWetSurfWatElev (bounds, &
       fveg, col_ws)
    !
    ! !DESCRIPTION:
    ! Read monthly vegetation data for two consec. months.
    !
    ! !USES:
    use elm_varpar       , only : numpft
    use pftvarcon        , only : noveg
    use fileutils        , only : getfil
    use spmdMod          , only : masterproc, mpicom, MPI_REAL8, MPI_INTEGER
    use shr_scam_mod     , only : shr_scam_getCloseLatLon
    use clm_time_manager , only : get_nstep,get_curr_calday,get_curr_date
    use elm_varctl       , only : wetl_col1_elev_offset, wetl_elev_yr_first, wetl_elev_yr_last
    use LandunitType   , only: lun_pp
    use ColumnType   , only: col_pp
    use landunit_varcon   , only: istwet
    use netcdf
    
    !
    ! !ARGUMENTS:
    type(bounds_type) , intent(in) :: bounds
    character(len=*)  , intent(in) :: fveg      ! file with monthly vegetation data
    type(column_water_state), intent(inout) :: col_ws
    !
    ! !LOCAL VARIABLES:
    character(len=256) :: locfn           ! local file name
    type(file_desc_t)  :: ncid            ! netcdf id
    integer :: g,p,c     ! indices
    integer :: dimid,varid                ! input netCDF id's
    integer :: ntim                       ! number of input data time samples
    integer :: nlon_i                     ! number of input data longitudes
    integer :: nlat_i                     ! number of input data latitudes
    integer :: npft_i                     ! number of input data pft types
    integer :: ier                        ! error code
    integer :: closelatidx,closelonidx
    real(r8):: closelat,closelon
    logical :: readvar
    real(r8), pointer :: SurfWatElev(:,:,:)        ! lai read from input files
    character(len=32) :: subname = 'readDailyWetSurfWatElev'
    integer :: jday        ! julian day of the year
    integer :: year,mon,day,sec    !Date components for end of current time step
    integer :: yr_eff              ! year whose water level is used
    character(len=32) :: wvarname  ! SurfWatElev_Wet_<year>
    
    !-----------------------------------------------------------------------

    ! Determine necessary indices

    jday =  get_curr_calday()
    call get_curr_date(year,mon,day,sec)
    
    allocate(&
         SurfWatElev(bounds%begg:bounds%endg,0:numpft,0:364), &
         stat=ier)
    if (ier /= 0) then
       write(iulog,*)subname, 'allocation big error '
       call endrun(msg=errMsg(__FILE__, __LINE__))
    end if

    ! ----------------------------------------------------------------------
    ! Open Surface Water Elevation file
    ! Read data and convert from gridcell to pft data
    ! ----------------------------------------------------------------------

    call getfil(fveg, locfn, 0)
    call ncd_pio_openfile (ncid, trim(locfn), 0)

    if (single_column) then
       call shr_scam_getCloseLatLon (ncid, scmlat, scmlon, closelat, closelon,&
            closelatidx, closelonidx)
    endif

    ! Variable for the current year: SurfWatElev_Wet_<year>; with wetl_elev_yr_first/last set, model years
    ! outside that range cycle through it (e.g. 2018-2019 in a spinup with cycled 2018-2019 forcing).
    ! A missing year-specific variable falls back to the year-less SurfWatElev_Wet (published behaviour).
    yr_eff = year
    if (wetl_elev_yr_first > 0 .and. wetl_elev_yr_last >= wetl_elev_yr_first) then
       if (year < wetl_elev_yr_first .or. year > wetl_elev_yr_last) then
          yr_eff = wetl_elev_yr_first + modulo(year - wetl_elev_yr_first, wetl_elev_yr_last - wetl_elev_yr_first + 1)
       end if
    end if
    write(wvarname,'(a,i4.4)') 'SurfWatElev_Wet_', yr_eff
    call ncd_io(ncid=ncid, varname=trim(wvarname), flag='read', data=SurfWatElev, dim1name=grlnd, &
         readvar=readvar)
    if (.not. readvar) then
       call ncd_io(ncid=ncid, varname='SurfWatElev_Wet', flag='read', data=SurfWatElev, dim1name=grlnd, &
            readvar=readvar)
       if (.not. readvar) call endrun(msg=' ERROR: SurfWatElev_Wet NOT on fveg file'//errMsg(__FILE__, __LINE__))
    end if


       ! Assign surface water depth to each pft
       do p = bounds%begp,bounds%endp
          g =veg_pp%gridcell(p)
          c = veg_pp%column(p)

          if (lun_pp%itype(col_pp%landunit(c)) == istwet) then
             ! index 13 (the published wetland patch type) for both the test and the value; the original test
             ! used the patch index p, which is out of the 0:numpft range at most sites
             col_ws%h2osfc_wet(c) = min(SurfWatElev(g,13,jday-1), 1200._r8)
             ! first wetland column (hummock) sits wetl_col1_elev_offset mm above the second (hollow)
             if (c == lun_pp%coli(col_pp%landunit(c))) then
                col_ws%h2osfc_wet(c) = col_ws%h2osfc_wet(c) - wetl_col1_elev_offset
             end if
          else
             col_ws%h2osfc_wet(c) = 0_r8
          endif
                       
       end do   ! end of loop over patches


    call ncd_pio_closefile(ncid)

    deallocate(SurfWatElev)

  end subroutine readDailyWetSurfWatElev

end module WetlandSurfWatElevation
