# This R-script is party based on "An Introduction to State Space Models" by Marc Wildi.

# The function "KF_slopes_mixed_factor_CC" performs the estimation of the LFS model, with the auxiliary series of claimant counts and Google Trends. It requires the following arguments:
# par: initial values for the model's parameters (13x1 vector).
# y: (6+n)xT matrix of the unemployed labour force, the claiamnt counts and the n Google trends (the first 5 series are the unemployed labour force and the 6th one is the claimant counts) (T=167).
# opti: if TRUE, optimizes the function.
# k: Tx5 matrix of thestandard errors of the GREG estimates.
# delta: autocorrelation coefficient of the survey errors.
# outofsample: if TRUE, computes the loglikelihood based on the out-of-sample forecast errors.
# parP10: large number for the diffuse initialization.
# nstates: number of state variables in the model.
# lambda: nx1 vector of estimated, by PCA, factor's loading: ONLY 1 FACTOR IS ESTIMATED FOR THE GOOGLE TRENDS.
# H: the nxn estimated covariance matrix, by PCA, of the idiosyncratic components of the Google Trends.
# ns.id: vector of length equal to the number of nonstationary idiosyncratic components. It should contain the ordered numbers corresponing to the nonstationary idiosyncratic components. 

# The lines that are not commented here, are commented on /LFS_model.R, /LFS_model_with_CC.R and /LFS_model_with_GT.R  


# Packages required to run the scripts:
library(magic)

  
  
