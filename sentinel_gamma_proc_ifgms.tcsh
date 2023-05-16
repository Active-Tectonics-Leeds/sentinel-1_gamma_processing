#!/bin/tcsh

if ($#argv != 2) then
  echo " "
  echo " usage: sentinel_gamma_proc_ifgms.tcsh masterdate interferogramlist.txt"
  echo " e.g. sentinel_gamma_proc_ifgms.tcsh 20180105 ifgmlist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Requires:"
  echo "           that you have already run: sentinel_gamma_proc_rslc.tcsh masterdate slclist"
  echo "           DEM of the area"
  echo "           a Processing Parameter File"
  echo "           a list of interferogram date pairs to process"
  echo "John Elliott: 24/10/2018, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 14/05/2019, Leeds"
  exit
endif

# Make a list of interferograms

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Master Date (for geodem)
set dateM = $1
echo Using Master Date: $dateM

# Interferogram List File
set listfile = $topdir/$2
if (-e $listfile) then
        echo "Using interferogram list file $listfile"
else
        echo "\033[1;31m ERROR - Interferogram list file $listfile missing - Exiting \033[0m"
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

# Number of filtering iterations
set nfilt = `grep nfilt $paramfile | awk '{print $2}'`

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`



# Start of Gamma Processing

# Loop through ifgms to make
mkdir $topdir/ifgms 
set nifgms = `wc $listfile | awk '{print $1}'`
echo Looping through $nifgms interferograms
set n = 1

while ( $n <= $nifgms )
        
        chdir $topdir
	# Date Pair
	set date1 = `awk '(NR=='$n'){print $1}' $listfile`
	set date2 = `awk '(NR=='$n'){print $2}' $listfile`

	echo $date1-$date2 

	# Test if output ifgms already exist
	if ( -e $topdir/output/$date1-$date2 ) then
                echo Interferogram $date1-$date2 already considered processed in output
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
	# TOPS SLC Registration
	echo "\033[1;31m Starting Interfeogram $date1-$date2 \033[0m"
	mkdir $topdir/ifgms/$date1-$date2
	chdir $topdir/ifgms/$date1-$date2
	ln -s $topdir/geodem/EQA* .
	ln -s $topdir/geodem/$dateM* .
	ln -s $topdir/rslc/$dateM/$dateM.mli* .
	ln -s $topdir/rslc/$date1/$date1* .
	ln -s $topdir/rslc/$date2/$date2* .

	# Get width of first date multilooked and DEM
	set widthmli = `grep range_samples $dateM.mli.par | awk '{print $2}'`
	set widthdem = `grep width EQA.dem_par | awk '{print $2}'`


	###########################
	# INTERFEROGRAM
	create_offset $date1.rslc.par $date2.rslc.par $date1\_$date2.off 1 $lksrng $lksazi 0
	phase_sim_orb $date1.rslc.par $date2.rslc.par $date1\_$date2.off $dateM.hgt $date1\_$date2.sim_unw $date1.rslc.par - - 1 1

	SLC_diff_intf $date1.rslc $date2.rslc $date1.rslc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.sim_unw $date1\_$date2.diff $lksrng $lksazi 0 0 0.2 1 1

	# Baseline Values
        base_init $date2.rslc.par $date1.rslc.par $date1\_$date2.off $date1\_$date2.diff $date1\_$date2.base 0
        base_perp $date1\_$date2.base $date2.rslc.par $date1\_$date2.off > $date1\_$date2.base.perp
	set bperp = `awk '(NR>12){print $8}' $date1\_$date2.base.perp | awk '(NF>0){SUM+=$1} END {print int(SUM/NR)}'`
	set bperp1 = `grep $date1 $topdir/rslc/$dateM.b_perp | awk '(NR=1){print $2}'`
	set bperp2 = `grep $date2 $topdir/rslc/$dateM.b_perp | awk '(NR=1){print $2}'`
	set sm = `date --date="$dateM" +%s`
	set s1 = `date --date="$date1" +%s`
	set s2 = `date --date="$date2" +%s`
	set ndays12 = `echo $s1 $s2 | awk '{print ($2-$1)/86400}'`
	set ndays1 = `echo $sm $s1 | awk '{print ($2-$1)/86400}'`
	set ndays2 = `echo $sm $s2 | awk '{print ($2-$1)/86400}'`
	touch $topdir/b.perp
	echo $n $date1 $date2 $bperp $ndays12 $ndays1 $ndays2 $bperp1 $bperp2  | awk '{printf "%4i %i %i %5.1i %4.1i %4.1i %4.1i %5.1i %5.1i\n", $1, $2, $3, $4, $5, $6, $7, $8, $9}' >> $topdir/b.perp 

	# Display Interferogram
	#dismph_pwr $date1\_$date2.diff $dateM.mli $widthmli &

	# Output raster
	rasmph_pwr $date1\_$date2.diff $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff.tif



	#############
	# FILTERING #
	#############

	###########################
	adf $date1\_$date2.diff $date1\_$date2.diff_sm1 $date1\_$date2.smcc $widthmli 0.3 64 7 - 0 - 0.2

	if ( $nfilt == 1 ) then
		\mv $date1\_$date2.diff_sm1 $date1\_$date2.diff_sm 
	else if ( $nfilt == 2 ) then
		# 2nd Filter
	        adf $date1\_$date2.diff_sm1 $date1\_$date2.diff_sm2 $date1\_$date2.smcc $widthmli 0.4 32 7 - 0 - 0.2
        	rasmph_pwr $date1\_$date2.diff_sm2 $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm2.tif
		\mv $date1\_$date2.diff_sm2 $date1\_$date2.diff_sm ; \rm $date1\_$date2.diff_sm1 
	else
		# 3rd Filter
        	adf $date1\_$date2.diff_sm1 $date1\_$date2.diff_sm2 $date1\_$date2.smcc $widthmli 0.4 32 7 - 0 - 0.2
        	rasmph_pwr $date1\_$date2.diff_sm2 $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm2.tif
		adf $date1\_$date2.diff_sm2 $date1\_$date2.diff_sm3 $date1\_$date2.smcc $widthmli 0.5 16 7 - 0 - 0.2
        	rasmph_pwr $date1\_$date2.diff_sm3 $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm3.tif
		\mv $date1\_$date2.diff_sm3 $date1\_$date2.diff_sm ; \rm $date1\_$date2.diff_sm2

	endif
	
	rasmph_pwr $date1\_$date2.diff_sm $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm.tif
 
	# Display Filtered Ifgm & Coherence
	#dismph_pwr $date1\_$date2.diff_sm $dateM.mli $widthmli &
	#discc $date1\_$date2.smcc $dateM.mli $widthmli


	# Coherence
	# Do on unsmoothed interferogram
	# Window currently at 5x5. (also triangular weighting - difference not investigated)
	cc_wave $date1\_$date2.diff $date1.rslc.mli $date2.rslc.mli $date1\_$date2.cc $widthmli 5 5 1

	#discc $date1\_$date2.cc $dateM.mli $widthmli

	# Output Coherence
	rascc $date1\_$date2.cc $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 0.1 0.9 1.0 .35 1 $date1\_$date2.cc.tif
	rascc $date1\_$date2.smcc $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 0.1 0.9 1.0 .35 1 $date1\_$date2.smcc.tif


	# Increment Ifgm count
	@ n++

end


# Output Montage
chdir $topdir/ifgms/
#montage -label '%f' */*.diff.tif -geometry +20+2 -pointsize 40 ifgms_diff.jpg
#montage -label '%f' */*.diff_sm.tif -geometry +20+2 -pointsize 40 ifgms_diff_sm.jpg
#montage -label '%f' */*.cc.tif -geometry +20+2 -pointsize 40 ifgms_cc.jpg
#montage -label '%f' */*.smcc.tif -geometry +20+2 -pointsize 40 ifgms_smcc.jpg


# Output list of interferograms to unwrap
basename -a `ls $topdir/ifgms/*/????????_????????.diff` | sed s/.diff// | sed s/_/\ / > $topdir/unwraplist.txt

# Next Step
echo sentinel_gamma_proc_unwrap.tcsh $dateM unwraplist.txt
