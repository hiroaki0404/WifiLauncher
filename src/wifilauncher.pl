#!/usr/bin/perl --
#
# $Id$
#
# Command line options are interfaces.
# See the settings file and pick up the command from ESSID
# with parameters:
#  -s status
#	Linkup:   on
#	Linkdown: off
#  -e ESSID
#
# Requires:
#	Config::Simple
#
#
# New BSD License
#
# Copyright (c) 2011  Hiroaki Abe <hiroaki0404@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.


use strict;
use FileHandle;
use IPC::Open2;
use POSIX qw(SIGALRM);
use Config::Simple;
use Sys::Syslog;
use File::Basename qw(basename);

if ($#ARGV != -1) {
    die "Usage:$0\n";
}
my $cfg = new Config::Simple($ENV{"HOME"}."/.wificmd");
if ($cfg == '') {
    die $ENV{"HOME"}."/.wificmd not found\n";
}
my %Config = $cfg->vars();
my @iflist=split(/ /, `echo 'list' |scutil|awk -F / '/Setup.*AirPort/{print \$4;}'`);

my $pid = open2(*Reader, *Writer, "scutil");

POSIX::sigaction(SIGALRM,
		 POSIX::SigAction->new(sub { print Writer "n.cancel\n" }))
    or die "Error setting SIGALRM handler: $!\n";

my $if;
foreach $if(@iflist) {
    chomp($if);
    print Writer "n.add State:/Network/Interface/$if/Link\n";
}
print Writer "n.watch\n";

openlog(basename($0), 'cons,pid', 'local0');
while(<Reader>){
    foreach $if(@iflist) {
	chomp($if);
	my $linkresult = `echo "show State:/Network/Interface/$if/Link" | scutil | awk '/Active/{print \$3;}'`;
	if ($linkresult eq "TRUE\n" ) {
	    $linkresult = "on";
	} else {
	    $linkresult = "off";
	}
	my $essidresult = `echo "show State:/Network/Interface/$if/AirPort" | scutil | awk '/SSID_STR/{print \$3;exit;}'`;
	chomp($essidresult);
	my $cmd = $Config{$essidresult.".cmd"};
	if ($cmd ne '') {
	    my $ret = system($cmd, "-s", $linkresult, "-e", "$essidresult");
	    syslog('info', "$cmd returns $ret");
	}else{
	    print "No command associated to $essidresult.\n";
	    syslog('info', "No command associated to $essidresult.\n");
	}
    }
}
print Writer "n.cancel\n";
close Writer;
close Reader;
closelog();

__END__
