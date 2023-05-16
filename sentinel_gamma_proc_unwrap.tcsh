#!/bin/tcsh

if ($#argv != 2) then
  echo " "
  echo " usage: sentinel_gamma_proc_unwrap.tcsh masterdate unwraplist.txt"
  echo " e.g. sentinel_gamma_proc_unwrap.tcsh 20180105 unwraplist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Requires:"
  echo "           that you have already run: sentinel_gamma_proc_ifgm.tcsh masterdate ifgmlist"
  echo "           DEM of the area"
  echo "           a Processing Parameter File"
  echo "           a list of interferogram date pairs to process"
  echo "John Elliott: 24/10/2018, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 14/05/2019, Leeds"
  exit
endif

# Make a list of interferograms to unwrap
#basename -a `ls $topdir/ifgms/*/????????_????????.diff` | sed s/.diff// | sed s/_/\ / > $topdir/unwraplist.txt

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Master Date (for geodem)
set dateM = $1
echo Using Master Date: $dateM

# Interferogram List File
set listfile = $topdir/$2
if (-e $listfile) then
        echo "Using Unwrap list file $listfile"
else
        echo "\033[1;31m ERROR - Unwrap list file $listfile missing - Exiting \033[0m"
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
# Number of Looks
set lksrng = `grep lksrng $paramfile | awk '{print $2}'`
set lksazi = `grep lksazi $paramfile | awk '{print $2}'`
echo Looks in range: $lksrng and azimuth: $lksazi

# Unwrapping
set r_patch = `grep r_patch $paramfile | awk '{print $2}'`
set az_patch = `grep az_patch $paramfile | awk '{print $2}'`
set r_init = `grep r_init $paramfile | awk '{print $2}'`
set az_init = `grep az_init $paramfile | awk '{print $2}'`
echo Unwrapping Patches: $r_patch $az_patch Unwrap Point: $r_init $az_init
# Choose wrap interval for fringes (e.g. 10 cm)
set rewrap_int = `grep rewrap_int $paramfile | awk '{print $2}'`

# Sentinel-1 Frequency 5.4050005GHz (implies air wavelength 5.545cm)
set rad2cm = `echo 5.545 | awk '{print $1/2/2/3.14159}'`
# For 10 cm this is 2.7725
set scale = `echo $rad2cm $rewrap_int | awk '{print 2*3.14159*$1/$2}'`

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`

# Test if unwraping point is outside interferogram dimensions
set widthmli = `grep range_samples $topdir/rslc/$dateM/$dateM.mli.par | awk '{print $2}'`
set lengthmli = `grep azimuth_lines $topdir/rslc/$dateM/$dateM.mli.par | awk '{print $2}'`
if ( $r_init > $widthmli || $az_init > $lengthmli ) then
	echo Unwrapping point $r_init $az_init outside interferogram dimensions $widthmli $lengthmli
	exit
endif



# Start of Gamma Processing

# Loop through ifgms to make
set nifgms = `wc $listfile | awk '{print $1}'`
echo Looping through $nifgms interferograms to unwrap
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
	sleep 2


	##############
	# Unwrapping #
	echo "\033[1;31m Starting Unwrapping Interfeogram $date1-$date2 \033[0m"
	chdir $topdir/ifgms/$date1-$date2

	# Get width of first date multilooked and DEM
	set widthmli = `grep range_samples $dateM.mli.par | awk '{print $2}'`
	set widthdem = `grep width EQA.dem_par | awk '{print $2}'`


	########## GAMMA MCF
	# Phase unwrapping mask
	# Be careful with what you are using as Coherence (smoothed or original) to mask
	rascc_mask $date1\_$date2.cc $dateM.mli $widthmli 1 1 0 1 1 0.1 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.mask.ras
	
	# Display Mask
	 #disras $date1\_$date2.mask.ras &

	# Unwrap Minimum Cost Function
	mcf $date1\_$date2.diff $date1\_$date2.cc $date1\_$date2.mask.ras $date1\_$date2.diff.unw $widthmli 0 - - - - $r_patch $az_patch - $r_init $az_init 1

	# Display unwrapped image
	 #disrmg $date1\_$date2.diff.unw $dateM.mli $widthmli 1 1 0 1.0 1. .20 0. &

	# Output raster
        rasrmg $date1\_$date2.diff.unw $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.diff.unw.tif	


	# Filtered Ifgm	
	# Phase unwrapping mask
	# Be careful with what you are using as Coherence (smoothed or original) to mask
	rascc_mask $date1\_$date2.smcc $dateM.mli $widthmli 1 1 0 1 1 0.3 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.mask_sm.ras
	
	# Display Mask
	# disras $date1\_$date2.mask.ras &

	# Unwrap Minimum Cost Function
	mcf $date1\_$date2.diff_sm $date1\_$date2.smcc $date1\_$date2.mask_sm.ras $date1\_$date2.diff_sm.unw $widthmli 0 - - - - $r_patch $az_patch - $r_init $az_init 1

	# Display unwrapped image
	# disrmg $date1\_$date2.diff_sm.unw $dateM.mli $widthmli 1 1 0 1.0 1. .20 0. &

	# Output raster
        rasrmg $date1\_$date2.diff_sm.unw $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.diff_sm.unw.tif	


	
	#######################
	# Improvement to unwrapping by downsampling, unwrapping, upsample and then use this as a phase model to unwrap
	# Multilook factor to reduce by
	set mf = 3
	multi_cpx $date1\_$date2.diff_sm $date1\_$date2.off $date1\_$date2.diff_sm_lks $date1\_$date2.off.lks $mf $mf 0 0
	multi_real $dateM.mli $date1\_$date2.off $dateM.lks.mli $date1\_$date2.off.lks $mf $mf 0 0
	multi_real $date1\_$date2.smcc $date1\_$date2.off $date1\_$date2.smcc_lks $date1\_$date2.off.lks $mf $mf 0 0

	set widthlksmli = `grep interferogram_width $date1\_$date2.off.lks | awk '{print $2}'`
	
	rascc_mask $date1\_$date2.smcc_lks $dateM.lks.mli $widthlksmli 1 1 0 1 1 0.3 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.lks.mask.ras
	#rascc_mask $date1\_$date2.cc_lks $dateM.lks.mli $widthlksmli 1 1 0 1 1 0.1 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.lks.mask.ras
	#disras $date1\_$date2.lks.mask.ras &
	
	# Unwrap (set also reference pixel)
	set r_init_sm = `echo $r_init $mf | awk '{print int($1/$2)}'`
	set az_init_sm = `echo $az_init $mf | awk '{print int($1/$2)}'`
	mcf $date1\_$date2.diff_sm_lks $date1\_$date2.smcc_lks $date1\_$date2.lks.mask.ras $date1\_$date2.diff_sm_lks.unw $widthlksmli 0 - - - - 1 1 - $r_init_sm $az_init_sm 1
	
	#disrmg $date1\_$date2.diff_sm_lks.unw $dateM.lks.mli $widthlksmli 1 1 0 1.0 1. .20 0. &
	
	# Upsample to full res (important must use existing full res  $date1\_$date2.off.corrected2 file as OFF-par_out to get original width when upscaling.
	multi_cpx $date1\_$date2.diff_sm_lks.unw $date1\_$date2.off.lks $date1\_$date2.diff_sm_lks_up $date1\_$date2.off -$mf -$mf
	multi_real $dateM.lks.mli $date1\_$date2.off.lks $dateM.lks_up.mli $date1\_$date2.off -$mf -$mf

	# Use unw_model with downsampled unwrapped phase to unwrap full resolution
	unw_model $date1\_$date2.diff_sm $date1\_$date2.diff_sm_lks_up $date1\_$date2.diff_sm_lks.unw $widthmli
	
	# Display unwrapped image
	#disrmg $date1\_$date2.diff_sm_lks.unw $dateM.mli $widthmli 1 1 0 1.0 1. .20 0. &

	# Output raster
       rasrmg $date1\_$date2.diff_sm_lks.unw $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.diff_sm_lks.unw.tif	






	############
	# SNAPHU   #
	############

	# Make Mask (note snaphu masks area in terms of cost, does not mask out area for unwrapping - masks out magnitude instead)
	rascc_mask $date1\_$date2.cc $dateM.mli $widthmli 1 1 0 1 1 0.1 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.mask_snaphu.tif
	convert $date1\_$date2.mask_snaphu.tif -threshold 0 -colorspace RGB $date1\_$date2.boolean.mask_snaphu.tif
	gdal_translate $date1\_$date2.boolean.mask_snaphu.tif -ot Byte -of ERS $date1\_$date2.snaphu.mask
	

	# Need to swap bytes first
	swap_bytes $date1\_$date2.diff_sm $date1\_$date2.diff_sm.swap 4
	swap_bytes $date1\_$date2.smcc $date1\_$date2.smcc.swap 4
	swap_bytes $date1\_$date2.cc $date1\_$date2.cc.swap 4

	# Setup Snaphu config file to output samples (not lines)
cat <<EOF > config.snaphu
OUTFILEFORMAT           ALT_SAMPLE_DATA
CORRFILEFORMAT          FLOAT_DATA
EOF

	# Unwrap with Snaphu (deformation mode) # edited line below changed 2 to 10 in tile row and colume
	snaphu-v2.0.0 -f config.snaphu -d $date1\_$date2.diff_sm.swap $widthmli -c $date1\_$date2.cc.swap -M $date1\_$date2.snaphu.mask -S --nproc 4 --tile 10 10 400 400 -v -o $date1\_$date2.diff_sm.unw.swap >& unwrap.txt

	# Swap Back
	swap_bytes $date1\_$date2.diff_sm.unw.swap tmp.unw 4

	# Split apart Unwrapped from two layers
	cpx_to_real tmp.unw $date1\_$date2.diff_sm_snaphu.unw $widthmli 1
	\rm tmp.unw

	# Display
	#disrmg $date1\_$date2.diff_sm_snaphu.unw $dateM.mli $widthmli 1 1 0 1.0 1. .20 0. &

	# Output raster
        rasrmg $date1\_$date2.diff_sm_snaphu.unw $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.diff_sm_snaphu.unw.tif	



	# Increment Ifgm count
	@ n++

end


# Output Montage
chdir $topdir/ifgms/
#montage -label '%f' */*.diff.unw.tif -geometry +20+2 -pointsize 40 ifgms_diff.unw.jpg
#montage -label '%f' */*.diff_sm.unw.tif -geometry +20+2 -pointsize 40 ifgms_diff_sm.unw.jpg
#montage -label '%f' */*.diff_sm_lks.unw.tif -geometry +20+2 -pointsize 40 ifgms_diff_sm_lks.unw.jpg
#montage -label '%f' */*.diff_sm_snaphu.unw.tif -geometry +20+2 -pointsize 40 ifgms_diff_sm_snaphu.unw.jpg


# Output list of interferograms to geocode
basename -a `ls $topdir/ifgms/*/????????_????????.diff_sm_snaphu.unw` | sed s/.diff_sm.unw// | sed s/_/\ / > $topdir/geocodelist.txt

# Next Step
echo sentinel_gamma_proc_geo.tcsh $dateM geocodelist.txt

