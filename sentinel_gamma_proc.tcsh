#!/bin/tcsh

if ($#argv != 2) then
  echo " "
  echo "usage: sentinel_gamma_proc.tcsh masterdate slavedate"
  echo "e.g. sentinel_gamma_proc.tcsh 20180607 20181005"
  echo "Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Requires:"
  echo "           zipfiles"
  echo "           DEM of the area"
  echo "           a Processing Parameter File"
  echo "John Elliott: 24/10/2018, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 04/04/2019, Leeds"
  exit
endif

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

# Other Utilities
# 7z - 7-zip
# GMT - grdmath, grdfilter, xyz2grd, ps2raster, psscale, grdimage, psbasemap, grdclip, grdinfo, gmtset, makecpt, grdtrend, grd2cpt, grdgradient
# montage
# convert
# gdal_translate 
# zip
# tar
# snaphu (not implemented)

# Scripts Called
# 
# png2kml_logos.tcsh
# ers_binary_to_grd.gmt4.tcsh
# create_ers_header.tcsh

# Date Pair
set date1 = $1
set date2 = $2

# Select Gamma Version
app setup gamma/20181130
#app setup gamma/20180704
#app setup gamma/20171201
echo "\033[1;31m Using Gamma Version: \033[0m"
which par_S1_SLC

echo Procesing with SComplex Storage

setenv OMP_NUM_THREADS 12


# Set GMTDEFAULT Paper Size so kmz files in correct place
app setup gmt/4.5.15
echo Running GMT Version 4


# Test if Dates in right order
if ( $date1 >= $date2 ) then
	echo "\033[1;31m ERROR - First date after second date - Exiting \033[0m"
exit
endif

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir
mkdir $topdir/slcs $topdir/safes

# Parameter File
set paramfile = $topdir/proc.param
if (-e $paramfile) then
        echo "Using parameter file $paramfile"
else
	echo "\033[1;31m ERROR - Parameter file $paramfile missing - Exiting \033[0m"
        exit
endif

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
endif

# Number of Looks
set lksrng = `grep lksrng $paramfile | awk '{print $2}'`
set lksazi = `grep lksazi $paramfile | awk '{print $2}'`
echo Looks in range: $lksrng and azimuth: $lksazi


# DEM
set dem = `grep demname $paramfile | awk '{print $2}'`
set demlat = `grep demlat $paramfile | awk '{print $2}'`
set demlon = `grep demlon $paramfile | awk '{print $2}'`
mkdir $topdir/dem
chdir $topdir
ln -s $topdir/../dem/srtm*/$dem* dem/
echo Oversampling DEM $dem by factor of $demlat in Latitude and $demlon in Longitude

# Test for DEM
if (-e dem/$dem.dem) then
        echo "\033[1;31m NOTE - Using DEM $dem.dem \033[0m"
else
        echo "\033[1;31m ERROR - DEM dem/$dem.dem does not exist \033[0m"
        exit
endif

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
set dim = `grep dim $paramfile | awk '{print $2}'`
set loslabel = `grep loslabel $paramfile | awk '{print $2}'`

# Pixel tracking offsets
# Number of Looks
set offproc = `grep offproc $paramfile | awk '{print $2}'`
set lksoffrng = `grep lksoffrng $paramfile | awk '{print $2}'`
set lksoffazi = `grep lksoffazi $paramfile | awk '{print $2}'`
set rwin = `grep rwin $paramfile | awk '{print $2}'`
set azwin = `grep azwin $paramfile | awk '{print $2}'`
set rstep = `grep rstep $paramfile | awk '{print $2}'`
set azstep = `grep azstep $paramfile | awk '{print $2}'`
set ccpthresh = `grep ccpthresh $paramfile | awk '{print $2}'`
set offres = `grep offres $paramfile | awk '{print $2}'`
set rfilt = `grep rfilt $paramfile | awk '{print $2}'`
set afilt = `grep afilt $paramfile | awk '{print $2}'`
set rlim = `grep rlim $paramfile | awk '{print $2}'`
set alim = `grep alim $paramfile | awk '{print $2}'`
set rcptlim = `grep rcptlim $paramfile | awk '{print $2}'`
set acptlim = `grep acptlim $paramfile | awk '{print $2}'`
set labelint = `grep labelint $paramfile | awk '{print $2}'`



# Pause to Read
sleep 2


# Cheat to skip parts
#if ( 1 == 0 ) then


#########################
# Start of Processing

# Unzip Files
chdir $topdir/zips
foreach zipfile (*zip)
	echo $zipfile
	#7z x $zipfile -o$topdir/safes
end



# Loop through the two dates
foreach date ( $date1 $date2 )

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
		rm SLC_tab$scene

		# Loop Through Subswaths
		set b = $substart
		while ( $b <= $subend )
			# Normal VV - Note outputting SCOMPLEX
			echo $safefile
        		par_S1_SLC $safefile/measurement/s1?-iw$b-slc-vv*.tiff $safefile/annotation/s1?-iw$b-slc-vv*.xml $safefile/annotation/calibration/calibration-s1?-iw$b-slc-vv*.xml $safefile/annotation/calibration/noise-s1?-iw$b-slc-vv*.xml $date.$scene.iw$b.all.slc.par $date.$scene.iw$b.all.slc $date.$scene.iw$b.all.slc.TOPS_par 1

			# Apply Precise Orbits if available - two week delay - downloaded daily by crontab on hal
			# Determine Satellite to pull correct orbit file
	                set sat = `echo $safefile | awk -F/ '{print substr($NF,3,1)}'`
			set nextday = `date --date=''$date' next day' +%Y%m%d`

			S1_OPOD_vec $date.$scene.iw$b.all.slc.par /nfs/a285/share/orbits_s1/precise_orbits/S1$sat\_OPER_AUX_POEORB_OPOD_*$nextday\T??????.EOF

			# Output SLC_tab text file
			echo $date.$scene.iw$b.all.slc $date.$scene.iw$b.all.slc.par $date.$scene.iw$b.all.slc.TOPS_par >> SLC_tab$scene

			@ b++
		end
		chdir ../	

		@ scene++
	end

end


# Concatenate Files
foreach date ( $date1 $date2 )
	
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

		# Make the text SLC tab output (all you need for one or two scenes)
		echo $date.iw$b.all.slc $date.iw$b.all.slc.par $date.iw$b.all.slc.TOPS_par >> SLC_tab$date

		if ( $nscenes == 3 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			#Don't need to make a tab3 as already exists
		else if ( $nscenes == 4 || $nscenes == 5 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
		else if ( $nscenes == 6 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
		else if ( $nscenes == 7 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
		else if ( $nscenes == 8 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
			echo $date.7-8.iw$b.all.slc $date.7-8.iw$b.all.slc.par $date.7-8.iw$b.all.slc.TOPS_par >> SLC_tab7-8
		else if ( $nscenes == 11 ) then
			echo $date.1-2.iw$b.all.slc $date.1-2.iw$b.all.slc.par $date.1-2.iw$b.all.slc.TOPS_par >> SLC_tab1-2
			echo $date.3-4.iw$b.all.slc $date.3-4.iw$b.all.slc.par $date.3-4.iw$b.all.slc.TOPS_par >> SLC_tab3-4
			echo $date.1-4.iw$b.all.slc $date.1-4.iw$b.all.slc.par $date.1-4.iw$b.all.slc.TOPS_par >> SLC_tab1-4
			echo $date.5-6.iw$b.all.slc $date.5-6.iw$b.all.slc.par $date.5-6.iw$b.all.slc.TOPS_par >> SLC_tab5-6
			echo $date.1-6.iw$b.all.slc $date.1-6.iw$b.all.slc.par $date.1-6.iw$b.all.slc.TOPS_par >> SLC_tab1-6
			echo $date.7-8.iw$b.all.slc $date.7-8.iw$b.all.slc.par $date.7-8.iw$b.all.slc.TOPS_par >> SLC_tab7-8
			echo $date.1-8.iw$b.all.slc $date.1-8.iw$b.all.slc.par $date.1-8.iw$b.all.slc.TOPS_par >> SLC_tab1-8
			echo $date.9-10.iw$b.all.slc $date.9-10.iw$b.all.slc.par $date.9-10.iw$b.all.slc.TOPS_par >> SLC_tab9-10
			echo $date.1-10.iw$b.all.slc $date.1-10.iw$b.all.slc.par $date.1-10.iw$b.all.slc.TOPS_par >> SLC_tab1-10
		else if ( $nscenes == 13 ) then
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
		endif

		@ b++
	# End burst loop
	end

	# Rename files if just single scene
	if ( $nscenes == 1 ) then
		set b = $substart
        	while ( $b <= $subend )
			mv $date.1.iw$b.all.slc $date.iw$b.all.slc
			mv $date.1.iw$b.all.slc.par $date.iw$b.all.slc.par
			mv $date.1.iw$b.all.slc.TOPS_par $date.iw$b.all.slc.TOPS_par
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
	else if ( $nscenes == 11 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
		SLC_cat_ScanSAR  SLC_tab7 SLC_tab8 SLC_tab7-8
		SLC_cat_ScanSAR  SLC_tab9 SLC_tab10 SLC_tab9-10
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
		SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab1-6
		SLC_cat_ScanSAR  SLC_tab1-6 SLC_tab7-8 SLC_tab1-8
		SLC_cat_ScanSAR  SLC_tab1-8 SLC_tab9-10 SLC_tab1-10
		SLC_cat_ScanSAR  SLC_tab1-10 SLC_tab11 SLC_tab$date
	else if ( $nscenes == 13 ) then
		SLC_cat_ScanSAR  SLC_tab1 SLC_tab2 SLC_tab1-2
		SLC_cat_ScanSAR  SLC_tab3 SLC_tab4 SLC_tab3-4
		SLC_cat_ScanSAR  SLC_tab5 SLC_tab6 SLC_tab5-6
		SLC_cat_ScanSAR  SLC_tab7 SLC_tab8 SLC_tab7-8
		SLC_cat_ScanSAR  SLC_tab9 SLC_tab10 SLC_tab9-10
		SLC_cat_ScanSAR  SLC_tab11 SLC_tab12 SLC_tab11-12
		SLC_cat_ScanSAR  SLC_tab1-2 SLC_tab3-4 SLC_tab1-4
		SLC_cat_ScanSAR  SLC_tab1-4 SLC_tab5-6 SLC_tab1-6
		SLC_cat_ScanSAR  SLC_tab1-6 SLC_tab7-8 SLC_tab1-8
		SLC_cat_ScanSAR  SLC_tab1-8 SLC_tab9-10 SLC_tab1-10
		SLC_cat_ScanSAR  SLC_tab1-10 SLC_tab11-12 SLC_tab1-12
		SLC_cat_ScanSAR  SLC_tab1-12 SLC_tab13 SLC_tab$date
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
		rm $date.iw[$substart-$subend].all.slc.tif
	endif
	cp $date.iw*.all.slc.tif ../

	# Display Spectra Wrapping - just display phase to see cycles within burst of each subswath	
	#dismph_fft $date.iw$subend.all.slc $widthslc 1 4000 1. .35 32 4 1 &
end



# Extract subset of bursts from Master
chdir $topdir/slcs/$date1/concat

if ( $extractburst == 1 ) then
# Create output copy tab file
	rm SLC_tabcopy
	set b = $substart
	while ($b <= $subend)
        	echo $date1.iw$b.crop.slc $date1.iw$b.crop.slc.par $date1.iw$b.crop.slc.TOPS_par >> SLC_tabcopy
        	@ b++
	end
	SLC_copy_ScanSAR SLC_tab$date1 SLC_tabcopy $topdir/burstlist.txt	
	
	# Make images	
	set b = $substart
	while ( $b <= $subend )
        	set widthslc = `grep range_samples $date1.iw$b.crop.slc.par | awk '{printf "%i ", $2}'`
		#disSLC $date1.iw$b.crop.slc $widthslc 1 2000 1. .35 1 &

	        # Generate Quicklook of entire subswath
        	rasSLC $date1.iw$b.crop.slc $widthslc 1 0 50 10 1. 0.35 1 1 0 $date1.iw$b.crop.slc.tif
        	@ b++
	end
	# Stick them into a single image if multiple subswaths
	if ( $nsubs > 1 ) then
		montage $date1.iw[$substart-$subend].crop.slc.tif -tile $nsubs\x1 -geometry +0+0 $date1.iw$substart-$subend.crop.slc.tif
		rm $date1.iw[$substart-$subend].crop.slc.tif
	endif
	cp $date1.iw*.crop.slc.tif ../

	# Rename cropped files back to all
	set b = $substart
        while ( $b <= $subend )
		mv $date1.iw$b.crop.slc $date1.iw$b.all.slc
		mv $date1.iw$b.crop.slc.par $date1.iw$b.all.slc.par
		mv $date1.iw$b.crop.slc.TOPS_par $date1.iw$b.all.slc.TOPS_par
		@ b++
	end

endif

# Generate Burst Numbers to Pull Out which ones to copy
chdir $topdir/slcs/$date2/concat 
ln -s $topdir/slcs/$date1/concat/$date1.iw*par .
ln -s $topdir/slcs/$date1/concat/SLC_tab$date1 .
S1_BURST_tab SLC_tab$date1 SLC_tab$date2 BURST_tab

# Create output copy tab file
rm SLC_tabcopy
set b = $substart
while ($b <= $subend)
        echo $date2.iw$b.slc $date2.iw$b.slc.par $date2.iw$b.slc.TOPS_par >> SLC_tabcopy
        @ b++
end

# Extract out required bursts from slave
SLC_copy_ScanSAR SLC_tab$date2 SLC_tabcopy BURST_tab
mv $date2.iw?.slc* ../
chdir ../
rm -r scene? scene?? concat scenes.list


# Copy files and rename master (note porblem if moved, as moves links if extractbursts not used).
chdir $topdir/slcs/$date1
set b = $substart
while ( $b <= $subend )
	cp concat/$date1.iw$b.all.slc $date1.iw$b.slc 
	cp concat/$date1.iw$b.all.slc.par $date1.iw$b.slc.par 
	cp concat/$date1.iw$b.all.slc.TOPS_par $date1.iw$b.slc.TOPS_par
        @ b++
end
rm -r scene? scene?? concat scenes.list


# MLI Mosaic 20 secs
# output bursts to be considered into tab delimited file
foreach date ( $date1 $date2 ) 

	chdir $topdir/slcs/$date
	rm SLC_tab
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
	raspwr $date.mli $widthmli 1 0 5 5 1. 0.35 1 $date.mli.tif

	# SLC Mosaic
	# N.B. Doppler Centroid will vary strongly within mosaic with large steps at the interface between bursts
	# When using SLC for interferometery, need to know what multi-looking will be used later on to connect bursts
	SLC_mosaic_S1_TOPS SLC_tab $date.slc $date.slc.par $lksrng $lksazi

	# Multilook
	multi_look $date.slc $date.slc.par $date.slc.mli $date.slc.mli.par $lksrng $lksazi

end






#################################
# DEM and lookup table
echo "\033[1;31m Generating DEM files and lookup tables \033[0m"
sleep 2

mkdir $topdir/geodem
chdir $topdir/geodem
ln -s $topdir/slcs/$date1/$date1.slc.mli* .
ln -s $topdir/slcs/$date1/$date1.mli.par .
set widthmli = `grep range_samples $date1.mli.par | awk '{print $2}'`
swap_bytes $topdir/dem/$dem.dem $dem.swap.dem 4

# Get DEM sizes
set ncells = `grep NrOfCellsPerLine $topdir/dem/$dem.dem.ers | awk '{print $3}'`
set nlines = `grep NrOfLines $topdir/dem/$dem.dem.ers | awk '{print $3}'`
set xdim = `grep Xdimension $topdir/dem/$dem.dem.ers | awk '{printf "%.11f\n", $3}'`
set ydim = `grep Ydimension $topdir/dem/$dem.dem.ers | awk '{printf "%.11f\n", -$3}'`
set west = `grep Eastings $topdir/dem/$dem.dem.ers | awk '{printf "%.11f\n", $3}'`
set north = `grep Northings $topdir/dem/$dem.dem.ers | awk '{printf "%.11f\n", $3}'`
echo $ncells $nlines $xdim $ydim $west $north

# Generate par file
# # Answer questions
# # Need to remove file first if going to use EOF method of input,
# # as if file already exists, it uses slightly different inputs.
rm $dem.swap.dem_par
create_dem_par $dem.swap.dem_par<<EOF
EQA
WGS84
1
$dem.swap.dem_par
REAL*4
0
1
$ncells
$nlines
$ydim $xdim
$north $west
EOF

# Display DEM
#disdem_par $dem.swap.dem $dem.swap.dem_par &


# GEOCODING
# Look-up table
gc_map $date1.slc.mli.par - $dem.swap.dem_par $dem.swap.dem EQA.dem_par EQA.dem $date1.lt $demlat $demlon $date1.sim_sar u v inc psi pix ls_map 8 2

set widthdem = `grep width EQA.dem_par | awk '{print $2}'`

# Refinement of Geocoding lookup table
pixel_area $date1.slc.mli.par EQA.dem_par EQA.dem $date1.lt ls_map inc pix_sigma0 pix_gamma0

# Display simulated and MLI image
#dis2pwr pix_gamma0 $date1.slc.mli $widthmli $widthmli &

# Correction to geocoding table based upon simulated and real MLI image
create_diff_par $date1.slc.mli.par - $date1.diff_par 1 0

offset_pwrm pix_sigma0 $date1.slc.mli $date1.diff_par $date1.offs $date1.cpp 256 256 offsets 1 64 64 0.1

offset_fitm $date1.offs $date1.cpp $date1.diff_par coffs coffsets 0.1 1

gc_map_fine $date1.lt $widthdem $date1.diff_par $date1.lt_fine 1

# View lookuptable
#dismph $date1.lt_fine $widthdem &

# Geocode mli image using lookup table
geocode_back $date1.slc.mli $widthmli $date1.lt_fine EQA.$date1.slc.mli $widthdem - 2 0

# Display Geocoded image
#dispwr EQA.$date1.slc.mli $widthdem 1 4000 1. .35 0 &

# Transforming DEM heights into SAR Geometry of MLI
# Need to get number of lines from MLI file to make hgt correct length
set lengthmli = `grep azimuth_lines $date1.mli.par | awk '{print $2}'`
geocode $date1.lt_fine EQA.dem $widthdem $date1.hgt $widthmli $lengthmli 2 0

# Display transformed DEM
#dishgt $date1.hgt $date1.slc.mli $widthmli &

# Geocode back DEM
geocode_back $date1.hgt $widthmli $date1.lt_fine $date1.hgt.geo $widthdem - 0 0




#######################
# TOPS SLC Registration
echo "\033[1;31m Starting TOPS SLC Registration \033[0m"
mkdir $topdir/ifgms $topdir/ifgms/$date1-$date2
chdir $topdir/ifgms/$date1-$date2
ln -s $topdir/slcs/$date1/$date1* .
ln -s $topdir/slcs/$date2/$date2* .
ln -s $topdir/geodem/$date1* .
ln -s $topdir/geodem/EQA* .

# Get width of first date multilooked and DEM
set widthmli = `grep range_samples $date1.mli.par | awk '{print $2}'`
set widthdem = `grep width EQA.dem_par | awk '{print $2}'`

# Refinement text files
rm RSLC2_tab SLC2_tab SLC1_tab
set b = $substart
while ($b <= $subend)
        echo $date2.iw$b.rslc $date2.iw$b.rslc.par $date2.iw$b.rslc.TOPS_par >> RSLC2_tab
        echo $date2.iw$b.slc $date2.iw$b.slc.par $date2.iw$b.slc.TOPS_par >> SLC2_tab
        echo $date1.iw$b.slc $date1.iw$b.slc.par $date1.iw$b.slc.TOPS_par >> SLC1_tab
        @ b++
end




#########################
# GENERATE INTERFEOGRAM #
#########################
echo "\033[1;31m Generating First Interferogram \033[0m"
sleep 2

# Calculate co-registration lookup table using rdc_trans
rdc_trans $date1.slc.mli.par $date1.hgt $date2.slc.mli.par $date2.slc.mli.lt
#dismph $date2.slc.mli.lt $widthmli

# Resample SLC using Lookup Table and SLC offset
SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $date1.slc.par $date2.slc.mli.lt $date1.slc.mli.par $date2.slc.mli.par - RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt
# You may want to output screentext >& output.txt

# Residual offset between master and slave SLC moasaic
create_offset $date1.slc.par $date2.slc.par $date1\_$date2.off 1 $lksrng $lksazi 0

# Residual difference between master SLC mosiac and slave SLC mosaic using RSLC cross-correlation
offset_pwr $date1.slc $date2.rslc $date1.slc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.offs $date1\_$date2.ccp 256 64 - 1 64 64 0.1 5
# Note Changed 12/02/2018 (version v5.4 clw/cm 20-Mar-2017 - inconsistent with manual pg 26 S1 Usres Dec 2017)

offset_fit $date1\_$date2.offs $date1\_$date2.ccp $date1\_$date2.off - - 0.1 1 0


#################################
# FIRST PRELIMINARY INTERFEROGRAM

phase_sim_orb $date1.slc.par $date2.slc.par $date1\_$date2.off $date1.hgt $date1\_$date2.sim_unw $date1.slc.par - - 1 1

# Display Simulated Ifgm
#disrmg $date1\_$date2.sim_unw $date1.mli $widthmli &

SLC_diff_intf $date1.slc $date2.rslc $date1.slc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.sim_unw $date1\_$date2.diff $lksrng $lksazi 0 0 0.2 1 1 >& output.txt

# Display Interferogram
#dismph_pwr $date1\_$date2.diff $date1.mli $widthmli &

# Output raster
rasmph_pwr $date1\_$date2.diff $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.initial.diff.tif


# Baseline Values
base_init $date2.slc.par $date1.slc.par $date1\_$date2.off $date1\_$date2.diff $date1\_$date2.base 0
base_perp $date1\_$date2.base $date2.slc.par $date1\_$date2.off > $date1\_$date2.base.perp


###########################
# ESTIMATE AZIMUTH OFFSET #
###########################
echo "\033[1;31m Initiating First Azimuth Offset \033[0m"
sleep 2

# Re-iterate the process until the accuracy is a small fraction of an SLC pixel, especially in azimuth
# (final azimuth offset poly. coeff.: <0.02)
SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $date1.slc.par $date2.slc.mli.lt $date1.slc.mli.par $date2.slc.mli.par $date1\_$date2.off RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt

create_offset $date1.slc.par $date2.slc.par $date1\_$date2.off1 1 $lksrng $lksazi 0

offset_pwr $date1.slc $date2.rslc $date1.slc.par $date2.rslc.par $date1\_$date2.off1 $date1\_$date2.offs $date1\_$date2.ccp 256 64 - 1 64 64 0.1 5

offset_fit $date1\_$date2.offs $date1\_$date2.ccp $date1\_$date2.off1 - - 0.1 1 0


# Test of Offset value ot test for refinement in aximuth offset
set offtest = `grep azimuth_offset_polynomial $date1\_$date2.off1 | awk '{print sqrt($2*$2)}' | awk '{ print ($1 < 0.01) ? 1 : 0 }'`
if ( $offtest == 0 ) then

# Add the offsets together
offset_add $date1\_$date2.off $date1\_$date2.off1 $date1\_$date2.off.total

# Resample again with this total offset
SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $date1.slc.par $date2.slc.mli.lt $date1.slc.mli.par $date2.slc.mli.par $date1\_$date2.off.total RSLC2_tab $date2.rslc $date2.rslc.par >& output.txt

# Output Ifgm
#phase_sim_orb $date1.slc.par $date2.slc.par $date1\_$date2.off $date1.hgt $date1\_$date2.sim_unw $date1.slc.par - - 1 1

#SLC_diff_intf $date1.slc $date2.rslc $date1.slc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.sim_unw $date1\_$date2.diff.test1 $lksrng $lksazi 0 0 0.2 1 1

# Display Interferogram
#dismph_pwr $date1\_$date2.diff.test1 $date1.mli $widthmli &

# Output raster
#rasmph_pwr $date1\_$date2.diff.test1 $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff.test01.tif
#convert $date1\_$date2.diff.test01.tif $date1\_$date2.diff.test01.png

else 
	cp $date1\_$date2.off $date1\_$date2.off.total
endif
 

############################
# REFINE AZIMUTH OFFSET USING SPECTRAL DIVERSITY
S1_coreg_overlap SLC1_tab RSLC2_tab $date1\_$date2 $date1\_$date2.off.total $date1\_$date2.off.corrected 0.8 0.01 0.8 1 >& output.txt

# Resample again with this corrected offset
SLC_interp_lt_ScanSAR SLC2_tab $date2.slc.par SLC1_tab $date1.slc.par $date2.slc.mli.lt $date1.slc.mli.par $date2.slc.mli.par $date1\_$date2.off.corrected RSLC2_tab $date2.rslc $date2.rslc.par  >& output.txt


###########################
# INTERFEROGRAM
phase_sim_orb $date1.slc.par $date2.slc.par $date1\_$date2.off $date1.hgt $date1\_$date2.sim_unw $date1.slc.par - - 1 1

SLC_diff_intf $date1.slc $date2.rslc $date1.slc.par $date2.rslc.par $date1\_$date2.off $date1\_$date2.sim_unw $date1\_$date2.diff $lksrng $lksazi 0 0 0.2 1 1

# Display Interferogram
#dismph_pwr $date1\_$date2.diff $date1.mli $widthmli &

# Output raster
rasmph_pwr $date1\_$date2.diff $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff.tif

# GEOCODE INTERFEROGRAM
geocode_back $date1\_$date2.diff $widthmli $date1.lt_fine $date1\_$date2.diff.geo $widthdem - 0 1

# Output raster
rasmph $date1\_$date2.diff.geo $widthdem 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff.geo.tif

# Convert to png with transparency of black masked out
convert $date1\_$date2.diff.geo.tif -transparent black $date1-$date2.diff.geo.png



#############
# FILTERING #
#############

###########################
adf $date1\_$date2.diff $date1\_$date2.diff_sm $date1\_$date2.smcc $widthmli 0.3 64 7 - 0 - 0.2
rasmph_pwr $date1\_$date2.diff_sm $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm.tif

# 2nd Filter
adf $date1\_$date2.diff_sm $date1\_$date2.diff_sm2 $date1\_$date2.smcc2 $widthmli 0.4 32 7 - 0 - 0.2
rasmph_pwr $date1\_$date2.diff_sm2 $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm2.tif

# 3rd Filter
adf $date1\_$date2.diff_sm2 $date1\_$date2.diff_sm3 $date1\_$date2.smcc3 $widthmli 0.5 16 7 - 0 - 0.2
rasmph_pwr $date1\_$date2.diff_sm3 $date1.mli $widthmli 1 1 0 $raspixavr $raspixavaz 1. .20 1 $date1\_$date2.diff_sm3.tif

# Display Filtered Ifgm & Coherence
#dismph_pwr $date1\_$date2.diff_sm3 $date1.mli $widthmli &
#discc $date1\_$date2.smcc3 $date1.mli $widthmli


# Geocode Coherence
geocode_back $date1\_$date2.smcc3 $widthmli $date1.lt_fine $date1\_$date2.smcc3.geo $widthdem - 2
rascc $date1\_$date2.smcc3.geo EQA.$date1.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz 0.1 0.9 1.0 .20 1 $date1\_$date2.smcc3.geo.tif
convert $date1\_$date2.smcc3.geo.tif -transparent black $date1-$date2.smcc3.geo.png


###########################
# GEOCODE 1st Filtered Ifgms
geocode_back $date1\_$date2.diff_sm $widthmli $date1.lt_fine $date1\_$date2.diff_sm.geo $widthdem - 0 1

######################
# Amplitude 1st Date
geocode_back $date1.mli $widthmli $date1.lt_fine $date1.mli.geo $widthdem - 2

raspwr $date1.mli.geo $widthdem 1 0 $raspixavr $raspixavaz 0.5 .35 1 $date1.mli.geo.tif 0 0
convert $date1.mli.geo.tif -transparent black $date1.mli.geo.png


# Amplitude 2nd Date

# Multilook
multi_look $date2.rslc $date2.rslc.par $date2.rslc.mli $date2.rslc.mli.par $lksrng $lksazi
geocode_back $date2.rslc.mli $widthmli $date1.lt_fine $date2.mli.geo $widthdem - 2

raspwr $date2.mli.geo $widthdem 1 0 4 4 0.5 .35 1 $date2.mli.geo.tif 0 0

#convert $date2.mli.geo.tif -transparent black -resize 50% $date2.mli.geo.png
convert $date2.mli.geo.tif -transparent black $date2.mli.geo.png


# Coherence
# Do on unsmoothed interferogram
# Window currently at 5x5. (also triangular weighting - difference not investigated)
cc_wave $date1\_$date2.diff $date1.mli $date2.rslc.mli $date1\_$date2.cc $widthmli 5 5 1

#discc $date1\_$date2.cc $date1.mli $widthmli

geocode_back $date1\_$date2.cc $widthmli $date1.lt_fine $date1\_$date2.cc.geo $widthdem - 2

rascc $date1\_$date2.cc.geo EQA.$date1.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz 0.1 0.9 1.0 .35 1 $date1\_$date2.cc.geo.tif

#convert $date1\_$date2.cc.geo.tif -transparent black -resize 25% $date1-$date2.cc.geo.png
convert $date1\_$date2.cc.geo.tif -transparent black $date1-$date2.cc.geo.png


# Cheat to start from here
#endif
#chdir $topdir/ifgms/$date1-$date2
#set widthmli = `grep range_samples $date1.mli.par | awk '{print $2}'`


###############
# UNWRAPPING
########## MCF

# Phase unwrapping mask
# Be careful with what you are using as Coherence (smoothed or original) to mask
rascc_mask $date1\_$date2.smcc3 $date1.mli $widthmli 1 1 0 1 1 0.3 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.mask.ras
#rascc_mask $date1\_$date2.cc $date1.mli $widthmli 1 1 0 1 1 0.2 0.0 0.1 0.9 1.0 0.20 1 $date1\_$date2.mask.ras
# Display Mask
# disras $date1\_$date2.mask.ras &

# Unwrap Minimum Cost Function
mcf $date1\_$date2.diff_sm3 $date1\_$date2.smcc $date1\_$date2.mask.ras $date1\_$date2.diff_sm.unw $widthmli 0 - - - - $r_patch $az_patch - $r_init $az_init 1

# Display unwrapped image
# disrmg $date1\_$date2.diff_sm.unw $date1.mli $widthmli 1 1 0 1.0 1. .20 0. &

# Geocode unwrapped
geocode_back $date1\_$date2.diff_sm.unw $widthmli $date1.lt_fine $date1\_$date2.diff.unw.geo $widthdem - 0

# Display Unwrapped Geocoded
# disrmg $date1\_$date2.diff.unw.geo EQA.$date1.slc.mli $widthdem &

# Output raster
rasrmg $date1\_$date2.diff.unw.geo EQA.$date1.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz 1. 1. .20 0 1 $date1\_$date2.diff.unw.geo.tif
# Convert to png with transparency of black masked out
convert $date1\_$date2.diff.unw.geo.tif -transparent black $date1-$date2.diff.unw.geo.png

# Output raster with a different unwrapping scale
rasrmg $date1\_$date2.diff.unw.geo EQA.$date1.slc.mli $widthdem 1 1 0 $raspixavr $raspixavaz $scale 1. .20 0 1 $date1\_$date2.diff.wrap"$rewrap_int"cm.unw.geo.tif
# Convert to png with transparency of black masked out
convert $date1\_$date2.diff.wrap"$rewrap_int"cm.unw.geo.tif -transparent black $date1-$date2.diff.wrap"$rewrap_int"cm.unw.geo.png


############
# SNAPHU   #
# UNTESTED #
############
# Need to swap bytes first
#swap_bytes $date1\_$date2.diff_sm3 $date1\_$date2.diff_sm3.swap 4
#swap_bytes $date1\_$date2.smcc $date1\_$date2.smcc.swap 4

# Setup Snaphu config file to output samples (not lines)
#cat <<EOF > config.snaphu
#OUTFILEFORMAT           ALT_SAMPLE_DATA
#CORRFILEFORMAT          FLOAT_DATA
#EOF

# Unwrap with Snaphu (deformation mode)
#snaphu -f config.snaphu -d $date1\_$date2.diff_sm3.swap $widthmli -c $date1\_$date2.smcc.swap --nproc 4 --tile 2 2 50 50 -v -o $date1\_$date2.diff_sm3.unw.swap

# Swap Back
#swap_bytes $date1\_$date2.diff_sm3.unw.swap tmp.unw 4

# Split apart Unwrapped from two layers
#cpx_to_real tmp.unw $date1\_$date2.diff_sm_snaphu.unw $widthmli 1

# Display
#  disrmg $date1\_$date2.diff_sm_snaphu.unw - $widthmli



# Cheat to start from here
#endif
#chdir $topdir/ifgms/$date1-$date2
#set widthmli = `grep range_samples $date1.mli.par | awk '{print $2}'`
#set widthdem = `grep width EQA.dem_par | awk '{print $2}'`
#set nscenes = 11






###########################
# END OF GAMMA PROCESSING #
###########################



################
# Output Files #
################ 
# Geographic Co-ordinates of Geocoded Files
set north = `grep corner_lat  EQA.dem_par | awk '{print $2}'`
set west = `grep corner_lon  EQA.dem_par | awk '{print $2}'`
set dlat = `grep post_lat  EQA.dem_par | awk '{print $2}'`
set dlon = `grep post_lon  EQA.dem_par | awk '{print $2}'`
set width = `grep width  EQA.dem_par | awk '{print $2}'`
set length = `grep nlines  EQA.dem_par | awk '{print $2}'`
set south = `echo $north $dlat $length | awk '{printf("%.7f"i, $1+$2*$3)}'`
set east = `echo $west $dlon $width | awk '{printf("%.7f", $1+$2*$3)}'`
echo $west $east $south $north
set dimkm = `echo $dim | awk '{print $1/1000}'`
set dlatpos = `echo $dlat | sed 's/-//'`


# Test for number of scenes as for longer kmz gmt plots, need to restrict height otherwise does not plot geographically correct
if ( $nscenes > 4 ) then
	set papersize = 10
else
	set papersize = 20
endif
gmtset PAPER_MEDIA = a0
gmtset PAGE_ORIENTATION = portrait


# Unwrapped MCF
png2kml_logos.tcsh $date1-$date2.diff.unw.geo 0 1 $west $east $south $north

# Swap bytes
swap_bytes $date1\_$date2.diff.unw.geo $date1\_$date2.diff.unw.geo.bin 4

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.diff.unw.geo.bin.ers $dlon $dlatpos $length $width $west $north unwrapped_phase_radians

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.diff.unw.geo.bin -G$date1\_$date2.diff.unw.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
#grdsample $date1\_$date2.diff.unw.geo.bin.grd -G$date1\_$date2.diff.unw.geo.100m.bin.grd -I0.1k -Qn0.1
# Grdfilter seems better way to deal with NaNs by taking median value, grdsample ends up with lots of holes
grdfilter $date1\_$date2.diff.unw.geo.bin.grd -G$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Remove Median Value and Convert to cm
grdmath $date1\_$date2.diff.unw.geo."$dim"m.bin.grd $date1\_$date2.diff.unw.geo."$dim"m.bin.grd MED SUB $rad2cm MUL = $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd

# Output kmz of unwrapped file
grd2cpt $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd -Cpolar -E100 -I -T= -Z > unwrap_polar.cpt
grdimage $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd -JQ$papersize -Cunwrap_polar.cpt -S-n -Q -V  > $date1-$date2.diff.unw.cm.geo."$dim"m.ps
# Put -K above if grdcontour used
#grdcontour $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd -JQ$papersize -C$int -L-100/100 -A$int+s2+ucm -Gd2 -Wa1,darkblue -Q100 -V -O >>  $date1-$date2.diff.unw.cm.geo."$dim"m.ps
ps2raster $date1-$date2.diff.unw.cm.geo."$dim"m.ps -E300 -TG -W+k+t"$date1-$date2.diff.unw.cm.geo."$dim"m.bin.grd"+l16/-1 -V

# Plot Scale
psscale -Cunwrap_polar.cpt -D2/1/4/0.3h -B$loslabel/:"los cm": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_unwrap.ps
ps2raster -A -TG -P scale_unwrap.ps

png2kml_logos.tcsh $date1-$date2.diff.unw.cm.geo."$dim"m scale_unwrap 1 $west $east $south $north


# Unwrapped Different Interval
png2kml_logos.tcsh $date1-$date2.diff.wrap"$rewrap_int"cm.unw.geo 0 1 $west $east $south $north

# Wrapped
png2kml_logos.tcsh $date1-$date2.diff.geo 0 1 $west $east $south $north


# Interferogram Phase
# Extract Phase from complex
cpx_to_real $date1\_$date2.diff.geo $date1\_$date2.diff.phs.geo $widthdem 4

# Swap bytes
swap_bytes $date1\_$date2.diff.phs.geo $date1\_$date2.diff.phs.geo.bin 4

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.diff.phs.geo.bin.ers $dlon $dlatpos $length $width $west $north phase_radians


# Geocoded Interferogram 1st Filter
# Extract Phase from complex
cpx_to_real $date1\_$date2.diff_sm.geo $date1\_$date2.diff_sm.phs.geo $widthdem 4

# Swap bytes
swap_bytes $date1\_$date2.diff_sm.phs.geo $date1\_$date2.diff_sm.phs.geo.bin 4

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.diff_sm.phs.geo.bin.ers $dlon $dlatpos $length $width $west $north phase_radians





##############
# Look Vectors
look_vector $date1.mli.par - EQA.dem_par EQA.dem lv_theta_tmp lv_phi_tmp
swap_bytes lv_theta_tmp lv_theta 4
swap_bytes lv_phi_tmp lv_phi 4
rm lv_theta_tmp lv_phi_tmp
mv lv_theta $date1\_$date2.lv_theta.geo.bin
mv lv_phi $date1\_$date2.lv_phi.geo.bin

#  lv_theta  (output) SAR look-vector elevation angle (at each map pixel)
#  lv_theta: PI/2 -> up  -PI/2 -> down
#  lv_phi    (output) SAR look-vector orientation angle at each map pixel
#  lv_phi: 0 -> East  PI/2 -> North

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.lv_theta.geo.bin.ers $dlon $dlatpos $length $width $west $north elevation_angle
create_ers_header.tcsh $date1\_$date2.lv_phi.geo.bin.ers $dlon $dlatpos $length $width $west $north orientation_angle

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.lv_theta.geo.bin -G$date1\_$date2.lv_theta.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid (using interferogram region) Dimensions selected above
grdfilter $date1\_$date2.lv_theta.geo.bin.grd -R$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -G$date1\_$date2.lv_theta.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Convert from radians to Degrees
# Masked to where there is data
grdmath 90 $date1\_$date2.lv_theta.geo."$dim"m.bin.grd R2D SUB $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd DIV MUL = $date1\_$date2.lv_theta.deg.geo."$dim"m.bin.grd

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.lv_phi.geo.bin -G$date1\_$date2.lv_phi.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $date1\_$date2.lv_phi.geo.bin.grd -R$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -G$date1\_$date2.lv_phi.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Convert from radians to Degrees
# Masked to where there is data
grdmath -180 $date1\_$date2.lv_phi.geo."$dim"m.bin.grd R2D SUB $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd DIV MUL = $date1\_$date2.lv_phi.deg.geo."$dim"m.bin.grd


# Convert to Line-of-Sight Vector
# Note Theta varies from 30-45 degrees
# V = cos (theta)
# H = sin (theta)
# Phi is -10 for ascending, and -170 for decending
# E = H cos (phi)
# N = H sin (phi)
# Because we want East, North, Up
# Have to multipy Eastward component by -1 to get consistent sign for motion towards the satellite
grdmath $date1\_$date2.lv_theta.deg.geo."$dim"m.bin.grd COSD = $date1\_$date2.lv_up.geo."$dim"m.bin.grd
grdmath $date1\_$date2.lv_theta.deg.geo."$dim"m.bin.grd SIND $date1\_$date2.lv_phi.deg.geo."$dim"m.bin.grd COSD MUL -1 MUL = $date1\_$date2.lv_east.geo."$dim"m.bin.grd
grdmath $date1\_$date2.lv_theta.deg.geo."$dim"m.bin.grd SIND $date1\_$date2.lv_phi.deg.geo."$dim"m.bin.grd SIND MUL = $date1\_$date2.lv_north.geo."$dim"m.bin.grd
# Test squares sum to 1
#grdmath $date1\_$date2.lv_up.geo."$dim"m.bin.grd SQR $date1\_$date2.lv_east.geo."$dim"m.bin.grd SQR ADD $date1\_$date2.lv_north.geo."$dim"m.bin.grd SQR ADD SQRT = total.grd



##### Output Smooth Coherence
# Swap bytes
swap_bytes $date1\_$date2.smcc3.geo $date1\_$date2.smcc3.geo.bin 4

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.smcc3.geo.bin.ers $dlon $dlatpos $length $width $west $north coherence

# Output grd file
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.smcc3.geo.bin -G$date1\_$date2.smcc3.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $date1\_$date2.smcc3.geo.bin.grd -R$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -G$date1\_$date2.smcc3.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3



################## DEM
# Output DEM
swap_bytes $date1.hgt.geo $date1.hgt.geo.bin 4

# Output as ERS header file
create_ers_header.tcsh $date1.hgt.geo.bin.ers $dlon $dlatpos $length $width $west $north elevation

# Output grd file
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1.hgt.geo.bin -G$date1.hgt.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $date1.hgt.geo.bin.grd -R$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -G$date1.hgt.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3


# Plot DEM
grd2cpt -Cjet -E10 $date1.hgt.geo."$dim"m.bin.grd -Z > height.cpt
grdimage $date1.hgt.geo."$dim"m.bin.grd -JQ$papersize -Cheight.cpt -S-n -Q > $date1.hgt.geo."$dim"m.bin.ps
ps2raster $date1.hgt.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$date1.hgt.geo."$dim"m"+l16/-1 -V

# Plot Scale
psscale -Cheight.cpt -D2/1/4/0.3h -B500/:"Elevation m": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_topo.ps
ps2raster -A -TG -P scale_topo.ps

# Plot Hillshaded DEM
grdgradient $date1.hgt.geo."$dim"m.bin.grd -G$date1.hgt.geo."$dim"m.bin.illum.grd -A135 -Ne0.6
grdimage $date1.hgt.geo."$dim"m.bin.grd -I$date1.hgt.geo."$dim"m.bin.illum.grd -JQ$papersize -C/nfs/a285/homes/earjre/oxford/comethome/johne/templates/grey.cpt -S-n -Q -V > $date1.hgt.shaded.geo."$dim"m.bin.ps
ps2raster $date1.hgt.shaded.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$date1.hgt.geo."$dim"m"+l16/-1 -V

# Output KMZ
rm -r files
mkdir files
cp $date1.hgt.geo."$dim"m.bin.png files/$date1.hgt.geo."$dim".m.bin.png
cp $date1.hgt.shaded.geo."$dim"m.bin.png files/$date1.hgt.shaded.geo."$dim".m.bin.png
cp scale_topo.png files/
set outfile = $date1.hgt.geo."$dim"m.kml
cat <<EOF > $outfile
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
<Folder>
<name>DEM and Hillshade</name>
<GroundOverlay>
        <name>$date1.hgt.geo.$dim.m</name>
        <Icon>
                <href>files/$date1.hgt.geo.$dim.m.bin.png</href>
                <viewBoundScale>0.75</viewBoundScale>
        </Icon>
        <LatLonBox>
                <north>$north</north>
                <south>$south</south>
                <east>$east</east>
                <west>$west</west>
        </LatLonBox>
</GroundOverlay>
<GroundOverlay>
        <name>$date1.hgt.shaded.geo.$dim.m</name>
        <Icon>
                <href>files/$date1.hgt.shaded.geo.$dim.m.bin.png</href>
                <viewBoundScale>0.75</viewBoundScale>
        </Icon>
        <LatLonBox>
                <north>$north</north>
                <south>$south</south>
                <east>$east</east>
                <west>$west</west>
        </LatLonBox>
</GroundOverlay>
</Folder>
<Folder>
<name>Scale</name>
<ScreenOverlay>
        <name>Elevation Scale Bar</name>
        <Icon>
                <href>files/scale_topo.png</href>
        </Icon>
        <overlayXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
</Folder>
</Document>
</kml>
EOF

# Zip to a kmz file
zip -r $date1.hgt.geo."$dim"m.kmz $date1.hgt.geo."$dim"m.kml files



#### FLAT IFGM Unwrapped polar, and rewrapped fringes
# Flatten Interfergrams and Output as Unwrapped/Rewrapped kmz in cm
grdtrend $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd -N3r -Ttrend.grd -V
grdmath $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd trend.grd SUB = $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.bin.grd


# Output kmz of unwrapped file
grd2cpt $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.bin.grd -Cpolar -E100 -I -T= -Z > unwrap_polar.cpt
grdimage $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.bin.grd -JQ$papersize -Cunwrap_polar.cpt -S-n -Q -V  > $date1-$date2.diff.unw.cm.geo."$dim"m.flat.ps
ps2raster $date1-$date2.diff.unw.cm.geo."$dim"m.flat.ps -E600 -TG -W+k+t"$date1-$date2.diff.unw.cm.geo."$dim"m.flat.bin.grd"+l16/-1 -V

# Plot Scale
psscale -Cunwrap_polar.cpt -D2/1/4/0.3h -B$loslabel/:"los cm": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_unwrap.ps
ps2raster -A -TG -P scale_unwrap.ps

png2kml_logos.tcsh $date1-$date2.diff.unw.cm.geo."$dim"m.flat scale_unwrap 1 $west $east $south $north

# Rewrap
set wrapnumhalf = 1
set intwrap = 0.5
set wrapnum = `echo $wrapnumhalf | awk '{print $1*2}'`
set wrapoffset = `echo $wrapnumhalf | awk '{print $1+$1*1000}'`

makecpt -Cseis -I -T-$wrapnumhalf/$wrapnumhalf/0.1 -Z  > rewrap_seis.cpt

grdmath $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.bin.grd $wrapoffset ADD $wrapnum FMOD $wrapnumhalf SUB = $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum.bin.grd

# Plot rewrapped ifgm
grdimage $date1\_$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum.bin.grd -JQ$papersize -Crewrap_seis.cpt -S-n -Q -V > $date1-$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum.ps
ps2raster $date1-$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum.ps -E600 -TG -W+k+t"$date1-$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum"+l16/-1 -V

# Plot Scale
psscale -Crewrap_seis.cpt -D2/1/4/0.3h -B$intwrap/:"los cm": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_rewrap.ps
ps2raster -A -TG -P scale_rewrap.ps

png2kml_logos.tcsh $date1-$date2.diff.unw.cm.geo."$dim"m.flat.rewrap$wrapnum scale_rewrap 1 $west $east $south $north






###############################
# Amplitude & Coherence
png2kml_logos.tcsh $date1.mli.geo 0 1 $west $east $south $north
png2kml_logos.tcsh $date2.mli.geo 0 1 $west $east $south $north
png2kml_logos.tcsh $date1-$date2.cc.geo 0 1 $west $east $south $north

# Convert to binary files, ers header, then geotiff
# Swap bytes
swap_bytes $date1.mli.geo $date1.mli.geo.bin 4
# Output as ERS header file
create_ers_header.tcsh $date1.mli.geo.bin.ers $dlon $dlatpos $length $width $west $north amplitude
gdal_translate -a_nodata 0 -ot Float32 $date1.mli.geo.bin.ers $date1.mli.geo.tif
gdal_translate -a_nodata 0 -of GMT $date1.mli.geo.bin.ers $date1.mli.geo.grd

# Swap bytes
swap_bytes $date2.mli.geo $date2.mli.geo.bin 4
# Output as ERS header file
create_ers_header.tcsh $date2.mli.geo.bin.ers $dlon $dlatpos $length $width $west $north amplitude
gdal_translate -a_nodata 0 -ot Float32 $date2.mli.geo.bin.ers $date2.mli.geo.tif
gdal_translate -a_nodata 0 -of GMT $date2.mli.geo.bin.ers $date2.mli.geo.grd


# Create amplitude difference and translate back
grdmath $date2.mli.geo.grd $date1.mli.geo.grd SUB = $date2-$date1.mli.geo.grd
gdal_translate -a_nodata 0 -ot Float32 $date2-$date1.mli.geo.grd $date2-$date1.mli.geo.tif
gdal_translate -a_nodata 0 -ot Float32 -of ERS -a_srs EPSG:4326 $date2-$date1.mli.geo.grd $date2-$date1.mli.geo.ers

grdmath $date2.mli.geo.grd $date1.mli.geo.grd SUB $date1.mli.geo.grd DIV = $date2-$date1.scaled.mli.geo.grd
gdal_translate -a_nodata 0 -ot Float32 $date2-$date1.scaled.mli.geo.grd $date2-$date1.scaled.mli.geo.tif
gdal_translate -a_nodata 0 -ot Float32 -of ERS -a_srs EPSG:4326 $date2-$date1.scaled.mli.geo.grd $date2-$date1.scaled.mli.geo.ers


# Swap bytes
swap_bytes $date1\_$date2.cc.geo $date1\_$date2.cc.geo.bin 4
# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.cc.geo.bin.ers $dlon $dlatpos $length $width $west $north coherence
gdal_translate -a_nodata 0 -ot Float32 $date1\_$date2.cc.geo.bin.ers $date1\_$date2.cc.geo.tif

# Output grd file
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.cc.geo.bin -G$date1\_$date2.cc.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $date1\_$date2.cc.geo.bin.grd -R$date1\_$date2.diff.unw.geo."$dim"m.bin.grd -G$date1\_$date2.cc.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3






# Make Tar Files for distribution
tar -cf $date1-$date2.diff.unw.enu.tar $date1-$date2.diff.unw.geo.kmz $date1-$date2.diff.unw.cm.geo."$dim"m.kmz $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd $date1\_$date2.lv_east.geo."$dim"m.bin.grd $date1\_$date2.lv_north.geo."$dim"m.bin.grd $date1\_$date2.lv_up.geo."$dim"m.bin.grd

tar -cf $date1-$date2.diff.unw.phi-theta-deg.tar $date1-$date2.diff.unw.geo.kmz $date1-$date2.diff.unw.cm.geo."$dim"m.kmz $date1\_$date2.diff.unw.cm.geo."$dim"m.bin.grd $date1\_$date2.lv_theta.deg.geo."$dim"m.bin.grd $date1\_$date2.lv_phi.deg.geo."$dim"m.bin.grd






# Test if processing offsets
if ( $offproc == 0 ) then
	exit
endif

#########################
# Offset Pixel Tracking #
#########################

# Deramping Bursts (pg 37 Sentinel-1 Guide, v1.7 Dec 2017)
chdir $topdir/slcs/$date1
echo $date1.iw1.slc.deramp $date1.iw1.slc.deramp.par $date1.iw1.slc.deramp.TOPS_par > SLC1_tab.deramp
echo $date1.iw2.slc.deramp $date1.iw2.slc.deramp.par $date1.iw2.slc.deramp.TOPS_par >> SLC1_tab.deramp
echo $date1.iw3.slc.deramp $date1.iw3.slc.deramp.par $date1.iw3.slc.deramp.TOPS_par >> SLC1_tab.deramp
SLC_deramp_S1_TOPS SLC_tab SLC1_tab.deramp 0 1

create_diff_par $date1.iw1.slc.par - $date1.iw1.slc.diff_par 1 0
create_diff_par $date1.iw2.slc.par - $date1.iw2.slc.diff_par 1 0
create_diff_par $date1.iw3.slc.par - $date1.iw3.slc.diff_par 1 0

ln -s $topdir/ifgms/$date1-$date2/$date2.iw?.rslc .
sub_phase $date2.iw1.rslc $date1.iw1.slc.deramp.dph $date1.iw1.slc.diff_par $date2.iw1.rslc.deramp 2 0
sub_phase $date2.iw2.rslc $date1.iw2.slc.deramp.dph $date1.iw2.slc.diff_par $date2.iw2.rslc.deramp 2 0
sub_phase $date2.iw3.rslc $date1.iw3.slc.deramp.dph $date1.iw3.slc.diff_par $date2.iw3.rslc.deramp 2 0

echo $date2.iw1.rslc.deramp $date1.iw1.slc.deramp.par $date1.iw1.slc.deramp.TOPS_par > RSLC2_tab.deramp
echo $date2.iw2.rslc.deramp $date1.iw2.slc.deramp.par $date1.iw2.slc.deramp.TOPS_par >> RSLC2_tab.deramp
echo $date2.iw3.rslc.deramp $date1.iw3.slc.deramp.par $date1.iw3.slc.deramp.TOPS_par >> RSLC2_tab.deramp

SLC_mosaic_S1_TOPS SLC1_tab.deramp $date1.slc.deramp $date1.slc.deramp.par $lksoffrng $lksoffazi
SLC_mosaic_S1_TOPS RSLC2_tab.deramp $date2.rslc.deramp $date2.rslc.deramp.par $lksoffrng $lksoffazi

# Remove Links
rm $date2.iw?.rslc
# Move deramped slcs to slc directory
mv $date2.rslc.deramp* ../$date2
mv $date2.iw?.rslc.deramp* ../$date2



# Cheat to start from here
endif
set widthmli = `grep range_samples $date1.mli.par | awk '{print $2}'`


# Offset file for tracking
chdir $topdir; mkdir offsets offsets/$date1-$date2; chdir offsets/$date1-$date2
ln -s $topdir/slcs/$date1/$date1.slc.deramp* .
ln -s $topdir/slcs/$date2/$date2.rslc.*deramp* .
create_offset $date1.slc.deramp.par $date2.rslc.deramp.par $date1\_$date2.fullpix.off 1 $lksoffrng $lksoffazi 0

# Pixel Tracking
#set widthslc = `grep range_samples $date1.slc.deramp.par | awk '{print $2}'`
#rasSLC $date1.slc.deramp $widthslc 1 - 4 4 1. .35 1 1 - $date1.slc.deramp.tif
#offset_pwr_tracking $date1.slc.deramp $date2.rslc.deramp $date1.slc.deramp.par $date2.rslc.deramp.par $date1\_$date2.fullpix.off $date1\_$date2.fullpix.offs $date1\_$date2.fullpix.ccp $rwin $azwin $date1\_$date2.fullpix.offs.txt 2 0.05 $rstep $azstep - - - - 7

# Note last three parameters
# Output in slant range and azimuth
# Not removing polynomial
offset_tracking $date1\_$date2.fullpix.offs $date1\_$date2.fullpix.ccp $date1.slc.deramp.par $date1\_$date2.fullpix.off $date1\_$date2.fullpix.off.dispmap $date1\_$date2.fullpix.off.dispval 1 $ccpthresh 0

# Extract Range and Azimuth (stores as real and imaginary part)
set widthoff = `grep range_samples $date1\_$date2.fullpix.off | awk '{print $2}'`
cpx_to_real $date1\_$date2.fullpix.off.dispmap $date1\_$date2.fullpix.off.dispmap.rng $widthoff 0
cpx_to_real $date1\_$date2.fullpix.off.dispmap $date1\_$date2.fullpix.off.dispmap.azi $widthoff 1

# Display Offsets
rashgt $date1\_$date2.fullpix.off.dispmap.rng - $widthoff 1 1 0 1 1 1.5 1. .35 1 $date1\_$date2.fullpix.off.dispmap.rng.tif
convert $date1\_$date2.fullpix.off.dispmap.rng.tif $date1\_$date2.fullpix.off.dispmap.rng.png
rashgt $date1\_$date2.fullpix.off.dispmap.azi - $widthoff 1 1 0 1 1 1.5 1. .35 1 $date1\_$date2.fullpix.off.dispmap.azi.tif
convert $date1\_$date2.fullpix.off.dispmap.azi.tif $date1\_$date2.fullpix.off.dispmap.azi.png

# Multilook amplitude image for background & also generating new geocoding
# look up table depending on window step size (offsets based upon full resolution slc)
multi_look $date1.slc.deramp $date1.slc.deramp.par $date1.off.mli $date1.off.mli.par $rstep $azstep
raspwr $date1.off.mli $widthoff - - 1 1 - - - $date1.off.mli.tif
convert $date1.off.mli.tif $date1.off.mli.png

# Generate Lookup table
ln -s $topdir/geodem/$dem.swap.dem_par .
ln -s $topdir/geodem/$dem.swap.dem .
gc_map $date1.off.mli.par - $dem.swap.dem_par $dem.swap.dem EQA.off.dem_par EQA.off.dem $date1.off.lt $demlat $demlon $date1.off.sim_sar u v inc psi pix ls_map 8 2
set widthoffdem = `grep width EQA.off.dem_par | awk '{print $2}'`

# Geocode files
# Range
geocode_back $date1\_$date2.fullpix.off.dispmap.rng $widthoff $date1.off.lt $date1\_$date2.fullpix.off.dispmap.rng.geo $widthoffdem - 0
# Swap bytes
swap_bytes $date1\_$date2.fullpix.off.dispmap.rng.geo $date1\_$date2.fullpix.off.dispmap.rng.geo.bin 4
# Azimuth
geocode_back $date1\_$date2.fullpix.off.dispmap.azi $widthoff $date1.off.lt $date1\_$date2.fullpix.off.dispmap.azi.geo $widthoffdem - 0
# Swap bytes
swap_bytes $date1\_$date2.fullpix.off.dispmap.azi.geo $date1\_$date2.fullpix.off.dispmap.azi.geo.bin 4


# Output Files
set north = `grep corner_lat  EQA.off.dem_par | awk '{print $2}'`
set west = `grep corner_lon  EQA.off.dem_par | awk '{print $2}'`
set dlat = `grep post_lat  EQA.off.dem_par | awk '{print $2}'`
set dlon = `grep post_lon  EQA.off.dem_par | awk '{print $2}'`
set width = `grep width  EQA.off.dem_par | awk '{print $2}'`
set length = `grep nlines  EQA.off.dem_par | awk '{print $2}'`
set south = `echo $north $dlat $length | awk '{printf("%.7f"i, $1+$2*$3)}'`
set east = `echo $west $dlon $width | awk '{printf("%.7f", $1+$2*$3)}'`
set dlatpos = `echo $dlat | sed 's/-//'`

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.fullpix.off.dispmap.rng.geo.bin.ers $dlon $dlatpos $length $width $west $north range-offset-m
create_ers_header.tcsh $date1\_$date2.fullpix.off.dispmap.azi.geo.bin.ers $dlon $dlatpos $length $width $west $north azimuth-offset-m

# Clean up with GMT
set bounds = -R$west/$east/$south/$north

# Range
ers_binary_to_grd.gmt4.tcsh $date1\_$date2.fullpix.off.dispmap.rng.geo.bin f 0
grdclip $date1\_$date2.fullpix.off.dispmap.rng.geo.bin.grd -G$date1\_$date2.gamma.rng.-$rlim.$rlim.off.geo.grd -Sa$rlim/NaN -Sb-$rlim/NaN
grdinfo $date1\_$date2.gamma.rng.-$rlim.$rlim.off.geo.grd

# Median Filter
#grdfilter $date1\_$date2.gamma.rng.-$rlim.$rlim.off.geo.grd -D1 -Fm$rfilt -G$date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd -I$offres $bounds
grdfilter $date1\_$date2.gamma.rng.-$rlim.$rlim.off.geo.grd -D1 -Fm$rfilt -G$date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd -I$offres
# Mode Filter - noiser but manitains fault offset as sharper.
#grdfilter $date1\_$date2.gamma.rng.-$rlim.$rlim.off.geo.grd -D1 -Fp$rfilt -G$date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd -I$offres

# Plot
makecpt -Cpolar -D -T-$rcptlim/$rcptlim/0.1 -Z > offsets_rng.cpt
set psfile = $date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.ps
grdimage -JM20 $bounds -Coffsets_rng.cpt $date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd -Q-n -V -K --PAPER_MEDIA=a1 > $psfile
psbasemap -JM20 $bounds -BNsEwa0.5 --BASEMAP_TYPE=plain -V -O -K >> $psfile
psscale -Coffsets_rng.cpt -D5/1.3/8/0.4h -B"$labelint"::/:"Range Offsets (m)": -E -V -O >> $psfile
ps2raster -A -Tf -P $psfile

# Azimuth
ers_binary_to_grd.gmt4.tcsh $date1\_$date2.fullpix.off.dispmap.azi.geo.bin f 0
grdclip $date1\_$date2.fullpix.off.dispmap.azi.geo.bin.grd -G$date1\_$date2.gamma.azi.-$alim.$alim.off.geo.grd -Sa$alim/NaN -Sb-$alim/NaN
grdinfo $date1\_$date2.gamma.azi.-$alim.$alim.off.geo.grd

# Median Filter
#grdfilter $date1\_$date2.gamma.azi.-$alim.$alim.off.geo.grd -D1 -Fm$afilt -G$date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd -I$offres $bounds
grdfilter $date1\_$date2.gamma.azi.-$alim.$alim.off.geo.grd -D1 -Fm$afilt -G$date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd -I$offres
# Mode Filter - noiser but manitains fault offset as sharper.
#grdfilter $date1\_$date2.gamma.azi.-$alim.$alim.off.geo.grd -D1 -Fp$afilt -G$date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd -I$offres

# Plot
makecpt -Cpolar -D -T-$acptlim/$acptlim/0.1 -Z > offsets_azi.cpt
set psfile = $date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.ps
grdimage -JM20 $bounds -Coffsets_azi.cpt $date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd -Q-n -V -K --PAPER_MEDIA=a1 > $psfile
psbasemap -JM20 $bounds -BNsEwa0.5 --BASEMAP_TYPE=plain -V -O -K >> $psfile
psscale -Coffsets_azi.cpt -D5/1.3/8/0.4h -B"$labelint"::/:"Azimuth Offsets (m)": -E -V -O >> $psfile
ps2raster -A -Tf -P $psfile


######## KMZ
# Output kmz of Offsets
# Range
set psfile = $date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.ps
grdimage -JQ$papersize -Coffsets_rng.cpt $date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd -S-n -Q -V > $psfile
ps2raster $psfile -E600 -TG -W+k+t"$date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.grd"+l16/-1 -V

# Plot Scale
psscale -Coffsets_rng.cpt -D2/1/4/0.3h -B"$labelint"/:"Range Offset (m)": -E --ANNOT_FONT_SIZE_PRIMARY=4p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_rng_offsets.ps
ps2raster -A -TG -P scale_rng_offsets.ps

# Azimuths
set psfile = $date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.ps
grdimage -JQ$papersize -Coffsets_azi.cpt $date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd -S-n -Q -V > $psfile
ps2raster $psfile -E600 -TG -W+k+t"$date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.grd"+l16/-1 -V

# Plot Scale
psscale -Coffsets_azi.cpt -D2/1/4/0.3h -B"$labelint"/:"Azimuth Offset (m)": -E --ANNOT_FONT_SIZE_PRIMARY=4p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_azi_offsets.ps
ps2raster -A -TG -P scale_azi_offsets.ps

rm -r files
mkdir files
cp $date1\_$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.png files/$date1-$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.png
cp $date1\_$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.png files/$date1-$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.png
cp scale_rng_offsets.png files/
cp scale_azi_offsets.png files/
cp /nfs/a285/homes/earjre/oxford/comethome/johne/misc/crests/2014_lics_logo/lics15_nerc_kmz.png files/lics.png
cp /nfs/a285/homes/earjre/oxford/comethome/johne/misc/crests/2016_comet/comet_new16_kmz.png files/comet.png
cp /nfs/a285/homes/earjre/oxford/comethome/johne/EwF/logo/Ewf_logo_v7_kmz.png files/ewf.png
set outfile = $date1\_$date2.gamma.offsets.rng.-$rlim.$rlim.azi.-$alim.$alim.median.off.geo.kml
cat <<EOF > $outfile
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
xmlns:gx="http://www.google.com/kml/ext/2.2"
xmlns:kml="http://www.opengis.net/kml/2.2"
xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
<Folder>
<name>Azimuth Offsets</name>
<GroundOverlay>
        <name>$date1-$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo</name>
        <Icon>
                <href>files/$date1-$date2.gamma.azi.-$alim.$alim.median$afilt.km.off.geo.png</href>
                <viewBoundScale>0.75</viewBoundScale>
        </Icon>
        <LatLonBox>
                <north>$north</north>
                <south>$south</south>
                <east>$east</east>
                <west>$west</west>
        </LatLonBox>
</GroundOverlay>
<ScreenOverlay>
        <name>Offsets Scale Bar</name>
        <Icon>
                <href>files/scale_azi_offsets.png</href>
        </Icon>
        <overlayXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
</Folder>
<Folder>
<name>Range Offsets</name>
<GroundOverlay>
        <name>$date1-$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo</name>
        <Icon>
                <href>files/$date1-$date2.gamma.rng.-$rlim.$rlim.median$rfilt.km.off.geo.png</href>
                <viewBoundScale>0.75</viewBoundScale>
        </Icon>
        <LatLonBox>
                <north>$north</north>
                <south>$south</south>
                <east>$east</east>
                <west>$west</west>
        </LatLonBox>
</GroundOverlay>
<ScreenOverlay>
        <name>Offsets Scale Bar</name>
        <Icon>
                <href>files/scale_rng_offsets.png</href>
        </Icon>
        <overlayXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.5" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
</Folder>
<Folder>
<name>Logos</name>
<ScreenOverlay>
        <name>LiCS NERC</name>
        <Icon>
                <href>files/lics.png</href>
        </Icon>
        <overlayXY x="0" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0.12" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
<ScreenOverlay>
        <name>COMET NERC</name>
        <Icon>
                <href>files/comet.png</href>
        </Icon>
        <overlayXY x="0.9" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.9" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0.16" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
<ScreenOverlay>
        <name>EwF NERC</name>
        <Icon>
                <href>files/ewf.png</href>
        </Icon>
        <overlayXY x="0.0" y="0.0" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.01" y="0.01" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0.10" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
</Folder>
</Document>
</kml>
EOF


# Zip to a kmz file
zip -r $date1\_$date2.gamma.offsets.rng.-$rlim.$rlim.azi.-$alim.$alim.median.off.geo.kmz $date1\_$date2.gamma.offsets.rng.-$rlim.$rlim.azi.-$alim.$alim.median.off.geo.kml files

######### Look Vectors
look_vector $date1.off.mli.par - EQA.off.dem_par EQA.off.dem lv_theta_tmp lv_phi_tmp
swap_bytes lv_theta_tmp lv_theta 4
swap_bytes lv_phi_tmp lv_phi 4
rm lv_theta_tmp lv_phi_tmp
mv lv_theta $date1\_$date2.off.lv_theta.geo.bin
mv lv_phi $date1\_$date2.off.lv_phi.geo.bin

#  lv_theta  (output) SAR look-vector elevation angle (at each map pixel)
#  lv_theta: PI/2 -> up  -PI/2 -> down
#  lv_phi    (output) SAR look-vector orientation angle at each map pixel
#  lv_phi: 0 -> East  PI/2 -> North

# Output as ERS header file
create_ers_header.tcsh $date1\_$date2.off.lv_theta.geo.bin.ers $dlon $dlatpos $length $width $west $north elevation-angle
create_ers_header.tcsh $date1\_$date2.off.lv_phi.geo.bin.ers $dlon $dlatpos $length $width $west $north orientation-angle

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.off.lv_theta.geo.bin -G$date1\_$date2.off.lv_theta.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid (using offsets region) Dimensions selected above
# Median Filter
grdfilter $date1\_$date2.off.lv_theta.geo.bin.grd -D1 -Fm$rfilt -G$date1\_$date2.off.lv_theta.median.geo.bin.grd -I$offres

# Convert from radians to Degrees
grdmath 90 $date1\_$date2.off.lv_theta.median.geo.bin.grd R2D SUB = $date1\_$date2.off.lv_theta.deg.geo.bin.grd


# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $date1\_$date2.off.lv_phi.geo.bin -G$date1\_$date2.off.lv_phi.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid (using offsets region) Dimensions selected above
# Median Filter
grdfilter $date1\_$date2.off.lv_phi.geo.bin.grd -D1 -Fm$rfilt -G$date1\_$date2.off.lv_phi.median.geo.bin.grd -I$offres

# Convert from radians to Degrees
grdmath -180 $date1\_$date2.off.lv_phi.median.geo.bin.grd R2D SUB = $date1\_$date2.off.lv_phi.deg.geo.bin.grd

# Convert to Line-of-Sight Vector
# Note Theta varies from 30-45 degrees
# V = cos (theta)
# H = sin (theta)
# Phi is -10 for ascending, and -170 for decending
# E = H cos (phi)
# N = H sin (phi)
# Because we want East, North, Up
# Have to multipy Eastward component by -1 to get consistent sign for motion towards the satellite
grdmath $date1\_$date2.off.lv_theta.deg.geo.bin.grd COSD = $date1\_$date2.off.lv_up.geo.bin.grd
grdmath $date1\_$date2.off.lv_theta.deg.geo.bin.grd SIND $date1\_$date2.off.lv_phi.deg.geo.bin.grd COSD MUL -1 MUL = $date1\_$date2.off.lv_east.geo.bin.grd
grdmath $date1\_$date2.off.lv_theta.deg.geo.bin.grd SIND $date1\_$date2.off.lv_phi.deg.geo.bin.grd SIND MUL = $date1\_$date2.off.lv_north.geo.bin.grd
# Test squares sum to 1
#grdmath $date1\_$date2.off.lv_up.geo.bin.grd SQR $date1\_$date2.off.lv_east.geo.bin.grd SQR ADD $date1\_$date2.off.lv_north.geo.bin.grd SQR ADD SQRT = total-off.grd

# Azimuth directions (untested for sign)
# Note opposite convention used above where motion along track for ascending is negative (westwards) and positive (northwards)
grdmath $date1\_$date2.off.lv_phi.deg.geo.bin.grd SIND = $date1\_$date2.azioff.lv_east.geo.bin.grd
grdmath $date1\_$date2.off.lv_phi.deg.geo.bin.grd COSD = $date1\_$date2.azioff.lv_north.geo.bin.grd
#grdmath $date1\_$date2.azioff.lv_east.geo.bin.grd SQR $date1\_$date2.azioff.lv_north.geo.bin.grd SQR ADD = total-azioff.grd


