package	RWS::TermCast::Consumer ;

use	strict ;
use	warnings ;

use	base qw(POE::Session::Attribute) ;
use	Log::Agent ;
use	RWS::TermCast::Catalog ;
use	RWS::TermCast::Telnet ;
use	POE qw(Session Wheel::ReadWrite Filter::Stream) ;
use	POSIX qw(strftime) ;

use	constant	SCR_OPEN =>
    "\e(B\e)0\e[?1048h\e[?1047h\e[1;24r\e[m\x0f\e[4l\e[?7h\e[?1h\e=\e[H\e[2J" ;
use	constant	SCR_CLOSE =>
    "\e[24;1H\e[?1047l\e[?1048l\n\e[?1l\e[?25h\e>" ;
use	constant	SCR_LINE => "\e[%dd%s\r\n" ;

sub	_start : Object {
        my ($self, $sess, $sock) = @_[OBJECT, SESSION, ARG0] ;
	logdbg(4, '_start (%s)', $self) ;
	$self->{wheel} = new POE::Wheel::ReadWrite(
	    Handle => $sock,
	    InputEvent => 'tn_input',
	    ErrorEvent => 'failure',
	    Filter => POE::Filter::Stream->new()
	) ;
	$self->{tn} = RWS::TermCast::Telnet->new() ;
	my $data = $self->{tn}->set_opt(
	    chr(1) => chr(251),
	    chr(3) => chr(251)
	) ;
	$self->{wheel}->put($data) if $data ;
	$self->{mode} = 'menu' ;
	$self->{choices} = {} ;
	$self->{page} = 0 ;
	RWS::TermCast::Catalog->register(watch => $sess->ID, $sess->ID) ;
	$self->display_menu() ;
}

sub	serial_time {
	my $s = strftime(" %Yy %mm %dd %T", gmtime(shift));
	$s =~ s/(\d\d\d\d)y/($1 - 1970) . 'y'/e ;
	$s =~ s/(\d+)([md])/($1 - 1) . $2/eg ;
	$s =~ s/\s+0+[ymd]//g ;
	$s =~ s/^\s+// ;
	return $s ;
}

sub	display_menu {
    	my $self = shift ;
	my $l = 2 ;
	my $s_cnt = RWS::TermCast::Catalog->count('stream') ;
	my $w_cnt = RWS::TermCast::Catalog->count('watch') ;
        my $sessions = $s_cnt . ' active session' . ($s_cnt == 1 ? '' : 's');
        my $watchers = $w_cnt . ' viewer'         . ($w_cnt == 1 ? '' : 's');
	my @lines = (
'## TermCast - public terminal session reflector',
'## Service homepage is at http://noway.ratry.ru/jsn/termcast/',
"## $sessions, $watchers connected",
"During playback, hit 'q' to return here.",
'',
        ) ;

	my @choices = RWS::TermCast::Catalog->list('stream') ;
	if (@choices) {
	    my $now = time() ;
	    my $p = $self->{page} || 0 ;
	    my $maxp = int((@choices - 1) / 14) ;
	    $p = $maxp if $p * 14 > @choices ;
	    $p = 0 if $p < 0 ;
	    $self->{page} = $p if $self->{page} > $p ;
	    push @lines,
		sprintf(
		    'The following sessions are in progress (page %d of %d):',
		    $p + 1, $maxp + 1) ;
	    @choices = @choices[$p * 14 .. ($p + 1) * 14] ;
	    my $key = "a" ;
	    $self->{choices} = {} ;
	    for (grep { $_ } @choices) {
		push @lines,
		    " $key) $_->{desc} (idle "
		    . serial_time($now - $_->{last_ts})
		    . ", connected "
		    . serial_time($now - $_->{first_ts})
		    . ", "
		    . $_->{consumers}
		    . " viewer" . ($_->{consumers} == 1 ? "" : "s")
		    . ", $_->{len} bytes"
		    . ")" ;
		$self->{choices}->{$key} = $_->{sid} ;
		$key ++ ;
	    }
	} else {
	    push @lines, 'This service looks deserted...' ;
	}
	push @lines, '' ;

	my $txt = SCR_CLOSE . SCR_OPEN ;
	$txt .= sprintf(SCR_LINE, $_ + 2, $lines[$_]) for 0 .. $#lines ;
	$txt .=
 "Watch which session? (any key refreshes, 'q' quits, '>'/'<' for next/prev) => " ;
	$self->output($txt) ;
}

