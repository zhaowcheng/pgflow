#!/bin/bash -e
# Copy the deps of all elf files in `ELFDIR` to `LIBDIR`.

PROGNAME=$(basename $0)
if [[ $# != 2 ]]; then
    echo "Usage: $PROGNAME ELFDIR LIBDIR" >&2
    exit 1
fi

ELFDIR=$1
LIBDIR=$2

for elf in `find $ELFDIR -type f -exec file {} + | grep ELF | cut -d: -f1`; do 
    echo "Analysing $elf"
    ldd $elf
    for sopath in `ldd $elf | grep -E '.+.so.* => /.+.so.* \(0x.+\)' | awk '{print $3}'`; do 
        sopaths+=($sopath)
    done
done

sopaths=(`for i in ${sopaths[*]}; do echo $i; done | sort -u`) 

for sopath in ${sopaths[*]}; do
    echo "Processing $sopath" 
    soname=`basename $sopath`
    if [[ (! -e $LIBDIR/$soname) ]]; then
        cp -v $sopath $LIBDIR
    fi
done
