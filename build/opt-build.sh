#!/bin/bash

set -xe

if [[ -z "${TMPDIR}" ]]; then
  TMPDIR=/tmp
fi

set -u

if [ "$#" -lt "1" ] ; then
  echo "Please provide an installation path such as /opt/ICGC"
  exit 1
fi


# get path to this script
SCRIPT_PATH=`dirname $0`;
SCRIPT_PATH=`(cd $SCRIPT_PATH && pwd)`

# get the location to install to
INST_PATH=$1
mkdir -p $1
INST_PATH=`(cd $1 && pwd)`
echo $INST_PATH

# get current directory
INIT_DIR=`pwd`

CPU=`grep -c ^processor /proc/cpuinfo`
if [ $? -eq 0 ]; then
  if [ "$CPU" -gt "6" ]; then
    CPU=6
  fi
else
  CPU=1
fi
echo "Max compilation CPUs set to $CPU"

SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $SETUP_DIR/distro # don't delete the actual distro directory until the very end
mkdir -p $INST_PATH/bin
cd $SETUP_DIR

## biobambam2 first
BB_INST=$INST_PATH/biobambam2
if [ ! -e $SETUP_DIR/bbb2.sucess ]; then
  curl -sSL --retry 10 https://github.com/gt1/biobambam2/releases/download/${VER_BBB2}/biobambam2-${VER_BBB2}-x86_64-etch-linux-gnu.tar.gz > distro.tar.gz
  mkdir -p $BB_INST
  tar --strip-components 3 -C $BB_INST -zxf distro.tar.gz
  rm -f $BB_INST/bin/curl # don't let this file in SSL doesn't work
  rm -rf distro.* distro/*
  touch $SETUP_DIR/bbb2.success
fi

# make sure tools installed can see the install loc of libraries
set +u
export LD_LIBRARY_PATH=`echo $INST_PATH/lib:$LD_LIBRARY_PATH | perl -pe 's/:\$//;'`
export PATH=`echo $INST_PATH/bin:$BB_INST/bin:$PATH | perl -pe 's/:\$//;'`
export MANPATH=`echo $INST_PATH/man:$BB_INST/man:$INST_PATH/share/man:$MANPATH | perl -pe 's/:\$//;'`
export PERL5LIB=`echo $INST_PATH/lib/perl5:$PERL5LIB | perl -pe 's/:\$//;'`
set -u

## INSTALL CPANMINUS
set -eux
curl -sSL https://cpanmin.us/ > $SETUP_DIR/cpanm
perl $SETUP_DIR/cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH App::cpanminus
rm -f $SETUP_DIR/cpanm

## SAMTOOLS (tar.bz2)
if [ ! -e $SETUP_DIR/samtools.success ]; then
  curl -sSL --retry 10 https://github.com/samtools/samtools/releases/download/${VER_SAMTOOLS}/samtools-${VER_SAMTOOLS}.tar.bz2 > distro.tar.bz2
  rm -rf distro/*
  tar --strip-components 1 -C distro -xjf distro.tar.bz2
  cd distro
  ./configure --enable-plugins --enable-libcurl --with-htslib=$INST_PATH --prefix=$INST_PATH
  make clean
  make -j$CPU all
  make install
  cd $SETUP_DIR
  rm -rf distro.* distro/*
  touch $SETUP_DIR/samtools.success
fi

##### DEPS for PCAP - layered on top #####

## build BWA (tar.gz)
if [ ! -e $SETUP_DIR/bwa.success ]; then
  curl -sSL --retry 10 https://github.com/lh3/bwa/archive/${VER_BWA}.tar.gz > distro.tar.gz
  rm -rf distro/*
  tar --strip-components 1 -C distro -zxf distro.tar.gz
  make -C distro -j$CPU
  cp distro/bwa $INST_PATH/bin/.
  rm -rf distro.* distro/*
  touch $SETUP_DIR/bwa.success
fi

## Bio::DB::HTS (tar.gz)
if [ ! -e $SETUP_DIR/Bio-DB-HTS.success ]; then
  ## add perl deps
  cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Module::Build
  cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Bio::Root::Version

  curl -sSL --retry 10 https://github.com/Ensembl/Bio-DB-HTS/archive/${VER_BIODBHTS}.tar.gz > distro.tar.gz
  rm -rf distro/*
  tar --strip-components 1 -C distro -zxf distro.tar.gz
  cd distro
  perl Build.PL --install_base=$INST_PATH --htslib=$INST_PATH
  ./Build
  ./Build test
  ./Build install
  cd $SETUP_DIR
  rm -rf distro.* distro/*
  touch $SETUP_DIR/Bio-DB-HTS.success
fi

cd $HOME
rm -rf $SETUP_DIR
