#!/usr/bin/perl

use strict;
use warnings;

use Cwd;
use Dpkg::Control::Info;
use Dpkg::Deps;




############# Read ENV and ARGV ##############################
# .................. set NETWORK ...........................
my $network = $ENV{'NETWORK'};

# .................. set repopath ...........................
my $repopath = $ARGV[0];
if(-d $repopath){
	if($repopath =~ m/^(.*)$/){
		$repopath = $1;
	}
}
else{
	die "no repository";
}
# .................. set GUI ...........................
my $guibool = 0;
if($ENV{'GUI'}){
	print STDERR "Testing GUI\n";
	$guibool = 1;
}
else{
	print STDERR "No GUI\n";
}
# .................. set APTPROXY ...........................
my $aptproxybool = 0;
if($ENV{'APTPROXY'}){
	$aptproxybool = $ENV{'APTPROXY'};
	print STDERR "Using APT Proxy $aptproxybool\n";
}
else{
	print STDERR "No APT Proxy\n";
	#die "bad";
}

# .................. set TESTING ...........................
my $testingbool = 0;
if($ENV{'TESTING'}){
	print STDERR "Doing Testing only\n";
	$testingbool = 1;
}
else{
	print STDERR "Compiling package\n";
}

my $workdir = getcwd();

mkdir($workdir.'/work') || print STDERR "already made work directory";
$workdir .= '/work';

############ define global vars #######################################

my $uid = $<;
my $gid = $uid;

my @cmd;


sub getdependencies {
	my $curdir = getcwd();
	chdir($repopath);
	my $control = Dpkg::Control::Info->new();
	my $fields = $control->get_source();
	my $build_depends = deps_parse($fields->{'Build-Depends'});
	$build_depends =~ s/\([\>\=0-9a-zA-Z\s\.]+\)//g;
	$build_depends =~ s/,/ /g;
	chdir($curdir);
	return split(/\s+/,$build_depends);
}

sub destroyimage{
	my $id = shift;
	die "no id" unless defined $id && $id =~ m/^([0-9a-fA-F]+)$/;
	#my @c = ('docker','rmi',$id);
	my $output = `docker rmi $id`;
	print STDERR $output;
	
	#`rm -r $workdir/* || echo "nothing to delete"`;
}

sub writerunsh{
	open(my $fh,'>',$workdir.'/run.sh') || die "could not write run.sh";
	print $fh '#!/bin/bash'."\n";
	if($testingbool){
		print $fh "/bin/bash --login\n";
	}
	else{
		print $fh qq{
	exec /src/pkg/run.pl $uid $gid stable upstream
		};
	}
	close($fh);
	my $output = `chmod +x $workdir/run.sh`;
	print STDERR "$output";
	
	# copy run.pl to workdir (becomes /src/pkg/run.pl)
	`cp build/run.pl $workdir/run.pl`;
}

sub buildpackages{
	my $id = shift;
	die "no id" unless defined $id && $id =~ m/^([0-9a-f]+)$/;

	my @extra;
	if(defined $ENV{'DNS'} && $ENV{'DNS'} =~ m/^([\.0-9]+)$/){
		print STDERR "Special DNS=$1\n";
		push(@extra,'--dns',$1);
	}

	# docker run --rm=true -v `pwd`:/src/code -v $tmppath:/src/pkg -it $id
	my @cmd = ('docker','run',@extra,'--rm=true');

	if($guibool){
		push(@cmd,split(/\s/,"-v /tmp/.X11-unix:/tmp/.X11-unix -v /tmp/.XIM-unix:/tmp/.XIM-unix"));
		push(@cmd,split(/\s/,"-v /tmp/.font-unix:/tmp/.font-unix -v /tmp/.ICE-unix:/tmp/.ICE-unix"));
		push(@cmd,split(/\s/,'-e DISPLAY=$DISPLAY'));
	}
	if(defined $network && 0 < length($network)){
		print STDERR "Setting Network=$network\n";
		push(@cmd,split(/\s/,"--network=$network"));
	}

	push(@cmd,'-v',$repopath.':/src/code','-v',$workdir.':/src/pkg','-it',$id);

	if($testingbool){
		print STDERR "Doing bash testing\n";
		exec(@cmd) || die "cannot fork:$!";
		exit(1);	
	}
	else{
		print STDERR "Running from scratch\n";
		my $pid = open(my $fh,'-|',@cmd) || die "cannot fork:$!";
		while(<$fh>){
			print "$_";
		}
		waitpid($pid,0);
	}

}


my @basedeps = ('git-buildpackage','devscripts','build-essential','make','libprivileges-drop-perl','sudo');

# TODO: get this from debian/changelog
my $maintainer = 'Joel De Jesus "dejesus.joel@e-flamingo.net"';

my $baseimg = '';


# get the architecture
print STDERR "Getting the architecture\n";
my $arch = `uname -a`;
if($arch =~ m/amd64/){
	$arch = 'amd64';
	$baseimg = 'base:jessie';
}
elsif($arch =~ m/armhf/){
	$arch = 'armhf';
	$baseimg = 'raspbian:jessie';
}
else{
	die "bad arch";
}


# build the run.sh script
open(my $fh,'>',$workdir.'/Dockerfile') || die "failed to open file($workdir): $!";
print $fh qq{
	FROM $baseimg
	MAINTAINER $maintainer
	ENV DEBIAN_FRONTEND noninteractive
};

my @deparray = getdependencies();
writerunsh();
die "no dependencies, double check" unless 0 < scalar(@deparray);
print $fh 'ARG proxy'."\n";
print $fh 'RUN if [ -z ${proxy+x} ]; then echo "no apt proxy" 1>&2; else echo "Acquire::http::Proxy \"http://$proxy\";" > /etc/apt/apt.conf.d/proxy.conf && echo "got proxy=$proxy" 1>&2 ; fi'."\n";
print $fh "ADD run.sh /usr/local/bin/run.sh\n";
print $fh join(' ','RUN','apt-get','update','&&','apt-get','install','-y',@deparray,@basedeps)."\n";
print $fh "RUN groupadd -g $gid builder && useradd -s /bin/bash -u $uid -g $gid -m builder && chmod +x /usr/local/bin/run.sh\n";
print $fh 'CMD ["/usr/local/bin/run.sh"]'."\n";
close($fh);

########### build image ################################################
print STDERR "building container\n";

my $imgname = 'builder:'.time();
@cmd = ('docker','build','--force-rm=true');

if($aptproxybool){
	push(@cmd,'--build-arg','proxy='.$aptproxybool);
}
if(defined $network && 0 < length($network)){
	print STDERR "Setting Network=$network\n";
	push(@cmd,split(/\s/,"--network $network"));
}
push(@cmd,'-t',$imgname,'-f',"$workdir/Dockerfile",$workdir);
$fh = undef;
my $pid = open($fh,'-|',@cmd) || die "bad fork:$!";
my $image_id = '';
while(my $line = <$fh>){
	print STDERR "$line"; 
	$image_id = $line;
}
chomp($image_id);

if($image_id =~ m/([0-9a-zA-Z]+)$/){
	$image_id = $1;
}
waitpid($pid,0);
print STDERR "Unlinking run.sh\n";
unlink($workdir.'/run.sh');
print STDERR "Image ID=$image_id\n";

######## build package in new container ##################################
buildpackages($image_id);

######## do clean up #####################################################
print STDERR "Doing clean up\n";
print STDERR "..Deleting image\n";
destroyimage($image_id);






