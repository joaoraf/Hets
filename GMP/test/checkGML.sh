#!/bin/sh

# testing GML formulae
for i in *.g
do
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~processing GML f from $i"
    ../main 4 $i
done
