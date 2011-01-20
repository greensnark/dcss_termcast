package	RWS::TermCast::Telnet ;

# i can't believe it. srsly.

use	strict ;
use	warnings ;

use	constant		TN_IAC => chr(255) ;
use	constant		TNC_DONT => chr(254) ;
use	constant		TNC_DO => chr(253) ;
use	constant		TNC_WONT => chr(252) ;
use	constant		TNC_WILL => chr(251) ;
use	constant		TNC_SB => chr(250) ;
use	constant		TNC_SE => chr(240) ;
# 

sub	new {
    my $pkg = shift ;
    my $self = bless {
	l_opts => {},
	r_opts => {},
	buff => ''
    }, $pkg ;
    return $self ;
}

my	%_yes = (
    TNC_DO, TNC_WILL,
    TNC_DONT, TNC_WONT,
    TNC_WILL, TNC_DO,
    TNC_WONT, TNC_DONT
) ;

my	%_no = (
    TNC_DO, TNC_WONT,
    TNC_DONT, TNC_WILL,
    TNC_WILL, TNC_DONT,
    TNC_WONT, TNC_DO
) ;

sub	filter_out {
    my ($self, $data) = @_ ;
    $data =~ s/\xff/\xff\xff/g ;
    return $data ;
}

sub	process_input {
    my ($self, $data) = @_ ;
    my $d = $self->{buff} . $data ;
    my $ready = '' ;
    my $reply = '' ;
    my $p ;

    while (($p = index($d, TN_IAC)) != -1) {
	$ready .= substr($d, 0, $p) ;
	substr($d, 0, $p) = '' ;
	if (length($d) == 1) {
	    $self->{buff} = $d ;
	    $d = '' ;
	    last ;
	}
	my $cmd = substr($d, 1, 1) ;
	if ($cmd eq TN_IAC) {
	    substr($d, 0, 2) = '' ;
	    $ready .= TN_IAC ;
	} elsif (grep { $_ eq $cmd } (TNC_DO, TNC_DONT, TNC_WILL, TNC_WONT)) {
	    if (length($d) < 3) {
		$self->{buff} = $d ;
		$d = '' ;
		last ;
	    }
	    my $opt = substr($d, 2, 1) ;
	    substr($d, 0, 3) = '' ;
	    if ($cmd eq TNC_DO || $cmd eq TNC_DONT) {
		if (($self->{l_opts}->{$opt} || TNC_DONT) ne $cmd) {
		    if ($self->remote_do($opt, $cmd)) {
			$self->{l_opts}->{$opt} = $cmd ;
			$reply .= TN_IAC . $_yes{$cmd} . $opt ;
		    } else {
			$reply .= TN_IAC . $_no{$cmd} . $opt ;
		    }
		}
	    } elsif ($cmd eq TNC_WILL || $cmd eq TNC_WONT) {
		if (($self->{r_opts}->{$opt} || TNC_WONT) ne $cmd) {
		    if ($self->remote_will($opt, $cmd)) {
			$self->{r_opts}->{$opt} = $cmd ;
			$reply .= TN_IAC . $_yes{$cmd} . $opt ;
		    } else {
			$reply .= TN_IAC . $_no{$cmd} . $opt ;
		    }
		}
	    }
	} elsif ($cmd eq TNC_SB) {
	    if (($p = index($d, TNC_SE)) != -1) {
		substr($d, 0, $p + 1) = '' ;
	    } else {
		$self->{buff} = $d ;
		$d = '' ;
		last ;
	    }
	} else {
	    substr($d, 0, 2) = '' ;
	}
    }
    $ready .= $d ;
    return ($ready, $reply) ;
}

sub	set_opt {
    my ($self, %a) = @_ ;
    my $send = '' ;

    while (my ($opt, $cmd) = each(%a)) {
	my $ycmd = $_yes{$cmd} ;
	if ($ycmd eq TNC_DONT || $ycmd eq TNC_DO) {
	    if (($self->{l_opts}->{$opt} || TNC_WONT) ne $ycmd) {
		$self->{l_opts}->{$opt} = $ycmd ;
		$send .= TN_IAC . $cmd . $opt ;
	    }
	} elsif ($cmd eq TNC_WONT || $cmd eq TNC_WILL) {
	    if (($self->{r_opts}->{$opt} || TNC_DONT) ne $ycmd) {
		$self->{r_opts}->{$opt} = $ycmd ;
		$send .= TN_IAC . $cmd . $opt ;
	    }
	} else {
	    die 'say what?' ;
	}
    }
    return $send ;
}

sub	remote_do {
    return undef
}
sub	remote_will {
    return undef
}

1 ;

