package	RWS::TermCast::Catalog ;

use	strict ;
use	warnings ;

my	$srv = {} ;

sub	register {
    	my ($pkg, $service, $id, $desc) = @_ ;
	my $now = time() ;
	($srv->{$service} ||= {})->{$id} = {
	    sid => $id,
	    desc => $desc,
	    last_ts => $now,
	    first_ts => $now,
	    len => 0,
      	    consumers => 0
	} ;
}

sub	update {
    	my ($pkg, $service, $id, $len) = @_ ;
	if (my $t = $srv->{$service}{$id}) {
	    $t->{last_ts} = time ;
	    $t->{len} = $len ;
	}
}

sub	unregister {
    	my ($pkg, $service, $id) = @_ ;
	if (my $s = $srv->{$service}) {
	    delete $s->{$id} ;
	}
}

sub	consumer_count {
    	my ($pkg, $service, $id, $delta) = @_ ;
	if (my $s = $srv->{$service}) {
	    if (my $c = $s->{$id}) {
		return ($c->{consumers} += ($delta || 0)) ;
	    }
	}
	return 0 ;
}

sub	count {
    	my ($pkg, $service) = @_ ;
	return int(keys %{$srv->{$service}}) ;
}

sub	list {
    	my ($pkg, $service) = @_ ;
	return
	    sort { $a->{first_ts} <=> $b->{first_ts} }
	    values %{$srv->{$service} || {}} ;

	return map { { desc => $_, sid => $_, last_ts => 0 } } qw(
	    vel illum dolore eu feugiat nulla facilisis at vero eros et
	    accumsan et iusto odio dignissim qui blandit praesent luptatum
	    zzril delenit augue duis dolore te feugait nulla facilisi
	    Nam liber tempor cum soluta nobis eleifend option congue nihil
	    imperdiet doming id quod mazim placerat facer possim assum.) ;
}

1 ;

