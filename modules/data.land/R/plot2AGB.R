## convert composite ring & census data into AGB

plot2AGB <- function(unit.conv=0.02){
  
  ## Jenkins: hemlock (kg)
  b0 <- -2.5384
  b1 <- 2.4814
  
  ## load data
  outfolder <- settings$outdir
  load(paste(outfolder,"DBH_summary.RData",sep=""))
  nrep = length(full.dia)
  nt = ncol(full.dia[[1]])
  
  ## set up storage
  NPP <- array(NA,c(mplot,nrep,nt-1))
  AGB <- array(NA,c(mplot,nrep,nt))
  
  ## sample over tree chronologies
  for(g in 1:nrep){
    
    ## convert tree diameter to biomass    
    biomass <- exp(b0 + b1*log(full.dia[[g]]))
  
    for(j in 1:mplot){
      
      ## aggregate to stand AGB      
      AGB[j,g,] <- apply(biomass[ijindex[,1]==j,],2,sum,na.rm=TRUE)*unit.conv
  
      ## diff to get NPP
      NPP[j,g,] <- diff(AGB[j,g,])
      
    }
  }
  
  mAGB <- sAGB <- matrix(NA,mplot,nt)
  mNPP <- sNPP <- matrix(NA,mplot,nt-1)
  for(i in 1:mplot){
    mNPP[i,] <- apply(NPP[i,,],2,mean,na.rm=TRUE)
    sNPP[i,] <- apply(NPP[i,,],2,sd,na.rm=TRUE)
    mAGB[i,] <- apply(AGB[i,,],2,mean,na.rm=TRUE)
    sAGB[i,] <- apply(AGB[i,,],2,sd,na.rm=TRUE)
  }

  pdf(paste(outfolder,"plot2AGB.pdf",sep="/"))
  par(mfrow=c(2,1))
  for(i in 1:mplot){
    up = mNPP[i,]+sNPP[i,]*1.96
    low = mNPP[i,]-sNPP[i,]*1.96
    plot(yrvec[-1],mNPP[i,],ylim=range(c(up,low)),ylab="Mg/ha/yr",xlab="year" ) 
    lines(yrvec[-1],up)
    lines(yrvec[-1],low)
    upA = mAGB[i,]+sAGB[i,]*1.96
    lowA = mAGB[i,]-sAGB[i,]*1.96
    plot(yrvec,mAGB[i,],ylim=range(c(upA,lowA)),ylab="Mg/ha",xlab="year")
    lines(yrvec,upA)
    lines(yrvec,lowA)
  }
  dev.off()
  save(mNPP,sNPP,mAGB,sAGB,yrvec,file=paste(outfolder,"plot2AGB.Rdata",sep="/"))
  
}