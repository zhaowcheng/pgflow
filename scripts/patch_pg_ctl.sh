#!/usr/bin/env bash
# 为 plpython 和 plperl 正常运行而修改 pg_ctl.c

set -e

PROGNAME=$(basename $0)
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME PGCTLSRC LANGS" >&2
    echo "Example1: $PROGNAME ./src/bin/pg_ctl.c python" >&2
    echo "Example2: $PROGNAME ./src/bin/pg_ctl.c perl" >&2
    echo "Example3: $PROGNAME ./src/bin/pg_ctl.c python,perl" >&2
    exit 1
fi

PGCTLSRC=$1
LANGS=$2

sed -i '/#include <unistd.h>/i #include <libgen.h>' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i char pg_ctl_path[MAXPGPATH];' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i char *bin_path;' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i char perllib[MAXPGPATH];' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i char pythonlib[MAXPGPATH];' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i find_my_exec(argv0, pg_ctl_path);' $PGCTLSRC
sed -i '/pm_pid = start_postmaster();/i bin_path = dirname(pg_ctl_path);' $PGCTLSRC
if [[ $LANGS =~ perl ]]; then
    sed -i '/pm_pid = start_postmaster();/i sprintf(perllib, "%s/../lib/perl", bin_path);' $PGCTLSRC
    sed -i '/pm_pid = start_postmaster();/i setenv("PERL5LIB", perllib, 1);' $PGCTLSRC
fi
if [[ $LANGS =~ python ]]; then
    sed -i '/pm_pid = start_postmaster();/i sprintf(pythonlib, "%s/../lib/python", bin_path);' $PGCTLSRC
    sed -i '/pm_pid = start_postmaster();/i setenv("PYTHONPATH", pythonlib, 1);' $PGCTLSRC
fi
