##' @title sda.enkf
##' @name  sda.enkf
##' @author Michael Dietze \email{dietze@bu.edu}
##' 
##' @param settings    PEcAn settings object
##' @param IC          data.frame of initial condition sample (nens X nstate)
##' @param prior       data.frame of model parameter sample (nense X nstate)
##' @param obs         data.frame of observations with columns: mean, sd
##' 
##' @description State Variable Data Assimilation: Ensemble Kalman Filter
##' 
##' @return NONE
##' 
sda.enkf <- function(settings,IC,prior,obs){
  
  ## settings
  model = settings$model$model_type
  write = settings$database$bety$write
  defaults <- settings$pfts
  outdir <- settings$run$host$outdir
  host <- settings$run$host
  start.year = strftime(settings$run$site$met.start,"%Y")
  end.year   = strftime(settings$run$site$met.end,"%Y")
  nens = nrow(IC)
  
  if(nrow(prior) == 1 | is.null(nrow(prior))){
    var.names = names(prior)
    prior = as.data.frame(matrix(rep(prior,each=nens),nrow=nens))
    names(prior) = var.names
  }
  
  sda.demo <- TRUE  ## debugging flag
  unit.conv <-  0.001*2#  kgC/ha/yr to Mg/ha/yr
    
  ## open database connection
  if(write){
    con <- try(db.open(settings$database$bety), silent=TRUE)
    if(is.character(con)){
      con <- NULL
    }
  } else {
    con <- NULL
  }
  
  # Get the workflow id
  if ("workflow" %in% names(settings)) {
    workflow.id <- settings$workflow$id
  } else {
    workflow.id <- -1
  }
  
  # create an ensemble id
  if (!is.null(con)) {
    # write enseblem first
    now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    db.query(paste("INSERT INTO ensembles (created_at, runtype, workflow_id) values ('", 
                   now, "', 'EnKF', ", workflow.id, ")", sep=''), con)
    ensemble.id <- db.query(paste("SELECT id FROM ensembles WHERE created_at='", now, "'", sep=''), con)[['id']]
  } else {
    ensemble.id <- -1
  }
  
  ## model-specific functions
  do.call("require",list(paste0("PEcAn.",model)))
  my.write.config <- paste("write.config.",model,sep="")
  if(!exists(my.write.config)){
    print(paste(my.write.config,"does not exist"))
    print(paste("please make sure that the PEcAn interface is loaded for",model))
    stop()
  }
  
  ## split clim file
  full.met <- settings$run$site$met
  new.met  <- file.path(settings$rundir,basename(full.met))
  file.copy(full.met,new.met)
  met <- split.met.SIPNET(new.met)
  
  
  ###-------------------------------------------------------------------###
  ### perform initial set of runs                                       ###
  ###-------------------------------------------------------------------###  
  run.id = list()
  for(i in 1:nens){
    
    ## set RUN.ID
    if (!is.null(con)) {
      now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      paramlist <- paste("EnKF:",i)
      db.query(paste("INSERT INTO runs (model_id, site_id, start_time, finish_time, outdir, created_at, ensemble_id,",
                   " parameter_list) values ('", 
                   settings$model$id, "', '", settings$run$site$id, "', '", settings$run$start.date, "', '", 
                   settings$run$end.date, "', '", settings$run$outdir , "', '", now, "', ", ensemble.id, ", '", 
                   paramlist, "')", sep=''), con)
      run.id[[i]]<- db.query(paste("SELECT id FROM runs WHERE created_at='", now, "' AND parameter_list='", paramlist, "'", 
                             sep=''), con)[['id']]
    } else {
      run.id[[i]] = paste("EnKF",i,sep=".")
    }
    dir.create(file.path(settings$rundir, run.id[[i]]), recursive=TRUE)
    dir.create(file.path(settings$modeloutdir, run.id[[i]]), recursive=TRUE)
    
    ## write config
    do.call(my.write.config,args=list(defaults,list(pft=prior[i,],env=NA),
                                      settings, run.id[[i]],inputs = list(met=met[1]),IC=IC[i,]))
    
    ## write a README for the run
    cat("runtype     : sda.enkf\n",
        "workflow id : ", as.character(workflow.id), "\n",
        "ensemble id : ", as.character(ensemble.id), "\n",
        "ensemble    : ", i, "\n",
        "run id      : ", as.character(run.id[[i]]), "\n",
        "pft names   : ", as.character(lapply(settings$pfts, function(x) x[['name']])), "\n",
        "model       : ", model, "\n",
        "model id    : ", settings$model$id, "\n",
        "site        : ", settings$run$site$name, "\n",
        "site  id    : ", settings$run$site$id, "\n",
        "met data    : ", new.met, "\n",
        "start date  : ", settings$run$start.date, "\n",
        "end date    : ", settings$run$end.date, "\n",
        "hostname    : ", settings$run$host$name, "\n",
        "rundir      : ", file.path(settings$run$host$rundir, run.id[[i]]), "\n",
        "outdir      : ", file.path(settings$run$host$outdir, run.id[[i]]), "\n",
        file=file.path(settings$rundir, run.id[[i]], "README.txt"), sep='')
      
  }
  
  ## add the jobs to the list of runs
  cat(as.character(run.id),file=file.path(settings$rundir, "runs.txt"),sep="\n",append=FALSE)
      
  ## start model run
  start.model.runs(settings,settings$database$bety$write)
  

  time = start.year:end.year
  nt = length(time)
  ens = list()
  NPPm = rep(NA,nens)
  FORECAST <- ANALYSIS <- list()
  enkf.params <- list()
  ###-------------------------------------------
  ### loop over time
  ###-------------------------------------------
  for(t in 1:nt){

    ### load output
    forecast = IC
    for(i in 1:nens){
      ens[[i]] <- read.output(run.id[[i]],file.path(outdir, run.id[[i]]),
                              start.year = time[t],end.year=time[t],
                              variables=c("NPP","AbvGrndWood","TotSoilCarb","LeafC","SoilMoistFrac","SWE","Litter")
                              )
      NPPm[i] <- mean(ens[[i]]$NPP)*unit.conv ## kg C m-2 s-1 -> Mg/ha/yr [Check]
      last = length(ens[[i]]$NPP)
      forecast$plantWood[i] = ens[[i]]$AbvGrndWood[last]*1000 ## kgC/m2 -> gC/m2
      forecast$lai[i] = ens[[i]]$LeafC[last]*prior$SLA[i]*2 ## kgC/m2*m2/kg*2kg/kgC -> m2/m2
      forecast$litter[i] = ens[[i]]$Litter[last]*1000 ##kgC/m2 -> gC/m2
      forecast$soil[i] = ens[[i]]$TotSoilCarb[last]*1000 ## kgC/m2 -> gC/m2
      forecast$litterWFrac[i] = ens[[i]]$SoilMoistFrac[last] ## unitless
      forecast$soilWFrac[i] = ens[[i]]$SoilMoistFrac[last] ## unitless
      forecast$snow[i] = ens[[i]]$SWE[last]*0.1 ## kg/m2 -> cm
      #forecast$microbe[i] = NA
   }
   X    = cbind(NPPm,forecast)
   FORECAST[[t]] = X
    
 ### Analysis step
 X$snow = runif(nens,0,0.01)
 mu.f = apply(X,2,mean,na.rm=TRUE)
 Pf   = cov(X)
 Y    = obs$mean[t]
 R    = obs$sd[t]^2
 H    = matrix(c(1,rep(0,ncol(forecast))),1,ncol(X))
 if(!is.na(Y)){
   K    = Pf%*%t(H)%*%solve(R+H%*%Pf%*%t(H))
   mu.a = mu.f + K%*%(Y-H%*%mu.f)
   Pa   = (diag(ncol(X)) - K%*%H)%*%Pf
 } else {
   mu.a = mu.f
   Pa   = Pf
 }
 enkf.params[[t]] = list(mu.f = mu.f, Pf=Pf,mu.a=mu.a,Pa=Pa) 
 
 ## update state matrix
analysis = as.data.frame(rmvnorm(nens,mu.a,Pa,method="svd"))
names(analysis) = names(X)
 # EAKF
 if(FALSE){
   analysis = X
   
   ## Math from Anderson 2001. gives correct mean but incorrect var
   A.svd = svd(Pf)
   F = A.svd$v
   G = diag(sqrt(A.svd$d))
   B.svd = svd(t(G)%*%t(F)%*%t(H)%*%solve(R)%*%H%*%F%*%G)
   U = B.svd$v
   B = diag((1+B.svd$d)^(-0.5))
   A = solve(t(F))%*%t(G)*solve(t(U))%*%t(B)%*%solve(t(G))%*%t(F)
   for(i in 1:nens){
     analysis[i,] = t(A)%*%matrix(as.numeric(X[i,])-mu.f)+mu.a
   }
   
   ## HACK IGNORNING COVARIANCE
   for(i in 1:nens){
     analysis[i,] = mu.a + (matrix(as.numeric(X[i,]))-mu.f)*sqrt(diag(Pa)/diag(Pf))
   }   
   
 }
## analysis sanity check
for(i in 2:ncol(analysis)){
  analysis[analysis[,i]<0,i] = 0.0
}

 ANALYSIS[[t]] = analysis
 
 ### Forecast step
 if(t < nt){
   for(i in 1:nens){   
     file.rename(file.path(outdir,run.id[[i]],"sipnet.out"),file.path(outdir,run.id[[i]],paste0("sipnet.out",time[t])))
     file.remove(file.path(settings$rundir,run.id[[i]],"sipnet.clim"))
     do.call(my.write.config,args=list(defaults,list(pft=prior[i,],env=NA),
                                     settings, run.id[[i]],inputs = list(met=met[t+1]),IC=analysis[i,-1]))   
  }
 }
 ## start model run
 start.model.runs(settings,settings$database$bety$write)
 
}  ## end loop over time
###-------------------------------------------


## save all outputs
save(FORECAST,ANALYSIS,enkf.params,file=file.path(settings$outdir,"sda.ENKF.Rdata"))

if(FALSE){
  ### Load Data
  if(sda.demo){
    ## use one of the ensemble members as the true data
    NPP <- read.output("ENS00001",settings$outdir,variables="NPP",model=model)$NPP
    ytrue = tapply(NPP,Year,mean)*unit.conv
    sd <- 0.3  ## pseudo data uncertainty
    y <- rnorm(nt,ytrue,sd) ## add noise
  } else {
    load(file.path(settings$outdir,"plot2AGB.Rdata"))
    mch = which(yrvec %in% time)
    y = mNPP[1,mch]   ## data mean
    sd = sNPP[1,mch]  ## data uncertainty 
  }
}  

#### Post-processing

  ### Diagnostic graphs  
  pdf(file.path(settings$outdir,"EnKF.pdf"))
  
  ## plot ensemble, filter, and data mean's and CI's
  par(mfrow=c(1,1))
  y = obs[1:length(time),]
  plot(time,y$mean,ylim=range(c(y$mean+1.96*y$sd,y$mean-1.96*y$sd)),type='n',xlab="time",ylab="Mg/ha/yr")
  ciEnvelope(time,y$mean-y$sd*1.96,y$mean+y$sd*1.96,col="lightblue")
  lines(time,y$mean,type='b',col="darkblue")
  
  pink = col2rgb("pink")
  alphapink = rgb(pink[1],pink[2],pink[3],100,max=255)
  Xbar = laply(FORECAST,function(x){return(mean(x$NPPm,na.rm=TRUE))})
  Xci  = laply(FORECAST,function(x){return(quantile(x$NPPm,c(0.025,0.975)))})
  plot(time,y$mean,ylim=range(c(y$mean+1.96*y$sd,y$mean-1.96*y$sd)),type='n',xlab="time",ylab="Mg/ha/yr")
  ciEnvelope(time,y$mean-y$sd*1.96,y$mean+y$sd*1.96,col="lightblue")
  lines(time,y$mean,type='b',col="darkblue")
  #if(sda.demo) lines(time,ensp[ref,],col=2,lwd=2)
  ciEnvelope(time,Xci[1:nt,1],Xci[1:nt,2],col=alphapink)
  lines(time,Xbar[1:nt],col=6,type='b')

  green = col2rgb("green")
  alphagreen = rgb(green[1],green[2],green[3],100,max=255)
  Xa = laply(ANALYSIS,function(x){return(mean(x$NPPm,na.rm=TRUE))})
  XaCI  = laply(ANALYSIS,function(x){return(quantile(x$NPPm,c(0.025,0.975)))})
  plot(time,y$mean,ylim=range(c(y$mean+1.96*y$sd,y$mean-1.96*y$sd)),type='n',xlab="time",ylab="Mg/ha/yr")
  ciEnvelope(time,y$mean-y$sd*1.96,y$mean+y$sd*1.96,col="lightblue")
  lines(time,y$mean,type='b',col="darkblue")
  ciEnvelope(time,Xci[1:nt,1],Xci[1:nt,2],col=alphapink)
  lines(time,Xbar[1:nt],col=2,type='b')
  ciEnvelope(time,XaCI[1:nt,1],XaCI[1:nt,2],col=alphagreen)
  lines(time,Xa[1:nt],col="darkgreen",type='b')
  legend("topleft",c("Data","Forecast","Analysis"),col=c(4,2,3),lty=1,cex=1)
  
### Plots demonstrating how the constraint of your target variable 
### impacts the other model pools and fluxes
  
  ## plot scatter plots of outputs
  pairs(FORECAST[[nt]])
  pairs(ANALYSIS[[nt]])

  ## time series of outputs
  for(i in 1:ncol(X)){
    Xa = laply(ANALYSIS,function(x){return(mean(x[,i],na.rm=TRUE))})
    XaCI  = laply(ANALYSIS,function(x){return(quantile(x[,i],c(0.025,0.975)))})
    plot(time,Xa,ylim=range(XaCI),type='n',xlab="time",main=names(X)[i])
    ciEnvelope(time,XaCI[,1],XaCI[,2],col="lightblue")
    lines(time,Xa,type='b',col="darkblue")
  }
  
  dev.off()
  
}
