#! /usr/bin/perl

use	FindBin ;
use lib "$FindBin::Bin/../lib" ;

use	strict ;
use	warnings ;

use	RWS::TermCast ;

RWS::TermCast->run(@ARGV) ;
