#' Effect size combination meta analysis.
#'
#' Performs effect-size meta-analyses across all studies and seperately for
#' each tissue source.
#'
#'
#' Builds on \code{\link[GeneMeta]{zScores}} function from GeneMeta by allowing for genes
#' that were not measured in all studies. This implementation also uses moderated unbiased
#' effect sizes calculated by \code{\link[metaMA]{effectsize}} from metaMA and determines
#' false discovery rates using \code{\link[fdrtool]{fdrtool}}.
#'
#' @param diff_exprs Previous result of \code{\link{diff_expr}}, which can
#'    be reloaded using \code{\link{load_diff}}.
#' @param cutoff Minimum fraction of contrasts that must have measured each gene.
#'    Between 0 and 1.
#' @param by_source Should seperate meta-analyses be performed for each tissue
#'    source added with \code{\link{add_sources}}?
#'
#' @return A list of named lists, one for each tissue source. Each list contains
#'    two named data.frames. The first, \code{filt}, has all the columns below for genes
#'    present in cutoff or more fraction of contrasts. The second, \code{raw}, has only
#'    \code{dprime} and \code{vardprime} columns, but for all genes (NAs for genes
#'    not measured by a given contrast).
#'    \item{dprime}{Unbiased effect sizes (one column per contrast).}
#'    \item{vardprime}{Variances of unbiased effect sizes (one column per contrast).}
#'    \item{mu}{Overall mean effect sizes.}
#'    \item{var}{Variances of overall mean effect sizes.}
#'    \item{z}{Overall z score = \code{mu / sqrt(var)}.}
#'    \item{fdr}{False discovery rates calculated by \code{fdrtool}.}
#'
#' @export
#'
#' @examples
#'
#' library(lydata)
#'
#' # location of data
#' data_dir <- system.file("extdata", package = "lydata")
#'
#' # gather GSE names
#' gse_names  <- c("GSE9601", "GSE15069", "GSE50841", "GSE34817", "GSE29689")
#'
#' # load previous analysis
#' anals <- load_diff(gse_names, data_dir)
#'
#' # add tissue sources to perform seperate meta-analyses for each source (optional)
#' # anals <- add_sources(anals, data_dir)
#'
#' # perform meta-analysis
#' es <- es_meta(anals, by_source = TRUE)

es_meta <- function(diff_exprs, cutoff = 0.3, by_source = FALSE) {


    # used for analysis per diff_exprs
    es_meta_src <- function(diff_exprs, cutoff) {

        # get dp and vardp
        es <- get_es(diff_exprs, cutoff)

        # if just one contrast, use its values
        if (ncol(es$filt) == 2) {
            es$filt$mu  <- es$filt[[1]]
            es$filt$var <- es$filt[[2]]
            es$filt$fdr <- diff_exprs[[1]]$top_tables[[1]]$adj.P.Val

            return(es)
        }

        df <- es$filt

        dp  <- df[, seq(1, ncol(df), 2)]
        var <- df[, seq(2, ncol(df), 2)]

        # get Cochran Q statistic
        Q <- f.Q(dp, var)

        # get tau (between study variance)
        tau <- tau2.DL(Q,
                       num.studies = apply(var, 1, function(x) sum(!is.na(x))),
                       my.weights  = 1 / var)

        # add tau to vardp then calculate mean effect sizes and variance
        var <- var + tau
        df$mu  <- mu.tau2(dp, var)
        df$var <- var.tau2(var)

        # get z-score and fdr
        df$z   <- df$mu/sqrt(df$var)
        df$fdr <- fdrtool::fdrtool(df$z, plot = FALSE, verbose = FALSE)$qval

        es$filt <- df[order(df$fdr), ]

        return(es)
    }


    if (by_source) {
        # check for sources
        null_sources <- sapply(diff_exprs, function(anal) is.null(anal$sources))

        if (any(null_sources)) {
            message("Sources missing from diff_exprs (to add, use add_sources).\nContinuing with by_source = FALSE.")
            es <- list(all = es_meta_src(diff_exprs, cutoff))

        } else {
            anals_src <- list(all = diff_exprs)
            anals_src <- c(anals_src, setup_src(diff_exprs, "top_tables"))

            es <- lapply(anals_src, es_meta_src, cutoff)
        }


    } else {
        es <- list(all = es_meta_src(diff_exprs, cutoff))
    }

    return(es)
}


