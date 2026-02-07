#!/usr/bin/env bash
# 拷贝 perl 标准库文件。

set -e

PROGNAME=$(basename $0)
if [[ $# != 1 ]]; then
    echo "Usage: $PROGNAME LIBDIR" >&2
    exit 1
fi

LIBDIR=$1
PLLIBDIR=$LIBDIR/perl

for path in $(perl -e 'print join("\n", @INC, "")'); do
    # Carp.pm 是标准库，如果存在该文件则判定为标准库目录。
    if [ -e $path/Carp.pm ]; then
        mkdir $PLLIBDIR
        cp -rv $path/* $PLLIBDIR/
        chmod +w -R $PLLIBDIR
        # 删除不需要的文件。
        find $PLLIBDIR -name "*.pod" -exec rm -fv {} +
        break
    fi
done
