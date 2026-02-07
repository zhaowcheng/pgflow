#!/usr/bin/env bash
# 拷贝 python 标准库文件。

set -e

PROGNAME=$(basename $0)
if [[ $# != 1 ]]; then
    echo "Usage: $PROGNAME LIBDIR" >&2
    exit 1
fi

LIBDIR=$1
PYLIBDIR=$LIBDIR/python

for path in $(python -c 'import sys; print("\n".join(sys.path[1:]))'); do
    # abc.py 是标准库，如果存在该文件则判定为标准库目录。
    if [ -e $path/abc.py ]; then
        mkdir $PYLIBDIR
        cp -rv $path/* $PYLIBDIR/
        chmod +w -R $PYLIBDIR
        # 删除不需要的文件。
        find $PYLIBDIR -name "*.pyc" -o -name "*.pyo" -o -name python.o -exec rm -fv {} +
        rm -rfv $PYLIBDIR/site-packages/*
        break
    fi
done
