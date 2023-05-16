#!/bin/tcsh

if ($#argv != 1) then
  echo " "
  echo " usage: sentinel_gamma_proc_out.tcsh outputlist.txt"
  echo " e.g. sentinel_gamma_proc_out.tcsh outputlist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Requires:"
  echo "           that you have already run: sentinel_gamma_proc_geo.tcsh masterdate geocodelist"
  echo "           a Processing Parameter File"
  echo "           a list of geocoded date pairs to process to final output"
  echo "John Elliott: 24/10/2018, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 14/05/2019, Leeds"
  exit
endif

# Make a list of previously geocoded interferograms
#basename -a `ls $topdir/geo/*/????????_????????.diff.unw.geo` | sed 's/.diff.unw.geo//' | sed 's/_/\ /' > $topdir/outputlist.txt


# Set GMTDEFAULT Paper Size so kmz files in correct place
app setup gmt/4.5.15
echo Running GMT Version 4

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir


# Interferogram List File
set listfile = $topdir/$1
if (-e $listfile) then
        echo "Using Geocoding list file $listfile"
else
        echo "\033[1;31m ERROR - Geocoding list file $listfile missing - Exiting \033[0m"
        exit
endif


# Parameter File
set paramfile = $topdir/proc.param
if (-e $paramfile) then
        echo "Using parameter file $paramfile"
else
	echo "\033[1;31m ERROR - Parameter file $paramfile missing - Exiting \033[0m"
        exit
endif


# Select Gamma Version
set gammaver = `grep gammaver $paramfile | awk '{print $2}'`
app setup gamma/$gammaver
echo "\033[1;31m Using Gamma Version: \033[0m"
which par_S1_SLC

echo Procesing with SComplex Storage

setenv OMP_NUM_THREADS 12


# PARAMETERS
# Choose wrap interval for fringes (e.g. 10 cm)
set rewrap_int = `grep rewrap_int $paramfile | awk '{print $2}'`

# Sentinel-1 Frequency 5.4050005GHz (implies air wavelength 5.545cm)
set rad2cm = `echo 5.545 | awk '{print $1/2/2/3.14159}'`
# For 10 cm this is 2.7725
set scale = `echo $rad2cm $rewrap_int | awk '{print 2*3.14159*$1/$2}'`

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`
set dim = `grep dim $paramfile | awk '{print $2}'`
set loslabel = `grep loslabel $paramfile | awk '{print $2}'`



# Files to copy
# Master par files
# Offset text files and ESD results
# Perpendicular Baseline
# Tiffs of bursts
# DEM
# Look Vectors
# Ifgms - wrapped, unwrapped, rewrapped 
# Coherence (smoothed, unsmoothed)
# KMZ files
# Amplitudes


# Start of Processing

# Loop through ifgms to make output products for and copy accross to out directory
mkdir $topdir/output


############
# GEOCODED #
# GMT Paper Size
set papersize = 10
gmtset PAPER_MEDIA = a0
gmtset PAGE_ORIENTATION = portrait

# Geographic Co-ordinates of Geocoded Files
set north = `grep corner_lat  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set west = `grep corner_lon  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set dlat = `grep post_lat  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set dlon = `grep post_lon  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set width = `grep width  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set length = `grep nlines  $topdir/geodem/EQA.dem_par | awk '{print $2}'`
set south = `echo $north $dlat $length | awk '{printf("%.7f"i, $1+$2*$3)}'`
set east = `echo $west $dlon $width | awk '{printf("%.7f", $1+$2*$3)}'`
echo $west $east $south $north
set dimkm = `echo $dim | awk '{print $1/1000}'`
set dlatpos = `echo $dlat | sed 's/-//'`


set widthdem = `grep width $topdir/geodem/EQA.dem_par | awk '{print $2}'`


# Loop through all interferograms
set nifgms = `wc $listfile | awk '{print $1}'`
echo Looping through $nifgms interferograms to make outputs for
sleep 2
set n = 1

while ( $n <= $nifgms )
        
        chdir $topdir
	# Date Pair
	set date1 = `awk '(NR=='$n'){print $1}' $listfile`
	set date2 = `awk '(NR=='$n'){print $2}' $listfile`

	echo $date1-$date2 

	# Test if output ifgms already exist
        if ( -e $topdir/output/$date1-$date2 ) then
                echo Interferogram $date1-$date2 already considered processed
                # Increment Ifgm count
                @ n++
                continue
        endif

	# Test if Dates in right order
	if ( $date1 >= $date2 ) then
		echo "\033[1;31m ERROR - First date after second date - Exiting \033[0m"
		exit
	endif


	#######################
	# OUTPUT FILES
	echo "\033[1;31m Starting Outputting Files \033[0m"
	mkdir $topdir/output/$date1-$date2
	chdir $topdir/output/$date1-$date2

	set ifgmpath = $topdir/geo/$date1-$date2
	
	

	# INTERFEROGRAMS
	# Wrapped
	cp $ifgmpath/$date1-$date2.diff.geo.png .
	png2kml_logos.tcsh $date1-$date2.diff.geo 0 1 $west $east $south $north
	\rm $date1-$date2.diff.geo.png
	cp $ifgmpath/$date1-$date2.diff_sm.geo.png .
	png2kml_logos.tcsh $date1-$date2.diff_sm.geo 0 1 $west $east $south $north
	\rm $date1-$date2.diff_sm.geo.png
	
	# Loop through Unwrapped types
	foreach diff ( diff diff_sm diff_sm_lks diff_sm_snaphu )

		# Unwrapped
		cp $ifgmpath/$date1-$date2.$diff.unw.geo.png .
		png2kml_logos.tcsh $date1-$date2.$diff.unw.geo 0 1 $west $east $south $north
	
		# Swap bytes
		swap_bytes $ifgmpath/$date1\_$date2.$diff.unw.geo $date1\_$date2.$diff.unw.geo.bin 4
		
		# Output as ERS header file
		create_ers_header.tcsh $date1\_$date2.$diff.unw.geo.bin.ers $dlon $dlatpos $length $width $west $north unwrapped_phase_radians
		
		# Output as GMT grd format
		xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.$diff.unw.geo.bin -G$date1\_$date2.$diff.unw.geo.bin.grd -F -N0 -ZTLf
		
		# Downsample Grid
		# Grdfilter seems better way to deal with NaNs by taking median value, grdsample ends up with lots of holes
		# Note resampling pattern of NaN holes seen sometimes if resampling close to original size? (change dimension slightly and it seems fine)
		grdfilter $date1\_$date2.$diff.unw.geo.bin.grd -G$date1\_$date2.$diff.unw.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3		

		# Remove Median Value and Convert to cm
		grdmath $date1\_$date2.$diff.unw.geo."$dim"m.bin.grd $date1\_$date2.$diff.unw.geo."$dim"m.bin.grd MED SUB $rad2cm MUL = $date1\_$date2.$diff.unw.cm.geo."$dim"m.bin.grd
		
		# Output kmz of unwrapped file
		grd2cpt $date1\_$date2.$diff.unw.cm.geo."$dim"m.bin.grd -Cpolar -E100 -I -T= -Z > unwrap_polar.cpt
		grdimage $date1\_$date2.$diff.unw.cm.geo."$dim"m.bin.grd -JQ$papersize -Cunwrap_polar.cpt -S-n -Q -V  > $date1-$date2.$diff.unw.cm.geo."$dim"m.ps
		# Put -K above if grdcontour used
		#grdcontour $date1\_$date2.$diff.unw.cm.geo."$dim"m.bin.grd -JQ$papersize -C$int -L-100/100 -A$int+s2+ucm -Gd2 -Wa1,darkblue -Q100 -V -O >>  $date1-$date2.$diff.unw.cm.geo."$dim"m.ps
		ps2raster $date1-$date2.$diff.unw.cm.geo."$dim"m.ps -E300 -TG -W+k+t"$date1-$date2.$diff.unw.cm.geo."$dim"m.bin.grd"+l16/-1 -V
		
		# Plot Scale
		psscale -Cunwrap_polar.cpt -D2/1/4/0.3h -B$loslabel/:"los cm": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_unwrap.ps
		ps2raster -A -TG -P scale_unwrap.ps
		
		png2kml_logos.tcsh $date1-$date2.$diff.unw.cm.geo."$dim"m scale_unwrap 1 $west $east $south $north
		
		# Unwrapped Different Interval
		cp $ifgmpath/$date1-$date2.$diff.wrap"$rewrap_int"cm.unw.geo.png .
		png2kml_logos.tcsh $date1-$date2.$diff.wrap"$rewrap_int"cm.unw.geo 0 1 $west $east $south $north

		
		# Clean up Files
		\rm $date1\_$date2.$diff.unw.geo.bin $date1\_$date2.$diff.unw.geo.bin.ers $date1\_$date2.$diff.unw.geo.bin.grd $date1\_$date2.$diff.unw.geo."$dim"m.bin.grd 
		\rm $date1-$date2.$diff.unw.geo.png $date1-$date2.$diff.wrap"$rewrap_int"cm.unw.geo.png $date1-$date2.$diff.unw.cm.geo."$dim"m.png

	end	
	



	
	# Interferogram Phase
	foreach diff ( diff diff_sm )
	
		# Extract Phase from complex
		cpx_to_real $ifgmpath/$date1\_$date2.$diff.geo $date1\_$date2.$diff.phs.geo $widthdem 4
		
		# Swap bytes
		swap_bytes $date1\_$date2.$diff.phs.geo $date1\_$date2.$diff.phs.geo.bin 4
		
		# Output as ERS header file
		create_ers_header.tcsh $date1\_$date2.$diff.phs.geo.bin.ers $dlon $dlatpos $length $width $west $north phase_radians
			
		# Output as GMT grd format
		xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.$diff.phs.geo.bin -G$date1\_$date2.$diff.phs.geo.bin.grd -F -N0 -ZTLf
			
		# Downsample Grid
		grdfilter $date1\_$date2.$diff.phs.geo.bin.grd -G$date1\_$date2.$diff.phs.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3
			
		# Clean Up Files
		\rm $date1\_$date2.$diff.phs.geo $date1\_$date2.$diff.phs.geo.bin $date1\_$date2.$diff.phs.geo.bin.ers $date1\_$date2.$diff.phs.geo.bin.grd
		
	end


	###########
	# Coherence (and Smooth Coherence)
	foreach cc ( cc smcc )
		
		# Swap bytes
		swap_bytes $ifgmpath/$date1\_$date2.$cc.geo $date1\_$date2.$cc.geo.bin 4
		
		# Output as ERS header file
		create_ers_header.tcsh $date1\_$date2.$cc.geo.bin.ers $dlon $dlatpos $length $width $west $north coherence
		
		# Output grd file
		xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.$cc.geo.bin -G$date1\_$date2.$cc.geo.bin.grd -F -N0 -ZTLf
		
		# Downsample Grid
		grdfilter $date1\_$date2.$cc.geo.bin.grd -G$date1\_$date2.$cc.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3
		
		# KMZ
		cp $ifgmpath/$date1-$date2.$cc.geo.png .
		png2kml_logos.tcsh $date1-$date2.$cc.geo 0 1 $west $east $south $north
		
		# Clean up Files
		\rm $date1\_$date2.$cc.geo.bin $date1\_$date2.$cc.geo.bin.ers $date1\_$date2.$cc.geo.bin.grd $date1-$date2.$cc.geo.png
		
	end


	# Clean up
	\rm -r files
	\rm unwrap_polar.cpt scale_unwrap.ps scale_unwrap.png scale_rewrap.ps scale_rewrap.png rewrap_seis.cpt
	\rm $date1-$date2.*.kml $date1-$date2.*.ps



	# Increment Ifgm count
	@ n++

end



# Directories to remove
#echo Remove the following directories \(with care\)
#echo safes slcs ifgms geo 

