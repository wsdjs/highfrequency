spotvol <- function(data, method = "detper", ..., on = "minutes", k = 5,
                    marketopen = "09:30:00", marketclose = "16:00:00",
                    tz = "GMT")  
{
  if (on == "seconds" | on == "secs") 
    delta <- k 
  if (on == "minutes" | on == "mins") 
    delta <- k*60  
  if (on == "hours") 
    delta <- k*3600 
  
  if (inherits(data, what = "xts")) {
    data <- xts(data, order.by = as.POSIXct(time(data), tz = tz), tzone = tz)
    dates <- unique(format(time(data), "%Y-%m-%d"))
    cDays <- length(dates)
    rdata <- mR <- c()
    intraday <- seq(from = chron::times(marketopen), 
                    to = chron::times(marketclose), 
                    by = chron::times(delta/(24*3600))) 
    if (as.character(tail(intraday, 1)) != marketclose) 
      intraday <- c(intraday, marketclose)
    intraday <- intraday[2:length(intraday)]
    for (d in 1:cDays) {
      datad <- data[as.character(dates[d])]
      if (!all(format(time(datad), format = "%Z") == tz)) 
        stop(paste("Not all data on ", dates[d], " is in time zone \"", tz,
                   "\". This may be due to daylight saving time. Try using a",
                   " time zone without daylight saving, such as GMT.", 
                   sep = ""))
      datad <- aggregatePrice(datad, on = on, k = k , marketopen = marketopen,
                             marketclose = marketclose, tz = tz)
      z <- xts(rep(1, length(intraday)), tzone = tz, 
              order.by = as.POSIXct(paste(dates[d], as.character(intraday), 
                                    sep=" "), tz = tz))
      datad <- merge.xts(z, datad)$datad
      datad <- na.locf(datad)
      rdatad <- makeReturns(datad)
      rdatad <- rdatad[time(rdatad) > min(time(rdatad))]
      rdata <- rbind(rdata, rdatad)
      mR <- rbind(mR, as.numeric(rdatad))
    }
  } else if (class(data) == "matrix") {
    mR <- data
    rdata <- NULL
  } else stop("Input data has to consist of either of the following: 
            1. An xts object containing price data
            2. A matrix containing return data")

  options <- list(...)
  out <- switch(method, 
           detper = detper(mR, rdata = rdata, options = options), 
           stochper = stochper(mR, rdata = rdata, options = options),
           kernel = kernelestim(mR, rdata = rdata, delta, options = options),
           piecewise = piecewise(mR, rdata = rdata, options = options),
           garch = garch_s(mR, rdata = rdata, options = options))  
  return(out)
}

# Deterministic periodicity model
# 
# Modified spotVol function from highfrequency package
detper <- function(mR, rdata = NULL, options = list()) 
{
  # default options, replace if user-specified
  op <- list(dailyvol = "bipower", periodicvol = "TML", dummies = FALSE, 
             P1 = 5, P2 = 5)
  op[names(options)] <- options 
  
  cDays <- nrow(mR)
  M <- ncol(mR)
  if (cDays == 1 & is.null(rdata)) { 
    mR <- as.numeric(mR)
    estimdailyvol <- switch(op$dailyvol, 
                           bipower = rBPCov(mR), 
                           medrv = medRV(mR), 
                           rv = rCov(mR))
  } else {
    if (is.null(rdata)) {
      estimdailyvol <- switch(op$dailyvol, 
                             bipower = apply(mR, 1, "rBPCov"),
                             medrv = apply(mR, 1, "medRV"),
                             rv = apply(mR, 1, "rCov"))
    } else {
      estimdailyvol <- switch(op$dailyvol, 
                              bipower = apply.daily(rdata, rBPCov),
                              medrv = apply.daily(rdata, medRV),
                              rv = apply.daily(rdata, rCov))
      dates = time(estimdailyvol)
    }
  }  
  if (cDays <= 50) {
    print("Periodicity estimation requires at least 50 observations. 
          Periodic component set to unity")
    estimperiodicvol = rep(1, M)
  } else {
    mstdR <- mR/sqrt(as.numeric(estimdailyvol) * (1/M))
    selection <- c(1:M)[ (nrow(mR)-apply(mR,2,'countzeroes')) >=20] 
    # preferably no na is between
    selection <- c( min(selection) : max(selection) )
    mstdR <- mstdR[,selection]
    estimperiodicvol_temp <- diurnal(stddata = mstdR, method = op$periodicvol, 
                                     dummies = op$dummies, P1 = op$P1, 
                                     P2 = op$P2)[[1]]
    estimperiodicvol <- rep(1,M)
    estimperiodicvol[selection] <- estimperiodicvol_temp
    mfilteredR <- mR/matrix(rep(estimperiodicvol, cDays), byrow = T, 
                            nrow = cDays)
    estimdailyvol <- switch(op$dailyvol, 
                            bipower = apply(mfilteredR, 1, "rBPCov"),
                            medrv = apply(mfilteredR, 1, "medRV"), 
                            rv = apply(mfilteredR, 1, "rCov"))
    spot <- rep(sqrt(as.numeric(estimdailyvol) * (1/M)), each = M) * 
              rep(estimperiodicvol, cDays)
    if (is.null(rdata)) {
      spot <- matrix(spot, nrow = cDays, ncol = M, byrow = TRUE)
    } else {
      spot <- xts(spot, order.by = time(rdata))
      estimdailyvol <- xts(estimdailyvol, order.by = dates)
      estimperiodicvol <- xts(estimperiodicvol, order.by = time(rdata[1:M]))
    }
    out <- list(spot = spot, daily = estimdailyvol, periodic = estimperiodicvol)
    class(out) <- "spotvol"
    return(out)
  }
}

# Stochastic periodicity model
# 
# This function estimates the spot volatility by using the stochastic periodcity
# model of Beltratti & Morana (2001)
stochper <- function(mR, rdata = NULL, options = list()) 
{
  #require(FKF)
  # default options, replace if user-specified
  op <- list(init = list(), P1 = 5, P2 = 5, control = list(trace=1, maxit=500))
  op[names(options)] <- options 
  
  N <- ncol(mR)
  days <- nrow(mR)
  mR[mR == 0] <- NA
  logr2 <- log(mR^2)
  rvector <- as.vector(t(logr2)) 
  lambda <- (2*pi)/N;
  
  # default starting values of parameters
  sp <- list(sigma = 0.03,
             sigma_mu = 0.005,
             sigma_h = 0.005,
             sigma_k = 0.05,
             phi = 0.2,
             rho = 0.98,
             mu = c(2, -0.5),
             delta_c = rep(0, max(1,op$P1)),
             delta_s = rep(0, max(1,op$P2)))
  
  # replace if user has specified different values
  sp[names(op$init)] <- op$init
  
  # check input
  for (i in c("sigma", "sigma_mu", "sigma_h", "sigma_k", "phi", "rho")) {
    if (sapply(sp, length)[i] != 1) stop(paste(i, " must be a scalar"))  
  }
  if (length(sp$mu) != 2) 
    stop("mu must have length 2")
  if (length(sp$delta_c) != op$P1 & op$P1 > 0) 
    stop("delta_c must have length equal to P1")
  if (length(sp$delta_s) != op$P2 & op$P2 > 0) 
    stop("delta_s must have length equal to P2")
  if (length(sp$delta_c) < 1) 
    stop("delta_c must at least have length 1")
  if (length(sp$delta_s) < 1) 
    stop("delta_s must at least have length 1")
  
  # transform parameters to allow for unrestricted optimization 
  # (domain -Inf to Inf)
  par_t <- c(sigma = log(sp$sigma), sigma_mu = log(sp$sigma_mu), 
             sigma_h = log(sp$sigma_h), sigma_k = log(sp$sigma_k), 
             phi = log(sp$phi/(1-sp$phi)), rho = log(sp$rho/(1-sp$rho)),
             mu = sp$mu, delta_c = sp$delta_c, delta_s = sp$delta_s) 
  
  opt <- optim(par_t, loglikBM, yt = rvector, N = N, days = days, P1 = op$P1, 
               P2 = op$P2, method="BFGS", control = op$control)
  
  # recreate model to obtain volatility estimates
  ss <- ssmodel(opt$par, days, N, P1 = op$P1, P2 = op$P2)
  kf <- FKF::fkf(a0 = ss$a0, P0 = ss$P0, dt = ss$dt, ct = ss$ct, Tt = ss$Tt, 
                 Zt = ss$Zt, HHt = ss$HHt, GGt = ss$GGt, 
                 yt = matrix(rvector, ncol = length(rvector)))
  sigmahat <- as.vector(exp((ss$Zt%*%kf$at[,1:(N*days)] + ss$ct + 1.27)/2))
  
  # transform parameter estimates back
  estimates <- c(exp(opt$par["sigma"]), exp(opt$par["sigma_mu"]), 
                 exp(opt$par["sigma_h"]), exp(opt$par["sigma_k"]),
                 exp(opt$par["phi"])/(1+exp(opt$par["phi"])), 
                 exp(opt$par["rho"])/(1+exp(opt$par["rho"])), opt$par[-(1:6)])

  if (is.null(rdata)) {
    spot <- matrix(sigmahat, nrow = days, ncol = N, byrow = TRUE)
  } else {
    spot <- xts(sigmahat, order.by = time(rdata))
  }
  out <- list(spot = spot, par = estimates)
  class(out) <- "spotvol"
  return(out)
}

# Calculate log likelihood using Kalman Filter
# 
# This function returns the average log likehood value of the stochastic 
# periodicity model, given the input parameters.
loglikBM <- function(par_t, yt, days, N = 288, P1 = 5, P2 = 5)
{
  ss <- ssmodel(par_t, days, N, P1 = P1, P2 = P2)
  yt <- matrix(yt, ncol = length(yt))
  kf <- FKF::fkf(a0 = ss$a0, P0 = ss$P0, dt = ss$dt, ct = ss$ct, Tt = ss$Tt, 
                 Zt = ss$Zt, HHt = ss$HHt, GGt = ss$GGt, yt = yt)
  return(-kf$logLik/length(yt))
}

# Generate state space model
# 
# This function creates the state space matrices from the input parameters.
# The output is in the format used by the FKF package.
ssmodel <- function(par_t, days, N = 288, P1 = 5, P2 = 5)
{
  par <- c(exp(par_t["sigma"]), exp(par_t["sigma_mu"]), exp(par_t["sigma_h"]), 
           exp(par_t["sigma_k"]), exp(par_t["phi"])/(1+exp(par_t["phi"])), 
           exp(par_t["rho"])/(1+exp(par_t["rho"])), par_t[-(1:6)])
  lambda <- (2*pi)/288
  a0 <- c(0, 0, par["delta_c1"], par["delta_s1"])
  if (P1 == 0) 
    a0[3] <- par["delta_c"]
  if (P2 == 0) 
    a0[4] <- par["delta_s"]   
  m <- length(a0)
  P0 <- Tt <- Ht <- matrix(0, m, m)
  diag(Tt) <- c(1, par["phi"], rep(par["rho"]*cos(lambda), 2))
  Tt[3,4] <- par["rho"]*sin(lambda)
  Tt[4,3] <- par["rho"]*-sin(lambda)
  Zt <- matrix(c(1, 1, 1, 0), ncol = m)
  Gt <- sqrt(0.5*pi^2)
  GGt <- Gt %*% t(Gt)
  diag(Ht) <- c(par["sigma_mu"], par["sigma_h"], rep(par["sigma_k"], 2))
  HHt <- Ht %*% t(Ht)
  dt <- matrix(0, nrow = m)
  ct <- log(par["sigma"]^2) - 1.270363
  
  # calculate deterministic part c2, add to ct
  n <- 1:N
  M1 <- (2*n)/(N+1)
  M2 <- (6*n^2)/((N+1)*(N+2))
  c2 <- par["mu1"]*M1 + par["mu2"]*M2
  if (P1 > 1) {
    for (k in 2:P1) {
      c2 <- c2 + par[paste("delta_c", k, sep="")]*cos(k*lambda*n) 
    }  
  }
  if (P2 > 1) {
    for (p in 2:P2) {
      c2 <- c2 + par[paste("delta_s", p, sep="")]*sin(p*lambda*n)
    }  
  }
  ct <- matrix(ct + c2, ncol = N*days)
  
  return(list(a0 = a0, P0 = P0, Tt = Tt, Zt = Zt, GGt = GGt, HHt = HHt, 
              dt = dt, ct = ct))
}

# Kernel estimation method
# 
# See Kristensen (2010)
kernelestim <- function(mR, rdata = NULL, delta = 300, options = list())
{
  # default options, replace if user-specified
  op <- list(type = "gaussian", h = NULL, est = "cv", lower = NULL, 
             upper = NULL)
  op[names(options)] <- options
  
  D <- nrow(mR)
  N <- ncol(mR)
  if (N < 100 & op$est == "cv") 
    warning("Cross-validation may not return optimal results in small samples.")
  if (op$type == "beta" & op$est == "quarticity" ) {
    warning("No standard estimator available for Beta kernel bandwidth.
                Cross-validation will be used instead.")
    op$est = "cv" 
  }
  t <- (1:N)*delta
  S <- N*delta
  if (is.null(op$h)) { 
    h <- numeric(D) 
  } else {
    h <- rep(op$h, length.out = D)
  }
  sigma2hat <- matrix(NA, nrow = D, ncol = N)
  for(d in 1:D) {
    if (is.null(op$h)) {
      quarticity <- (N/3)*rowSums(mR^4)
      qscale <- quarticity^0.2
      qmult <- qscale/sqrt((1/D)*sum(qscale^2))
      if (op$est == "cv") 
        cat(paste("Estimating optimal bandwidth for day", d, "of", D, "...\n"))
      h[d] <- estbandwidth(mR[d, ], delta = delta, qmult = qmult[d], 
                           type = op$type, est = op$est, lower = op$lower, 
                           upper = op$upper)
    }
    for(n in 1:N) {
      if (op$type == "beta") {
        K <- kernelk(t/S, type = op$type, b = h[d], y = t[n]/S)
      } else {
        K <- kernelk((t-t[n])/h[d], type = op$type)/h[d]
      }
      K <- K/sum(K)
      sigma2hat[d, n] <- K %*% (mR[d, ]^2)
    }
  }
  spot <- as.vector(t(sqrt(sigma2hat)))
  if (is.null(rdata)) {
    spot <- matrix(spot, nrow = D, ncol = N, byrow = TRUE)
  } else {
    spot <- xts(spot, order.by = time(rdata))
  }
  out <- list(spot = spot, par = list(h = h))
  class(out) <- "spotvol"
  return(out)
}

# calculate values of certain kernels
# arguments b and y only needed for type == "beta"
kernelk <- function(x, type = "gaussian", b = 1, y = 1)
{
  if (type == "gaussian") 
    return(dnorm(x))  
  if (type == "epanechnikov") {
    z <- (3/4)*(1-x^2)
    z[abs(x) > 1] <- 0
    return(z)
  }
  if (type == "beta") 
    return(dbeta(x, y/b + 1, (1-y)/b + 1))
}

# estimate optimal bandwidth paramater h
# by default, this is done through crossvalidation (cv)
# else the formula for h_opt in Kristensen(2010) is approximated
estbandwidth <- function(x, delta = 300, qmult = 1, type = "gaussian", 
                         est = "cv", lower = NULL, upper = NULL)
{
  N <- length(x)
  S <- N*delta
  default <- bw.nrd0((1:N)*delta)
  if (type == "epanechnikov") 
    default <- default*2.34
  if (est == "quarticity")  
    h <- default*qmult 
  if (est == "cv") {
    if (type == "beta") {
      if (is.null(lower)) 
        lower <- 0.0001
      if (is.null(upper)) 
        upper <- 1
    } else {
      if (is.null(lower)) 
        lower <- default/3
      if (is.null(upper)) 
        upper <- default*3
    }
    opt <- optimize(ISE, c(lower, upper), x = x, type = type, delta = delta)
    h <- opt$minimum
  }
  return(h)
}

# calculate Integrated Square Error, given bandwidth h
ISE <- function(h, x, delta = 300, type = "gaussian")
{
  N <- length(x)
  t <- (1:N)*delta
  S <- N*delta
  sigma2hat <- rep(NA, N)
  for(n in 1:N) {
    if (type == "beta") {
      K <- kernelk(t/S, type = type, b = h, y = t[n]/S)
    } else {
      K <- kernelk((t - t[n])/h, type = type)/h
    }
    K[n] <- 0
    K <- K/sum(K)
    sigma2hat[n] <- K %*% (x^2) 
  }    
  tl <- 5
  tu <- N-5
  ISE <- sum(((x[tl:tu]^2) - sigma2hat[tl:tu])^2)
  return(ISE)
}

# Piecewise constant volatility method
# See Fried (2012)
piecewise <- function(mR, rdata = NULL, options = list())
{
  # default options, replace if user-specified
  op <- list(type = "MDa", m = 40, n = 20, alpha = 0.005, volest = "bipower",
             online = TRUE)
  op[names(options)] <- options
  
  N <- ncol(mR)
  D <- nrow(mR)
  vR <- as.numeric(t(mR))
  spot <- rep(NA, N*D)
  cp <- changePoints(vR, type = op$type, alpha = op$alpha, m = op$m, n = op$n)  
  for (i in 1:(N*D)) {
    if (op$online) {
      if (i > op$n) {
        lastchange <- max(which(cp + op$n < i))
      } else {
        lastchange = 1
      } 
      lastchange <- cp[lastchange]
      spot[i] = switch(op$volest, 
                       bipower = sqrt((1/(i - lastchange + 1)) * 
                                      (rBPCov(vR[(lastchange + 1):i]))),
                       medrv = sqrt((1/(i - lastchange + 1)) * 
                                   (medRV(vR[(lastchange+1):i]))),
                       rv = sqrt((1/(i - lastchange + 1)) * 
                                (rCov(vR[(lastchange + 1):i]))),
                       sd = sd(vR[(lastchange + 1):i]),
                       tau = robustbase::scaleTau2(vR[(lastchange + 1):i]))
    } else {
      from <- cp[max(which(cp < i))]
      to <- min(c(N*D, cp[which(cp >= i)]))
      len <- to - from
      spot[i] <- switch(op$volest, 
                        bipower = sqrt((1/len)*(rBPCov(vR[from:to]))),
                        medrv = sqrt((1/len)*(medRV(vR[from:to]))),
                        rv = sqrt((1/len)*(rCov(vR[from:to]))),
                        sd = sd(vR[from:to]),
                        tau = robustbase::scaleTau2(vR[from:to]))
    }
  } 
  if (is.null(rdata)) {
    spot <- matrix(spot, nrow = D, ncol = N, byrow = TRUE)
  } else {
    spot <- xts(spot, order.by = time(rdata))
  }
  out <- list(spot = spot, cp = cp)
  class(out) <- "spotvol"
  return(out) 
}

# Detect points on which the volatility level changes
# Input vR should be vector of returns
# Returns vector of indices after which the volatility level in vR changed
changePoints <- function(vR, type = "MDa", alpha = 0.005, m = 40, n = 20)
{
  logR <- log((vR - mean(vR))^2)
  L <- length(logR)
  points <- 0
  np <- length(points)
  N <- n + m
  cat("Detecting change points...\n")
  for (t in 1:L) { 
    if (t - points[np] >= N) {
      reference <- logR[(t - N + 1):(t - n)]
      testperiod <- logR[(t - n + 1):t]  
      if(switch(type,
                MDa = MDtest(reference, testperiod, type = type, alpha = alpha),
                MDb = MDtest(reference, testperiod, type = type, alpha = alpha),
                DM = DMtest(reference, testperiod, alpha = alpha))) {
        points <- c(points, t - n)     
        np <- np + 1
        cat(paste("Change detected at observation", points[np], "...\n"))
      }    
    }
  }
  return(points)
}

# Difference of medians test
# See Fried (2012)
# Returns TRUE if H0 is rejected
DMtest <- function(x, y, alpha = 0.005)
{
  m <- length(x)
  n <- length(y)
  xmed <- median(x)
  ymed <- median(y)
  xcor <- x - xmed
  ycor <- y - ymed
  delta1 <- ymed - xmed
  out <- density(c(xcor, ycor), kernel = "epanechnikov")
  fmed <- as.numeric(BMS::quantile.density(out, probs = 0.5))
  fmedvalue <- (out$y[max(which(out$x < fmed))] + 
                  out$y[max(which(out$x < fmed))+1])/2
  test <- sqrt((m*n)/(m + n))*2*fmedvalue*delta1
  return(abs(test) > qnorm(1-alpha/2))
}

# Median difference test
# See Fried (2012)
# Returns TRUE if H0 is rejected
MDtest <- function(x, y, alpha = 0.005, type = "MDa")
{
  m <- length(x)
  n <- length(y)
  N <- m + n
  lambda <- m/N
  yrep <- rep(y, each = m)
  delta2 <- median(yrep - x)
  if (type == "MDa") {
    z <- rep(0, N)
    z[1:m] <- x
    z[(m+1):N] <- y
    dif <- rep(z, each = length(z))
    dif <- dif - z
    dif[which(dif == 0)] <- NA
  } else if (type == "MDb") {
    difx <- rep(x, each = length(x))
    difx <- difx - x
    dify <- rep(y, each = length(y))
    dify <- dify - y
    dif <- rep(0, length(difx) + length(dify))
    dif[1:length(difx)] <- difx
    dif[(length(difx) + 1):(length(difx) + length(dify))] <- dify
    dif[which(dif == 0)] <- NA
  } else stop(paste("Type", type, "not found."))
  out <- density(dif, na.rm = TRUE, kernel = "epanechnikov")
  g0 <- (out$y[max(which(out$x < 0))] + out$y[max(which(out$x < 0)) + 1])/2
  test <- sqrt(12*lambda*(1 - lambda)*N)*g0*delta2
  return(abs(test) > qnorm(1 - alpha/2))
}

# GARCH with seasonality (external regressors)
garch_s <- function(mR, rdata = NULL, options = list())
{
  # default options, replace if user-specified
  op <- list(model = "eGARCH", order = c(1,1), dist = "norm", P1 = 5, 
             P2 = 5, solver.control = list())
  op[names(options)] <- options
  
  D <- nrow(mR)
  N <- ncol(mR)
  mR <- mR - mean(mR)
  X <- intraday_regressors(D, N = N, order = 2, almond = FALSE, P1 = op$P1,
                           P2 = op$P2)
  spec <- rugarch::ugarchspec(variance.model = list(model = op$model, 
                                                    external.regressors = X,
                                                    garchOrder = op$order),                    
                              mean.model = list(include.mean = FALSE),
                                                distribution.model = op$dist)
  if (is.null(rdata)) {
    cat(paste("Fitting", op$model, "model..."))
    fit <- tryCatch(rugarch::ugarchfit(spec = spec, data = as.numeric(t(mR)), 
                                       solver = "nloptr", 
                                       solver.control = op$solver.control),
                    error = function(e) e,
                    warning = function(w) w)
    if (inherits(fit, what = c("error", "warning"))) {
      stop(paste("GARCH optimization routine did not converge.\n", 
                 "Message returned by ugarchfit:\n", fit))
    }
    spot <- as.numeric(rugarch::sigma(fit))
  } else {
    cat(paste("Fitting", op$model, "model..."))
    fit <- tryCatch(rugarch::ugarchfit(spec = spec, data = rdata, 
                                       solver = "nloptr",
                                       solver.control = op$solver.control), 
                    error = function(e) e,
                    warning = function(w) w)
    if (inherits(fit, what = c("error", "warning"))) {
      stop(paste("GARCH optimization routine did not converge.\n", 
                 "Message returned by ugarchfit:\n", fit))
    } 
    spot <- rugarch::sigma(fit)
  }
  out <- list(spot = spot, ugarchfit = fit)
  class(out) <- "spotvol"
  return(out)
}
    
plot.spotvol <- function(x, ...)
{
  options <- list(...)
  plottable <- c("spot", "periodic", "daily")
  elements <- names(x)
  nplots <- sum(is.element(plottable, elements))
  
  if (nplots == 3) {
    par(mar = c(3, 3, 3, 1))
    layout(matrix(c(1,2,1,3), nrow = 2))
  }
  spot <- as.numeric(t(x$spot))
  
  if(is.element("length", names(options))) {
    length = options$length
  } else {
    length = length(spot)
  }
  
  plot(spot[1:length], type = "l", xlab = "", ylab = "")
  title(main = "Spot volatility")
  if ("cp" %in% elements)
    abline(v = x$cp[-1], lty = 3, col = "gray70")
  if ("periodic" %in% elements) {
    periodic <- as.numeric(t(x$periodic))
    if (inherits(data, what = "xts")) {
      intraday <- time(x$periodic)
      plot(x = intraday, y = periodic, type = "l", xlab = "", ylab = "")
    } else {
      plot(periodic, type = "l", xlab = "", ylab = "") 
    }
    title(main = "Intraday periodicity")
  }
  if ("daily" %in% elements) {
    daily <- as.numeric(t(x$daily))
    if (inherits(data, what = "xts")) {
      dates <- as.Date(time(x$daily))
      plot(x = dates, y = daily, type = "l", xlab = "", ylab = "")
    } else {
      plot(daily, type = "l", xlab = "", ylab = "")
    }
    title(main = "Daily volatility")
  } 
}

intraday_regressors <- function(D, N = 288, order = 1, almond = TRUE, 
                                dummies = FALSE, P1 = 5, P2 = 5)
{  
  if (order == 1) {
    vi <- rep(c(1:N), each = D)
  } else {
    vi <- rep(c(1:N), D)
  }
  X <- c()
  if (!dummies) {
    if (P1 > 0) {
      for (j in 1:P1) {
        X <- cbind(X, cos(2 * pi * j * vi/N))
      }
    }
    M1 <- (N + 1)/2
    M2 <- (2 * N^2 + 3 * N + 1)/6
    ADD <- (vi/M1)
    X <- cbind(X, ADD)
    ADD <- (vi^2/M2)
    X <- cbind(X, ADD)
    if (P2 > 0) {
      ADD <- c()
      for (j in 1:P2) {
        ADD <- cbind(ADD, sin(2 * pi * j * vi/N))
      }
    }
    X <- cbind(X, ADD)
    if (almond) {
      opening <- vi - 0
      stdopening <- (vi - 0)/80
      almond1_opening <- (1 - (stdopening)^3)
      almond2_opening <- (1 - (stdopening)^2) * (opening)
      almond3_opening <- (1 - (stdopening)) * (opening^2)
      X <- cbind(X, almond1_opening, almond2_opening, almond3_opening)
      closing <- max(vi) - vi
      stdclosing <- (max(vi) - vi)/max(vi)
      almond1_closing <- (1 - (stdclosing)^3)
      almond2_closing <- (1 - (stdclosing)^2) * (closing)
      almond3_closing <- (1 - (stdclosing)) * (closing^2)
      X <- cbind(X, almond1_closing, almond2_closing, almond3_closing)
    }
  } else {
    for (d in 1:N) {
      dummy <- rep(0, N)
      dummy[d] <- 1
      dummy <- rep(dummy, each = D)
      X <- cbind(X, dummy)
    }
  }
  return(X)
}

### auxiliary internal functions copied from highfrequency package

countzeroes = function( series )
{
  return( sum( 1*(series==0) ) )
}

HRweight = function( d,k){
  # Hard rejection weight function
  w = 1*(d<=k); return(w)
}

shorthscale = function( data )
{
  sorteddata = sort(data);
  n = length(data);
  h = floor(n/2)+1;
  M = matrix( rep(0,2*(n-h+1) ) , nrow= 2 );
  for( i in 1:(n-h+1) ){
    M[,i] = c( sorteddata[ i ], sorteddata[ i+h-1 ] )
  }
  return( 0.7413*min( M[2,]-M[1,] ) );
}

diurnal = 
  function (stddata, method = "TML", dummies = F, P1 = 6, P2 = 4) 
  {
    cDays = dim(stddata)[1]
    intraT = dim(stddata)[2]
    meannozero = function(series) {
      return(mean(series[series != 0]))
    }
    shorthscalenozero = function(series) {
      return(shorthscale(series[series != 0]))
    }
    WSDnozero = function(weights, series) {
      out = sum((weights * series^2)[series != 0])/sum(weights[series != 
                                                                 0])
      return(sqrt(1.081 * out))
    }
    if (method == "SD" | method == "OLS") {
      seas = sqrt(apply(stddata^2, 2, "meannozero"))
    }
    if (method == "WSD" | method == "TML") {
      seas = apply(stddata, 2, "shorthscalenozero")
      shorthseas = seas/sqrt(mean(seas^2))
      shorthseas[shorthseas == 0] = 1
      weights = matrix(HRweight(as.vector(t(stddata^2)/rep(shorthseas, 
                                                           cDays)^2), qchisq(0.99, df = 1)), ncol = dim(stddata)[2], 
                       byrow = T)
      for (c in 1:intraT) {
        seas[c] = WSDnozero(weights[, c], stddata[, c])
      }
    }
    seas = na.locf(seas,na.rm=F) #do not remove leading NA
    seas = na.locf(seas,fromLast=T)
    seas = seas/sqrt(mean(seas^2))
    if (method == "OLS" | method == "TML") {
      c = center()
      vstddata = as.vector(stddata)
      nobs = length(vstddata)
      vi = rep(c(1:intraT), each = cDays)
      if (method == "TML") {
        if( length(vstddata)!= length(seas)*cDays ){ print(length(vstddata)); print(length(seas)); print(cDays)}
        firststepresids = log(abs(vstddata)) - c - log(rep(seas, 
                                                           each = cDays))
      }
      X = intraday_regressors(cDays, N = intraT, dummies = dummies, P1 = P1, P2 = P2)
      selection = c(1:nobs)[vstddata != 0]
      vstddata = vstddata[selection]
      X = X[selection, ]
      if (method == "TML") {
        firststepresids = firststepresids[selection]
      }
      vy = matrix(log(abs(vstddata)), ncol = 1) - c
      if (method == "OLS") {
        Z = try(solve(t(X) %*% X), silent = T)
        if (inherits(Z, "try-error")) {
          print("X'X is not invertible. Switch to TML")
        }
        else {
          theta = solve(t(X) %*% X) %*% t(X) %*% vy
          rm(X)
          rm(vy)
        }
      }
      if (method == "TML") {
        inittheta = rep(0, dim(X)[2])
        l = -2.272
        u = 1.6675
        nonoutliers = c(1:length(vy))[(firststepresids > 
                                         l) & (firststepresids < u)]
        truncvy = vy[nonoutliers]
        rm(vy)
        truncX = X[nonoutliers, ]
        rm(X)
        negtruncLLH = function(theta) {
          res = truncvy - truncX %*% matrix(theta, ncol = 1)
          return(mean(-res - c + exp(2 * (res + c))/2))
        }
        grnegtruncLLH = function(theta) {
          res = truncvy - truncX %*% matrix(theta, ncol = 1)
          dres = -truncX
          return(apply(-dres + as.vector(exp(2 * (res + 
                                                    c))) * dres, 2, "mean"))
        }
        est = optim(par = inittheta, fn = negtruncLLH, gr = grnegtruncLLH, 
                    method = "BFGS")
        theta = est$par
        rm(truncX)
        rm(truncvy)
      }
# disable plot for now      
#       plot(seas, main = "Non-parametric and parametric periodicity estimates", 
#            xlab = "intraday period", type = "l", lty = 3)
#       legend("topright", c("Parametric", "Non-parametric"), cex = 1.1,
#              lty = c(1,3), lwd = 1, bty = "n")
        seas = diurnalfit(theta = theta, P1 = P1, P2 = P2, intraT = intraT, 
                                         dummies = dummies)
#       lines(seas, lty = 1)
      return(list(seas, theta))
    }
    else {
      return(list(seas))
    }
  }

diurnalfit = function( theta , P1 , P2 , intraT , dummies=F )
{
  vi = c(1:intraT) ;  
  M1 = (intraT+1)/2 ; M2 = (2*intraT^2 + 3*intraT + 1)/6;
  
  # Regressors that do not depend on Day of Week:
  X = c()
  if(!dummies){
    if ( P1 > 0 ){ for( j in 1:P1 ){ X = cbind( X , cos(2*pi*j*vi/intraT) )   }  } 
    
    ADD = (vi/M1 ) ; X = cbind(X,ADD);
    ADD = (vi^2/M2); X = cbind(X,ADD);
    if ( P2 > 0 ){ ADD= c(); for( j in 1:P2 ){  ADD = cbind( ADD , sin(2*pi*j*vi/intraT)  ) }}; X = cbind( X , ADD ) ; 
    
    #openingeffect
    opening = vi-0 ; stdopening = (vi-0)/80 ;
    almond1_opening   = ( 1 - (stdopening)^3 );
    almond2_opening   = ( 1 - (stdopening)^2 )*( opening);
    almond3_opening   = ( 1 - (stdopening)   )*( opening^2);   
    X = cbind(  X, almond1_opening , almond2_opening , almond3_opening   )  ;
    
    #closing effect
    closing = max(vi)-vi ; stdclosing = (max(vi)-vi)/max(vi) ;
    almond1_closing   = ( 1 - (stdclosing)^3 );
    almond2_closing   = ( 1 - (stdclosing)^2 )*( closing);
    almond3_closing   = ( 1 - (stdclosing)   )*( closing^2);   
    X = cbind(  X, almond1_closing , almond2_closing , almond3_closing   )  ;
    
  }else{
    for( d in 1:intraT){
      dummy = rep(0,intraT); dummy[d]=1; 
      X = cbind(X,dummy); 
    }
  }
  # Compute fit
  seas = exp( X%*%matrix(theta,ncol=1) );
  seas = seas/sqrt(mean( seas^2) )    
  return( seas )          
}

center = function()
{
  g=function(y){ return( sqrt(2/pi)*exp(y-exp(2*y)/2)  )}
  f=function(y){ return( y*g(y)    )  }
  return( integrate(f,-Inf,Inf)$value )
}

# modified version of 'aggregatePrice' from highfrequency package
aggregatePrice = function (ts, FUN = "previoustick", on = "minutes", k = 1, marketopen = "09:30:00", marketclose = "16:00:00", tz = "GMT") 
{
  ts2 = aggregatets(ts, FUN = FUN, on, k)
  date = strsplit(as.character(index(ts)), " ")[[1]][1]
  
  #open
  a = as.POSIXct(paste(date, marketopen), tz = tz)
  b = as.xts(matrix(as.numeric(ts[1]),nrow=1), a)
  ts3 = c(b, ts2)
  
  #close
  aa = as.POSIXct(paste(date, marketclose), tz = tz)
  condition = index(ts3) < aa
  ts3 = ts3[condition]
  bb = as.xts(matrix(as.numeric(last(ts)),nrow=1), aa)
  ts3 = c(ts3, bb)
  
  return(ts3)
}
