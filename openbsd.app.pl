use warnings;
use strict;

use feature 'switch';

use Mojolicious::Lite -signatures;
use Mojo::SQLite;

if ( $^O eq "openbsd" ) {
    require OpenBSD::Pledge;
    require OpenBSD::Unveil;

    OpenBSD::Unveil::unveil( "/",            "" )  or die;
    OpenBSD::Unveil::unveil( "./current.db", "r" ) or die;
    OpenBSD::Unveil::unveil( "./stable.db",  "r" ) or die;
    OpenBSD::Unveil::unveil( "/usr/local",   "r" ) or die;

    # Needed to create the -shm and -wal db files.
    OpenBSD::Unveil::unveil( ".", "rwc" ) or die;

    OpenBSD::Pledge::pledge(qw( stdio dns inet rpath proc flock wpath cpath ))
      or die;
}

helper current => sub { state $sql = Mojo::SQLite->new('sqlite:current.db') };
helper stable  => sub { state $sql = Mojo::SQLite->new('sqlite:stable.db') };

my $query = q{
    SELECT
	FULLPKGNAME,
	FULLPKGPATH,
	COMMENT,
	DESCRIPTION,
	highlight(ports_fts, 2, '<b>', '</b>') AS COMMENT_MATCH,
	highlight(ports_fts, 3, '<b>', '</b>') AS DESCR_MATCH
    FROM ports_fts
    WHERE ports_fts MATCH ? ORDER BY rank;
};

my $title = "OpenBSD.app";
my $descr = "OpenBSD package search";

get '/' => sub ($c) {
    my $v = $c->validation;

    my $search = $c->param('search');

    my $current = $c->param('current');
    my $format  = $c->param('format');

    $c->stash( title => $title );
    $c->stash( descr => $descr );

    if ( defined $search && $search ne "" ) {
        my $db = $c->stable->db;
        $db = $c->current->db if defined $current;

        my $results = $db->query( $query, $search )->hashes;

        given ($format) {
            when ("json") {
                $c->render( json => $results );
            }
            default {
                $c->render(
                    template => 'results',
                    search   => $search,
                    results  => $results
                );
            }
        }
    }
    else {
        $c->render( template => 'index' );
    }
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
<html class="no-js" lang="">
  <head>
    <title><%= $title %></title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="<%= $descr %>">
    <link
      rel="search"
      type="application/opensearchdescription+xml"
      href="/openbsd-app-opensearch.xml" />
    <style>
      body {
        font-family: Avenir, 'Open Sans', sans-serif;
	background-color: #ffffea;
      }

      table {
        border-collapse:separate;
        border:solid black 1px;
        border-radius:6px;
	background-color: #fff;
      }
      
      td, th {
        border-left:solid black 1px;
        border-top:solid black 1px;
      }

      th {
        white-space: nowrap;
	padding: 6px;
      }

      .search {
        padding: 10px;
	margin: 10px;
        border-radius:6px;
	box-shadow: 2px 2px 2px black;
      }
      
      th, .search {
        border-top: none;
	background-color: #eaeaff;
      }
      
      td:first-child, th:first-child {
        border-left: none;
      }

      td {
	padding: 10px;
	text-align: left;
      }

      .nowrap {
        white-space: nowrap;
      }

      footer, .wrap, .results {
	text-align: center;
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <h3><a href="/">OpenBSD.app - search packages</a></h3>
      <div class="search">
        %= form_for '/' => begin
	  %= text_field search => ""
	  -current
	  %= check_box 'current'
	  %= submit_button 'Search...'
        % end
      </div>
    </div>
    <div class="results">
      <%== content %>
    </div>
    <hr />
    <footer>
      <p><a href="https://github.com/qbit/openbsd.app">OpenBSD.app</a> © 2022</p>
      <p><a href="https://github.com/qbit/pkg">Prefer CLI?</a></p>
    </footer>
  </body>
</html>

@@ results.html.ep
% layout 'default';
<p>
  Found <b><%= @$results %></b> results for '<b><%= $search %></b>'<br />
  <a href="/?search=<%= $search %>&format=json">View as JSON</a>
</p>
  <table class="results">
    <thead>
      <tr>
        <th>Package Name</th>
        <th>Path</th>
	<th>Comment</th>
	<th>Description</th>
      </tr>
    </thead>
% foreach my $result (@$results) {
    <tr>
      <td class="nowrap"><%= $result->{FULLPKGNAME} %></td>
      <td class="nowrap"><%= $result->{FULLPKGPATH} %></td>
      <td class="nowrap"><%== $result->{COMMENT_MATCH} %></td>
      <td><%== $result->{DESCR_MATCH} %></td>
    </tr>
% }
  </table>

@@ index.html.ep
% layout 'default';
Welcome! Default search queries OpenBSD 7.2 package sets. You can search -current (packages from 2022-09-23) by toggling the '-current' checkbox.

@@ openbsd-app-opensearch.xml.ep
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/"
                       xmlns:moz="http://www.mozilla.org/2006/browser/search/">
  <ShortName><%= $title %></ShortName>
  <Description><%= $descr %></Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Image width="32" height="32" type="image/x-icon">https://openbsd.org/favicon.ico</Image>
  <Url type="text/html" template="https://openbsd.app/?search={searchTerms}"/>
  <moz:SearchForm>https://openbsd.app/</moz:SearchForm>
</OpenSearchDescription>
