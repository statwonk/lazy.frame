.onLoad = function(libname,pkgname)
{
  options(lazy.frame.threads=2L)
  options(lazy.frame.tempdir=tempdir)
}
.onUnload = function(libpath)
{
  options(lazy.frame.threads=c())
  options(lazy.frame.tempdir=c())
}

`.lazy.frame_finalizer` = function(x)
{
  invisible(.Call("FREE",x, PACKAGE="lazy.frame"))
}

`column_attr` = function(x, col, which)
{
  if(!is.numeric(col)) stop("col must be numeric")
  if(!is.character(which)) stop("which must be characer")
  id = as.character(col)
  if(!exists(id,envir=x)) stop("invalid column index")
  x[[id]][[which]]
}

`column_attr<-` = function(x,col,which,value)
{
  if(!is.numeric(col)) stop("col must be numeric")
  if(!is.character(which)) stop("which must be characer")
  id = as.character(col)
  if(!exists(id,envir=x)) stop("invalid column index")
  assign(which, value, envir=x[[id]])
  x$attrs = TRUE
  x
}

`lazy.frame` = function(file, sep=",", gz=FALSE,
                        skip=0L, stringsAsFactors=FALSE, header=FALSE, ...)
{
   if(missing(file)) stop("'file' must be specified")
   if("lazy.frame" %in% class(file))
   {
     file$data = .Call("REOPEN", file$data, as.integer(gz), PACKAGE="lazy.frame")
     return(file)
   }
   obj = new.env()
   obj$data=.Call("OPEN",
                  as.character(file),
                  as.integer(gz),
                  PACKAGE="lazy.frame")
   reg.finalizer(obj$data, .lazy.frame_finalizer, TRUE)
   obj$call = match.call()
   obj$row.names = 0
   if(!is.null(obj$call$row.names)){
     obj$row.names = obj$call$row.names
     if(!is.numeric(obj$row.names) || length(obj$row.names)>1)
     stop("lazy frames only support row names from a single column in the file")
   }
   obj$sep = sep
   obj$args = list(...)
   obj$which = NULL
   obj$header = header
   obj$skip = skip
   obj$stringsAsFactors = stringsAsFactors
   obj$internalskip = as.integer(skip + header)
   obj$attrs = FALSE
   nl = .Call("NUMLINES",obj$data, PACKAGE="lazy.frame")
   n = min(nl,5)
   f = tempfile()
   b = .Call("RANGE",obj$data,1L,as.integer(n),f, PACKAGE="lazy.frame")
   tmp = .getframe(obj,f,header=header,skip=skip)
   if(any(class(tmp)=="error")) {
     rm(obj)
     stop(tmp)
   }
   if(nrow(tmp)<n){
     obj$header = TRUE
     obj$internalskip = as.integer(skip + header)
   }
   nc = ncol(tmp)
   obj$dim = c(nl-obj$internalskip,nc)
   for(j in 1:nc )
     obj[[as.character(j)]] = new.env()
   obj$dimnames = list(NULL, colnames(tmp))
   class(obj) = "lazy.frame"
   obj
}

`.getframe` = function(x,f,header=FALSE,skip=0L)
{
  tmp = tryCatch(
    do.call("read.table",
      args=c(
        list(file=f,
             sep=x$sep,
             skip=skip,
             header=header,
             stringsAsFactors=x$stringsAsFactors),
        x$args)),
      error=function(e) e)
# DEBUG # system2("cat",args=f)
  unlink(f)
  if(!(any(class(tmp)=="error"))) {
    if(ncol(tmp)==length(names(x)))
      names(tmp) = names(x)
  }
  tmp
}

`names.lazy.frame` = function(x)
{
  dimnames(x)[[2]]
}

`summary.lazy.frame` = function(x)
{
  warning("Not yet supported")
  invisible()
}

`[<-.lazy.frame` = function(x, j, k, ..., value)
{
  stop("File frames are read-only.")
}