# used by es_meta and path_meta to group top/padog tables by source
setup_src <- function(anals, ttype = c("top_tables", "padog_tables")) {

    anals_srcs <- list()

    # contrast sources
    con_src <- unlist(sapply(unname(anals), `[[`, 'sources'))

    # get added pairs
    added_prs <- lapply(anals, function(anal) anal$pairs)
    added_prs <- unique(unlist(added_prs, recursive = FALSE, use.names = FALSE))

    # get non-pair sources
    is_prs <- con_src %in% unlist(added_prs)
    added_src <- sapply(unique(con_src[!is_prs]), list, USE.NAMES = FALSE)


    # get anals by source
    for (src in c(added_prs, added_src)) {

        src_name <- paste(src, collapse = ', ')

        anals_srcs[[src_name]] <- lapply(anals, function(anal) {
            is_src <- con_src[names(anal[[ttype]])] %in% src

            if (any(is_src)) {
                anal[[ttype]] <- anal[[ttype]][is_src]
                anal
            }
            else NULL
        })
    }

    # remove NULL entries
    anals_srcs <- lapply(anals_srcs, function(anals_src) anals_src[!sapply(anals_src, is.null)])

    return(anals_srcs)
}



# ---------------------


# Get dprimes and vardprimes values for each contrast.
#
# @inheritParams es_meta
# @return data.frame with dprime and vardprime values.

get_es <- function(diff_exprs, cutoff = 0.3) {

    # add dprimes and vardprimes to top tables
    diff_exprs <- add_es(diff_exprs)

    # get top tables
    es <- lapply(diff_exprs, function(study) study$top_tables)
    nm <- unlist(lapply(es, names))
    nm <- paste(c('dprime', 'vardprime'), rep(nm, each=2), sep='.')
    es <- unlist(es, recursive = FALSE, use.names = FALSE)

    # get desired top table columns
    es <- lapply(es, function(top) {
        top$SYMBOL <- row.names(top)
        top[, c("SYMBOL", "dprime", "vardprime")]
    })

    # merge dataframes
    es <- merge_dataframes(es)
    names(es) <- nm


    # only keep genes where more than cutoff fraction of studies have data
    filt <- apply(es, 1, function(x) sum(!is.na(x))) >= (ncol(es) * cutoff)

    return(list(filt = es[filt, ], raw = es))
}


# ---------------------


# Add metaMA effectsize values to top tables.
#
# Used internally by \code{setup_combo_data} and \code{\link[crossmeta]{es_meta}}
# to add moderated unbiased standardised effect sizes (dprimes) to top tables
# from differential expression analysis.
#
# @param diff_exprs Result from call to \code{\link[crossmeta]{diff_expr}}.
# @param cols Columns from \code{\link[metaMA]{effectsize}} result to add to
#    top tables.
#
# @export
# @seealso \link[crossmeta]{diff_expr}, \link[crossmeta]{es_meta}.
#
# @return diff_exprs with specified columns added to top_tables for each contrast.
#
# @examples
# library(crossmeta)
# library(lydata)
#
# # location of raw data
# data_dir <- system.file("extdata", package = "lydata")
#
# # load previous analysis for eset
# anal <- load_diff("GSE9601", data_dir)
#
# # add dprime and vardprime to top tables
# anal <- add_es(anal)

add_es <- function(diff_exprs, cols = c("dprime", "vardprime")) {

    for (i in seq_along(diff_exprs)) {

        # get study degrees of freedom and group classes
        study <- diff_exprs[[i]]

        df <- study$ebayes_sv$df.residual + study$ebayes_sv$df.prior
        classes <- study$pdata$group

        for (con in names(study$top_tables)) {
            # get group names for contrast
            groups <- gsub("GSE.+?_", "", con)
            groups <- strsplit(groups, "-")[[1]]

            # get sample sizes for groups
            ni <- sum(classes == groups[2])
            nj <- sum(classes == groups[1])

            # bind effect size values with top table
            tt <- study$top_tables[[con]]
            es <- metaMA::effectsize(tt$t, ((ni * nj)/(ni + nj)), df)[, cols, drop = FALSE]
            tt <- cbind(tt, es)

            # store results
            study$top_tables[[con]] <- tt
        }
        diff_exprs[[i]] <- study
    }
    return(diff_exprs)
}


# ---------------------


# Merge a list of data.frames.
#
# @param ls List of data.frames.
# @param key Column to merge data.frames on.
#
# @return A merged data.frame with \code{key} set to row names.


merge_dataframes <- function(ls, keys = "SYMBOL") {

    # ensure non 'by' names are not duplicated
    ls = Map(function(x, i)
        stats::setNames(x, ifelse(names(x) %in% keys,
                                  names(x),
                                  sprintf('%s.%d', names(x), i))),
        ls, seq_along(ls))

    # merge list
    res <- Reduce(function(...) merge(..., by = keys, all = TRUE), ls)

    # format result
    row.names(res) <- res[, keys[1]]
    res[, keys[1]] <- NULL
    return(res)
}

# ---------------------

# Modifed f.Q from GeneMeta (allows NAs)
#
# Compute Cochran's Q statistic. Allows genes that were not measured in all
# studies.
#
# @param dadj Dataframe of unbiased effect sizes (dprimes) for each contrast.
# @param varadj Dataframe of variances for unbiased effect sizes (vardprimes)
#    for each contrast.
#
# @return A vector of length equal to the number of rows of dadj with the Q
#    statistics.

