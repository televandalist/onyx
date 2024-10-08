#!/bin/bash

VERSION=$(cat -)
if [[ ! $VERSION =~ ^[0-9]{8}$ ]]; then
  echo "Not a valid program version."
  exit 1
fi
ZIPNAME=onyx-$VERSION-macos-x64
rm -rf $ZIPNAME $ZIPNAME.zip
mv mac $ZIPNAME
zip -r $ZIPNAME.zip $ZIPNAME
