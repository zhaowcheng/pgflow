#!/bin/bash -e
# Copy the deps of all elf files in `ELFDIR` to `DESTDIR`.

PROGNAME=$(basename "$0")
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $PROGNAME ELFDIR DESTDIR [EXCLUDEDIRS]" >&2
    echo "  EXCLUDEDIRS: colon-separated paths, e.g. /lib:/usr/lib" >&2
    exit 1
fi

ELFDIR=$1
DESTDIR=$2
EXCLUDEDIRS=${3:-}
EXCLUDEDIRS=$EXCLUDEDIRS:$DESTDIR

in_excludedirs() {
    local so="$1"
    IFS=':' read -r -a dirs <<< "$EXCLUDEDIRS"
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ -e "$d/$(basename "$so")" ]]; then
            return 0
        fi
    done
    return 1
}

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
    if !(in_excludedirs "$sopath"); then
        cp -v "$sopath" "$DESTDIR"
    fi
done
