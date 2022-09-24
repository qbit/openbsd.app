use Mojolicious::Lite -signatures;
use Mojo::SQLite;
use Data::Dumper;

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

    if ( defined $search && $search ne "" ) {
	return $c->render(text => 'Bad CSRF token!', status => 403) if $v->csrf_protect->has_error('csrf_token');

	my $db = $c->stable->db;
	#$db = $c->unstable->db if defined $unstable; 

	my $results = $db->query($query, $search)->hashes;
        $c->render( template => 'results', search => $search, results => $results );
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
      }

      th,
      td {
        border: 1px solid;
	padding: 5px;
      }
      
      table {
        margin: 0 auto;
        display: block;
        overflow-x: auto;
        border-spacing: 0;
      }

      .popup {
        display: none;
      }

      .result:hover~.popup {
        display: block;
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="search">
        %= form_for '/' => begin
	  %= text_field search => ""
	  %= csrf_field
	  %= submit_button 'Search...'
        % end
      </div>
    </div>
    <hr />
    <%== content %>
    <hr />
    <footer>
    <a href="https://github.com/qbit/openbsd.app">OpenBSD.app</a> © 2022
    </footer>
  </body>
</html>

@@ results.html.ep
% layout 'default';
Found <%= @$results %> reslts for for '<%= $search %>':
  <table>
    <thead>
      <tr>
        <th>Path</th>
	<th>Comment</th>
	<th>Description</th>
      </tr>
    </thead>
% foreach my $result (@$results) {
    <tr>
      <td><%= $result->{FULLPKGPATH} %></td>
      <td><%== $result->{COMMENT_MATCH} %></td>
      <td><%== $result->{DESCR_MATCH} %></td>
    </tr>
% }
  </table>

@@ index.html.ep
% layout 'default';
Welcome!
