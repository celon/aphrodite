#! /bin/bash --login
PWD=$(pwd)
SOURCE="${BASH_SOURCE[0]}"
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

$DIR/../bin/setup.sh

cd $DIR

if [[ -z $2 ]]; then
	echo "Full test suites start"
	ruby $DIR/suite/all.rb --verbose
else
	echo "Single test suites start: $2"
	ruby $DIR/suite/all.rb --name $2
fi
cd $PWD