`[.lazy.frame` = function(x, j, k, ...)
{
  f = match.call()
  drop=ifelse(is.null(f$drop),TRUE,f$drop)
# This abuse of array subsetting is used for the fast
# single-column 'which' function in comparison operations.
  if(missing(j)) {
    if(missing(k)) stop("Really?")
    if(length(k)>1)
      stop("Selection of all rows is limited to single column")
    if(is.character(k)) k = match(k,names(x))
    if(!is.numeric(k)) stop("Invalid column index")
    x$which = as.integer(k)
    return(x)
  }
  if(missing(k))
    k = 1:(x$dim[2])
  if(is.character(k)) k = match(k,names(x))
  if(!is.numeric(k)) stop("Invalid column index")
  if(any(k<1) || any(j<1)) stop("Non-positive indices not supported")
  badk = which(k>(x$dim[2]))
  if(length(badk)>0) k = k[-badk]
  d = dim(x)
  x$which = NULL
# A too-expensive check for sequential indices?
  tmp = c()
  if(sum(diff(j)-1)==0) {
    n  = as.integer(min(j) + x$internalskip)
    m  = as.integer(max(j) + x$internalskip - n + 1)
    w = tempfile(tmpdir=options("lazy.frame.tempdir")[[1]]())
    b = .Call("RANGE",x$data,n,m,w, PACKAGE="lazy.frame")
    tmp = .getframe(x,w)
  } else {
    j = j + x$internalskip
    badj = which(j>nrow(x))
    if(length(badj)>0) j = j[-badj]
    w = tempfile(tmpdir=options("lazy.frame.tempdir")[[1]]())
    b = .Call("LINES",x$data,as.integer(j),w, PACKAGE="lazy.frame")
    tmp = .getframe(x,w)
  }
  if(any(class(tmp)=="error")) stop(tmp)
  if(x$attrs){
# some column attributes have been set, apply them:
    for(l in k){
      id = as.character(l)
      a = ls(x[[id]])
      if(length(a)>0) {
        for(b in a) {
          attr(tmp[,l],b) <- x[[id]][[b]]
        }
      }
    }
  }
  tmp[,k,drop=drop]
}

Ops.lazy.frame = function(e1,e2) {
  col = e1$which
  e1$which = NULL
  NP = tryCatch(
         as.integer(options("lazy.frame.threads")),
         error=function(e) 2L)
  if(is.null(NP) || is.na(NP) || length(NP)<1) NP = 2L
  OP <- switch(.Generic,"=="=1L,
                         "!="=2L,
                         ">="=3L,
                         "<="=4L,
                         ">"= 5L,
                         "<"= 6L)
  if(!inherits(e1,"lazy.frame")) stop("Left-hand side must be lazy.frame object")
  if(is.null(col)) stop("Can only compare a single column")
  w = .Call("WHICH",e1$data,
                as.integer(col),
                as.integer(e1$row.names),
                as.integer(e1$internalskip),
                as.character(e1$sep),
                OP, e2, NP, PACKAGE="lazy.frame")
  w[w>0]
}

`dim.lazy.frame` = function(x)
{
  x$dim
}

`dim<-.lazy.frame` = function(x, value)
{
  x$dim <- value
  x
}

`dimnames.lazy.frame` = function(x)
{
  x$dimnames
}

`dimnames<-.lazy.frame` = function(x, value)
{
  x$dimnames = value
  x
}

`names<-.lazy.frame` = function(x,value)
{
  x$dimnames[[2]] = make.names(value[1:(x$dim[2])])
  x
}

`head.lazy.frame` = function(x, n=6L, ...)
{
  if(is.null(x$which)) return(x[1:min(nrow(x),n),])
  cat("Note: If you really want this whole column as a vector, supply the row indices too.\n")
  x[1:min(nrow(x),n),x$which,drop=FALSE]
}

`tail.lazy.frame` = function(x, n=6L, ...)
{
  x[max((nrow(x)-n),1):nrow(x),]
}

`str.lazy.frame` = function(object, ...)
{
  cat("Str summary of the file.object internals:\n")
  print(ls.str(object))
  cat("\nStr summary of the data head:\n")
  str(object[1:min(nrow(object),6),,drop=FALSE])
  cat("The complete data set consists of",object$dim[[1]],"rows.\n")
}

`print.lazy.frame` = function(x, ...)
{
  cat("\nLazy person's file-backed data frame for",x$call$file,"\n\n")
  print(head(x))
  j = x$dim[1]-6
  if(j>2) cat("and (",j,"more rows not displayed...)\n")
}

`ncol.lazy.frame` = function(x) x$dim[2]
`nrow.lazy.frame` = function(x) x$dim[1]
`dim.lazy.frame` = function(x) x$dim
