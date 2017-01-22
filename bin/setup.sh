#! /bin/bash --login
PWD=$(pwd)
SOURCE="${BASH_SOURCE[0]}"
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
APD_DIR="$( cd -P "$( dirname "$SOURCE" )/../" && pwd )"

function abort(){
	echo "Task abort, reason: $@"
	exit -1
}

if [[ -z $1 ]]; then
	abort "Ruby version not specified."
fi

rubyver=$1

cd $APD_DIR
echo "==================================="
echo "Setup under $rubyver"
rvm 2>/dev/null 1>/dev/null || abort 'rvm failure.'
rvm reload
echo "Switch to ruby $rubyver"

rm -rvf $APD_DIR/Gemfile.lock $APD_DIR/*/Gemfile.lock

cd $APD_DIR/

rvm use $rubyver || \
	( rvm get stable && \
	  rvm install $rubyver && \
	  rvm use $rubyver ) || \
	  	abort 'ruby env failure.'

echo "Test if bootstrap could be load."
ruby $APD_DIR/common/bootstrap.rb
if [ $? -eq 0 ]; then
	exit
fi
cd $APD_DIR/test/ && \
	( gem install bundle && \
	bundle install ) || \
		abort 'ruby gem lib failure.'

for subdir in $APD_DIR $APD_DIR/*
do
	if [ -f $subdir/Gemfile ]; then
		cd $subdir
		echo "install gem under $( basename $subdir )"
		bundle install || abort 'bundle install failure'
	fi
done

echo "Test if bootstrap could be load again."
ruby $APD_DIR/common/bootstrap.rb
if [ $? -eq 0 ]; then
	exit
fi
abort 'ruby gem lib failure.'
