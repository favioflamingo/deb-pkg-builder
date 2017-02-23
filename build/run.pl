#!/usr/bin/perl

use strict;
use warnings;

#use Privileges::Drop;

# run.pl 8 8 stable upstream

#print STDERR "Dropping privileges\n";
#`chown -R builder:builder /root/.config`;
#Privileges::Drop::drop_uidgid($ARGV[0], $ARGV[1]);

my ($debian,$upstream) = ($ARGV[2],$ARGV[3]);

if($debian =~ m/^([0-9a-zA-Z\.\-]+)$/){
	$debian = $1;
}
else{
	die "bad value for debian branch";
}

if($upstream =~ m/^([0-9a-zA-Z\.\-]+)$/){
	$upstream = $1;
}
else{
	die "bad value for upstream branch";
}

chdir('/src/code') || die "cannot complete script: $!";

`ls 1>&2`;


system('git','checkout',$debian);

my @cmd = ('gbp','buildpackage','--git-debian-branch='.$debian,'--git-export-dir=/src/pkg', 
  '--git-upstream-branch='.$upstream,'--git-upstream-tree='.$upstream,'--git-force-create',
  '--git-tag');
  
print STDERR "Forking and beginning build process\n";
my $pid = fork();
if($pid == 0){
	print STDERR "Running ".join(' ',@cmd)."\n";
	exec(@cmd) || die "could not fork:$!";
	exit(1);
}

waitpid($pid,0);


__END__

