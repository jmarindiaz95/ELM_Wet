#!/usr/bin/env python3
"""Single-point E3SM/ELM inputs for Quistococha (PE-QFR), site name 1x1pt_PE-QFR.

Writes under <inputdata>:
  share/domains/domain.clm/domain.lnd.1x1pt_PE-QFR.nc      single-cell domain (0.5 deg box around the tower)
  lnd/clm2/surfdata_map/surfdata_1x1pt_PE-QFR_simyr2000.nc  QUI cell extracted from the global E3SM v2 surface file,
                                                           100% natural vegetation, PFT 4 (broadleaf evergreen tropical tree)
  atm/datm7/1x1pt_PE-QFR/CLM1PT_data/YYYY-MM.nc           tower forcing 2018-2019 as one point, RH added
                                                           (ELM_USRDAT CLM1PT streams read RH, the CLM_SPRUCE files carry QBOT)

Wetland landunit and water level are added in a later step (this is the smoke-test surface file).
Usage: python3 make_qui_e3sm_inputs.py --surf <global surfdata> --forc <CLM_SPRUCE 2x1pt_PE-QFR forcing dir> --out <inputdata>
"""
import argparse, glob, os
import numpy as np
import netCDF4 as nc

LAT, LON = -3.834417, 360.0 - 73.318917
SITE = '1x1pt_PE-QFR'

p = argparse.ArgumentParser()
p.add_argument('--surf', required=True)
p.add_argument('--forc', required=True)
p.add_argument('--out', required=True)
a = p.parse_args()

# ---------------------------------------------------------------- surface data
src = nc.Dataset(a.surf)
lon2 = np.array(src['LONGXY'][:]); lat2 = np.array(src['LATIXY'][:])
lon2 = np.where(lon2 < 0, lon2 + 360, lon2)
j, i = np.unravel_index(np.argmin((lat2 - LAT) ** 2 + (lon2 - LON) ** 2), lat2.shape)
print(f'nearest global cell: j={j} i={i} lat={lat2[j, i]:.3f} lon={lon2[j, i]:.3f}')

os.makedirs(f'{a.out}/lnd/clm2/surfdata_map', exist_ok=True)
fs = f'{a.out}/lnd/clm2/surfdata_map/surfdata_{SITE}_simyr2000.nc'
dst = nc.Dataset(fs, 'w', format='NETCDF4_CLASSIC' if src.file_format.startswith('NETCDF4') else 'NETCDF3_64BIT_OFFSET')
for d, dim in src.dimensions.items():
    n = 1 if d in ('lsmlat', 'lsmlon') else (None if dim.isunlimited() else len(dim))
    dst.createDimension(d, n)
dst.setncatts({k: src.getncattr(k) for k in src.ncattrs()})
for name, v in src.variables.items():
    fill = v.getncattr('_FillValue') if '_FillValue' in v.ncattrs() else None
    o = dst.createVariable(name, v.dtype, v.dimensions, fill_value=fill)
    o.setncatts({k: v.getncattr(k) for k in v.ncattrs() if k != '_FillValue'})
    sl = tuple(slice(j, j + 1) if d == 'lsmlat' else slice(i, i + 1) if d == 'lsmlon' else slice(None) for d in v.dimensions)
    o[:] = v[sl] if v.dimensions else v[...]
src.close()

def setv(name, val):
    if name in dst.variables:
        dst[name][:] = val
    else:
        print(f'  (no {name} in surface file)')

setv('LATIXY', LAT); setv('LONGXY', LON)
for v in ['PCT_CROP', 'PCT_LAKE', 'PCT_WETLAND', 'PCT_GLACIER', 'PCT_URBAN']:
    setv(v, 0.0)
setv('PCT_NATVEG', 100.0)
if 'PCT_NAT_PFT' in dst.variables:
    x = np.zeros(dst['PCT_NAT_PFT'].shape); x[4] = 100.0; dst['PCT_NAT_PFT'][:] = x
