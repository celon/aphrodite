#! /bin/bash --login
PWD=$(pwd)
SOURCE="${BASH_SOURCE[0]}"
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

function abort(){
	echo "Task abort, reason: $@"
	exit -1
}

if [[ -z $1 ]]; then
	abort "Ruby version not specified."
fi

rubyver=$1

cd $DIR
echo "==================================="
echo "Testing under $rubyver"
rvm 2>/dev/null 1>/dev/null || abort 'rvm failure.'
rvm use $rubyver || ( rvm install $rubyver && rvm use $rubyver ) || abort 'ruby env failure.'
rm -rf $DIR/../Gemfile.lock $DIR/Gemfile.lock 2>&1 > /dev/null
cd $DIR
bundle install 2>/dev/null 1>/dev/null || abort 'bundler install failure'
ruby $DIR/suite/all.rb
cd $PWD
