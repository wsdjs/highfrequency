% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data.R
\docType{data}
\name{sampleQData}
\alias{sampleQData}
\title{Sample of cleaned quotes for stock XXX for 1 day}
\format{
xts object
}
\usage{
sampleQData
}
\description{
An xts object containing the raw quotes for the imaginary stock XXX for 1 day, in the typical NYSE TAQ database format. 
This is the cleaned version of the data sample \code{\link{sampleQDataRaw}}, using \code{quotesCleanup}.
}
\examples{
\dontrun{
#The code to create sampleQData from raw data is 
sampleQData <- quotesCleanup(
qDataRaw = sampleQDataRaw, exchanges = "N", type = "standard", 
report = FALSE)[, c("SYMBOL", "BID", "BIDSIZ", "OFR", "OFRSIZ", "MODE")]
# These are the historically included columns.
}

}
\keyword{datasets}
