% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/explore_path.R
\name{explore_paths}
\alias{explore_paths}
\title{Explore pathway meta analyses.}
\usage{
explore_paths(es_res, path_res, drug_info = NULL, type = c("both", "mimic",
  "reverse"))
}
\arguments{
\item{es_res}{Result of call to \code{\link{es_meta}}.}

\item{path_res}{Result of call to \code{\link{path_meta}}.}

\item{drug_info}{Matrix of differential expression values for drugs (rows are genes, columns are drugs).
If NULL (default), \code{\link[ccdata]{cmap_es}} is used.}

\item{type}{Desired direction of drug action on query signature (see details).}
}
\value{
None
}
\description{
Shiny app for interactively exploring the results of effect-size and pathway meta-analyses.
The app also interfaces with the ccmap package in order to explore drugs that are predicted
to reverse or mimic your signature.
}
\details{
For a given tissue source (top left dropdown box) and KEGG pathway (bottom left dropdown box, ordered
by increasing false discovery rate), effect-sizes (y-axis) are plotted for each gene in the pathway
(x-axis, ordered by decreasing asbsolute effect size).

For each gene, open circles give the effect-sizes for each contrast. The transparency of the open
circles is proportional to the standard deviation of the effect-size for each contrast.
For each gene, error bars give one standard deviation above and below the the overall meta-analysis
effect-size.

The top drugs for the full signature in a given tissue (top right dropdown box, red points) and
just the pathway genes (bottom right dropdown box, blue points) are orderered by decreasing
(if \code{type} is 'both' or 'mimic') or increasing (if \code{type} is 'reverse') similarity.
Positive and negative cosine similarities correspond to drugs that, respectively, mimic and
reverse the query signature.

Drug effect sizes can be made visible by either clicking the legend entries (top left of plot) or
selecting a new drug in the dropdown boxes.

When a new tissue source or pathway is selected, the top drug and pathway dropdown boxes
are approriately updated.
}
\examples{
library(lydata)
library(ccdata)

data_dir  <- system.file("extdata", package = "lydata")
gse_names  <- c("GSE9601", "GSE15069", "GSE50841", "GSE34817", "GSE29689")

# load result of previous call to diff_expr:
es_anals <- load_diff(gse_names, data_dir)

# run shiny GUI to add tissue sources
# es_anals <- add_sources(es_anals, data_dir)

# perform effect-size meta-analyses for each tissue source
es_res <- es_meta(es_anals, by_source = TRUE)

# load result of previous call to diff_path:
# path_anals <- load_path(gse_names, data_dir)

# perform pathway meta-analyses for each tissue source
# path_res <- path_meta(path_anals, ncores = 1, nperm = 100, by_source = TRUE)

# explore pathway meta-analyses
# explore_paths(es_res, path_res)

}
