% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/realized_measures.R
\name{rSkew}
\alias{rSkew}
\title{Realized skewness of highfrequency return series.}
\usage{
rSkew(rData, alignBy = NULL, alignPeriod = NULL, makeReturns = FALSE)
}
\arguments{
\item{rData}{a zoo/xts object containing all returns in period t for one asset.}

\item{alignBy}{a string, align the tick data to "seconds"|"minutes"|"hours".}

\item{alignPeriod}{an integer, align the tick data to this many [seconds|minutes|hours].}

\item{makeReturns}{boolean, should be TRUE when rData contains prices instead of returns. FALSE by   default.}
}
\value{
numeric
}
\description{
Function returns Realized skewness, defined in Amaya et al. (2011).

Assume there is \eqn{N} equispaced returns in period \eqn{t}. Let \eqn{r_{t,i}} be a return (with \eqn{i=1, \ldots,N}) in period \eqn{t}.

Then, the rSkew is given by
  \deqn{
    \mbox{rSkew}_{t}= \frac{\sqrt{N} \sum_{i=1}^{N}(r_{t,i})^3}{RV_{t}^{3/2}} 
  }
  
in which
\eqn{RV_{t}:} realized variance
}
\examples{
data(sampleTData)
rSkew(sampleTData$PRICE,alignBy ="minutes", alignPeriod =5, makeReturns = TRUE)

}
\references{
Amaya, D., Christoffersen, P., Jacobs, K. and Vasquez, A. (2011). Do realized skewness and kurtosis predict the cross-section of equity returns?. CREATES research paper. p. 3-7.
}
\author{
Giang Nguyen, Jonathan Cornelissen and Kris Boudt
}
\keyword{highfrequency}
\keyword{rSkew}
