package RWS::TermCast;

use strict;
use warnings;

our @ISA = qw();

our $VERSION = '0.06';

use	Log::Agent ;
use	Log::Agent::Driver::File ;
use	RWS::TermCast::Config ;
use	RWS::TermCast::Inetd ;
use	RWS::TermCast::Provider ;
use	RWS::TermCast::Consumer ;
use	POE qw(Kernel) ;

sub	run {
    my ($pkg, @args) = @_ ;
    my $cfg = RWS::TermCast::Config->conf ;
    my %la = %{$cfg->{log_agent}} ;
    if (my $f = delete $la{-file}) {
	$la{-driver} = Log::Agent::Driver::File->make(-file => $f) ;
    }
    logconfig(%la) ;
    RWS::TermCast::Inetd->spawn({
	alias => 'provider',
	'socket' => 'tcp:31337',
	session_pkg => 'RWS::TermCast::Provider'
    }) ;
    RWS::TermCast::Inetd->spawn({
	alias => 'consumer',
	'socket' => 'tcp:37331',
	session_pkg => 'RWS::TermCast::Consumer'
    }) ;
    POE::Kernel->run() ;
}

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

RWS::TermCast - Perl extension for blah blah blah

=head1 SYNOPSIS

  use RWS::TermCast;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for RWS::TermCast, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

dmitry kim, E<lt>jason@nichego.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by dmitry kim

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
