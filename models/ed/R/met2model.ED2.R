#-------------------------------------------------------------------------------
# Copyright (c) 2012 University of Illinois, NCSA.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the 
# University of Illinois/NCSA Open Source License
# which accompanies this distribution, and is available at
# http://opensource.ncsa.illinois.edu/license.html
#-------------------------------------------------------------------------------
## R Code to convert from NACP intercomparison NETCDF met files
## into ED2 ascii met files

## It requires the rhdf5 library, which is not available on CRAN, but by can be installed locally:
# >source("http://bioconductor.org/biocLite.R")
# >biocLite("rhdf5")

##If files already exist in "Outfolder", the default function is NOT to overwrite them and 
##only gives user the notice that file already exists. If user wants to overwrite the existing files, just change 
##overwrite statement below to TRUE.


met2model.ED2 <- function(in.path,in.prefix,outfolder,lst,overwrite=FALSE){
  overwrite = as.logical(overwrite)
  lst = as.numeric(lst)
  
  #files = dir(in.path,in.prefix,full.names=TRUE)
  files = dir(in.path,in.prefix)
  filescount = files[grep(pattern="*.nc",files)]
  
  require(rhdf5)
  require(ncdf4)
  require(ncdf)
  
### FUNCTIONS
dm <- c(0,32,60,91,121,152,182,213,244,274,305,335,366)
dl <- c(0,32,61,92,122,153,183,214,245,275,306,336,367)
month <- c("JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC")
mon_num <- c("01","02","03","04","05","06","07","08","09","10","11","12")
day2mo <- function(year,day){
  leap <- (year %% 4 == 0)
  mo <- rep(NA,length(day))
  mo[leap] <- findInterval(day[leap],dl)
  mo[!leap] <- findInterval(day[!leap],dm)
  return(mo)
}


## loop over files
for(i in 1:length(filescount)){

  ## extract file root name
  #froot <- substr(files[i],1,28)
  #print(c(i,froot))
  
  ## check to see if the outfolder is defined, if not create directory for output
  if(!file.exists(outfolder)){
    dir.create(outfolder)
  }

  ## open netcdf
  nc <- nc_open(paste0(in.path,files[i]))
  
  ## determine starting year
  base.time <- unlist(strsplit(files[i],'[.]'))
  base.time <- as.numeric(base.time[length(base.time)-1])
  if(is.na(base.time)){
      print(c("did not extract base time correctly",i))
      break
    }

  ## determine GMT adjustment
  ## lst <- site$LST_shift[which(site$acro == froot)]
  
  
  ## extract variables
  lat  <- ncvar_get(nc,"lat")
  lon  <- ncvar_get(nc,"lon")
  sec   <- nc$dim$t$vals
  Tair <- ncvar_get(nc,"air_temperature")
  Qair <- ncvar_get(nc,"specific_humidity")  #humidity (kg/kg)
  U <- ncvar_get(nc,"eastward_wind")
  V <- ncvar_get(nc,"northward_wind")
  Rain <- ncvar_get(nc,"precipitation_flux")
  pres <- ncvar_get(nc,"air_pressure")
  SW   <- ncvar_get(nc,"surface_downwelling_shortwave_flux")
  LW   <- ncvar_get(nc,"surface_downwelling_longwave_flux")
  CO2  <- try(ncvar_get(nc,"CO2air"))
  useCO2 = is.numeric(CO2)  

  ## convert time to seconds
  sec = udunits2::ud.convert(sec,unlist(strsplit(nc$dim$t$units," "))[1],"seconds")
  
  nc_close(nc)
  
  dt <- sec[2]-sec[1]
  toff <- -lst*3600/dt

  ##buffer to get to GMT
  slen <- length(SW)
  Tair <- c(rep(Tair[1],toff),Tair)[1:slen]
  Qair <- c(rep(Qair[1],toff),Qair)[1:slen]
  U <- c(rep(U[1],toff),U)[1:slen]
  V <- c(rep(V[1],toff),V)[1:slen]
  Rain <- c(rep(Rain[1],toff),Rain)[1:slen]
  pres <- c(rep(pres[1],toff),pres)[1:slen]
  SW <- c(rep(SW[1],toff),SW)[1:slen]
  LW <- c(rep(LW[1],toff),LW)[1:slen]
  if(useCO2)  CO2 <- c(rep(CO2[1],toff),CO2)[1:slen]
 
  
  ##build time variables (year, month, day of year)
  nyr <- floor(length(sec)/86400/365*dt)
  yr <- NULL
  doy <- NULL
  hr <- NULL
  asec <- sec
  for(y in base.time+1:nyr-1){
    ytmp <- rep(y,365*86400/dt)
    dtmp <- rep(1:365,each=86400/dt)
    if(y %% 4 == 0){  ## is leap
      ytmp <- rep(y,366*86400/dt)
      dtmp <- rep(1:366,each=86400/dt)
    }
    if(is.null(yr)){
      yr <- ytmp
      doy <- dtmp
      hr <- rep(NA,length(dtmp))
    } else {
      yr <- c(yr,ytmp)
      doy <- c(doy,dtmp)
      hr <- c(hr,rep(NA,length(dtmp)))
    }
    rng <- length(doy) - length(ytmp):1 + 1
    asec[rng] <- asec[rng] - asec[rng[1]]
    hr[rng] <- (asec[rng] - (dtmp-1)*86400)/86400*24
  }
  mo <- day2mo(yr,doy)
  if(length(yr) < length(sec)){
    rng <- (length(yr)+1):length(sec)
    yr[rng] <- rep(y+1,length(rng))
    doy[rng] <- rep(1:366,each=86400/dt)[1:length(rng)]
    hr[rng] <- rep(seq(0,length=86400/dt,by=dt/86400*24),366)[1:length(rng)]
  }
  
  ## calculate potential radiation
  ## in order to estimate diffuse/direct
  f <- pi/180*(279.5+0.9856*doy)
  et <- (-104.7*sin(f)+596.2*sin(2*f)+4.3*sin(4*f)-429.3*cos(f)-2.0*cos(2*f)+19.3*cos(3*f))/3600  #equation of time -> eccentricity and obliquity
  merid <- floor(lon/15)*15
  if(merid<0) merid <- merid+15
  lc <- (lon-merid)*-4/60  ## longitude correction
  tz <- merid/360*24 ## time zone
  midbin <- 0.5*dt/86400*24 ## shift calc to middle of bin
  t0 <- 12+lc-et-tz-midbin   ## solar time
  h <- pi/12*(hr-t0)  ## solar hour
  dec <- -23.45*pi/180*cos(2*pi*(doy+10)/365)  ## declination

  cosz <- sin(lat*pi/180)*sin(dec)+cos(lat*pi/180)*cos(dec)*cos(h)
  cosz[cosz<0] <- 0
  
  rpot <- 1366*cosz
  rpot <- rpot[1:length(SW)]
  
  SW[rpot < SW] <- rpot[rpot<SW] ## ensure radiation < max
      ### this causes trouble at twilight bc of missmatch btw bin avergage and bin midpoint
  frac <- SW/rpot
  frac[frac>0.9] <- 0.9  ## ensure some diffuse
  frac[frac < 0.0] <- 0.0
  frac[is.na(frac)] <- 0.0
  frac[is.nan(frac)] <- 0.0
  SWd <- SW*(1-frac)  ## Diffuse portion of total short wave rad
  
### convert to ED2.1 hdf met variables
  n     <- length(Tair)
  nbdsfA <- (SW - SWd) * 0.57 # near IR beam downward solar radiation [W/m2]
  nddsfA <- SWd * 0.48        # near IR diffuse downward solar radiation [W/m2]
  vbdsfA <- (SW - SWd) * 0.43 # visible beam downward solar radiation [W/m2]
  vddsfA <- SWd * 0.52        # visible diffuse downward solar radiation [W/m2]
  prateA <- Rain              # precipitation rate [kg_H2O/m2/s]
  dlwrfA <- LW                # downward long wave radiation [W/m2]
  presA  <- pres              # pressure [Pa]
  hgtA   <- rep(50,n)         # geopotential height [m]
  ugrdA  <- U                 # zonal wind [m/s]
  vgrdA  <- V                 # meridional wind [m/s]
  shA    <- Qair              # specific humidity [kg_H2O/kg_air]
  tmpA   <- Tair              # temperature [K]
  if(useCO2){
    co2A   <- CO2               # surface co2 concentration [ppm]
  }
  
  ## create directory
  #if(system(paste("ls",froot),ignore.stderr=TRUE)>0) system(paste("mkdir",froot))
  
  ## write by year and month
  for(y in base.time+1:nyr-1){
    sely <- which(yr == y)
    for(m in unique(mo[sely])){
      selm <- sely[which(mo[sely] == m)]
      mout <- paste(outfolder,"/",y,month[m],".h5",sep="")     
      if(file.exists(mout)){
        if(overwrite==TRUE){
          file.remove(mout)
          h5createFile(mout)
        }
        if(overwrite==FALSE){
          logger.setLevel("Warning! The file already exists! Moving to next month!")
          next
        }        
      }
      else h5createFile(mout)
      dims <- c(length(selm),1,1)
      nbdsf <- array(nbdsfA[selm],dim=dims)
      nddsf <- array(nddsfA[selm],dim=dims)
      vbdsf <- array(vbdsfA[selm],dim=dims)
      vddsf <- array(vddsfA[selm],dim=dims)
      prate <- array(prateA[selm],dim=dims)
      dlwrf <- array(dlwrfA[selm],dim=dims)
      pres  <- array(presA[selm],dim=dims)
      hgt   <- array(hgtA[selm],dim=dims)
      ugrd  <- array(ugrdA[selm],dim=dims)
      vgrd  <- array(vgrdA[selm],dim=dims)
      sh    <- array(shA[selm],dim=dims)
      tmp   <- array(tmpA[selm],dim=dims)
      if(useCO2){
        co2   <- array(co2A[selm],dim=dims)
      }
      h5write(nbdsf,mout,"nbdsf")
      h5write(nddsf,mout,"nddsf")
      h5write(vbdsf,mout,"vbdsf")
      h5write(vddsf,mout,"vddsf")
      h5write(prate,mout,"prate")
      h5write(dlwrf,mout,"dlwrf")
      h5write(pres,mout,"pres")
      h5write(hgt,mout,"hgt")
      h5write(ugrd,mout,"ugrd")
      h5write(vgrd,mout,"vgrd")
      h5write(sh,mout,"sh")
      h5write(tmp,mout,"tmp")
      if(useCO2){
          h5write(co2,mout,"co2")
      }
     
      
    }
  }

  ## write DRIVER file
  sites <- 1
  metfile <- paste(outfolder,"/ED_MET_DRIVER_HEADER",sep="")
  metpath <- paste(outfolder,"/",sep="")
  metgrid <- c(1,1,1,1,floor(lon),floor(lat))
  metvar <- c("nbdsf","nddsf","vbdsf","vddsf","prate","dlwrf","pres","hgt","ugrd","vgrd","sh","tmp","co2")
  nmet <- length(metvar)
  metfrq <- rep(dt,nmet)
  metflag <- rep(1,nmet)
  if(!useCO2){
    metflag[metvar=="co2"] = 4
    metfrq[metvar=="co2"] = 380
  }
  write.table("#header",metfile,row.names=FALSE,col.names=FALSE)
  write.table(sites,metfile,row.names=FALSE,col.names=FALSE,append=TRUE)
  write.table(metpath,metfile,row.names=FALSE,col.names=FALSE,append=TRUE,quote=FALSE)
  write.table(matrix(metgrid,nrow=1),metfile,row.names=FALSE,col.names=FALSE,append=TRUE,quote=FALSE)
  write.table(nmet,metfile,row.names=FALSE,col.names=FALSE,append=TRUE,quote=FALSE)
  write.table(matrix(metvar,nrow=1),metfile,row.names=FALSE,col.names=FALSE,append=TRUE)
  write.table(matrix(metfrq,nrow=1),metfile,row.names=FALSE,col.names=FALSE,append=TRUE,quote=FALSE)
  write.table(matrix(metflag,nrow=1),metfile,row.names=FALSE,col.names=FALSE,append=TRUE,quote=FALSE)
 
} ### end loop over met files

} ### end met2model.ED2
