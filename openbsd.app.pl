use feature 'switch';
use Mojolicious::Lite -signatures;
use Mojo::SQLite;

#helper unstable => sub { state $sql = Mojo::SQLite->new('sqlite:unstable.db') };
helper stable => sub { state $sql = Mojo::SQLite->new('sqlite:stable.db') };

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

get '/' => sub ($c) {
    my $v = $c->validation;

    my $search = $c->param('search');

    #my $unstable = $c->param('unstable');
    my $format = $c->param('format');

    if ( defined $search && $search ne "" ) {

        #return $c->render( text => 'Bad CSRF token!', status => 403 )
        #  if $v->csrf_protect->has_error('csrf_token');

        my $db = $c->stable->db;

        #$db = $c->unstable->db if defined $unstable;

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

app->start;
__DATA__
@@ layouts/default.html.ep
<!doctype html>
<html class="no-js" lang="">
  <head>
    <title>OpenBSD.app</title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="OpenBSD package search">
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
Welcome!
