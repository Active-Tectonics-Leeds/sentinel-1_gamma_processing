# sentinel-1_gamma_processing
Tcsh scripts for processing sentinel-1 data into interferograms. Created by John Elliott 20/05/2015, updated 14/05/2019. Maintained by John Condon. 

# Requirements:
Safes and zips of SLC sentinel-1 data 
DEM file in binary 4byte with ers header (gdal_translate -ot Float32 -of ERS $dem.tif $dem.dem)
proc.param file 
datelist.txt file 

# Script run order:
Run sentinel_gamma_proc.tcsh to run all scripts in sequence. 
## Otherwise:
>>sentinel_gamma_proc_slc.tcsh <primary date> datelist.txt 
>>sentinel_gamma_proc_dem.tcsh <primary date>
>>sentinel_gamma_proc_rslcs.tcsh <primary date> slclist.txt
>>sentinel_gamma_proc_ifgms.tcsh <primary date> ifgmlist.txt
>>sentinel_gamma_proc_unwrap.tcsh <primary date> unwraplist.txt
>>sentinel_gamma_proc_geo.tcsh <primary date> geocodelist.txt
>>sentinel_gamma_proc_out.tcsh outputlist.txt
  

## sentinel_gamma_proc_slc.tcsh
Does the unzip, extract tiff/xml info, orbit state vector, slc generation, mosaicing, matching to master extent, and DEM/lookup tables

## sentinel_gamma_proc_dem.tcsh 
 Does the DEM/lookup tables and look vectors

## sentinel_gamma_proc_rslcs.tcsh
   Does the resampling of the secondary slcs to a common primary, then successive secondary slcs to previous rslc with Enhanced Spectral Diversity
 
## sentinel_gamma_proc_ifgms.tcsh
  Constructs interferograms from rslcs, filters and saves coherence and phase. 
  
## sentinel_gamma_proc_unwrap.tcsh 
  Unwraps interferograms using both snaphu and Gamma MCF
 
## sentinel_gamma_proc_geo.tcsh
  geocodes both unwrapped and wrapped interferograms, edited by J.C to produce geotiff not just image and raw binary files 
  
## sentinel_gamma_proc_out.tcsh 
 Converts and downsamples output to .grd files for use in gmt 
  

