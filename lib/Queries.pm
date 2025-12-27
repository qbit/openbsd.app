package Queries;

use HTML::Escape qw/escape_html/;

our $dbFile       = "combined.db";
our $sqlPortsFile = "/usr/local/share/sqlports";

our $query = q{
    SELECT
	  FULLPKGNAME,
	  FULLPKGPATH,
	  COMMENT,
	  DESCRIPTION,
      HOMEPAGE,
	  highlight(%s, 2, '**', '**') AS COMMENT_MATCH,
	  highlight(%s, 3, '**', '**') AS DESCR_MATCH
    FROM %s
    WHERE %s MATCH ? ORDER BY rank;
};

our $depTreeQuery = q{
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

our $depQuery = q{
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
SELECT distinct(name) FROM under_port;
};

our $reverseQuery = q{
  WITH RECURSIVE d (fullpkgpath, dependspath, type) as 
    (select root.fullpkgpath, root.dependspath, root.type 
        from _canonical_depends root 
        join _paths  
            on root.dependspath=_paths.canonical 
        join _paths p2  
            on p2.fullpkgpath = ? and p2.id=_paths.pkgpath
        where root.type!=3             
    union                                      
        select child.fullpkgpath, child.dependspath, child.type 
            from d parent, _canonical_depends child   
        where parent.fullpkgpath=child.dependspath and child.type!=3)
            select distinct _paths.fullpkgpath from d                                           
        join _paths  
            on _paths.id=d.fullpkgpath 
        order by _paths.fullpkgpath;
};

our $pathQuery = q{
    SELECT
	  FULLPKGNAME,
	  FULLPKGPATH,
	  COMMENT,
	  DESCRIPTION,
	  HOMEPAGE
    FROM %s
    WHERE FULLPKGPATH = ?;
};

our $title = "OpenBSD.app";
our $descr = "OpenBSD package search";

sub na {
    my $stuff = shift;
    if (defined $stuff) {
	return $stuff;
    }
    return "-";
}

sub set_query {
    my $is_current = shift;
    if ($is_current) {
        return sprintf( $query, ("current_ports_fts") x 4 );
    }

    return sprintf( $query, ("stable_ports_fts") x 4 );
}

sub micron {
    my $str = shift;
    $str =~ s/\*\*(\w+)\*\*/`!$1`!/g;
    return $str
}

sub to_micron {
    my $results = shift;
    foreach my $result (@$results) {
	$result->{DESCR_MATCH} = micron( $result->{DESCR_MATCH} );
	$result->{COMMENT_MATCH} = micron( $result->{COMMENT_MATCH} );
    }
}

sub markdown {
    my $str = shift;
    $str = escape_html($str);
    $str =~ s/\*\*(\w+)\*\*/<strong>$1<\/strong>/g;
    $str =~ s/\n/<br \/>/g;
    return $str;
}

sub to_md {
    my $results = shift;
    foreach my $result (@$results) {
        $result->{DESCR_MATCH}   = markdown( $result->{DESCR_MATCH} );
        $result->{COMMENT_MATCH} = markdown( $result->{COMMENT_MATCH} );
    }

}

sub fix_fts {
    my $s = shift;
    return "" unless defined $s;
    $s =~ s/[^\w]/ /g;
    $s =~ s/^\s+//g;
    $s =~ s/\s+$//g;
    return $s;
}

1;
