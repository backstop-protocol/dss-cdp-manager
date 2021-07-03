#!/bin/sh


copyDappFolders () {
    normalDir="`cd "$2";pwd`"
    echo "copying $1 folders..."
    for dir in $1/*; do
        echo "copying $dir to $normalDir/$(basename $dir)"
        mkdir -p $normalDir/$(basename $dir)
        `cp $dir/src/*.* $normalDir/$(basename $dir)`
        if [ -d "$dir/lib" ]
        then 
            copyDappFolders "$dir/lib" $2
        fi
    done
}

target=$PWD/$1
copyDappFolders "../lib" $target