sub	tn_input : Object {
    	my ($self, $poe, $data) = @_[OBJECT, KERNEL, ARG0] ;
	my ($d, $reply) = $self->{tn}->process_input($data) ;
	$self->{wheel}->put($reply) if $reply ;
	$poe->yield(input => $d) if $d ;
}

sub	output {
    	my ($self, $data) = @_ ;
	$self->{wheel}->put($self->{tn}->filter_out($data)) if $self->{wheel} ;
}

sub	input : Object {
    	my ($self, $poe, $sess, $data) = @_[OBJECT, KERNEL, SESSION, ARG0] ;
	if ($self->{mode} eq 'menu') {
	    if ($data eq '>') {
		$self->{page} ++ ;
		$self->display_menu() ;
	    } elsif ($data eq '<') {
		$self->{page} -- if $self->{page} ;
		$self->display_menu() ;
	    } elsif ($data eq 'q') {
		$self->output(SCR_CLOSE) ;
                $self->{wheel}->event(FlushedEvent => 'flushed') if $self->{wheel}
	    } elsif (my $sid = $self->{choices}->{$data}) {
		$self->{mode} = 'watch' ;
		RWS::TermCast::Catalog->consumer_count(stream => $sid, 1) ;
		$poe->post($sid => 'register') ;
		$self->{service_sid} = $sid ;
		$self->output(SCR_CLOSE . SCR_OPEN) ;
	    } else {
		$self->display_menu() ;
	    }
	} elsif ($self->{mode} eq 'watch') {
	    if ($data eq 'q') {
		$self->{mode} = 'menu' ;
		$self->{page} = 0 ;
		$poe->post($self->{service_sid} => 'unregister') ;
		RWS::TermCast::Catalog->consumer_count(
		    stream => $self->{service_sid}, -1) ;
		$self->{service_sid} = undef ;
		$self->display_menu() ;
	    }
	}
}

sub     flushed : Object {
    my ($self) = $_[OBJECT] ;
    delete $self->{wheel} ;
}

sub	service_data : Object {
    	my ($self, $data) = @_[OBJECT, ARG0] ;
	$self->output($data) ;
}

sub	service_end : Object {
        my ($self, $poe) = @_[OBJECT, KERNEL] ;
	if ($self->{mode} eq 'watch') {
	    $self->{mode} = 'menu' ;
	    $self->{page} = 0 ;
	    $self->{service_sid} = undef ;
	    $self->display_menu() ;
	}
}

sub	failure : Object {
    	my ($self, $poe, $call, $code, $line) =
	    @_[OBJECT, KERNEL, ARG0 .. ARG2] ;
	if ($call eq "read" && $code == 0) {
	    logdbg(1, "eof") ;
	} else {
	    logwarn("($self) $call(): $code/$line") ;
	}
	if ($self->{mode} eq 'watch') {
	    RWS::TermCast::Catalog->consumer_count(
		stream => $self->{service_sid}, -1) ;
	    $poe->post($self->{service_sid} => 'unregister') ;
	    $self->{service_sid} = undef ;
	}
	delete $self->{wheel} ;
}

sub	_stop : Object {
    	my ($self, $sess, $poe) = @_[OBJECT, SESSION, KERNEL] ;
	RWS::TermCast::Catalog->unregister(watch => $sess->ID) ;
}

sub	DESTROY { logdbg(6, '%s DESTROY', shift) }

1 ;
