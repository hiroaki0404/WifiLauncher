#!/bin/sh
/usr/bin/perl -e "use Config::Simple;"
if [ $? != 0 ]; then
	exit 112
fi
/usr/bin/ruby -e "require 'rubygems'; require 'html/htmltokenizer';"
if [ $? != 0 ]; then
	exit 113
fi
/usr/bin/ruby -e "require 'rubygems'; require 'httpclient';"
if [ $? != 0 ]; then
	exit 114
fi

