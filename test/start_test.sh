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
echo "Test under $rubyver"
rvm 2>/dev/null 1>/dev/null || abort 'rvm failure.'
rvm reload
echo "Switch to ruby $rubyver"

rm -rf $DIR/../Gemfile.lock $DIR/Gemfile.lock 2>&1 > /dev/null
rvm use $rubyver || \
	( rvm get stable && \
	  rvm install $rubyver && \
	  rvm use $rubyver && \
	  gem install bundle && \
	  bundle install ) || \
	  	abort 'ruby env failure.'

echo "Test if bootstrap could be load."
ruby $DIR/../common/bootstrap.rb || \
	( gem install bundle && \
	  bundle install ) || \
	  	abort 'ruby gem lib failure.'

cd $DIR

if [[ -z $2 ]]; then
	echo "Full test suites start"
	ruby $DIR/suite/all.rb
else
	echo "Single test suites start: $2"
	ruby $DIR/suite/all.rb --name $2
fi
cd $PWD
