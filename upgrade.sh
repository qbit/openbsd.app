#!/usr/bin/env sh

set -xe

mkdir -p /tmp/openbsd_app/{stable,current}

CURRENT_VER="7.49"
STABLE_VER="7.37"
CURRENT_FILE=${1:-/tmp/openbsd_app/current/share/sqlports}
STABLE_FILE=${2:-/tmp/openbsd_app/stable/share/sqlports}
SIGNIFY="${SIGNIFY:-signify}"
CURRENT_PUB=$(readlink -f /etc/signify/openbsd-73-pkg.pub)
STABLE_PUB=$(readlink -f /etc/signify/openbsd-73-pkg.pub)

(
	cd /tmp/openbsd_app/current
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/snapshots/packages/amd64/sqlports-${CURRENT_VER}.tgz
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/snapshots/packages/amd64/SHA256.sig
	${SIGNIFY} -C -p ${CURRENT_PUB} -x SHA256.sig sqlports-${CURRENT_VER}.tgz
	tar -C . -zxvf sqlports-${CURRENT_VER}.tgz
)

(
	cd /tmp/openbsd_app/stable
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/7.3/packages/amd64/sqlports-${STABLE_VER}.tgz
	curl -L -O https://cdn.openbsd.org/pub/OpenBSD/7.3/packages/amd64/SHA256.sig
	${SIGNIFY} -C -p ${STABLE_PUB} -x SHA256.sig sqlports-${STABLE_VER}.tgz
	tar -C . -zxvf sqlports-${STABLE_VER}.tgz
)

SQL=$(cat <<EOF
	ATTACH DATABASE '%s' AS ports;

	CREATE VIRTUAL TABLE
	    %s
	USING fts5(
	    FULLPKGNAME,
	    FULLPKGPATH,
	    COMMENT,
	    DESCRIPTION,
	    HOMEPAGE);

	INSERT INTO
	    %s
	(FULLPKGNAME, FULLPKGPATH, COMMENT, DESCRIPTION, HOMEPAGE)
	SELECT
	    fullpkgname,
	    _paths.fullpkgpath,
	    comment,
	    _descr.value,
	    homepage
	FROM
	    ports._ports
	JOIN _paths ON _paths.id=_ports.fullpkgpath
	JOIN _descr ON _descr.fullpkgpath=_ports.fullpkgpath;

EOF
)

if [ -d ~/openbsd.app ]; then
	rm -f ~/openbsd.app/combined.db
	printf "$SQL\n" ${CURRENT_FILE} \
		"current_ports_fts" \
		"current_ports_fts" | sqlite3 ~/openbsd.app/combined.db
	printf "$SQL\n" ${STABLE_FILE} \
		"stable_ports_fts" \
		"stable_ports_fts" | sqlite3 ~/openbsd.app/combined.db
else
	# dev mode
	rm -f ~/src/openbsd.app/combined.db
	printf "$SQL\n" ${CURRENT_FILE} \
		"current_ports_fts" \
		"current_ports_fts" | sqlite3 ~/src/openbsd.app/combined.db
	printf "$SQL\n" ${STABLE_FILE} \
		"stable_ports_fts" \
		"stable_ports_fts" | sqlite3 ~/src/openbsd.app/combined.db
fi
