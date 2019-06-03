#!/usr/bin/env bash
##############################################################################
## This is used to package .deb packages and upload them to the launchpad
## ppa servers for building.
##
## If no argument is given, creates a package for the develop branch
## and uploads it to the ethereum/ethereum-dev ppa.
##
## If an argument is given, it is used as a tag and the resulting package
## is uploaded to the ethereum/ethereum ppa.
##
## The gnupg key for "builds@ethereum.org" has to be present in order to sign
## the package.
##
## It will clone the Solidity git from github, determine the version,
## create a source archive and push it to the ubuntu ppa servers.
##
## This requires the following entries in /etc/dput.cf:
##
##  [ethereum-dev]
##  fqdn			= ppa.launchpad.net
##  method			= ftp
##  incoming		= ~ethereum/ethereum-dev
##  login			= anonymous
##
##  [ethereum]
##  fqdn			= ppa.launchpad.net
##  method			= ftp
##  incoming		= ~ethereum/ethereum
##  login			= anonymous
##
##  [ethereum-static]
##  fqdn			= ppa.launchpad.net
##  method			= ftp
##  incoming		= ~ethereum/ethereum-static
##  login			= anonymous

##
##############################################################################

set -ev

keyid=36CF9F4DACE538F8F7ED8484E80FD058F7C6DF61
email=daniel@ekpyron.org
packagename=z3-static
version=4.8.5
distribution=static
build_distribution=cosmic

cd /tmp/
rm -rf $distribution
mkdir $distribution
cd $distribution

pparepo=ethereum-experimental-static
ppafilesurl=https://launchpad.net/~ekpyron/+archive/ubuntu/${pparepo}/+files

# Fetch source
git clone --depth 1 --branch Z3-${version} https://github.com/Z3Prover/z3.git
cd z3
debversion="$version"

CMAKE_OPTIONS="-DBUILD_LIBZ3_SHARED=OFF -DCMAKE_BUILD_TYPE=Release -DUSE_OPENMP=OFF"

# gzip will create different tars all the time and we are not allowed
# to upload the same file twice with different contents, so we only
# create it once.
if [ ! -e /tmp/${packagename}_${debversion}.orig.tar.gz ]
then
    tar --exclude .git -czf /tmp/${packagename}_${debversion}.orig.tar.gz .
fi
cp /tmp/${packagename}_${debversion}.orig.tar.gz ../

# Create debian package information

mkdir debian
echo 9 > debian/compat
cat <<EOF > debian/control
Source: z3-static
Section: science
Priority: extra
Maintainer: Daniel <daniel@ekpyron.org>
Build-Depends: ${SMTDEPENDENCY}debhelper (>= 9.0.0),
               cmake,
               g++,
               git,
               libgmp-dev,
               python-all
Standards-Version: 3.9.5
Homepage: https://github.com/Z3Prover/z3
Vcs-Git: git://github.com/Z3Prover/z3.git
Vcs-Browser: https://github.com/Z3Prover/z3

Package: z3-static
Architecture: any-i386 any-amd64
Multi-Arch: same
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: Z3 SMT solver (static build).
 Static build of the SMT solver Z3.
EOF
cat <<EOF > debian/rules
#!/usr/bin/make -f
# -*- makefile -*-
# Sample debian/rules that uses debhelper.
#
# This file was originally written by Joey Hess and Craig Small.
# As a special exception, when this file is copied by dh-make into a
# dh-make output file, you may use that output file without restriction.
# This special exception was added by Craig Small in version 0.37 of dh-make.
#
# Modified to make a template file for a multi-binary package with separated
# build-arch and build-indep targets  by Bill Allombert 2001

# Uncomment this to turn on verbose mode.
export DH_VERBOSE=1

# This has to be exported to make some magic below work.
export DH_OPTIONS


%:
	dh \$@ --buildsystem=cmake

override_dh_auto_test:

#override_dh_installdocs:
#	make -C docs html
#	dh_installdocs docs/_build/html

override_dh_shlibdeps:
	dh_shlibdeps --dpkg-shlibdeps-params=--ignore-missing-info

override_dh_auto_configure:
	dh_auto_configure -- ${CMAKE_OPTIONS}
EOF
cat <<EOF > debian/copyright
Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: z3
Source: https://github.com/Z3Prover/z3

Files: *
Copyright: Microsoft Corporation
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
EOF
cat <<EOF > debian/changelog
z3-static (0.0.1-0ubuntu4) saucy; urgency=low

  * Initial release.

 -- Daniel <daniel@ekpyron.org>  Mon, 03 Jun 2019 14:50:20 +0000
EOF
echo docs > debian/docs
mkdir debian/source
echo "3.0 (quilt)" > debian/source/format
chmod +x debian/rules

versionsuffix=0ubuntu4~${distribution}
EMAIL="$email" dch -v 1:${debversion}-${versionsuffix} "build of ${version}"

# build source package
# If packages is rejected because original source is already present, add
# -sd to remove it from the .changes file
# -d disables the build dependencies check
debuild -S -d -sa -us -uc

# prepare .changes file for Launchpad
sed -i -e s/UNRELEASED/${build_distribution}/ -e s/urgency=medium/urgency=low/ ../*.changes

# check if ubuntu already has the source tarball
(
cd ..
orig=${packagename}_${debversion}.orig.tar.gz
orig_size=$(ls -l $orig | cut -d ' ' -f 5)
orig_sha1=$(sha1sum $orig | cut -d ' ' -f 1)
orig_sha256=$(sha256sum $orig | cut -d ' ' -f 1)
orig_md5=$(md5sum $orig | cut -d ' ' -f 1)

if wget --quiet -O $orig-tmp "$ppafilesurl/$orig"
then
    echo "[WARN] Original tarball found in Ubuntu archive, using it instead"
    mv $orig-tmp $orig
    new_size=$(ls -l *.orig.tar.gz | cut -d ' ' -f 5)
    new_sha1=$(sha1sum $orig | cut -d ' ' -f 1)
    new_sha256=$(sha256sum $orig | cut -d ' ' -f 1)
    new_md5=$(md5sum $orig | cut -d ' ' -f 1)
    sed -i -e s,$orig_sha1,$new_sha1,g -e s,$orig_sha256,$new_sha256,g -e s,$orig_size,$new_size,g -e s,$orig_md5,$new_md5,g *.dsc
    sed -i -e s,$orig_sha1,$new_sha1,g -e s,$orig_sha256,$new_sha256,g -e s,$orig_size,$new_size,g -e s,$orig_md5,$new_md5,g *.changes
fi
)

# sign the package
debsign --re-sign -k ${keyid} ../${packagename}_${debversion}-${versionsuffix}_source.changes

# upload
dput ${pparepo} ../${packagename}_${debversion}-${versionsuffix}_source.changes
