#!/bin/tcsh 

if ($#argv != 2) then
  echo " "
  echo " usage: sentinel_gamma_proc_slcs.tcsh masterdate datelist"
  echo " e.g. sentinel_gamma_proc_slcs.tcsh 20180105 datelist.txt"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Does the unzip, extract tiff/xml info, orbit state vector, slc generation, mosaicing, matching to master extent, and DEM/lookup tables"
  echo " Requires:"
  echo "           zipfiles"
  echo "           DEM of the area"
  echo "           a Processing Parameter File proc.param"
  echo "           a list of dates to process (excluding master)"
  echo " "
  echo " Make list of dates (removing the master)"
  echo " "
  echo "John Elliott: 31/01/2019, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 14/05/2019, Leeds"
  exit
endif
  
# List of master dates
# ls -d safes/*SAFE | awk '{print substr($1,24,8)}' | sort -n -u | awk '($1!='$dateM') {print $1}' > datelist.txt


# GAMMA Commands Run
# par_S1_SLC 
# S1_OPOD_vec
# SLC_cat_ScanSAR (previously SLC_cat_S1_TOPS)
# disSLC
# rasSLC 
# dismph_fft
# SLC_copy_ScanSAR (previously SLC_copy_S1_TOPS)
# S1_BURST_tab
# multi_look_ScanSAR (previously multi_S1_TOPS)
# dispwr
# raspwr
# SLC_mosaic_S1_TOPS
# multi_look
# swap_bytes
# create_dem_par
# disdem_par
# gc_map
# pixel_area
# dis2pwr
# create_diff_par
# offset_pwrm
# offset_fitm
# gc_map_fine
# dismph 
# geocode_back
# dispwr
# geocode
# dishgt
# rdc_trans
# SLC_interp_lt_ScanSAR (previously SLC_interp_lt_S1_TOPS)
# create_offset
# offset_pwr
# offset_fit
# phase_sim_orb
# disrmg
# SLC_diff_intf 
# dismph_pwr
# rasmph_pwr
# base_init
# base_perp
# offset_add
# S1_coreg_overlap
# adf 
# discc 
# rascc
# cc_wave
# rascc_mask
# mcf 
# cpx_to_real
# look_vector
# SLC_deramp_S1_TOPS
# sub_phase
# offset_pwr_tracking
# offset_tracking
# rashgt
# 

# Other Utilities (not necessarily within this script)
# 7z - 7-zip
# GMT - grdmath, grdfilter, xyz2grd, ps2raster, psscale, grdimage, psbasemap, grdclip, grdinfo, gmtset, makecpt, grdtrend, grd2cpt, grdgradient
# montage
# convert
# gdal_translate
# zip
# tar
# snaphu 

# Scripts Called
#
# png2kml_logos.tcsh
# ers_binary_to_grd.gmt4.tcsh
# create_ers_header.tcsh


# Full Chain
# sentinel_gamma_proc_slcs.tcsh $dateM datelist.txt; sentinel_gamma_proc_dem.tcsh $dateM; sentinel_gamma_proc_rslcs.tcsh $dateM slclist.txt; sentinel_gamma_proc_ifgms.tcsh $dateM ifgmlist.txt; sentinel_gamma_proc_unwrap.tcsh $dateM unwraplist.txt; sentinel_gamma_proc_geo.tcsh $dateM geocodelist.txt; sentinel_gamma_proc_out.tcsh outputlist.txt



# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Date Pair (DateS is a list of slave dates)
set dateM = $1
set dateS = $2

# Epoch List File
if (-e $dateS) then
        echo "Using Epoch list file $dateS"
else
        echo "\033[1;31m ERROR - Epoch list file $dateS missing - Exiting \033[0m"
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
# Set which of subwaths to pull out 1,2,3
set substart = `grep substart $paramfile | awk '{print $2}'`
set subend = `grep subend $paramfile | awk '{print $2}'`
set nsubs = `echo $substart $subend | awk '{print $2-$1+1}'`
echo "Processing from Subswath $substart to $subend, a total of $nsubs subswaths"
set extractburst = `grep extractburst $paramfile | awk '{print $2}'`
if ( $extractburst == 1 ) then
	if (-e $topdir/burstlist.txt) then
        	echo "\033[1;31m NOTE - Extracting subset of bursts \033[0m"
		more $topdir/burstlist.txt
	else
        	echo "\033[1;31m ERROR - Burst subset list does not exist \033[0m"
		exit
	endif
	
	# Test if correct number of lines in burstlist
	set linetest = `awk '(NF==2){print $0}' burstlist.txt | wc -l`
	if ( $linetest != $nsubs ) then
		echo "\033[1;31m ERROR - Not enough lines of burst numbers in burstlist.txt to match number of subswaths \033[0m"
		exit
	endif
endif


# Number of Looks
set lksrng = `grep lksrng $paramfile | awk '{print $2}'`
set lksazi = `grep lksazi $paramfile | awk '{print $2}'`
echo Looks in range: $lksrng and azimuth: $lksazi

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`


# Pause to Read
sleep 2



# Unzip Files
mkdir $topdir/slcs $topdir/safes
#chdir $topdir/zips
#foreach zipfile (*zip)
	#echo $zipfile
	#7z x $zipfile -o$topdir/safes
#end




# Test if Master RSLC Exists and link across files for making slave slcs same extent
if ( -e $topdir/rslc/$dateM/$dateM.rslc ) then
	echo Master RSLC exists - linking to slcs directory	

	mkdir $topdir/slcs $topdir/slcs/$dateM
	chdir $topdir/slcs/$dateM
	set b = $substart
	while ($b <= $subend)

        	ln -s $topdir/rslc/$dateM/$dateM.iw$b.rslc $dateM.iw$b.slc
        	ln -s $topdir/rslc/$dateM/$dateM.iw$b.rslc.par $dateM.iw$b.slc.par
        	ln -s $topdir/rslc/$dateM/$dateM.iw$b.rslc.TOPS_par $dateM.iw$b.slc.TOPS_par

        	@ b++
	end
	ln -s $topdir/rslc/$dateM/$dateM.rslc $dateM.slc
	ln -s $topdir/rslc/$dateM/$dateM.rslc.par $dateM.slc.par
	ln -s $topdir/rslc/$dateM/$dateM.rslc.mli $dateM.slc.mli
	ln -s $topdir/rslc/$dateM/$dateM.rslc.mli.par $dateM.slc.mli.par
	ln -s $topdir/rslc/$dateM/$dateM.mli* .
	ln -s $topdir/rslc/$dateM/SLC_tab$dateM .
endif


#############################
# Start of Gamma Processing #

# Loop through the two dates
chdir $topdir
foreach date ( $dateM `cat $dateS` )

	if ( -e $topdir/rslc/$date/$date.rslc ) then
		echo RSLC $date already exists
		continue
	endif
	
	# Make Date directory and enter
	chdir $topdir
	echo Processing Date: $date
	mkdir slcs/$date; chdir slcs/$date

	# Determine the number of scenes
	ls $topdir/safes | grep $date > scenes.list
	set nscenes = `wc -l scenes.list | awk '{print $1}'`
	echo Number of Scenes on date $date to Process: $nscenes
	set scene = 1
	
	# Loop through Scenes
	while ( $scene <= $nscenes )
		set safefile = $topdir/safes/`awk '(NR=='$scene'){print $1}' scenes.list`
		mkdir scene$scene; chdir scene$scene				
		\rm SLC_tab$scene; touch SLC_tab$scene

		# Loop Through Subswaths
		set b = $substart
		while ( $b <= $subend )
			# Normal VV - Note outputting SCOMPLEX
			echo $safefile
        		par_S1_SLC $safefile/measurement/s1?-iw$b-slc-vv*.tiff $safefile/annotation/s1?-iw$b-slc-vv*.xml $safefile/annotation/calibration/calibration-s1?-iw$b-slc-vv*.xml $safefile/annotation/calibration/noise-s1?-iw$b-slc-vv*.xml $date.$scene.iw$b.all.slc.par $date.$scene.iw$b.all.slc $date.$scene.iw$b.all.slc.TOPS_par 1

			# Apply Precise Orbits if available - two week delay - downloaded daily by contrab on hal
			# Determine Satellite to pull correct orbit file
	                set sat = `echo $safefile | awk -F/ '{print substr($NF,3,1)}'`
			set nextday = `date --date=''$date' next day' +%Y%m%d`

		#	S1_OPOD_vec $date.$scene.iw$b.all.slc.par /nfs/a285/share/orbits_s1/precise_orbits/S1$sat\_OPER_AUX_POEORB_OPOD_*$nextday\T??????.EOF
			S1_OPOD_vec $date.$scene.iw$b.all.slc.par /nfs/a285/homes/ee18jwc/datasets/orbital_data/S1$sat/S1$sat\_OPER_AUX_POEORB_OPOD_*$nextday\T??????.EOF
			# Output SLC_tab text file
			echo $date.$scene.iw$b.all.slc $date.$scene.iw$b.all.slc.par $date.$scene.iw$b.all.slc.TOPS_par >> SLC_tab$scene

			@ b++
		end
		chdir ../	

		@ scene++
	end

end




# Concatenate Files
chdir $topdir
foreach date ( $dateM `cat $dateS` )
	
	if ( -e $topdir/rslc/$date/$date.rslc ) then
		echo RSLC $date already exists
		continue
	endif
	
	chdir $topdir/slcs/$date
	mkdir concat; chdir concat
	ln -s ../scene*/*slc* .
	ln -s ../scene*/SLC_tab* .
	
	# Determine the number of scenes
	ls $topdir/safes | grep $date > scenes.list
	set nscenes = `wc -l scenes.list | awk '{print $1}'`
	echo Number of Scenes on date $date to Process: $nscenes

	set b = $substart
	while ( $b <= $subend )

		# Make the text SLC tab output (all you need for one or two scenes)i
		touch SLC_tab$date
		echo $date.iw$b.all.slc $date.iw$b.all.slc.par $date.iw$b.all.slc.TOPS_par >> SLC_tab$date

		if ( $nscenes == 3 ) then
			touch SLC_tab1-2
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			#Don't need to make a tab3 as already exists
		else if ( $nscenes == 4 || $nscenes == 5 ) then
			touch SLC_tab1-2 SLC_tab3-4	
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
		else if ( $nscenes == 6 ) then
			touch SLC_tab1-2 SLC_tab3-4 SLC_tab1-4 SLC_tab5-6
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
		else if ( $nscenes == 7 ) then
			touch SLC_tab1-2 SLC_tab3-4 SLC_tab1-4 SLC_tab5-6 SLC_tab1-6
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
		else if ( $nscenes == 8 ) then
			touch SLC_tab1-2 SLC_tab3-4 SLC_tab1-4 SLC_tab5-6 SLC_tab1-6 SLC_tab7-8
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
			echo $date.7-8.iw$b.all.slc $date.7-8.iw$b.all.slc.par $date.7-8.iw$b.all.slc.TOPS_par >> SLC_tab7-8
		else if ( $nscenes == 16 ) then
			touch SLC_tab1-2 SLC_tab3-4 SLC_tab1-4 SLC_tab5-6 SLC_tab1-6 SLC_tab7-8 SLC_tab1-8 SLC_tab9-10 SLC_tab1-10 SLC_tab11-12 SLC_tab1-12 SLC_tab13-14 SLC_tab1-14 SLC_tab15-16 SLC_tab1-16
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
			echo $date.7-8.iw$b.all.slc $date.7-8.iw$b.all.slc.par $date.7-8.iw$b.all.slc.TOPS_par >> SLC_tab7-8
			echo $date.1-8.iw$b.all.slc $date.1-8.iw$b.all.slc.par $date.1-8.iw$b.all.slc.TOPS_par >> SLC_tab1-8
                        echo $date.9-10.iw$b.all.slc $date.9-10.iw$b.all.slc.par $date.9-10.iw$b.all.slc.TOPS_par >> SLC_tab9-10
                        echo $date.1-10.iw$b.all.slc $date.1-10.iw$b.all.slc.par $date.1-10.iw$b.all.slc.TOPS_par >> SLC_tab1-10
                        echo $date.11-12.iw$b.all.slc $date.11-12.iw$b.all.slc.par $date.11-12.iw$b.all.slc.TOPS_par >> SLC_tab11-12
                        echo $date.1-12.iw$b.all.slc $date.1-12.iw$b.all.slc.par $date.1-12.iw$b.all.slc.TOPS_par >> SLC_tab1-12
			echo $date.13-14.iw$b.all.slc $date.13-14.iw$b.all.slc.par $date.13-14.iw$b.all.slc.TOPS_par >> SLC_tab13-14
                        echo $date.1-14.iw$b.all.slc $date.1-14.iw$b.all.slc.par $date.1-14.iw$b.all.slc.TOPS_par >> SLC_tab1-14
			echo $date.15-16.iw$b.all.slc $date.15-16.iw$b.all.slc.par $date.15-16.iw$b.all.slc.TOPS_par >> SLC_tab15-16
                        echo $date.1-16.iw$b.all.slc $date.1-16.iw$b.all.slc.par $date.1-16.iw$b.all.slc.TOPS_par >> SLC_tab1-16
		endif

		@ b++
	# End burst loop
	end

	# Rename files if just single scene
	if ( $nscenes == 1 ) then
		set b = $substart
        	while ( $b <= $subend )
			\mv $date.1.iw$b.all.slc $date.iw$b.all.slc
			\mv $date.1.iw$b.all.slc.par $date.iw$b.all.slc.par
			\mv $date.1.iw$b.all.slc.TOPS_par $date.iw$b.all.slc.TOPS_par
			@ b++
		end 
	endif
	
	# Concatenate Files for two or more scenes - need more if clauses for longer ones
	if ( $nscenes == 2 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab$date
	else if ( $nscenes == 3 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3 SLC_tab$date
	else if ( $nscenes == 4 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab$date
	else if ( $nscenes == 5 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab3-4 SLC_tab5 SLC_tab$date
	else if ( $nscenes == 6 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
		SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab$date
	else if ( $nscenes == 7 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
		SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab1-6  
		SLC_cat_ScanSAR  SLC_tab1-6 SLC_tab7 SLC_tab$date
	else if ( $nscenes == 8 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
		SLC_cat_ScanSAR  SLC_tab7 SLC_tab8 SLC_tab7-8
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
		SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab1-6  
		SLC_cat_ScanSAR  SLC_tab1-6 SLC_tab7-8 SLC_tab$date
	else if ( $nscenes == 16 ) then
                SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
                SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
                SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
                SLC_cat_ScanSAR  SLC_tab7 SLC_tab8 SLC_tab7-8
                SLC_cat_ScanSAR  SLC_tab9 SLC_tab10 SLC_tab9-10
                SLC_cat_ScanSAR  SLC_tab11 SLC_tab12 SLC_tab11-12
		SLC_cat_ScanSAR  SLC_tab13 SLC_tab14 SLC_tab13-14
                SLC_cat_ScanSAR  SLC_tab15 SLC_tab16 SLC_tab15-16
                SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
                SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab1-6
                SLC_cat_ScanSAR  SLC_tab1-6 SLC_tab7-8 SLC_tab1-8
                SLC_cat_ScanSAR  SLC_tab1-8 SLC_tab9-10 SLC_tab1-10
                SLC_cat_ScanSAR  SLC_tab1-10 SLC_tab11-12 SLC_tab1-12
                SLC_cat_ScanSAR  SLC_tab1-12 SLC_tab13-14 SLC_tab1-14
                SLC_cat_ScanSAR  SLC_tab1-14 SLC_tab15-16 SLC_tab$date
	endif

	
	# Make images	
	set b = $substart
	while ( $b <= $subend )
        	set widthslc = `grep range_samples $date.iw$b.all.slc.par | awk '{printf "%i ", $2}'`
		#disSLC $date.iw$b.all.slc $widthslc 1 2000 1. .35 1 &

	        # Generate Quicklook of entire subswath
        	rasSLC $date.iw$b.all.slc $widthslc 1 0 50 10 1. 0.35 1 1 0 $date.iw$b.all.slc.tif
        	@ b++
	end

	# Stick them into a single image if multiple subswaths
	if ( $nsubs > 1 ) then
		montage $date.iw[$substart-$subend].all.slc.tif -tile $nsubs\x1 -geometry +0+0 $date.iw$substart-$subend.all.slc.tif
		\rm $date.iw[$substart-$subend].all.slc.tif
	endif
	\cp $date.iw*.all.slc.tif ../

	# Display Spectra Wrapping - just display phase to see cycles within burst of each subswath	
	#dismph_fft $date.iw$subend.all.slc $widthslc 1 4000 1. .35 32 4 1 &
end



# Extract subset of bursts from Master
if ( -e $topdir/rslc/$dateM/$dateM.rslc ) then
	echo Master RSLC $dateM already exists
else
	chdir $topdir/slcs/$dateM/concat

	if ( $extractburst == 1 ) then
		# Create output copy tab file
		\rm SLC_tabcopy; touch SLC_tabcopy
		set b = $substart
		while ($b <= $subend)
        		echo $dateM.iw$b.crop.slc $dateM.iw$b.crop.slc.par $dateM.iw$b.crop.slc.TOPS_par >> SLC_tabcopy
        		@ b++
		end
		SLC_copy_ScanSAR SLC_tab$dateM SLC_tabcopy $topdir/burstlist.txt	
	
		# Make images	
		set b = $substart
		while ( $b <= $subend )
        		set widthslc = `grep range_samples $dateM.iw$b.crop.slc.par | awk '{printf "%i ", $2}'`
			#disSLC $dateM.iw$b.crop.slc $widthslc 1 2000 1. .35 1 &

	        	# Generate Quicklook of entire subswath
        		rasSLC $dateM.iw$b.crop.slc $widthslc 1 0 50 10 1. 0.35 1 1 0 $dateM.iw$b.crop.slc.tif
        		@ b++
		end
		# Stick them into a single image if multiple subswaths
		if ( $nsubs > 1 ) then
			montage $dateM.iw[$substart-$subend].crop.slc.tif -tile $nsubs\x1 -geometry +0+0 $dateM.iw$substart-$subend.crop.slc.tif
			\rm $dateM.iw[$substart-$subend].crop.slc.tif
		endif
		\cp $dateM.iw*.crop.slc.tif ../

		# Rename cropped files back to all
		set b = $substart
        	while ( $b <= $subend )
			\mv $dateM.iw$b.crop.slc $dateM.iw$b.all.slc
			\mv $dateM.iw$b.crop.slc.par $dateM.iw$b.all.slc.par
			\mv $dateM.iw$b.crop.slc.TOPS_par $dateM.iw$b.all.slc.TOPS_par
			@ b++
		end
	endif


	# Copy files and rename master (note problem if moved, as moves links if extractbursts not used).
	chdir $topdir/slcs/$dateM
	set b = $substart
	while ( $b <= $subend )
		\cp concat/$dateM.iw$b.all.slc $dateM.iw$b.slc 
		\cp concat/$dateM.iw$b.all.slc.par $dateM.iw$b.slc.par 
		\cp concat/$dateM.iw$b.all.slc.TOPS_par $dateM.iw$b.slc.TOPS_par
        	@ b++
	end
	# Rename files in burst tab to match those just copied across above
	sed 's/all.//g' concat/SLC_tab$dateM > SLC_tab$dateM
	\rm -r scene? concat scenes.list

endif


# Generate Burst Numbers to Pull Out which ones to copy
chdir $topdir
foreach date ( `cat $dateS` )

	if ( -e $topdir/rslc/$date/$date.rslc ) then
                echo RSLC $date already exists
                continue
        endif

	chdir $topdir/slcs/$date/concat 
	ln -s $topdir/slcs/$dateM/$dateM.iw*par .
	ln -s $topdir/slcs/$dateM/SLC_tab$dateM .
	S1_BURST_tab SLC_tab$dateM SLC_tab$date BURST_tab

	# Create output copy tab file
	\rm SLC_tabcopy; touch SLC_tabcopy
	set b = $substart
	while ($b <= $subend)
        	echo $date.iw$b.slc $date.iw$b.slc.par $date.iw$b.slc.TOPS_par >> SLC_tabcopy
        	@ b++
	end

	# Extract out required bursts from slave
	SLC_copy_ScanSAR SLC_tab$date SLC_tabcopy BURST_tab
	\mv $date.iw?.slc* ../
	chdir ../
	\rm -r scene? concat scenes.list

end



# MLI Mosaic 20 secs
# output bursts to be considered into tab delimited file
chdir $topdir
foreach date ( $dateM `cat $dateS` ) 

	if ( -e $topdir/rslc/$date/$date.rslc ) then
                echo RSLC $date already exists
                continue
        endif

	chdir $topdir/slcs/$date
	\rm SLC_tab; touch SLC_tab
	set b = $substart
	while ( $b <= $subend )
        	echo $date.iw$b.slc $date.iw$b.slc.par $date.iw$b.slc.TOPS_par >> SLC_tab
	        @ b++
	end

	multi_look_ScanSAR SLC_tab $date.mli $date.mli.par $lksrng $lksazi
	
	set widthmli = `grep range_samples $date.mli.par | awk '{print $2}'`
	
	# Display MLI
	#dispwr $date.mli $widthmli 1 0 1. .35 0 &

	# Output mosaic mli
	raspwr $date.mli $widthmli 1 0 $raspixavr $raspixavaz 1. 0.20 1 $date.mli.tif

	# SLC Mosaic
	# N.B. Doppler Centroid will vary strongly within mosaic with large steps at the interface between bursts
	# When using SLC for interferometery, need to know what multi-looking will be used later on to connect bursts
	SLC_mosaic_S1_TOPS SLC_tab $date.slc $date.slc.par $lksrng $lksazi

	# Multilook
	multi_look $date.slc $date.slc.par $date.slc.mli $date.slc.mli.par $lksrng $lksazi

end


# Copy across Master SLC to RSLC so there is an rslc directory and copies of files for ifgm making
if ( -e $topdir/rslc/$date/$date.rslc ) then
	echo Master RSLC $date already exists
else
	mkdir $topdir/rslc $topdir/rslc/$dateM
	chdir $topdir/rslc/$dateM
	set b = $substart
	while ($b <= $subend)
		
        	\cp $topdir/slcs/$dateM/$dateM.iw$b.slc $dateM.iw$b.rslc
        	\cp $topdir/slcs/$dateM/$dateM.iw$b.slc.par $dateM.iw$b.rslc.par
        	\cp $topdir/slcs/$dateM/$dateM.iw$b.slc.TOPS_par $dateM.iw$b.rslc.TOPS_par
		
        	@ b++
	end
	\cp $topdir/slcs/$dateM/$dateM.slc $dateM.rslc
	\cp $topdir/slcs/$dateM/$dateM.slc.par $dateM.rslc.par
	\cp $topdir/slcs/$dateM/$dateM.slc.mli $dateM.rslc.mli
	\cp $topdir/slcs/$dateM/$dateM.slc.mli.par $dateM.rslc.mli.par
	\cp $topdir/slcs/$dateM/$dateM.mli* .
	\cp $topdir/slcs/$dateM/$dateM.mli.tif $dateM.rslc.mli.tif 
	\cp $topdir/slcs/$dateM/SLC_tab$dateM .
endif



# Output list of slcs that worked
basename -a `ls $topdir/slcs/*/????????.slc` | sed s/.slc// > $topdir/slclist.txt
# If this is not the first run, need to identify the previous most recent rslc which is used in the ESD step
if ( -e $topdir/rslc/$dateM/$dateM.rslc ) then
	basename -a `ls $topdir/rslc/*/????????.rslc` | sort -u | sed s/.rslc// > tmp.txt
	basename -a `ls $topdir/slcs/*/????????.slc` | sed s/.slc// >> tmp.txt
	sort -n -u tmp.txt > $topdir/slclist.txt
	\rm tmp.txt
endif

# Output Montage
chdir $topdir/slcs
#montage -label '%f' */*.mli.tif -geometry +20+2 -pointsize 40 slcs.jpg


# Next step
if ( -e $topdir/geodem/$dateM.hgt ) then
	echo sentinel_gamma_proc_rslcs.tcsh $dateM slclist.txt
else
	echo sentinel_gamma_proc_dem.tcsh $dateM
endif

