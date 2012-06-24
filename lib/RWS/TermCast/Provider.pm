package	RWS::TermCast::Provider ;

use	strict ;
use	warnings ;

use	base qw(POE::Session::Attribute) ;
use	Log::Agent ;
use	RWS::TermCast::Auth ;
use	RWS::TermCast::Catalog ;
use	POE qw(Session Wheel::ReadWrite Filter::Stream) ;

sub	_start : Object {
        my ($self, $sock) = @_[OBJECT, ARG0] ;
	logdbg(4, '_start (%s)', $self) ;
	$self->{wheel} = new POE::Wheel::ReadWrite(
	    Handle => $sock,
	    InputEvent => 'input_auth',
	    ErrorEvent => 'failure',
	    Filter => POE::Filter::Stream->new()
	) ;
	$self->{hello} = '' ;
	$self->{consumers} = [] ;
}

sub	input_auth : Object {
    	my ($self, $poe, $sess, $data) = @_[OBJECT, KERNEL, SESSION, ARG0] ;
	logdbg(8, 'hello data') ;
	if ($data =~ s/^(.*)\r?\n\r?//) {
	    my $hello = delete $self->{hello} ;
	    $hello .= $1 ;
	    if ($hello !~ /^hello\s+([\S]+)\s+([\w-]+)/) {
		$self->{wheel}->put("protocol mismatch\n") ;
		delete $self->{wheel} ;
		return undef ;
	    }
	    if (!RWS::TermCast::Auth->validate($1, $2)) {
		$self->{wheel}->put("auth failure\n") ;
		delete $self->{wheel} ;
		return undef ;
	    }
	    $self->{stream} = "\e[2J" ;
	    $self->{init1} = '' ;
	    $self->{init2} = '' ;
	    $self->{user} = $1 ;
	    $self->{connected_ts} = time ;
	    $self->{wheel}->event(InputEvent => 'input') ;
	    $self->{wheel}->put("hello, $1\n") ;
	    RWS::TermCast::Catalog->register('stream' => $sess->ID => $1) ;
	    $poe->call($sess, 'input', $data) if $data ;
	} else {
	    $self->{hello} .= $data ;
	}
}

sub	input : Object {
    	my ($self, $poe, $sess, $data) = @_[OBJECT, KERNEL, SESSION, ARG0] ;
	$poe->post($_, service_data => $data) for @{$self->{consumers}} ;

    my $combined_data = $self->{stream} . $data;
    if ($combined_data =~ /.*\e\]2;(.*?)\007/s) {
      $self->{title} = $1;
      $self->{title_seq} = "\e]2;$self->{title}\007";
      RWS::TermCast::Catalog->update_title(
	    stream => $sess->ID, $self->{title}) ;
    }
	if ($data =~ s/(.*)(\e\[2J)/$2/) {
	    my $s = $self->{stream} . $1 ;
	    my $p ;
	    if (($p = rindex($s, "\e)")) != -1 && $p + 3 <= length($s)) {
		$self->{init1} = substr($s, $p, 3) ;
	    }
#	    if (($p = rindex($s, "\e(")) != -1 && $p + 3 <= length($s)) {
#		$self->{init2} = substr($s, $p, 3) ;
#	    }
	    $self->{stream} = ($self->{title_seq} || '') . $data ;
	} else {
	    $self->{stream} .= $data ;
	}

	# this is gonna hurt (rev3: told ya)
#	$self->{stream} = substr($self->{stream}, 2e4)
	substr($self->{stream}, 2e4, 7e4) = ''
	    if length($self->{stream}) > 1e5 ;

	RWS::TermCast::Catalog->update(
	    stream => $sess->ID, length($self->{stream})) ;
}

sub	register : Object {
        my ($self, $poe, $sess, $sender) = @_[OBJECT, KERNEL, SESSION, SENDER] ;
	$self->{wheel}->put("msg watcher connected\n") ;
	push @{$self->{consumers}}, $sender->ID ;
	$poe->post($sender->ID, service_data =>
	    ($self->{init1} . $self->{init2} . $self->{stream})) ;
}

sub	unregister : Object {
        my ($self, $poe, $sess, $sender) = @_[OBJECT, KERNEL, SESSION, SENDER] ;
	$self->{wheel}->put("msg watcher disconnected\n") ;
	$poe->post($sender, 'service_end') ;
	 $self->{consumers} =
	     [ grep { $_ ne $sender->ID } @{$self->{consumers}} ] ;
}

sub	failure : Object {
    	my	($self, $sess, $poe, $call, $code, $line) =
	    @_[OBJECT, SESSION, KERNEL, ARG0 .. ARG2] ;
	if ($call eq "read" && $code == 0) {
	    logdbg(1, "eof") ;
	} else {
	    logwarn("($self) $call(): $code/$line") ;
	}
	RWS::TermCast::Catalog->unregister('stream' => $sess->ID) ;
	$poe->post($_, 'service_end') for @{$self->{consumers}} ;
	$self->{wheel} = undef ;
}

sub	DESTROY { logdbg(6, '%s DESTROY', shift) }

1 ;
