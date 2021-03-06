#---------------- Load libraries. -----------------------------------------------------------------#
require(PEcAn.all)
require(PEcAn.data.atmosphere)
require(RPostgreSQL)

#--------------------------------------------------------------------------------------------------#
# Clear old database connections
for (i in dbListConnections(PostgreSQL())) db.close(i)

#--------------------------------------------------------------------------------------------------#
# Download raw NARR from the internet 

rm(list = setdiff(ls(), lsf.str()))
outfolder  <- "/projectnb/cheas/pecan.data/input/NARR/"
start_year <- 1979
end_year   <- 2013
pkg        <- "PEcAn.data.atmosphere"
NARR.host  <- "geo.bu.edu"

NARR_raw.id <- raw.NARR(outfolder,start_year,end_year,pkg,NARR.host) 
# NARR_raw.id should be 285

#--------------------------------------------------------------------------------------------------#
# Update NARR_CF
# input.id  <-  285
input.id  <-  NARR_raw.id
outfolder <- "/projectnb/cheas/pecan.data/input/NARR_CF/"
pkg       <- "PEcAn.data.atmosphere"
fcn       <- "met2cf.NARR"
write     <-  TRUE
username  <- ""

NARR_cf.id <- convert.input(input.id,outfolder,pkg,fcn,write,username,format) # doesn't update existing record
# NARR_cf.id should be 288

#--------------------------------------------------------------------------------------------------#
# Rechunk and Permute
input.id  <-  NARR_cf.id
outfolder <- "/projectnb/cheas/pecan.data/input/NARR_CF_Permute/"
write     <-  TRUE

NARR_perm.id <- permute.nc(input.id,outfolder,write)
#NARR_perm.id should be 1000000023

#--------------------------------------------------------------------------------------------------#
# Extract for location
input.id <- NARR_perm.id
newsite  <- 336
str_ns   <- paste0(newsite %/% 1000000000, "-", newsite %% 1000000000)

outfolder <- paste0("/projectnb/cheas/pecan.data/input/NARR_CF_site_",str_ns,"/")
pkg       <- "PEcAn.data.atmosphere"
fcn       <- "extract.NARR"
write     <- TRUE
username  <- ""

NARR_extract.id <- convert.input (input.id,outfolder,pkg,fcn,write,username,format,newsite = newsite)

#--------------------------------------------------------------------------------------------------#
# Prepare for ED Model

# Acquire lst (probably a better method, but this works for now)
lst <- site.lst(newsite)

# Convert to ED format
input.id <- NARR_extract.id

outfolder <- paste0("/projectnb/cheas/pecan.data/input/NARR_ED_site_",str_ns,"/")
pkg       <- "PEcAn.ED2"
fcn       <- "met2model.ED2"
write     <- TRUE
overwrite <- ""
username  <- ""

NARR_ED.id <- convert.input (input.id,outfolder,pkg,fcn,write,username,format,lst=lst,overwrite=overwrite)

#--------------------------------------------------------------------------------------------------#
# Clear old database connections
for (i in dbListConnections(PostgreSQL())) db.close(i)
