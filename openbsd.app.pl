#!/usr/bin/env perl

# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

use warnings;
use strict;
use Time::HiRes qw(time);
use File::Basename;

use feature 'switch';

use Mojolicious::Lite -signatures;
use Mojo::SQLite;

my $dbFile = "combined.db";

if ( $^O eq "openbsd" ) {
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;

    OpenBSD::Unveil::unveil( "/",          "" )    or die;
    OpenBSD::Unveil::unveil( $0,           "r" )   or die;
    OpenBSD::Unveil::unveil( dirname($0),  "rwc" ) or die;
    OpenBSD::Unveil::unveil( "/usr/local", "r" )   or die;

    OpenBSD::Pledge::pledge(qw(stdio dns inet rpath proc flock wpath cpath))
      or die;
}

my $mtime = ( stat($dbFile) )[9];
$mtime = scalar localtime $mtime;

helper sqlite => sub {
    state $sql = Mojo::SQLite->new;
    $sql->from_filename( $dbFile, { ReadOnly => 1, no_wal => 1 } );
    $sql->on(
        connection => sub {
            my ( $sql, $dbh ) = @_;
            $dbh->do("pragma journal_mode=DELETE");
        }
    );
    return $sql;
};

helper sqlports => sub {
    state $sql = Mojo::SQLite->new;
    $sql->from_filename( "/usr/local/share/sqlports",
        { ReadOnly => 1, no_wal => 1 } );
    $sql->on(
        connection => sub {
            my ( $sql, $dbh ) = @_;
            $dbh->do("pragma journal_mode=DELETE");
        }
    );
    return $sql;
};

my $query = q{
    SELECT
	  FULLPKGNAME,
	  FULLPKGPATH,
	  COMMENT,
	  DESCRIPTION,
	  highlight(%s, 2, '**', '**') AS COMMENT_MATCH,
	  highlight(%s, 3, '**', '**') AS DESCR_MATCH
    FROM %s
    WHERE %s MATCH ? ORDER BY rank;
};

my $depsQuery = q{
  WITH RECURSIVE
  under_port(name,level) AS (
    VALUES(? ,0)
    UNION ALL
    SELECT _depends.fulldepends, under_port.level+1
      FROM
        _depends
      JOIN _paths ON _paths.id=_depends.fullpkgpath
      join under_port ON _paths.fullpkgpath = under_port.name
      where
        _depends.type IN (0, 1)
     ORDER BY 2 DESC
  )
SELECT substr('..........',1,level*3) || name FROM under_port;
};

my $title = "OpenBSD.app";
my $descr = "OpenBSD package search";

sub markdown($str) {
    $str =~ s/\*\*(.+)\*\*/<strong>$1<\/strong>/g;
    $str =~ s/\n/<br \/>/g;
    return $str;
}

sub to_md ($results) {
    foreach my $result (@$results) {
        $result->{DESCR_MATCH}   = markdown( $result->{DESCR_MATCH} );
        $result->{COMMENT_MATCH} = markdown( $result->{COMMENT_MATCH} );
    }

}

sub set_query ($is_current) {
    if ($is_current) {
        return sprintf( $query, ("current_ports_fts") x 4 );
    }

    return sprintf( $query, ("stable_ports_fts") x 4 );
}

sub fix_fts ($s) {
    return "" unless defined $s;
    $s =~ s/[^\w]/ /g;
    $s =~ s/^\s+//g;
    $s =~ s/\s+$//g;
    return $s;
}

get '/tree' => sub ($c) {
    my $v = $c->validation;

    $c->stash( title => $title );
    $c->stash( descr => $descr );
    $c->stash( mtime => $mtime );

    my $search = $c->param('name');
    my $raw    = $c->param('raw');
    my $db     = $c->sqlports->db;

    if ( $raw ne "" ) {
        $c->render( text => $db->query( $depsQuery, $search )->text );
    }
    else {
        $c->render(
            template => 'tree',
            name     => $search,
            tree     => $db->query( $depsQuery, $search )->text
        );
    }
};

get '/' => sub ($c) {
    my $v = $c->validation;

    my $search = fix_fts $c->param('search');

    my $current = $c->param('current');
    my $format  = $c->param('format');

    $c->stash( title => $title );
    $c->stash( descr => $descr );
    $c->stash( mtime => $mtime );

    if ( defined $search && $search ne "" ) {
        my $db = $c->sqlite->db;

        my $q       = set_query( defined $current );
        my $start   = time();
        my $results = $db->query( $q, $search )->hashes;
        my $end     = time();
        my $elapsed = sprintf( "%2f\n", $end - $start );

        to_md($results);

        given ($format) {
            when ("json") {
                $c->render( json => $results );
            }
            default {
                $c->render(
                    template => 'results',
                    search   => $search,
                    elapsed  => $elapsed,
                    results  => $results
                );
            }
        }
    }
    else {
        $c->render( template => 'index' );
    }
};

