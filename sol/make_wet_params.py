#!/usr/bin/env python3
"""Copy the default ELM CN parameter file and add the CH4 parameters ELM-Wet reads.

ELM-Wet reads six parameters the standard file lacks. At a single-point site they are inert:
f_ch4_1/f_ch4_2 and MeasAereResis_1/_2 act only on columns 17 and 18 (the authors' Louisiana grid),
h2osfc_max only when the water level is not read from the surface file, and h2osfc_wet_lb is the
offset between the forced water level and the soil surface (0: the tower WTD is already relative to it).
Values: f_ch4_1 = f_ch4_2 = f_ch4 from the file, MeasAereResis_1/_2 = 1, h2osfc_max = 1200 mm, h2osfc_wet_lb = 0.
Usage: python3 make_wet_params.py <default params .nc> <output .nc>
"""
import sys, shutil
import netCDF4 as nc
src, out = sys.argv[1], sys.argv[2]
shutil.copyfile(src, out)
d = nc.Dataset(out, 'a')
f_ch4 = float(d['f_ch4'][...]) if 'f_ch4' in d.variables else 0.2
add = {'f_ch4_1': f_ch4, 'f_ch4_2': f_ch4, 'h2osfc_wet_lb': 0.0, 'h2osfc_max': 1200.0,
       'MeasAereResis_1': 1.0, 'MeasAereResis_2': 1.0}
for k, v in add.items():
    if k in d.variables:
        print(f'  {k} already present ({float(d[k][...])}), kept'); continue
    x = d.createVariable(k, 'f8', ()); x.long_name = 'ELM-Wet parameter (inert at single-point sites, see make_wet_params.py)'
    x.assignValue(v); print(f'  added {k} = {v}')
need = ['aereoxid','q10ch4','q10ch4base','f_ch4','rootlitfrac','cnscalefactor','redoxlag','lake_decomp_fact','redoxlag_vertical',
        'pHmax','pHmin','vmax_ch4_oxid','oxinhib','k_m','q10_ch4oxid','smp_crit','k_m_o2','k_m_unsat','vmax_oxid_unsat',
        'scale_factor_aere','nongrassporosratio','unsat_aere_ratio','porosmin','vgc_max','satpow','scale_factor_gasdiff',
        'scale_factor_liqdiff','f_sat','qflxlagd','highlatfact','q10lakebase','atmch4','rob','capthick']
miss = [k for k in need if k not in d.variables]
d.history = getattr(d, 'history', '') + '; ELM-Wet CH4 parameters added by sol/make_wet_params.py'
d.close()
if miss:
    print('ERROR: other CH4 parameters ELM-Wet reads are missing from', src, ':', miss); sys.exit(1)
print('wrote', out)
