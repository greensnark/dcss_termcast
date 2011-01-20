package	RWS::TermCast::Config ;

use	strict ;

my	$_cfg = bless {
    log_agent => {
	-trace => 10,
	-debug => 10,
	-caller => [-display => '[$package]'],
	-file => "termcastd.log"
    },
    dbi_args => ["dbi:SQLite:re.db", "", ""],
}, __PACKAGE__ ;

sub	conf { $_cfg }

1 ;