f.Q <- function (dadj, varadj) {
    w <- 1/varadj
    tmp1 <- w * dadj
    mu <- rowSums(tmp1, na.rm = TRUE)/rowSums(w, na.rm = TRUE)
    Q <- rowSums(w * (dadj - mu)^2, na.rm = TRUE)
}

# ---------------------

# Modifed tau2.DL from GeneMeta (allows NAs)

# tau2.DL is an estimation of tau in a random effects model (REM) using
# Cochran's Q statistic. Allows genes that were not measured in all studies.
#
# @param Q A vector of Cochran's Q statistics.
# @param num.studies A vector specifying the number of experiments in which each
#    gene was measured.
# @param my.weights A matrix with one column for each experiment containing the
#    variances of the effects that should be combined.
#
# @return A vector of tau values.

tau2.DL <- function (Q, num.studies, my.weights) {
    tmp1 <- rowSums(my.weights, na.rm = TRUE)
    tmp2 <- rowSums(my.weights^2, na.rm = TRUE)
    value <- cbind((Q - (num.studies - 1))/(tmp1 - (tmp2/tmp1)), 0)
    apply(value, 1, max)
}

# ---------------------

# Modifed mu.tau2 from GeneMeta (allows NAs)
#
# Estimate overall mean effect sizes. Allows genes that were not measured in all
# studies.
#
# @param my.d A matrix, with one column for each experiment, containing the
#    effects that should be combined.
# @param my.vars.new A matrix, with one column for each experiment, containing
#    the variances of the effects that should be combined.
#
# @return A vector with the estimates of the overall mean effect sizes.

mu.tau2 <- function (my.d, my.vars.new) {
    w <- 1/my.vars.new
    tmp1 <- w * my.d
    mu <- rowSums(tmp1, na.rm = TRUE)/rowSums(w, na.rm = TRUE)
}

# ---------------------

# Modifed var.tau2 from GeneMeta (allows NAs)
#
# Estimate variances of overall mean effect sizes. Allows genes that were not
# measured in all studies.
#
# @inheritParams mu.tau2
#
# @return

var.tau2 <- function (my.vars.new) {
    w <- 1/my.vars.new
    my.var <- 1/rowSums(w, na.rm = TRUE)
}


# ---------------------


#' Contribute results of meta-analysis to public database.
#'
#' Contributed results will be used to build a freely searchable database of
#' gene expression meta-analyses.
#'
#' Performs meta-analysis on \code{diff_exprs} using \code{es_meta}. Sends
#' overall mean effect size values and minimal information needed to reproduce
#' meta-analysis.
#'
#'
#' @param diff_exprs Result of call to \code{diff_expr}.
#' @param subject String identifying meta-analysis subject (e.g. "rapamycin" or
#'    "prostate_cancer").
#'
#' @export
#'
#' @return NULL (used to contribute meta-analysis).
#'
#' @examples
#' library(lydata)
#'
#' # location of data
#' data_dir <- system.file("extdata", package = "lydata")
#'
#' # gather GSE names
#' gse_names  <- c("GSE9601", "GSE15069", "GSE50841", "GSE34817", "GSE29689")
#'
#' # load differential expression analyses
#' anals <- load_diff(gse_names, data_dir)
#'
#' # contribute results of meta-analysis
#' # contribute(anals, subject = "LY294002")

contribute <- function(diff_exprs, subject) {

    # get pdata
    pcols <- c("treatment", "group", "pairs")
    pdata <- lapply(diff_exprs, function(x) x$pdata[, pcols])

    # get sources and pairs
    sources <- lapply(diff_exprs, `[[`, 'sources')
    pairs   <- lapply(diff_exprs, `[[`, 'pairs')

    # get contrasts
    cons  <- lapply(diff_exprs, function(x) colnames(x$ebayes_sv$contrasts))

    # get effect size values
    es <- es_meta(diff_exprs, by_source = TRUE)
    mu <- lapply(es, function(es_src) {
        src_mu <- es_src$filt[, 'mu']
        names(src_mu) <- row.names(es_src$filt)
        src_mu
    })

    # put it all together
    meta_info <- list(pdata = pdata, contrasts = cons, sources = sources, pairs = pairs, effectsize = mu)

    # upload to dropbox
    tstamp    <- format(Sys.time(), "%Y%m%d_%H%M%S_")
    save_name <- paste0(tstamp, subject, ".rds")

    saveRDS(meta_info, save_name)
    rdrop2::drop_upload(dtoken = token, save_name)
    message("Thank you for your contribution!")
    file.remove(save_name)

    # prevent printing on return
    save_name <- NULL
}
