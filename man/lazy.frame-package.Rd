\name{lazy.frame-package}
\alias{lazy.frame-package}
\title{File Frames: A lazy person's file-backed data frame.}
\description{
A lazy.frame is a data frame promise. It presents a delimited text file
as a kind of simple data frame, but without initially loading the file into memory.
Lazy frames load data from their backing files on demand, and are
useful for quickly and efficiently extracting subsets from large csv and other
text files.  They support normal and gzip-compressed files.
}
