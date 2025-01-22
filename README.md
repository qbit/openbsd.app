# OpenBSD.app

A site that allows quick full-text searching of OpenBSD packages for -stable and -current.

## Hacking

### Generating FTS5 databases


```
$ sqlite3 stable.db
> ATTACH DATABASE '/usr/local/share/sqlports' AS ports;
> CREATE VIRTUAL TABLE
	    ports_fts
	USING fts5(
	    FULLPKGNAME,
	    FULLPKGPATH,
	    COMMENT,
	    DESCRIPTION);
> INSERT INTO
	    ports_fts
	(FULLPKGNAME, FULLPKGPATH, COMMENT, DESCRIPTION)
	SELECT
	    fullpkgname,
	    _paths.fullpkgpath,
	    comment,
	    _descr.value
	FROM
	    ports._ports
	JOIN _paths ON _paths.id=_ports.fullpkgpath
	JOIN _descr ON _descr.fullpkgpath=_ports.fullpkgpath;
> .quit
```

.. and the same for `current.db` using `sqlports` from -current.

### Running on OpenBSD

```
$ doas pkg_add p5-Mojolicious p5-Text-Markdown p5-Mojo-SQLite sqlports
$ morbo openbsd.app.pl
```

### Running with nix/NixOS

```
nix shell
morbo openbsd.app.pl
```


## TODOs

- [X] `use OpenBSD::Pledge` / `use OpenBSD::Unveil`.
- [X] Automate building of the fts DBs.
    - Fetch $release sqlports and $current sqlports and create.
- [X] OpenSearch support.
- [X] ~~Parse input to match `Full-text Query Syntax`: https://www.sqlite.org/fts5.html .~~
    - Only searching for letters for now.
- [X] Style.
- [X] Stable and unstable search.
