#!/bin/tcsh

if ($#argv != 2) then
  echo " "
  echo " usage: sentinel_gamma_proc_rslcs.tcsh masterdate slclist"
  echo " e.g. sentinel_gamma_proc_rslcs.tcsh 20180105 slclist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Does the resampling of the slave slcs to a common master, then successive slave slcs to previous rslc with Enhanced Spectral Diversity"
  echo " Requires:"
  echo "           that you have already run: sentinel_gamma_proc_slc.tcsh masterdate slclist"
  echo "                                 and: sentinel_gamma_proc_dem.tcsh masterdate"
  echo "           a Processing Parameter File"
  echo "           a list of dates to process (including master)"
  echo " John Elliott: 31/01/2019, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo " Last Updated: 14/05/2019, Leeds"
  exit
endif

# Already ran in previous step. 
# basename -a `ls $topdir/slcs/*/????????.slc` | sed s/.slc// > $topdir/slclist.txt


# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Date Pair
set dateM = $1

# SLC List File
set listfile = $topdir/$2
if (-e $listfile) then
        echo "Using SLC list file $listfile"
else
        echo "\033[1;31m ERROR - SLC list file $listfile missing - Exiting \033[0m"
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
#set gammaver = `grep gammaver $paramfile | awk '{print $2}'`
set gammaver = 20210701
app setup gamma/$gammaver
echo "\033[1;31m Using Gamma Version: \033[0m"
which par_S1_SLC

echo Procesing with SComplex Storage

setenv OMP_NUM_THREADS 12


# PARAMETERS
# Set which of subwaths to pull out 1,2,3
set substart = `grep substart $paramfile | awk '{print $2}'`
set subend = `grep subend $paramfile | awk '{print $2}'`
set nsubs = `echo $substart $subend | awk '{print $2-$1+1}'`
echo "Processing from Subswath $substart to $subend, a total of $nsubs subswaths"

# Number of interferograms to make with N nearest slave rslcs
set nifgms = `grep nifgms $paramfile | awk '{print $2}'`

# Number of Looks
set lksrng = `grep lksrng $paramfile | awk '{print $2}'`
set lksazi = `grep lksazi $paramfile | awk '{print $2}'`
echo Looks in range: $lksrng and azimuth: $lksazi

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`


# Pause to Read
sleep 2

#if (1 == 0) then

# Perpendicular Baseline File
if ( -e $topdir/rslc/$dateM.b_perp ) then
        echo Baseline File already exists
else
	echo $dateM 0 > $topdir/rslc/$dateM.b_perp
endif


#############################
# Start of Gamma Processing #
# TOPS SLC Registration
echo "\033[1;31m Starting TOPS SLC Registration \033[0m"

# Loop through slave images
chdir $topdir
foreach date2 ( `cat $listfile | tail -n +2` )

	if ( -e $topdir/rslc/$date2/$date2.rslc ) then
                echo RSLC $date2 already exists
                continue
        endif

	chdir $topdir	
	echo "\033[1;31m Estimating Offsets for $dateM-$date2 \033[0m"

	mkdir $topdir/rslc/$date2
	chdir $topdir/rslc/$date2
	ln -s $topdir/geodem/EQA* .
	ln -s $topdir/geodem/$dateM* .
	ln -s $topdir/slcs/$dateM/$dateM* .
	ln -s $topdir/slcs/$date2/$date2* .

	# Get width of first date multilooked and DEM
	set widthmli = `grep range_samples $dateM.mli.par | awk '{print $2}'`
	set widthdem = `grep width EQA.dem_par | awk '{print $2}'`

	# Refinement text files
	rm RSLC2_tab SLC2_tab SLC1_tab; touch RSLC2_tab SLC2_tab SLC1_tab
	set b = $substart
	while ($b <= $subend)
        	echo $date2.iw$b.rslc $date2.iw$b.rslc.par $date2.iw$b.rslc.TOPS_par >> RSLC2_tab
        	echo $date2.iw$b.slc $date2.iw$b.slc.par $date2.iw$b.slc.TOPS_par >> SLC2_tab
        	echo $dateM.iw$b.slc $dateM.iw$b.slc.par $dateM.iw$b.slc.TOPS_par >> SLC1_tab
        	@ b++
	end
	ScanSAR_coreg.py SLC1_tab $dateM.slc.par SLC2_tab $date2.slc.par RSLC2_tab - $lksrng $lksazi --it1 5 --it2 5
	
	# Calculate co-registration lookup table using rdc_trans
	rdc_trans $dateM.slc.mli.par $dateM.hgt $date2.slc.mli.par $date2.slc.mli.lt
	#dismph $date2.slc.mli.lt $widthmli
	
	# Resample SLC using Lookup Table and SLC offset
	SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $dateM.slc.par $date2.slc.mli.lt $dateM.slc.mli.par $date2.slc.mli.par - RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt
	# You may want to output screentext >& output.txt
	
	# Residual offset between master and slave SLC moasaic
	create_offset $dateM.slc.par $date2.slc.par $dateM\_$date2.off 1 $lksrng $lksazi 0
	
	# Residual difference between master RSLC mosiac and slave SLC mosaic using RSLC cross-correlation
	offset_pwr $dateM.slc $date2.rslc $dateM.slc.par $date2.rslc.par $dateM\_$date2.off $dateM\_$date2.offs $dateM\_$date2.ccp 256 64 - 1 64 64 0.1 5
	# Note Changed 12/02/2018 (version v5.4 clw/cm 20-Mar-2017 - inconsistent with manual pg 26 S1 Usres Dec 2017)

	offset_fit $dateM\_$date2.offs $dateM\_$date2.ccp $dateM\_$date2.off - - 0.1 1 0
	
	
	#################################
	# FIRST PRELIMINARY INTERFEROGRAM
	phase_sim_orb $dateM.slc.par $date2.rslc.par $dateM\_$date2.off $dateM.hgt $dateM\_$date2.sim_unw $dateM.slc.par - - 1 1
	
	# Display Simulated Ifgm
	#disrmg $dateM\_$date2.sim_unw $dateM.mli $widthmli &
	
	SLC_diff_intf $dateM.slc $date2.rslc $dateM.slc.par $date2.rslc.par $dateM\_$date2.off $dateM\_$date2.sim_unw $dateM\_$date2.diff $lksrng $lksazi 0 0 0.2 1 1 >& output.txt
	
	# Display Interferogram
	#dismph_pwr $dateM\_$date2.diff $dateM.mli $widthmli &
	
	# Output raster
	#rasmph_pwr $dateM\_$date2.diff $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $dateM\_$date2.initial.diff.tif
	
	
	# Baseline Values
	base_init $date2.rslc.par $dateM.slc.par $dateM\_$date2.off $dateM\_$date2.diff $dateM\_$date2.base 0
	base_perp $dateM\_$date2.base $date2.rslc.par $dateM\_$date2.off > $dateM\_$date2.base.perp
	
	
	###########################
	# ESTIMATE AZIMUTH OFFSET #
	###########################
	echo "\033[1;31m Initiating First Azimuth Offset $dateM-$date2 \033[0m"
	sleep 1

	# Re-iterate the process until the accuracy is a small fraction of an SLC pixel, especially in azimuth
	# (final azimuth offset poly. coeff.: <0.02)
	SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $dateM.slc.par $date2.slc.mli.lt $dateM.slc.mli.par $date2.slc.mli.par $dateM\_$date2.off RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt
	
	create_offset $dateM.slc.par $date2.slc.par $dateM\_$date2.off1 1 $lksrng $lksazi 0
	
	offset_pwr $dateM.slc $date2.rslc $dateM.slc.par $date2.rslc.par $dateM\_$date2.off1 $dateM\_$date2.offs $dateM\_$date2.ccp 256 64 - 1 64 64 0.1 5
	
	offset_fit $dateM\_$date2.offs $dateM\_$date2.ccp $dateM\_$date2.off1 - - 0.1 1 0
	echo HERE!
	
	# Test of Offset value ot test for refinement in aximuth offset
	set offtest = `grep azimuth_offset_polynomial $dateM\_$date2.off1 | awk '{print sqrt($2*$2)}' | awk '{ print ($1 < 0.01) ? 1 : 0 }'`
	if ( $offtest == 0 ) then
		echo In THE IF
		# Add the offsets together
		offset_add $dateM\_$date2.off $dateM\_$date2.off1 $dateM\_$date2.off.totalcc
		
		# Resample again with this total offset
		SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $dateM.slc.par $date2.slc.mli.lt $dateM.slc.mli.par $date2.slc.mli.par $dateM\_$date2.off.totalcc RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt

		create_offset $dateM.slc.par $date2.slc.par $dateM\_$date2.off2 1 $lksrng $lksazi 0

		offset_pwr $dateM.slc $date2.rslc $dateM.slc.par $date2.rslc.par $dateM\_$date2.off2 $dateM\_$date2.offs $dateM\_$date2.ccp 256 64 - 1 64 64 0.1 5

		offset_fit $dateM\_$date2.offs $dateM\_$date2.ccp $dateM\_$date2.off2 - - 0.1 1 0

		offset_add $dateM\_$date2.off.totalcc  $dateM\_$date2.off2 $dateM\_$date2.off.totalcc2 
		
		SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $dateM.slc.par $date2.slc.mli.lt $dateM.slc.mli.par $date2.slc.mli.par $dateM\_$date2.off.totalcc2 RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt
		
		#Output Ifgm
		phase_sim_orb $dateM.slc.par $date2.rslc.par $dateM\_$date2.off $dateM.hgt $dateM\_$date2.sim_unw $dateM.slc.par - - 1 1
		
		SLC_diff_intf $dateM.slc $date2.rslc $dateM.slc.par $date2.rslc.par $dateM\_$date2.off $dateM\_$date2.sim_unw $dateM\_$date2.diff.test1 $lksrng $lksazi 0 0 0.2 1 1
		
#		 Display Interferogram
		dismph_pwr $dateM\_$date2.diff.test1 $dateM.mli $widthmli &
		
		# Output raster
		rasmph_pwr $dateM\_$date2.diff.test1 $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $dateM\_$date2.diff.test01.tif
		convert $dateM\_$date2.diff.test01.tif $dateM\_$date2.diff.test01.png
		
	else 
		cp $dateM\_$date2.off $dateM\_$date2.off.totalcc
	endif
	


	############################
	# REFINE AZIMUTH OFFSET USING SPECTRAL DIVERSITY
	set i=1
#	while ($i < 11)
#		echo WHILE LOOP HAS BEEN ENTERED ££££££££££££££££££££££££££££££££££££££££££
	 create_offset $dateM.slc.par $date2.rslc.par $dateM\_$date2.off 1 $lksrng $lksazi 0
       		 set date1 = `grep -B1 $date2 $listfile | awk '(NR==1){print $1}'`
		if ( $date1 != $dateM ) then
#			# Refinement text files - need to use previous resampled slave to be able to maintain coherence through time.
			ln -s $topdir/rslc/$date1/$date1.iw?.rslc* .
			ln -s $topdir/rslc/$date1/$date1.rslc* .
			rm $date1.rslc.mli.tif
			rm RSLC3_tab; touch RSLC3_tab
        		set b = $substart
        		while ($b <= $subend)
                		echo $date1.iw$b.rslc $date1.iw$b.rslc.par $date1.iw$b.rslc.TOPS_par >> RSLC3_tab
                		@ b++
        		end
			S1_coreg_overlap SLC1_tab RSLC2_tab $dateM\_$date2 $dateM\_$date2.off $dateM\_$date2.off.esd 0.8 0.01 0.8 1 RSLC3_tab >& output.txt
		else
			S1_coreg_overlap SLC1_tab RSLC2_tab $dateM\_$date2 $dateM\_$date2.off $dateM\_$date2.off.esd 0.8 0.01 0.8 1 >& output.txt
		endif
#		echo $i THE LOOP IS HERE 
		# Resample again with this corrected offset
	SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $dateM.slc.par $date2.slc.mli.lt $dateM.slc.mli.par $date2.slc.mli.par $dateM\_$date2.off.esd RSLC2_tab $date2.rslc $date2.rslc.par  >& output.txt
		
#		@ i++
#	end
	
	#################################
	# SECOND PRELIMINARY INTERFEROGRAM
	create_offset $date1.rslc.par $date2.rslc.par $date1\_$date2.off 1 $lksrng $lksazi 0
#	phase_sim_orb $date1.rslc.par $date2.rslc.par $date1\_$date2.off $dateM.hgt $date1\_$date2.sim_unw $date1.rslc.par - - 1 1
	
	# Display Simulated Ifgm
	#disrmg $date1\_$date2.sim_unw $dateM.mli $widthmli &
	echo HERE
	SLC_diff_intf $date1.rslc $date2.rslc $date1.rslc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.sim_unw $date1\_$date2.diff $lksrng $lksazi 0 0 0.2 1 1 >& output.txt
	
	# Display Interferogram
	dismph_pwr $date1\_$date2.diff $dateM.mli $widthmli &
	
	# Output raster
	rasmph_pwr $date1\_$date2.diff $dateM.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.esd.diff.tif


        # Create Multi-looked image of resampled slc
	multi_look_ScanSAR RSLC2_tab $date2.rslc.mli $date2.rslc.mli.par $lksrng $lksazi 0 SLC1_tab 		
 
	# Output mosaic mli
        raspwr $date2.rslc.mli $widthmli 1 0 $raspixavr $raspixavaz 1. 0.20 1 $date2.rslc.mli.tif



	# Output baseline relative to master
	base_init $dateM.slc.par $date2.rslc.par $dateM\_$date2.off - $dateM\_$date2.base 1
	base_perp $dateM\_$date2.base $date2.rslc.par $dateM\_$date2.off > $dateM\_$date2.base.perp
	set bperp = `awk '(NR>12){print $8}' $dateM\_$date2.base.perp | awk '(NF>0){SUM+=$1} END {print int(SUM/NR)}'`
	touch $topdir/rslc/$dateM.b_perp
	echo $date2 $bperp >> $topdir/rslc/$dateM.b_perp

	# Increment Slave Image
	@ n++
end





# Output list of rslcs that worked
chdir $topdir
basename -a `ls $topdir/rslc/*/????????.rslc` | sed s/.rslc// | sort -n -u > $topdir/tmp.txt
set nepochs = `wc -l tmp.txt | awk '{print $1}'`

# Generate list of interferograms to form from the NIFGMS nearest rslcs
set n = 1
touch tmp2.txt
while ( $n < $nepochs )
	set m = `awk '(NR=='$n'){print $1}' tmp.txt`
	set i = 1
       
	while ( $i <= $nifgms )
		echo $m `awk '(NR=='$n'+'$i'){print $1}' tmp.txt` >> tmp2.txt
		@ i++ 
	end
	
	@ n++
end
awk '(NF==2){print $1, $2}' tmp2.txt > ifgmlist.txt
rm tmp.txt tmp2.txt

# Output Montage
chdir $topdir/rslc
montage -label '%f' */*.rslc.mli.tif -geometry +20+2 -pointsize 40 rslcs.jpg

# Next step
echo sentinel_gamma_proc_ifgms.tcsh $dateM ifgmlist.txt

