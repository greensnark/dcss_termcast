package	RWS::TermCast::Inetd ;

use	strict ;
use	warnings ;

use	base qw(POE::Session::Attribute) ;

use	POE qw(Kernel Session Wheel::SocketFactory) ;
use	Log::Agent ;
use	Socket ;

sub	_start : Object {
    	my ($self, $poe, $cfg) = @_[OBJECT, KERNEL, ARG0] ;

	if (my $a = $cfg->{alias}) {
	    $poe->alias_set($a) ;
	}

	my (@sock_url) = split(/:/, $cfg->{socket} || die 'no socket??') ;
	my %sf_opts = (
	    SuccessEvent => 'accepted',
	    FailureEvent => 'failure',
	    SocketType => SOCK_STREAM
	) ;

	if ($sock_url[0] eq 'file') {
	    unlink $sock_url[1] if -e $sock_url[1] ;
	    $sf_opts{BindAddress} = $sock_url[1] ;
	    $sf_opts{SocketDomain} = AF_UNIX ;
	} elsif ($sock_url[0] eq 'tcp') {
	    $sf_opts{BindPort} = $sock_url[-1] ;
	    $sf_opts{BindAddress} = (@sock_url > 2) ? $sock_url[1] : '0.0.0.0' ;
	    $sf_opts{Reuse} = 1 ;
	    $sf_opts{SocketDomain} = AF_INET ;
	    $sf_opts{SocketProtocol} = 'tcp' ;
	    $sf_opts{ListenQueue} = SOMAXCONN ;
	}
	$self->{wheel} = POE::Wheel::SocketFactory->new(%sf_opts) ;
	logdbg(1, 'accepting %s connections on %s',
	    ($cfg->{alias} || 'unknown'), $cfg->{socket}) ;
	$self->{session_pkg} = $cfg->{session_pkg} || die 'no session_pkg??' ;
}

sub	accepted : Object {
    	my	($self, $sock) = @_[OBJECT, ARG0] ;
        setsockopt($sock ,SOL_SOCKET, SO_KEEPALIVE, 1)
            or logwarn("setsockopt: $!") ;
	logdbg(1, 'accepted (%s), spawning %s', $sock, $self->{session_pkg}) ;
	$self->{session_pkg}->spawn($sock) ;
}

sub	failure : Object {
    	my	($self, $call, $code, $msg) = @_[OBJECT, ARG0 .. ARG2] ;
	logwarn("call(): $code / $msg") ;
}

1 ;

