% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/data.R
\docType{data}
\name{sampleTData}
\alias{sampleTData}
\title{Sample of cleaned trades for stock XXX for 1 day}
\format{
A large \code{xts} object.
}
\usage{
sampleTData
}
\description{
An xts object containing the trades for the imaginary stock XXX for 1 day, in the typical NYSE TAQ database format.
This is the cleaned version of the data sample \code{\link{sampleTDataRaw}}, using \code{tradesCleanup} and \code{tradesCleanupUsingQuotes}.
}
\examples{
\dontrun{
#The code to create sampleTData from raw data is 
tradesAfterFirstCleaning <- tradesCleanup(tDataRaw = sampleTDataRaw, 
                                          exchanges = "N", report = FALSE)
                                          
cleanedQuotes <- quotesCleanup(qDataRaw = sampleQDataRaw, exchanges = "N", 
                               type = "standard", report = FALSE)
sampleTData <- tradesCleanupUsingQuotes(tData = tradesAfterFirstCleaning,
                                        qData = cleanedQuotes, lagQuotes = 2)
sampleTData <- sampleTData[,c("SYMBOL", "EX",  "PRICE", "SIZE", "COND", "CORR", "G127")]
# These are the historically included columns.
}

}
\keyword{datasets}
