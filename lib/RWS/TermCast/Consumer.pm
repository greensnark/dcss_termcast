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
    "\e(B\e)0\e[?1048h\e[?1047h\e[1;24r\e[m\x0f\e[4l\e[?7h\e[?1h\e=\e[H";
use constant    SCR_CLR => "\e[2J";
use	constant	SCR_CLOSE =>
    "\e[24;1H\e[?1047l\e[?1048l\n\e[?1l\e[?25h\e>" ;
use	constant	SCR_LINE => "\e[%dd%s\e[K\r\n" ;

my $TERMCAST_BANNER_FILE = 'termcast-banner.txt' ;
my $TICK = 2;

sub	_start : Object {
        my ($self, $sess, $sock, $poe) = @_[OBJECT, SESSION, ARG0, KERNEL] ;
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

    $poe->delay(tick => $TICK);
}

sub	serial_time {
	my $s = strftime(" %Yy %mm %dd %T", gmtime(shift));
	$s =~ s/(\d\d\d\d)y/($1 - 1970) . 'y'/e ;
	$s =~ s/(\d+)([md])/($1 - 1) . $2/eg ;
	$s =~ s/\s+0+[ymd]//g ;
	$s =~ s/^\s+// ;
	return $s ;
}

sub banner_lines {
  my $text = shift;
  split(/\n/, $text)
}

sub     banner {
  my $self = shift;

  my $sessions = $self->sessions_text;
  my $watchers = $self->watchers_text;
  my $suffix = <<BANNER_SUFFIX;

$sessions, $watchers connected

During playback, hit 'q' to return here.
BANNER_SUFFIX

  my @suffix = banner_lines($suffix);
  if (-r $TERMCAST_BANNER_FILE) {
    my @text = do { local (@ARGV, $/) = $TERMCAST_BANNER_FILE; <> };
    return (@text, @suffix)
  }
  else {
    my $banner_text = <<BANNER;
## Crawl TermCast
## Service homepage: http://crawl.develz.org/
## TermCast homepage: http://termcast.org/
BANNER
    return (banner_lines($banner_text), @suffix)
  }
}

sub     sessions_text {
  my $self = shift;
  my $s_cnt = RWS::TermCast::Catalog->count('stream') ;
  $s_cnt . ' active session' . ($s_cnt == 1 ? '' : 's');
}

sub     watchers_text {
  my $self = shift;
  my $w_cnt = RWS::TermCast::Catalog->count('watch') ;
  $w_cnt . ' viewer'         . ($w_cnt == 1 ? '' : 's');
}

sub nocolor_length {
  my $text = shift;
  $text =~ s/\e\[.*?m//g;
  length($text)
}

sub bolded_text {
  my $text = shift;
  "\e[1m$text\e[0m"
}

sub dim_text {
  my $text = shift;
  "\e[1;30m$text\e[0m"
}

sub dim_if_idle {
  my ($text, $idle) = @_;
  $idle ? dim_text($text) : $text
}

sub title_text {
  my $text = shift;
  "\e[0;33m$text\e[0m"
}

sub channel_name {
  my ($c, $idle) = @_;
  $idle ? $$c{desc} : bolded_text($$c{desc})
}

sub display_channel_desc {
  my ($key, $channel, $now) = @_;

  my $idle = channel_is_idle($channel, $now);
  my $base =
    join(" ",
         grep($_,
              "$key)",
              channel_name($channel, $idle),
              dim_if_idle(channel_status($channel, $now), $idle)));
  my $title = channel_title($channel);

  my $space = 80 - (nocolor_length($base) + 2);
  return $base if $space < 10;

  $title = substr($title, 0, $space) if length($title) > $space;
  return $base unless $title;

  "$base: " . ($idle ? dim_text($title) : title_text($title))
}

sub channel_viewers {
  my $c = shift;
  my $viewers = $c->{consumers};
  $viewers && "v:$viewers"
}

sub channel_title {
  my $c = shift;
  $c->{title}
}

sub channel_is_idle {
  my ($c, $now) = @_;
  my $idle = $now - $c->{last_ts};
  $idle > 10
}

sub channel_idle_flag {
  my ($c, $now) = @_;
  channel_is_idle($c, $now) && 'idle'
}

sub channel_status {
  my ($c, $now) = @_;
  my $status = join(", ",
                    grep($_,
                         channel_viewers($c),
                         channel_idle_flag($c, $now)));
  $status && "(" . $status . ")"
}

sub	display_menu {
    my ($self, $incremental_draw) = @_ ;
	my $l = 2 ;
	my @lines = $self->banner();

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
          my $desc = display_channel_desc($key, $_, $now);
		push @lines, $desc;
		$self->{choices}->{$key} = $_->{sid} ;
		$key ++ ;
	    }
	} else {
	    push @lines, 'This service looks deserted...' ;
	}
	push @lines, '' ;

    my $txt;
    if ($incremental_draw) {
      $txt = SCR_OPEN;
    } else {
      $txt = SCR_CLOSE . SCR_OPEN . SCR_CLR ;
    }

	$txt .= sprintf(SCR_LINE, $_ + 2, $lines[$_]) for 0 .. $#lines ;
	$txt .=
 "Watch which session? (any key refreshes, 'q' quits, '>'/'<' for next/prev) => \e[s\e[J\e[u" ;
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

sub tick : Object {
  my ($self, $poe, $sess) = @_[OBJECT, KERNEL, SESSION];
  return if $self->{dead} || !$self->{wheel};
  if ($self->{mode} eq 'menu') {
    $self->display_menu('incremental');
  }
  $poe->delay(tick => $TICK);
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
    $self->{dead} = 1;
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
    $self->{dead} = 1;
	delete $self->{wheel} ;
}

sub	_stop : Object {
    	my ($self, $sess, $poe) = @_[OBJECT, SESSION, KERNEL] ;
    $self->{dead} = 1;
	RWS::TermCast::Catalog->unregister(watch => $sess->ID) ;
}

sub	DESTROY { logdbg(6, '%s DESTROY', shift) }

1 ;
