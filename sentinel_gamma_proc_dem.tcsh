#!/bin/tcsh

if ($#argv != 1) then
  echo " "
  echo " usage: sentinel_gamma_proc_dem.tcsh masterdate"
  echo " e.g. sentinel_gamma_proc_dem.tcsh 20180105"
  echo " Processes Sentinel Interferometric WideSwath Data in TOPS mode using Gamma"
  echo " Does the DEM/lookup tables and look vectors"
  echo " Requires:"
  echo "           Master SLC processed"
  echo "           DEM of the area"
  echo "           a Processing Parameter File proc.param"
  echo "           that you have already run: sentinel_gamma_proc_slc.tcsh masterdate slclist"
  echo " "
  echo "John Elliott: 11/02/2019, Leeds, based upon sentinel_gamma.tcsh John Elliott: 20/02/2015, Oxford"
  echo "Last Updated: 21/07/2022, Leeds"
  exit
endif


# Set GMTDEFAULT Paper Size so kmz files in correct place
app setup gmt/4.5.15
echo Running GMT Version 4

# Store processing directory
set topdir = `pwd`
echo Processing in $topdir

# Master Date
set dateM = $1

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
# DEM
set dem = `grep demname $paramfile | awk '{print $2}'`
set demlat = `grep demlat $paramfile | awk '{print $2}'`
set demlon = `grep demlon $paramfile | awk '{print $2}'`
mkdir dem
ln -s $topdir/../dem/*/$dem* dem/
echo Oversampling DEM $dem by factor of $demlat in Latitude and $demlon in Longitude

# Test for DEM (as Geotiff)
if (-e dem/$dem.tif) then
        echo "\033[1;31m NOTE - Using DEM $dem.tif \033[0m"
else
        echo "\033[1;31m ERROR - DEM dem/$dem.tif does not exist \033[0m"
        exit
endif

# Output Figures Downsampling Average
set raspixavr = `grep raspixavr $paramfile | awk '{print $2}'`
set raspixavaz = `grep raspixavaz $paramfile | awk '{print $2}'`
set dim = `grep dim $paramfile | awk '{print $2}'`


# Pause to Read
sleep 1


#############################
# Start of GAMMA Processing #
#############################

# DEM and lookup table
echo "\033[1;31m Generating DEM files and lookup tables \033[0m"
mkdir $topdir/geodem
chdir $topdir/geodem
cp $topdir/slcs/$dateM/$dateM.slc.mli* .
cp $topdir/slcs/$dateM/$dateM.mli.par .
set widthmli = `grep range_samples $dateM.mli.par | awk '{print $2}'`
#swap_bytes $topdir/dem/$dem.dem $dem.swap.dem 4

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
#rm $dem.swap.dem_par
#create_dem_par $dem.swap.dem_par<<EOF
#EQA
#WGS84
#1
#$dem.swap.dem_par
#REAL*4
#0
#1
#$ncells
#$nlines
#$ydim $xdim
#$north $west
#EOF


# 2022 Update way to import DEM and apply geoid correction so relative to ellipsoid
dem_import $topdir/dem/$dem.tif $dem.swap.dem $dem.swap.dem_par 0 1 /apps/applications/gamma/$gammaver/2/default/DIFF/scripts/egm2008-5.dem /apps/applications/gamma/$gammaver/2/default/DIFF/scripts/egm2008-5.dem_par 0


# Display DEM
#disdem_par $dem.swap.dem $dem.swap.dem_par &


# GEOCODING
# Look-up table
gc_map $dateM.slc.mli.par - $dem.swap.dem_par $dem.swap.dem EQA.dem_par EQA.dem $dateM.lt $demlat $demlon $dateM.sim_sar u v inc psi pix ls_map 8 2

set widthdem = `grep width EQA.dem_par | awk '{print $2}'`

# Refinement of Geocoding lookup table
pixel_area $dateM.slc.mli.par EQA.dem_par EQA.dem $dateM.lt ls_map inc pix_sigma0 pix_gamma0

# Display simulated and MLI image
#dis2pwr pix_gamma0 $dateM.slc.mli $widthmli $widthmli &

# Correction to geocoding table based upon simulated and real MLI image
create_diff_par $dateM.slc.mli.par - $dateM.diff_par 1 0

offset_pwrm pix_sigma0 $dateM.slc.mli $dateM.diff_par $dateM.offs $dateM.cpp 256 256 offsets 1 64 64 0.1

offset_fitm $dateM.offs $dateM.cpp $dateM.diff_par coffs coffsets 0.1 1

gc_map_fine $dateM.lt $widthdem $dateM.diff_par $dateM.lt_fine 1

# View lookuptable
#dismph $dateM.lt_fine $widthdem &

# Geocode mli image using lookup table
geocode_back $dateM.slc.mli $widthmli $dateM.lt_fine EQA.$dateM.slc.mli $widthdem - 2 0

# Display Geocoded image
#dispwr EQA.$dateM.slc.mli $widthdem 1 4000 1. .35 0 &

# Transforming DEM heights into SAR Geometry of MLI
# Need to get number of lines from MLI file to make hgt correct length
set lengthmli = `grep azimuth_lines $dateM.mli.par | awk '{print $2}'`
geocode $dateM.lt_fine EQA.dem $widthdem $dateM.hgt $widthmli $lengthmli 2 0

# Display transformed DEM
#dishgt $dateM.hgt $dateM.slc.mli $widthmli &

# Output tif of DEM
rashgt $dateM.hgt - $widthmli - - - $raspixavr $raspixavaz - 1.0 0.35 - $dateM.hgt.tif

# Geocode back DEM
geocode_back $dateM.hgt $widthmli $dateM.lt_fine $dateM.hgt.geo $widthdem - 0 0

# Output tif of geocoded DEM
rashgt $dateM.hgt.geo - $widthdem - - - $raspixavr $raspixavaz - 1.0 0.35 - $dateM.hgt.geo.tif



##############
# Look Vectors
look_vector $dateM.mli.par - EQA.dem_par EQA.dem $dateM.lv_theta_geo $dateM.lv_phi_geo

# Geocode look vector into radar coordinates
geocode $dateM.lt_fine $dateM.lv_theta_geo $widthdem $dateM.lv_theta $widthmli $lengthmli 2 0
geocode $dateM.lt_fine $dateM.lv_phi_geo $widthdem $dateM.lv_phi $widthmli $lengthmli 2 0

#  lv_theta  (output) SAR look-vector elevation angle (at each map pixel)
#  lv_theta: PI/2 -> up  -PI/2 -> down
#  lv_phi    (output) SAR look-vector orientation angle at each map pixel
#  lv_phi: 0 -> East  PI/2 -> North





###############
# OUTPUT FILES
# GMT Paper Size
set papersize = 10
gmtset PAPER_MEDIA = a0
gmtset PAGE_ORIENTATION = portrait

swap_bytes $dateM.hgt.geo $dateM.hgt.geo.bin 4
swap_bytes $dateM.lv_theta_geo $dateM.lv_theta.geo.bin 4
swap_bytes $dateM.lv_phi_geo $dateM.lv_phi.geo.bin 4

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


# Output DEM files
# Output as ERS header file
create_ers_header.tcsh $dateM.hgt.geo.bin.ers $dlon $dlatpos $length $width $west $north elevation

# Output grd file
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $dateM.hgt.geo.bin -G$dateM.hgt.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $dateM.hgt.geo.bin.grd -G$dateM.hgt.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Plot DEM
grd2cpt -Cjet -E10 $dateM.hgt.geo."$dim"m.bin.grd -Z > height.cpt
grdimage $dateM.hgt.geo."$dim"m.bin.grd -JQ$papersize -Cheight.cpt -S-n -Q > $dateM.hgt.geo."$dim"m.bin.ps
ps2raster $dateM.hgt.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$dateM.hgt.geo."$dim"m"+l16/-1 -V

# Plot Scale
psscale -Cheight.cpt -D2/1/4/0.3h -B500/:"Elevation m": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_topo.ps
ps2raster -A -TG -P scale_topo.ps

# Plot Hillshaded DEM
grdgradient $dateM.hgt.geo."$dim"m.bin.grd -G$dateM.hgt.geo."$dim"m.bin.illum.grd -A135 -Ne0.6
grdimage $dateM.hgt.geo."$dim"m.bin.grd -I$dateM.hgt.geo."$dim"m.bin.illum.grd -JQ$papersize -C/nfs/a285/homes/earjre/oxford/comethome/johne/templates/grey.cpt -S-n -Q -V > $dateM.hgt.shaded.geo."$dim"m.bin.ps
ps2raster $dateM.hgt.shaded.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$dateM.hgt.geo."$dim"m"+l16/-1 -V


# Output KMZ
rm -r files
mkdir files
cp $dateM.hgt.geo."$dim"m.bin.png files/$dateM.hgt.geo."$dim".m.bin.png
cp $dateM.hgt.shaded.geo."$dim"m.bin.png files/$dateM.hgt.shaded.geo."$dim".m.bin.png
cp scale_topo.png files/
set outfile = $dateM.hgt.geo."$dim"m.kml
cat <<EOF > $outfile
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
<Folder>
<name>DEM and Hillshade</name>
<GroundOverlay>
        <name>$dateM.hgt.geo.$dim.m</name>
        <Icon>
                <href>files/$dateM.hgt.geo.$dim.m.bin.png</href>
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
        <name>$dateM.hgt.shaded.geo.$dim.m</name>
        <Icon>
                <href>files/$dateM.hgt.shaded.geo.$dim.m.bin.png</href>
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
zip -r $dateM.hgt.geo."$dim"m.kmz $dateM.hgt.geo."$dim"m.kml files

# Clean up
rm height.cpt $dateM.hgt.geo."$dim"m.bin.ps $dateM.hgt.geo."$dim"m.bin.png $dateM.hgt.geo."$dim"m.bin.kml scale_topo.ps scale_topo.png $dateM.hgt.shaded.geo."$dim"m.bin.ps $dateM.hgt.shaded.geo."$dim"m.bin.png $dateM.hgt.shaded.geo."$dim"m.bin.kml $dateM.hgt.geo."$dim"m.kml




# Look Vectors
# Output as ERS header file
create_ers_header.tcsh $dateM.lv_theta.geo.bin.ers $dlon $dlatpos $length $width $west $north elevation_angle
create_ers_header.tcsh $dateM.lv_phi.geo.bin.ers $dlon $dlatpos $length $width $west $north orientation_angle

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $dateM.lv_theta.geo.bin -G$dateM.lv_theta.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid (using height file) Dimensions selected above
grdfilter $dateM.lv_theta.geo.bin.grd -R$dateM.hgt.geo."$dim"m.bin.grd -G$dateM.lv_theta.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Convert from radians to Degrees
grdmath 90 $dateM.lv_theta.geo."$dim"m.bin.grd R2D SUB = $dateM.lv_theta.deg.geo."$dim"m.bin.grd

# Output as GMT grd format
xyz2grd -R$west/$east/$south/$north -I$dlon/$dlatpos $dateM.lv_phi.geo.bin -G$dateM.lv_phi.geo.bin.grd -F -N0 -ZTLf

# Downsample Grid
grdfilter $dateM.lv_phi.geo.bin.grd -R$dateM.hgt.geo."$dim"m.bin.grd -G$dateM.lv_phi.geo."$dim"m.bin.grd -I"$dim"e -Fm"$dimkm" -D3

# Convert from radians to Degrees
grdmath -180 $dateM.lv_phi.geo."$dim"m.bin.grd R2D SUB = $dateM.lv_phi.deg.geo."$dim"m.bin.grd


# Convert to Line-of-Sight Vector
# Note Theta varies from 30-45 degrees
# V = cos (theta)
# H = sin (theta)
# Phi is -10 for ascending, and -170 for decending
# E = H cos (phi)
# N = H sin (phi)
# Because we want East, North, Up
# Have to multipy Eastward component by -1 to get consistent sign for motion towards the satellite
grdmath $dateM.lv_theta.deg.geo."$dim"m.bin.grd COSD = $dateM.lv_up.geo."$dim"m.bin.grd
grdmath $dateM.lv_theta.deg.geo."$dim"m.bin.grd SIND $dateM.lv_phi.deg.geo."$dim"m.bin.grd COSD MUL -1 MUL = $dateM.lv_east.geo."$dim"m.bin.grd
grdmath $dateM.lv_theta.deg.geo."$dim"m.bin.grd SIND $dateM.lv_phi.deg.geo."$dim"m.bin.grd SIND MUL = $dateM.lv_north.geo."$dim"m.bin.grd

# ADDED By John.C create unscaled look vecotrs 
#grdmath $dateM.lv_theta.deg.geo.bin.grd COSD = $dateM.lv_up.geo.bin.grd
#grdmath $dateM.lv_theta.deg.geo.bin.grd SIND $dateM.lv_phi.deg.geo.bin.grd COSD MUL -1 MUL = $dateM.lv_east.geo.bin.grd
#grdmath $dateM.lv_theta.deg.geo.bin.grd SIND $dateM.lv_phi.deg.geo.bin.grd SIND MUL = $dateM.lv_north.geo.bin.grd


# Test squares sum to 1
#grdmath $dateM.lv_up.geo."$dim"m.bin.grd SQR $dateM.lv_east.geo."$dim"m.bin.grd SQR ADD $dateM.lv_north.geo."$dim"m.bin.grd SQR ADD SQRT = total.grd


# Plot Look Vectors (degrees)
grd2cpt -Cjet -E10 $dateM.lv_theta.deg.geo."$dim"m.bin.grd -Z > elev.cpt
grdimage $dateM.lv_theta.deg.geo."$dim"m.bin.grd -JQ$papersize -Celev.cpt -S-n -Q > $dateM.lv_theta.deg.geo."$dim"m.bin.ps
ps2raster $dateM.lv_theta.deg.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$dateM.lv_theta.deg.geo."$dim"m"+l16/-1 -V

# Plot Scale
psscale -Celev.cpt -D2/1/4/0.3h -B2/:"Incidence Angle (deg)": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_elev.ps
ps2raster -A -TG -P scale_elev.ps

# Plot Look Vectors (degrees)
grd2cpt -Cjet -E10 $dateM.lv_phi.deg.geo."$dim"m.bin.grd -Z > azi.cpt
grdimage $dateM.lv_phi.deg.geo."$dim"m.bin.grd -JQ$papersize -Cazi.cpt -S-n -Q > $dateM.lv_phi.deg.geo."$dim"m.bin.ps
ps2raster $dateM.lv_phi.deg.geo."$dim"m.bin.ps -E600 -TG -W+k+t"$dateM.lv_phi.deg.geo."$dim"m"+l16/-1 -V

# Plot Scale
psscale -Cazi.cpt -D2/1/4/0.3h -B0.1/:"Azimuth Angle (deg)": --ANNOT_FONT_SIZE_PRIMARY=3p --FRAME_PEN=0.5p --ANNOT_OFFSET_PRIMARY=0.05c --TICK_LENGTH=0.05c -V > scale_azi.ps
ps2raster -A -TG -P scale_azi.ps


# Output KMZ
rm -r files
mkdir files
mv $dateM.lv_theta.deg.geo."$dim"m.bin.png files/$dateM.lv_theta.deg.geo."$dim".m.bin.png
mv $dateM.lv_phi.deg.geo."$dim"m.bin.png files/$dateM.lv_phi.deg.geo."$dim".m.bin.png
mv scale_azi.png scale_elev.png files/
set outfile = $dateM.lv.deg.geo."$dim"m.kml
cat <<EOF > $outfile
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
<Folder>
<name>Look Vectors</name>
<GroundOverlay>
        <name>$dateM.lv_theta.deg.geo.$dim.m</name>
        <Icon>
                <href>files/$dateM.lv_theta.deg.geo.$dim.m.bin.png</href>
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
        <name>$dateM.lv_phi.deg.geo.$dim.m</name>
        <Icon>
                <href>files/$dateM.lv_phi.deg.geo.$dim.m.bin.png</href>
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
        <name>Incidence Angle Scale Bar</name>
        <Icon>
                <href>files/scale_elev.png</href>
        </Icon>
        <overlayXY x="0.25" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.25" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
<ScreenOverlay>
        <name>Azimuth Angle Scale Bar</name>
        <Icon>
                <href>files/scale_azi.png</href>
        </Icon>
        <overlayXY x="0.75" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.75" y="1" xunits="fraction" yunits="fraction"/>
        <rotationXY x="0" y="0" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="fraction" yunits="fraction"/>
</ScreenOverlay>
</Folder>
</Document>
</kml>
EOF

# Zip to a kmz file
zip -r $dateM.lv.deg.geo."$dim"m.kmz $dateM.lv.deg.geo."$dim"m.kml files

# Clean up
rm azi.cpt elev.cpt scale_azi.ps scale_elev.ps $dateM.lv_theta.deg.geo."$dim"m.bin.ps $dateM.lv_phi.deg.geo."$dim"m.bin.ps $dateM.lv_theta.deg.geo."$dim"m.bin.kml $dateM.lv_phi.deg.geo."$dim"m.bin.kml $dateM.lv.deg.geo."$dim"m.kml 
rm -r files



# Look Vectors in E,N,U in RADAR co-ordinates
# Swap Bytes
swap_bytes $dateM.lv_theta $dateM.lv_theta.bin 4
swap_bytes $dateM.lv_phi $dateM.lv_phi.bin 4

# Output as GMT grd format
xyz2grd -R0/1/0/1 -I$widthmli+/$lengthmli+ $dateM.lv_theta.bin -G$dateM.lv_theta.bin.grd -F -N0 -ZTLf
xyz2grd -R0/1/0/1 -I$widthmli+/$lengthmli+ $dateM.lv_phi.bin -G$dateM.lv_phi.bin.grd -F -N0 -ZTLf
# Convert from radians to Degrees
grdmath 90 $dateM.lv_theta.bin.grd R2D SUB = $dateM.lv_theta.deg.bin.grd
grdmath -180 $dateM.lv_phi.bin.grd R2D SUB = $dateM.lv_phi.deg.bin.grd


# Convert to Line-of-Sight Vector
# Note Theta varies from 30-45 degrees
# V = cos (theta)
# H = sin (theta)
# Phi is -10 for ascending, and -170 for decending
# E = H cos (phi)
# N = H sin (phi)
# Because we want East, North, Up
# Have to multipy Eastward component by -1 to get consistent sign for motion towards the satellite
grdmath $dateM.lv_theta.deg.bin.grd COSD = $dateM.lv_up.bin.grd
grdmath $dateM.lv_theta.deg.bin.grd SIND $dateM.lv_phi.deg.bin.grd COSD MUL -1 MUL = $dateM.lv_east.bin.grd
grdmath $dateM.lv_theta.deg.bin.grd SIND $dateM.lv_phi.deg.bin.grd SIND MUL = $dateM.lv_north.bin.grd


cp $dateM.lv_east.bin.grd $dateM.lv_east.final.bin.grd
cp $dateM.lv_north.bin.grd $dateM.lv_north.final.bin.grd
cp $dateM.lv_up.bin.grd $dateM.lv_up.final.bin.grd
# Test squares sum to 1
#grdmath $dateM.lv_up.bin.grd SQR $dateM.lv_east.bin.grd SQR ADD $dateM.lv_north.bin.grd SQR ADD SQRT = total.grd

# Output as binary
grd2xyz $dateM.lv_east.bin.grd -ZTLf > $dateM.lv_east.bin
grd2xyz $dateM.lv_north.bin.grd -ZTLf > $dateM.lv_north.bin
grd2xyz $dateM.lv_up.bin.grd -ZTLf > $dateM.lv_up.bin 

# Swap Back Bytes
swap_bytes $dateM.lv_east.bin $dateM.lv_east 4
swap_bytes $dateM.lv_north.bin $dateM.lv_north 4
swap_bytes $dateM.lv_up.bin $dateM.lv_up 4

# Clean Up
rm $dateM.lv_east.bin $dateM.lv_north.bin $dateM.lv_up.bin $dateM.lv_north.bin.grd $dateM.lv_east.bin.grd $dateM.lv_up.bin.grd $dateM.lv_theta.deg.bin.grd $dateM.lv_phi.deg.bin.grd $dateM.lv_phi.bin.grd $dateM.lv_theta.bin.grd $dateM.lv_phi.bin $dateM.lv_theta.bin

# Next Step
echo sentinel_gamma_proc_rslcs.tcsh $dateM slclist.txt
