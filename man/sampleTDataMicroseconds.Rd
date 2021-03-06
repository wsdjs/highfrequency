% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data.R
\docType{data}
\name{sampleTDataMicroseconds}
\alias{sampleTDataMicroseconds}
\title{Sample of cleaned trades for stock XXX for 2 days}
\format{
A data.table object.
}
\usage{
sampleTDataMicroseconds
}
\description{
An data.table object containing the trades for the imaginary stock XXX for 2 days, in the typical NYSE TAQ database format.
This is the cleaned version of the data sample \code{\link{sampleTDataRawMicroseconds}}, using \code{tradesCleanup}.
}
\examples{
\dontrun{
# The code to create the sampleTDataMicroseconds dataset from raw data is
sampleQDataMicroseconds <- quotesCleanup(qDataRaw = sampleQDataRawMicroseconds,
                                         exchanges = "N", type = "standard", report = FALSE)

tradesAfterFirstCleaning <- tradesCleanup(tDataRaw = sampleTDataRawMicroseconds, 
                                          exchanges = "N", report = FALSE)

sampleTDataMicroseconds <- tradesCleanupUsingQuotes(
  tData = tradesAfterFirstCleaning,
  qData = sampleQDataMicroseconds,
  lagQuotes = 0)[, c("DT", "SYMBOL", "PRICE", "SIZE")]
# Only some columns are included. These are the ones that were historically included.
}

}
\keyword{datasets}
