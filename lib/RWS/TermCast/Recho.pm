package	RWS::TermCast::Recho ;

# a session module PoC, testing only

use	strict ;
use	warnings ;

use	base qw(POE::Session::Attribute) ;
use	Log::Agent ;
use	POE qw(Session Wheel::ReadWrite Filter::Line) ;

sub	_start : Object {
        my ($self, $sock) = @_[OBJECT, ARG0] ;
	logdbg(4, '_start (%s)', $self) ;
	$self->{wheel} = new POE::Wheel::ReadWrite(
	    Handle => $sock,
	    InputEvent => 'input',
	    ErrorEvent => 'failure',
	    Filter => POE::Filter::Line->new(Literal => "\n")
	) ;
	$self->{wheel}->put("hello, $self!\n") ;
}

sub	input : Object {
    	my ($self, $line) = @_[OBJECT, ARG0] ;
	logdbg(6, '>> %s $%s', $self, $line) ;
	$line = reverse($line) ;
	$self->{wheel}->put($line) ;
}

sub	failure : Object {
    	my	($self, $call, $code, $line) = @_[OBJECT, ARG0 .. ARG2] ;
	if ($call eq "read" && $code == 0) {
	    logdbg(1, "eof") ;
	} else {
	    logwarn("($self) $call(): $code/$line") ;
	}
	$self->{wheel} = undef ;
}

sub	DESTROY { logdbg(6, '%s DESTROY', shift) }

1 ;
