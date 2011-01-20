package	RWS::TermCast::Auth ;

# XXX: just a stub

use	strict ;
use	warnings ;

my	$u = {} ;

sub	validate {
    	my ($pkg, $user, $pswd) = @_ ;
	$u->{$user} ||= $pswd ;
	return $u->{$user} eq $pswd ;
}

1 ;

