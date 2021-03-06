% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/realized_measures.R
\name{knChooseReMeDI}
\alias{knChooseReMeDI}
\title{ReMeDI tuning parameter
function to choose the tuning parameter, kn in ReMeDI estimation}
\usage{
knChooseReMeDI(
  pData,
  knEqual = FALSE,
  knMax = 10,
  tol = 0.05,
  size = 3,
  lower = 2,
  upper = 5,
  plot = FALSE
)
}
\arguments{
\item{pData}{xts or data.table containing the log-prices of the asset.}

\item{knEqual}{Use an altered version of the ReMeDI estimator, where we instead use equal kn, instead of kn and 2*kn for the windows. See Figure 1 of paper in reference section.}

\item{knMax}{max value of kn to be considered}

\item{tol}{tolerance for the minimizing value. If tol is high, the algorithm will choose a lower optimal value.}

\item{size}{size of the local window}

\item{lower}{lower boundary for the method if it fails to find an optimal value. If this is the case, the best kn between lower and upper is returned}

\item{upper}{upper boundary for the method if it fails to find an optimal value. If this is the case, the best kn between lower and upper is returned}

\item{plot}{logical whether to plot the errors.}
}
\value{
integer containing the optimal kn
}
\description{
ReMeDI tuning parameter
function to choose the tuning parameter, kn in ReMeDI estimation
}
\details{
This is the algorithm B.2 in the appendix of the Li and Linton (2019) working paper
}
\examples{
optimalKn <- knChooseReMeDI(sampleTDataMicroseconds[as.Date(DT) == "2018-01-02",],
                            knMax = 10, tol = 0.05, size = 3,
                            lower = 2, upper = 5, plot = TRUE)
optimalKn
\dontrun{
# We can also have a much larger search-space
optimalKn <- knChooseReMeDI(sampleTDataMicroseconds[, as.Date(DT) == "2018-01-02"],
                            knMax = 50, tol = 0.05,
                            size = 3, lower = 2, upper = 5, plot = TRUE)
optimalKn
}

}
\references{
A ReMeDI for Microstructure Noise
}
\author{
Emil Sjoerup
}