KF_slopes_mixed_factor_CC <- function(par,y,opti,k,delta,outofsample,parP10,nstates,lambda,H,ns.id){
    len <- length(y[1,])
    sigma_Ry <- par[1]
    sigma_omegay <- par[2]
    sigma_lambda <- par[3]
    sd_nu <- diag(exp(c(par[4], par[5], par[6], par[7], par[8])), 5,5)
    sigma_Rx <- par[9]      # variance of the claimant counts' slope's innovation.
    sigma_omegax <- par[10]      # variance of the claimant counts' seasonal component's innovation.
    sigma_Rz <- log(1)      # variance of the Google Trends' factor's innovation (it is fixed).
    x10 <- rep(0,nstates)
    Pttm1 <- lapply(seq_len(len+1), function(X) matrix(0,nstates,nstates))
    Ptt <- lapply(seq_len(len), function(X) matrix(0,nstates,nstates))
    P10 <- diag(c(rep(parP10[1],17),c(1,rep((1-delta^2),4),1,rep((1-delta^2),3),1,rep((1-delta^2),3)),rep(parP10[1],nstates-30)),nstates,nstates)     
    Pttm1[[1]] <- P10
    xtt <- matrix(0,nstates,(len))
    st.for <- matrix(0,nrow(y),len)
    xttm1 <- matrix(0,nstates,(len+1))
    xttm1[,1] <- x10
    R <- diag(1,nstates,nstates)
    D <- adiag(0, exp(sigma_Ry), exp(sigma_omegay)*diag(11), exp(sigma_lambda)*diag(4), sd_nu, diag(0,8,8), 0, exp(sigma_Rx), exp(sigma_omegax)*diag(11), exp(sigma_Rz), diag(sqrt(diag(H)[ns.id])))
    R[32,2] <- tanh(par[11])      # correlation between the LFS and the claimant counts' solpes' innovations.
    R[2,32] <- tanh(par[11])
    R[44,2] <- tanh(par[12])      # correlation between the LFS solpe's and the Google Trends' factor's innovations.
    R[2,44] <- tanh(par[12])
    Q <- D%*%R%*%D
    
    # Bulid T (the transition matrix):
    Tymu <- matrix(c(1,1,0,1),2,2, byrow=T)
    C <- array(0,dim=c(2,2,5))
    for (l in 1:5){
      C[,,l] <- matrix(c(cos((pi*l)/6),  sin((pi*l)/6), -sin((pi*l)/6), cos((pi*l)/6)),2,2,byrow=TRUE)
    }
    Tyomega <- adiag(C[,,1],C[,,2],C[,,3],C[,,4],C[,,5],-1)
    Tylambda <- diag(4)
    TyE <- rbind(matrix(0,9,5), cbind(diag(4), c(0,0,0,0)))
    delta <- delta
    TyE <- cbind(TyE, rbind(c(0,0,0,0),diag(delta,nrow=4,ncol=4),matrix(0,8,4)))
    TyE <- cbind(TyE, rbind(matrix(0,5,4),diag(4),matrix(0,4,4)))
    Ty <- adiag(Tymu, Tyomega, Tylambda, TyE)
    Tx <- adiag(Tymu, Tyomega)      # transition matrix of the claimant counts' state variables.
    Tz <- diag(1,ncol=(length(ns.id)+1), nrow=(length(ns.id)+1))      # transition matrix of the Google Trends' factor and the nonstationary idiosyncratic components.
    Tmatrix <- adiag(Ty, Tx, Tz)
    
    # Initialization of loglikelihood:
    logl <- 0
    
    # Start of KF recursions:
    for (i in 1:len){ 
      
      # Bulid Z:
      Zy <- c(1,0)
      Zy <- rep(Zy,6)
      Zy <- c(Zy,1)
      Zy <- rbind(Zy,Zy,Zy,Zy,Zy)
      Zy <- cbind(Zy,rbind(c(0,0,0,0),diag(4)))
      Zy <- cbind(Zy, diag(as.numeric(k[i,]), nrow=5, ncol=5), matrix(0, nrow=5, ncol=8))
      Zx <- c(1,0)
      Zx <- rep(Zx,6)
      Zx <- c(Zx,1)
      Zx <- rbind(Zx)
      one.ns.id <- rep(0, nrow(H))
      one.ns.id[ns.id] <- 1      # one if element of vector corresponds to nonstationary idiosyncratic component.
      Zz <- cbind(as.matrix(lambda,length(lambda),1),diag(one.ns.id))
      Zz <- Zz[,which(!apply(Zz,2,FUN = function(x){all(x == 0)}))]
      Z <- adiag(Zy,Zx,as.matrix(Zz))
      
      epshatoutofsample <- y[,i] - Z%*%xttm1[,i]
      diag.H <- diag(H)
      diag.H[ns.id] <- 0      # only variances of stationary idiosyncratic components.
      Fmatrix <- Z%*%Pttm1[[i]]%*%t(Z) + adiag(diag(0,ncol(waves),ncol(waves)),exp(2*par[13]),diag(diag.H,nrow(y)-ncol(waves)-1,nrow(y)-ncol(waves)-1))
      for (j in 1:nrow(y)){
        st.for[j,i] <- epshatoutofsample[j]/sqrt(Fmatrix[j,j])
      }
      if ((NaN %in% Fmatrix)==T){
        logl<- -P10[1]
      } else {
        svdFmatrix <- svd(Fmatrix)
        Kg <- Pttm1[[i]]%*%t(Z)%*%svdFmatrix$v%*%diag(1/svdFmatrix$d)%*%t(svdFmatrix$u)
        if (is.na(epshatoutofsample[1,])){
          Kg[,c(1:ncol(waves))] <- matrix(0,nstates,ncol(waves))
        }
        if (is.na(epshatoutofsample[ncol(waves)+1,])){
          Kg[,(ncol(waves)+1)] <- rep(0,nstates)
        }
        if (is.na(epshatoutofsample[ncol(waves)+2,])){
          Kg[,c((ncol(waves)+2):ncol(Kg))] <- matrix(0,nstates,ncol(Kg)-(ncol(waves)+1))
        }
        epshatoutofsample <- ifelse(is.na(epshatoutofsample), 0, epshatoutofsample)
        xtt[,i] <- xttm1[,i]+Kg%*%epshatoutofsample 
        epshatinsample <- y[,i]-Z%*%xtt[,i] 
        epshatinsample <- ifelse(is.na(epshatinsample), 0, epshatinsample)
        Ptt[[i]] <- Pttm1[[i]]-Kg%*%Z%*%Pttm1[[i]] 
        Pttm1[[i+1]] <- Tmatrix%*%Ptt[[i]]%*%t(Tmatrix)+Q 
        xttm1[,i+1] <- Tmatrix%*%xtt[,i] 
        
        # The optimization criterion:
        if (outofsample) {
          if (i <= (30-13) ){
            logl <- logl - nrow(y)/2*log(2*pi)
          } else if (i > (30-13) ){ 
            logl <- logl - nrow(y)/2*log(2*pi) - 1/2*log(det(Fmatrix)) - 1/2*t(epshatoutofsample)%*%svdFmatrix$v%*%diag(1/svdFmatrix$d)%*%t(svdFmatrix$u)%*%epshatoutofsample
            if ((NaN %in% logl)==T){
              logl<- -P10[1]
            }
          }
        } else {
          if (i <= (30-13) ){
            logl <- logl - nrow(y)/2*log(2*pi)
          } else if (i > (30-13) ){ 
            logl <- logl - nrow(y)/2*log(2*pi) - 1/2*log(det(Fmatrix)) - 1/2*t(epshatinsample)%*%svdFmatrix$v%*%diag(1/svdFmatrix$d)%*%t(svdFmatrix$u)%*%epshatinsample
            if ((NaN %in% logl)==T){
              logl<- -P10[1]
            }
          }
        }
      }
    }
    if (opti) {
      return(-logl)
    }
    else {
      return(list(logl=-logl, xtt=xtt,xttm1=xttm1,Pttm1=Pttm1,Ptt=Ptt,st.for=st.for))
    }
  } 
                  
                  
objopt <-  optim(par=c(log(2000),log(0.02),log(900),log(1.07),log(0.99*(1-0.21^2)),
                           log(1.01*(1-0.21^2)),log(1.13*(1-0.21^2)),log(1.06*(1-0.21^2)),log(3000),log(0.02),0,0,log(1000)),
                     KF_slopes_mixed_factor_CC,y=y,opti=T,k=k,delta=0.21,outofsample=T,
                     parP10=1000000000000,nstates=44,lambda=Lambda.hat.max[,1],H=H,  hessian=F, method="L-BFGS-B")
par <- objopt$par
obj <- KF_slopes_mixed_factor_CC(par=objopt$par,y=y,opti=F,k=k,delta=0.21,outofsample=T,parP10=1000000000000,
                                     nstates=44,lambda=Lambda.hat.max[,1],H=H)
    