get '/pico.classless.css' => sub ($c) {
    $c->reply->static('pico.classless.css');
};

get '/openbsd-app-opensearch.xml' => sub ($c) {
    $c->res->headers->content_type('application/opensearchdescription+xml');
    $c->render(
        template => 'openbsd-app-opensearch',
        format   => 'xml',
        title    => $title,
        descr    => $descr
    );
};

app->start;
__DATA__
@@ layouts/default.html.ep
<!doctype html>
<html class="no-js" lang="en">
  <head>
    <title><%= $title %></title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="<%= $descr %>">
    <link
      rel="search"
      type="application/opensearchdescription+xml"
      title="<%= $title %>"
      href="/openbsd-app-opensearch.xml" />
    <link rel="stylesheet" href="/pico.classless.css">
    <style>
    header {
        padding: 0px !important;
    }
    main {
        padding: 0px !important;
    }
    .nowrap {
        white-space: nowrap;
    }
    html {
      background-color: #ffffea;
    }
    #search {
      background-color: #fff;
    }

    table {
      background-color: #fff;
      border: 1px solid #dedeff;
    }

    table th {
      background-color: #dedeff;
    }
    .none {
      display: none;
    }
    </style>
  </head>
  <body>
  <header>
      <h3><a href="/">OpenBSD.app - search packages</a></h3>
      %= form_for '/' => begin
        %= label_for search => 'Search', class => 'none'
        %= search_field 'search', id => 'search', placeholder => 'Search', value => undef
        %= check_box 'current', id => 'current', role => "switch"
        %= label_for current => "Search -current"
        (<%= $mtime %></i>)
      % end
</header>
<main>
  <%== content %>
</main>
    <footer>
      <p><a href="https://github.com/qbit/openbsd.app">OpenBSD.app</a> © 2022 - proudly hosted on <a href="https://openbsd.amsterdam/">obsd.ams</a>!</p>
    </footer>
  </body>
</html>

@@ tree.html.ep
% layout 'default';
<div>
  <h3>Dependency tree for: <%= $name %></h3>
  <p>
    <pre><%= $tree %></pre>
  </p>
</div>

@@ results.html.ep
% layout 'default';
<p>
  Found <b><%= @$results %></b> results for '<b><%= $search %></b>' in <%= $elapsed %> seconds.<br />
  <a href="/?search=<%= $search %>&format=json">View as JSON</a>
</p>
  <table class="results" role="grid">
    <thead>
      <tr>
        <th class="nowrap">Package Name</th>
        <th>Path</th>
	<th>Comment</th>
	<th>Description</th>
      </tr>
    </thead>
% foreach my $result (@$results) {
    <tr>
      <td class="nowrap"><%= $result->{FULLPKGNAME} %></td>
      <td class="nowrap">
        <a
          href="/tree?name=<%= $result->{FULLPKGPATH} %>"
          title="Dependencies for <%= $result->{FULLPKGNAME} %>"
        ><%= $result->{FULLPKGPATH} %></a>
      </td>
      <td class=""><%== $result->{COMMENT_MATCH} %></td>
      <td><%== $result->{DESCR_MATCH} %></td>
    </tr>
% }
  </table>

@@ index.html.ep
% layout 'default';
<p>Welcome! Default search queries OpenBSD 7.3 package sets.</p>

@@ exception.html.ep
% layout 'default';
<h2>Invalid search</h2>

@@ openbsd-app-opensearch.xml.ep
<?xml version="1.0" encoding="utf-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/"
                       xmlns:moz="http://www.mozilla.org/2006/browser/search/">
  <ShortName><%= $title %></ShortName>
  <Description><%= $descr %></Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Image width="32" height="32" type="image/x-icon">https://openbsd.org/favicon.ico</Image>
  <Url type="text/html" method="GET" template="https://openbsd.app/?search={searchTerms}"/>
  <moz:SearchForm>https://openbsd.app/</moz:SearchForm>
</OpenSearchDescription>

