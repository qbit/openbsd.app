#!/usr/bin/env sh

set -e

mkdir -p /tmp/openbsd_app/{stable,current}

CURRENT_FILE=${1:-/tmp/openbsd_app/current/share/sqlports}
STABLE_FILE=${2:-/tmp/openbsd_app/stable/share/sqlports}

(
	cd /tmp/openbsd_app/current
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/snapshots/packages/amd64/sqlports-7.37.tgz
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/snapshots/packages/amd64/SHA256.sig
	signify -C -p /etc/signify/openbsd-73-pkg.pub -x SHA256.sig sqlports-7.37.tgz
	tar -C . -zxvf sqlports-7.37.tgz
)

(
	cd /tmp/openbsd_app/stable
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/7.3/packages/amd64/sqlports-7.37.tgz
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/7.3/packages/amd64/SHA256.sig
	signify -C -p /etc/signify/openbsd-73-pkg.pub -x SHA256.sig sqlports-7.37.tgz
	tar -C . -zxvf sqlports-7.37.tgz
)

SQL=$(cat <<EOF
	ATTACH DATABASE '%s' AS ports;

	CREATE VIRTUAL TABLE
	    %s
	USING fts5(
	    FULLPKGNAME,
	    FULLPKGPATH,
	    COMMENT,
	    DESCRIPTION);

	INSERT INTO
	    %s
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

EOF
)

rm -f ~/openbsd.app/combined.db
printf "$SQL\n" ${CURRENT_FILE} \
	"current_ports_fts" \
	"current_ports_fts" | sqlite3 ~/openbsd.app/combined.db
printf "$SQL\n" ${STABLE_FILE} \
	"stable_ports_fts" \
	"stable_ports_fts" | sqlite3 ~/openbsd.app/combined.db
