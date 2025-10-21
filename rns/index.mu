#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Queries;

use Mojo::Template;
use Mojo::SQLite;

my $sql = Mojo::SQLite->new;
$sql->from_filename( $Queries::dbFile, { ReadOnly => 1, no_wal => 1 } );

my $mt = Mojo::Template->new;

my $index = <<'INDEX';
-~
`c<%= $descr %>
-~

Search: `B444`<search`>`b
`<?|current|true`>`b Search -current`
`[Submit`:/page/index.mu`*]

--

Welcome! Default search queries OpenBSD 7.7 package sets.

--

OpenBSD.app © 2022-<%= $year %> - proudly hosted on obsda.ms ( https://openbsd.amsterdam )!

Prefer the CLI? Check out https://codeberg.org/qbit/pkg , which offers the same capabilities as this site.

Made with <3 by qbit | Buy me a coffee ( https://buymeacoffee.com/qbit )!
INDEX

my $result = <<'RESULT';
-~
`c<%= $descr %>
-~

Search: `B444`<search`>`b
`<?|current|true`>`b Search -current`
`[Submit`:/page/index.mu`*]

-=
`a
% foreach my $result (@$results) {
`=
Package Name: <%= $result->{FULLPKGNAME} %>
Comment:      <%= $result->{COMMENT_MATCH} %>
Homepage:     <%= Queries::na($result->{HOMEPAGE}) %>
Description:  <%= $result->{DESCR_MATCH} %>
`=
--
% }
-=

OpenBSD.app © 2022-<%= $year %> - proudly hosted on obsda.ms ( https://openbsd.amsterdam )!

Prefer the CLI? Check out https://codeberg.org/qbit/pkg , which offers the same capabilities as this site.

Made with <3 by qbit | Buy me a coffee ( https://buymeacoffee.com/qbit )!
RESULT

my $year = (localtime)[5] + 1900;

if ( defined $ENV{field_search} ) {
    my $current = $ENV{field_current};
    my $search  = $ENV{field_search};

    my $q  = Queries::set_query( defined $current );
    my $db = $sql->db;

    my $results = $db->query( $q, $search )->hashes;
    Queries::to_micron($results);
    
    print $mt->vars(1)->render(
        $result,
        {
            descr   => $Queries::descr,
            results => $results,
            year    => $year,
        }
    );
}
else {
    print $mt->vars(1)->render(
        $index,
        {
            descr => $Queries::descr,
            year  => $year
        }
    );
}