@@ favicon.ico (base64)
AAABAAQAICAAAAAAAACoCAAARgAAACAgEAAAAAAA6AIAAO4IAAAQEAAAAAAAAGgFAADWCwAAEBAQ
AAAAAAAoAQAAPhEAACgAAAAgAAAAQAAAAAEACAAAAAAAgAQAAAAAAAAAAAAAAAEAAAAAAAAAAAAA
AACAAACAAAAAgIAAgAAAAIAAgACAgAAAwMDAAICAgAAAAP8AAP8AAAD//wD/AAAA/wD/AP//AAD/
//8AwwAAAM8AAADbAAAA5wAAAPMAAAD/AAAA/xcXAP8vLwD/U1MA/2tnAP9/fwD/i4sA/5eXAP+j
owD/r68A/7u7AP/HxwD/z8cA/9vbAP/n5wD/8/MA//v3ACsrUwA3N18AQ0NrAE9PdwBXV38AY2OL
AG9vlwB/f6cAi4uzAJeXvwCnp88As7PbAL+/5wDHx+8Az8/3AFMrKwBfNzcAa0NDAHdPTwCDW1sA
j2dnAJtzcwCnf38As4uLAL+XlwDLo6MA16+vAOO7uwDrw8MA+9PTAC9TLwA7XzsAR2tHAFN3UwBf
g18Aa49rAHebdwCDp4MAj7OPAJu/mwCny6cAs9ezAL/jvwDL78sA1/vXAIdvlwCXf6cAp4+3ALOb
wwDDq9MAz7ffANvD6wCLl28Ak6N7AJ+vhwCru5MAt8efAMvbswDX578A4/PLAAtvmwAPe6MAE4ev
ABePtwAbm8MAF6fPABuz2wAjv+cAK8vzADfX/wD/8/8A/+v/AP/f/wD/0/8A/8f/AP+3/wD/o/8A
/5f/AP+D/wD/a/8A/0v/AOcA5wDXANcAwwDHALcAtwCjAKcAlwCXAIsAiwB3AHcAZwBnAE8AUwAv
ADMA6///AOf//wDf//8A0///ALv//wCb//8AP///AADz9wAA5+sAAN/fAADT0wAAx8cAALu7AACz
rwAAp6cAAJuXAACXjwAAf38AAHd3AABfXwAAR0cAADMzAP//9wD//+cA///bAP//xwD//7sA//+X
AP//fwD//1MA7+8AAOPjAADX1wAAy8sAAL+/AACzswAAo6MAAJeTAACLgwAAe3sAAGdrAABbWwAA
R0sAACMjAADz//MA3//nANf/1wDD/88Au/+7AKP/owCH/4cAZ/9nADf/NwAL/wAAAPMAAADrAAAA
4wAAANcAAADLAAAAvwAAALMAAACnAAAAnwAAAJMAAACHAAAAfwAAAHcAAABvAAAAZwAAAF8AAABT
AAAARwAAADcAAAAjAAD38/8A6+v/AN/f/wDT0/8Aw8P/AK+v/wCbm/8Ai4v/AHd3/wBnZ/8AU1P/
AEND/wAvL/8AFxf/AAAARwAAAFcAAABnAAAAcwAAAH8AAACLAAAAlwAAAKMAAACvAAAAuwAAAMMA
AADPAAAA2wAAAOcAAADzAHwAVACbAGkAugB+ANkAkwDwAKoA/yS2AP9IwgD/bM4A/5DaAP+05gDw
8PAA3NzcAMjIyAC0tLQAoKCgAICAgAAAAP8AAP8AAAD//wD/AAAA/wD/AP//AAD///8AAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAA39gAARQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9gAAAK1EAPaXAAAARwAAAAgAAAAA
AAAAAAAAAAAAAAAAlwAAgTVbCJVGAAeXAAAIAPZECAAAAEcAAAAAAAAA9gCXlq0AAEXLZpVGy5dE
rQAAyzX3ACgABwAAAAAAAACBOfeVliiVYpWWY5etrQAAAAAAAEaXlSgAAAAAAAAAAAAAR8tlaGhp
aZSXrQAAAAAAAAAAl5WVAAAIAAAAAAAAAAAAlopoaGhoaJcAAAAAAACtAJdil5YAl5ZIAAAAAACt
AJdpZWZoaGhplwAAAAAAAK2tlZQAlkiWYpf3AAAAADXLlpaVlpVmaGhllwAAAAAAra2XAACWl5eX
JpcAAAAAAJaXYmdlYpVlaGhjl601Na0ArTWtAACVAJUIlykAAACXZ2KWK/YuYpZnaGeUgTatrQAA
rTUAAJSXY5U5l/cAAJZpaGOWIg9Bl2RoaGWXNq2tra2tNwAAlZdiYyiXJwD1lopolZb1bSInZ2ho
Z5etNa2tra05AACVl5eWYpaVAACVaWWUlpRjlWJoaGhnlss1ra2trTetAJWWAPeXaJUALZZiJpaV
ZGJjaGhoaGWVlzU1rQCtrQAAlZX3APfLl/aWl5YiPJZpYpaXYmhoZ2OXO/dHAACtrQCVaJUn9vUI
AAArlUKBYpcqPz6XZ2hnZJY9PzfLAAAAAGKW9gAAAAAA9paVl5dnlzUIIpZmaGdiljk2rTc6RDU1
lUcAAAAAAAdFl5aWZ2dilzstlmNoZ2KXNa2tNTY3NZeXAAAAAAAAAAD2l2hpZ2dol5eXZGhklq2t
AK2tra2tl5VIAAAAAAAAAC1iZWRoaGhnAJdoZWKXra0Ara2trQBGK5dLAAAAAAAplpbLl2VnZ2lo
Z2Zil62tAK2trQDLlwAAAEgAAAAARyj1AACtl5doYpVilpetrQDLl8ut9yaXAAAAAAAAAAAAAAAA
CEU4lmMAADU7N60AAGZjJwAAAEUIAAAAAAAAAAAAAAAAAACVKDlHN5cm9gD2lmL3AAAAAPYAAAAA
AAAAAAAAAAAA95cAAAD1lwAAAAAplwAAAAAAAAAAAAAAAAAAAAAAAAAp9gAAAPRIAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//////////
/m///+5O7//2BMHf0YABH8AAAD/AAABvwAAAR8AAAAPAAAADwAAAAcAAAADAAAAAgAAAAMAAABCA
AAAIAAAAAMAAAA+AAAAfAAAAP8AAAB/AAAAPgAAA7xgAAP/wAA5//gEPf/znn//859/////f////
////////KAAAACAAAABAAAAAAQAEAAAAAACAAgAAAAAAAAAAAAAQAAAAAAAAAAQCBAAMhpwABNL0
ABxGTAAEqswAHGZ0AIyCfADMxswATEZEAPz+/AAsKiQApJ6cAGxqZABMjpwAXFZMAAAAAAD/////
//////////////////////////////////////////7////////////////////8j/P/////////
//////+v+O/0P/P///j/////////UY/+gh+lzuiM/zP/////jvHVFB1Bzq//ioVD/////4jzIiIk
XKqq+qpRT//////q8SIiIlqoqoylRV8x////6lIiIiJYr6qM4UMfVF///24RERIiJa+oju6KFTWq
//+BVCJEIiJeZujszzE0+v//UkG3fRIiTGzIjGikFB8//xIk2ZfEIkVszuy6oRRDNf8SIRmZsiIh
5u7suKRaFBH/0iQU3UIiIYbO7LyhX/Uk/xTNFEQiIiRWbI7IoR//M/FdlxJNVCIkV3uo7IQhr///
/XZBt3UiJBd76KiEX////1HVJWedIiTbbLtmYf////5REiRXcUIk5u7GZtX/////8SIiJVVCQcyI
zMhR//////QkIiI1IkXOjMyI/z////8VgSIiIiReyu7oM/////////zlJBQY7qherzX////////6
5UOGu+oyQ/////////////Ff+NP/8U/////////////z//8///9f////////////////////r///
////////////////////////////////////////////////////////////////////////////
/////v////5v///2Zuv/8YQDP8gAAD/IAAB/wAAAT8AAAEfAAAADwAAAC8AAAAXAAAAAwAAAAMAA
ABjAAAAcgAAAB+AAAB/AAAA/gAAAP+AAAD/gAADfwAAA//gABP/4AA///mOf//733////9//////
////////////KAAAABAAAAAgAAAAAQAIAAAAAABAAQAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAIAA
AIAAAACAgACAAAAAgACAAICAAADAwMAAgICAAAAA/wAA/wAAAP//AP8AAAD/AP8A//8AAP///wDD
AAAAzwAAANsAAADnAAAA8wAAAP8AAAD/FxcA/y8vAP9TUwD/a2cA/39/AP+LiwD/l5cA/6OjAP+v
rwD/u7sA/8fHAP/PxwD/29sA/+fnAP/z8wD/+/cAKytTADc3XwBDQ2sAT093AFdXfwBjY4sAb2+X
AH9/pwCLi7MAl5e/AKenzwCzs9sAv7/nAMfH7wDPz/cAUysrAF83NwBrQ0MAd09PAINbWwCPZ2cA
m3NzAKd/fwCzi4sAv5eXAMujowDXr68A47u7AOvDwwD709MAL1MvADtfOwBHa0cAU3dTAF+DXwBr
j2sAd5t3AIOngwCPs48Am7+bAKfLpwCz17MAv+O/AMvvywDX+9cAh2+XAJd/pwCnj7cAs5vDAMOr
0wDPt98A28PrAIuXbwCTo3sAn6+HAKu7kwC3x58Ay9uzANfnvwDj88sAC2+bAA97owATh68AF4+3
ABubwwAXp88AG7PbACO/5wAry/MAN9f/AP/z/wD/6/8A/9//AP/T/wD/x/8A/7f/AP+j/wD/l/8A
/4P/AP9r/wD/S/8A5wDnANcA1wDDAMcAtwC3AKMApwCXAJcAiwCLAHcAdwBnAGcATwBTAC8AMwDr
//8A5///AN///wDT//8Au///AJv//wA///8AAPP3AADn6wAA398AANPTAADHxwAAu7sAALOvAACn
pwAAm5cAAJePAAB/fwAAd3cAAF9fAABHRwAAMzMA///3AP//5wD//9sA///HAP//uwD//5cA//9/
AP//UwDv7wAA4+MAANfXAADLywAAv78AALOzAACjowAAl5MAAIuDAAB7ewAAZ2sAAFtbAABHSwAA
IyMAAPP/8wDf/+cA1//XAMP/zwC7/7sAo/+jAIf/hwBn/2cAN/83AAv/AAAA8wAAAOsAAADjAAAA
1wAAAMsAAAC/AAAAswAAAKcAAACfAAAAkwAAAIcAAAB/AAAAdwAAAG8AAABnAAAAXwAAAFMAAABH
AAAANwAAACMAAPfz/wDr6/8A39//ANPT/wDDw/8Ar6//AJub/wCLi/8Ad3f/AGdn/wBTU/8AQ0P/
AC8v/wAXF/8AAABHAAAAVwAAAGcAAABzAAAAfwAAAIsAAACXAAAAowAAAK8AAAC7AAAAwwAAAM8A
AADbAAAA5wAAAPMAfABUAJsAaQC6AH4A2QCTAPAAqgD/JLYA/0jCAP9szgD/kNoA/7TmAPDw8ADc
3NwAyMjIALS0tACgoKAAgICAAAAA/wAA/wAAAP//AP8AAAD/AP8A//8AAP///wAAAAAAAAAAAAAA
AAAAAAAAAAAACPcIAPQAAAAAAAAAAAD2J0c5lilER4FE9ggAAAAANZeUY2KXAAAAAJYoAAAABwCX
Z2loywAArZeWJ5crAPWXlWJiaGIAra2tAJeXJwcAlGItL5RplTWtra2XlZVGAGNilC5kaZStra2t
lyeWlfeWKpWVYmhiJjcArZeV9yf1lpWVOSpmZCg4Na2XKwAAAJVlZ5WWZmKtrTU1lwcAAAAolGdn
lWOXra2ty/ctAAAAADiWlZYmrZeXCCn0AAAAAAAACAgIRQArKAAAAAAAAAAAAPUAAAAAAAgAAAAA
AAAAAAAAAAAAAAAAAAAAAAAA//8AAOL/AACABwAAgAcAAAABAAAAAAAAgAAAAIAAAAAAAAAAAAMA
AIADAACAAwAAwAcAAOE/AADvvwAA//8AACgAAAAQAAAAIAAAAAEABAAAAAAAwAAAAAAAAAAAAAAA
EAAAAAAAAAAUERAAGXeaAC1ESAAGWHoABLL0ACQmIwBSX2MABJTOAHd+fwDDwsMAgKS0AI2XnQDU
09IAFExeABFpigANMT0AAAAAAAAAAAAACKgMAAAAAAombWJlWoAABS4e8AAC0ACQVEQAAA3fgMXe
5OAAAF/5DhujTVBQA9YBE6dDUAUN3b3jPkEiAFOyze1ud2ZV+AANd9JzUFX5AAY0cx8AULgAAG89
8F+GwAAACIggjQAAAAAJAAAIAAAAAAAAAAAAAAD//wAA4v8AAIAHAACABwAAAAEAAAAAAACAAAAA
gAAAAAAAAAAAAwAAgAMAAIADAADABwAA4T8AAO+/AAD//wAA
