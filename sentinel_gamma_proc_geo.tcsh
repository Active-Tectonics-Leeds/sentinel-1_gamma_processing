#!/bin/tcsh

if ($#argv != 2) then
  echo " "
  echo " usage: sentinel_gamma_proc_geo.tcsh masterdate geocodelist.txt"
  echo " e.g. sentinel_gamma_proc_geo.tcsh 20180105 geocodelist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Requires:"
  echo "           that you have already run: sentinel_gamma_proc_unwrap.tcsh masterdate unwraplist"
  echo "           DEM of the area"
  echo "           a Processing Parameter File"
  echo "           a list of unwrapped interferogram date pairs to process"
  echo "John Elliott: 24/10/2018, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 14/05/2019, Leeds"
  exit
endif

# Output list of interferograms to geocode
#basename -a `ls $topdir/ifgms/*/????????_????????.diff_sm.unw` | sed s/.diff_sm.unw// | sed s/_/\ / > $topdir/geocodelist.txt

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Master Date (for geodem)
set dateM = $1
echo Using Master Date: $dateM

# Interferogram List File
set listfile = $topdir/$2
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



# Start of Gamma Processing

# Loop through ifgms to make geocoded products for
mkdir $topdir/geo
set nifgms = `wc $listfile | awk '{print $1}'`
echo Looping through $nifgms interferograms to geocode
set n = 1

while ( $n <= $nifgms )
        echo made it here 
        chdir $topdir
	# Date Pair
	set date1 = `awk '(NR=='$n'){print $1}' $listfile`
	set date2 = `awk '(NR=='$n'){print $2}' $listfile`
	echo set dates
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
	sleep 2


	#######################
	# GEOCODING
	echo "\033[1;31m Starting Geocoding of Interferograms \033[0m"
	mkdir $topdir/geo/$date1-$date2
	chdir $topdir/geo/$date1-$date2
	ln -s $topdir/geodem/EQA* .
        ln -s $topdir/geodem/$dateM* .
	ln -s $topdir/ifgms/$date1-$date2/$dateM* .
	ln -s $topdir/ifgms/$date1-$date2/$date1\_$date2* .
	ln -s $topdir/ifgms/$date1-$date2/$date1.* .
	ln -s $topdir/ifgms/$date1-$date2/$date2.* .

	# Get width of first date multilooked and DEM
	set widthmli = `grep range_samples $dateM.mli.par | awk '{print $2}'`
	set widthdem = `grep width EQA.dem_par | awk '{print $2}'`


	###########################
	# GEOCODE INTERFEROGRAM and FILTERED
	foreach diff ( diff diff_sm )
		geocode_back $date1\_$date2.$diff $widthmli $dateM.lt_fine $date1\_$date2.$diff.geo $widthdem - 0 1

		# Output raster
		rasmph $date1\_$date2.$diff.geo $widthdem 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.$diff.geo.tif
		#output geotiff geocoded with dem_par file
		echo HERE first
		data2geotiff EQA.dem_par $date1\_$date2.$diff.geo 2 $date1\_$date2.$diff.geo.geocoded.float.tif - 
		data2geotiff EQA.dem_par $date1\_$date2.$diff.geo.tif 0 $date1\_$date2.$diff.geo.geocoded.image.tif 
		# Convert to png with transparency of black masked out
		convert $date1\_$date2.$diff.geo.tif -transparent black $date1-$date2.$diff.geo.png
	#	\rm $date1\_$date2.$diff.geo.tif

	end


	# Amplitudes 
	foreach date ( $date1 $date2 ) 
		
		geocode_back $date.rslc.mli $widthmli $dateM.lt_fine $date.mli.geo $widthdem - 2

		raspwr $date.mli.geo $widthdem 1 0 $raspixavr $raspixavaz 0.5 .35 1 $date.mli.geo.tif 0 0
		convert $date.mli.geo.tif -transparent black $date.mli.geo.png
		\rm $date.mli.geo.tif
	end


	# Coherence
	foreach cc ( cc smcc )
		geocode_back $date1\_$date2.$cc $widthmli $dateM.lt_fine $date1\_$date2.$cc.geo $widthdem - 2
		rascc $date1\_$date2.$cc.geo EQA.$dateM.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz 0.1 0.9 1.0 .20 1 $date1\_$date2.$cc.geo.tif
		convert $date1\_$date2.$cc.geo.tif -transparent black $date1-$date2.$cc.geo.png
		\rm $date1\_$date2.$cc.geo.tif
	end



	#######################
	# UNWRAPPED INTERFEROGRAMS
	foreach diff ( diff diff_sm_snaphu ) #diff_sm diff_sm_lks 
	
		# Geocode unwrapped
        	geocode_back $date1\_$date2.$diff.unw $widthmli $dateM.lt_fine $date1\_$date2.$diff.unw.geo $widthdem - 0
		
        	# Display Unwrapped Geocoded
        	# disrmg $date1\_$date2.$diff.unw.geo EQA.$dateM.slc.mli $widthdem &
		
        	# Output raster
        	rasrmg $date1\_$date2.$diff.unw.geo EQA.$dateM.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.$diff.unw.geo.tif
		#output geotiff geocoded with dem_par
		echo HERE second
	        data2geotiff EQA.dem_par $date1\_$date2.$diff.unw.geo 2 $date1\_$date2.$diff.unw.geo.geocoded.float.tif
                data2geotiff EQA.dem_par $date1\_$date2.$diff.unw.geo.tif 0 $date1\_$date2.$diff.unw.geo.geocoded.tif
        	# Convert to png with transparency of black masked out
        	convert $date1\_$date2.$diff.unw.geo.tif -transparent black $date1-$date2.$diff.unw.geo.png
	#	\rm $date1\_$date2.$diff.unw.geo.tif
		
        	# Output raster with a different unwrapping scale
        	rasrmg $date1\_$date2.$diff.unw.geo EQA.$dateM.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz $scale 1. .20 0 1 $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.tif
		# Output geotiff geocoded with dem_par file
		echo HERE third
		data2geotiff EQA.dem_par $date1\_$date2.$diff.unw.geo 2 $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.geocoded.float.tif
                data2geotiff EQA.dem_par $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.tif 2 $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.geocoded.tif
        	# Convert to png with transparency of black masked out
        	convert $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.tif -transparent black $date1-$date2.$diff.wrap"$rewrap_int"cm.unw.geo.png
	#	\rm $date1\_$date2.$diff.wrap"$rewrap_int"cm.unw.geo.tif
				
	end




	# Increment Ifgm count
	@ n++

end

# Output Montage
chdir $topdir/geo/
#montage -label '%f' */*.diff.geo.png -geometry +20+2 -pointsize 40 ifgms_diff.geo.jpg
#montage -label '%f' */*.cc.geo.png -geometry +20+2 -pointsize 40 ifgms_cc_geo.jpg
#montage -label '%f' */*.smcc.geo.png -geometry +20+2 -pointsize 40 ifgms_smcc_geo.jpg

#foreach diff ( diff diff_sm diff_sm_lks diff_sm_snaphu )
        #montage -label '%f' */*.$diff.unw.geo.png -geometry +20+2 -pointsize 40 ifgms_$diff.unw.geo.jpg
        #montage -label '%f' */*.$diff.wrap"$rewrap_int"cm.unw.geo.png -geometry +20+2 -pointsize 40 ifgms_$diff.wrap"$rewrap_int"cm.unw.geo.jpg
#end


# Output list of geocoded interferograms to output
basename -a `ls $topdir/geo/*/????????_????????.diff.unw.geo` | sed 's/.diff.unw.geo//' | sed 's/_/\ /' > $topdir/outputlist.txt

# Next Step
echo sentinel_gamma_proc_out.tcsh outputlist.txt