if 'ORGANIC' in dst.variables:                     # peat as in the CLM_SPRUCE PE-QFR file
    x = np.full(dst['ORGANIC'].shape, 130.0); x[-1] = 65.0; dst['ORGANIC'][:] = x
setv('PCT_SAND', 10.0); setv('PCT_CLAY', 50.0)
dst.history = f'QUI (PE-QFR) cell extracted from {os.path.basename(a.surf)} by sol/make_qui_e3sm_inputs.py'
dst.close()
print('wrote', fs)

# ---------------------------------------------------------------- domain
os.makedirs(f'{a.out}/share/domains/domain.clm', exist_ok=True)
fd = f'{a.out}/share/domains/domain.clm/domain.lnd.{SITE}.nc'
d = nc.Dataset(fd, 'w', format='NETCDF3_64BIT_OFFSET')
d.createDimension('ni', 1); d.createDimension('nj', 1); d.createDimension('nv', 4)
h = 0.25
for name, val, units in [('xc', LON, 'degrees_east'), ('yc', LAT, 'degrees_north')]:
    x = d.createVariable(name, 'f8', ('nj', 'ni')); x.units = units; x[:] = val
x = d.createVariable('xv', 'f8', ('nj', 'ni', 'nv')); x.units = 'degrees_east'; x[0, 0, :] = [LON - h, LON + h, LON + h, LON - h]
x = d.createVariable('yv', 'f8', ('nj', 'ni', 'nv')); x.units = 'degrees_north'; x[0, 0, :] = [LAT - h, LAT - h, LAT + h, LAT + h]
x = d.createVariable('mask', 'i4', ('nj', 'ni')); x[:] = 1
x = d.createVariable('frac', 'f8', ('nj', 'ni')); x[:] = 1.0
x = d.createVariable('area', 'f8', ('nj', 'ni')); x.units = 'radian2'
x[:] = np.deg2rad(2 * h) * (np.sin(np.deg2rad(LAT + h)) - np.sin(np.deg2rad(LAT - h)))
d.close()
print('wrote', fd)

# ---------------------------------------------------------------- forcing (one point, RH added)
od = f'{a.out}/atm/datm7/{SITE}/CLM1PT_data'
os.makedirs(od, exist_ok=True)
files = sorted(glob.glob(f'{a.forc}/[12][0-9][0-9][0-9]-[01][0-9].nc'))
assert files, f'no YYYY-MM.nc forcing files in {a.forc}'
for f in files:
    s = nc.Dataset(f)
    o = nc.Dataset(f'{od}/{os.path.basename(f)}', 'w', format='NETCDF3_CLASSIC')
    for dn, dim in s.dimensions.items():
        o.createDimension(dn, 1 if dn == 'lon' else len(dim))
    for name, v in s.variables.items():
        x = o.createVariable(name, v.dtype, v.dimensions)
        x.setncatts({k: v.getncattr(k) for k in v.ncattrs()})
        val = v[:]
        if 'lon' in v.dimensions:
            val = np.take(val, [0], axis=v.dimensions.index('lon'))
        x[:] = val
    t = s['TBOT'][:, :, 0:1].astype('f8'); q = s['QBOT'][:, :, 0:1].astype('f8'); pr = s['PSRF'][:, :, 0:1].astype('f8')
    e = q * pr / (0.622 + 0.378 * q)
    es = 611.2 * np.exp(17.67 * (t - 273.15) / (t - 29.65))
    x = o.createVariable('RH', 'f4', ('time', 'lat', 'lon')); x.units = '%'; x.long_name = 'relative humidity at the lowest atm level (RH)'
    x.mode = 'time-dependent'; x[:] = np.clip(100.0 * e / es, 1.0, 100.0)
    o['LONGXY'][:] = [LON]
    o.close(); s.close()
print(f'wrote {len(files)} forcing files to {od}')
