#!/usr/bin/perl -w
#
# Project Builder CMS module
# CMS subroutines brought by the the Project-Builder project
# which can be easily used by pbinit scripts
#
# $Id$
#
# Copyright B. Cornec 2007-2012
# Eric Anderson's changes are (c) Copyright 2012 Hewlett Packard
# Provided under the GPL v2

package ProjectBuilder::CMS;

use strict 'vars';
use Carp 'confess';
use Data::Dumper;
use English;
use File::Basename;
use File::Copy;
use POSIX qw(strftime);
use lib qw (lib);
use ProjectBuilder::Version;
use ProjectBuilder::Base;
use ProjectBuilder::Conf;
use ProjectBuilder::VCS;

# Inherit from the "Exporter" module which handles exporting functions.
 
use vars qw($VERSION $REVISION @ISA @EXPORT);
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_cms_init pb_cms_checkin pb_cms_get_pkg pb_cms_get_real_pkg pb_cms_compliant pb_cms_log);
($VERSION,$REVISION) = pb_version_init();

=pod

=head1 NAME

ProjectBuilder::CMS, part of the project-builder.org

=head1 DESCRIPTION

This modules provides configuration management system functions suitable for pbinit calls.

=head1 USAGE

=over 4

=item B<pb_cms_init>

This function setup the environment for the CMS system related to the URL given by the pburl configuration parameter.
The potential parameter indicates whether we should inititate the context or not.
It sets up environement variables (PBPROJDIR, PBDIR, PBREVISION, PBCMSLOGFILE) 

=cut

sub pb_cms_init {

my $pbinit = shift || undef;
my $param = shift || undef;

my ($pburl) = pb_conf_get("pburl");
pb_log(2,"DEBUG: Project URL of $ENV{'PBPROJ'}: $pburl->{$ENV{'PBPROJ'}}\n");
my ($scheme, $account, $host, $port, $path) = pb_get_uri($pburl->{$ENV{'PBPROJ'}});
my $vcscmd = pb_vcs_cmd($scheme);

my ($pbprojdir) = pb_conf_get_if("pbprojdir");

if ((defined $pbprojdir) && (defined $pbprojdir->{$ENV{'PBPROJ'}})) {
	$ENV{'PBPROJDIR'} = $pbprojdir->{$ENV{'PBPROJ'}};
} else {
	$ENV{'PBPROJDIR'} = "$ENV{'PBDEFDIR'}/$ENV{'PBPROJ'}";
}
# Expand potential env variable in it to allow string replacement
eval { $ENV{'PBPROJDIR'} =~ s/(\$ENV.+\})/$1/eeg };


# Computing the default dir for PBDIR.
# what we have is PBPROJDIR so work from that.
# Tree identical between PBCONFDIR and PBROOTDIR on one side and
# PBPROJDIR and PBDIR on the other side.

my $tmp = $ENV{'PBROOTDIR'};
$tmp =~ s|^$ENV{'PBCONFDIR'}/||;

#
# Check project cms compliance
#
my $turl = "$pburl->{$ENV{'PBPROJ'}}/$tmp";
$turl = $pburl->{$ENV{'PBPROJ'}} if ($scheme =~ /^(flat)|(ftp)|(http)|(file)\b/o);
pb_cms_compliant(undef,'PBDIR',"$ENV{'PBPROJDIR'}/$tmp",$turl,$pbinit);


if ($scheme =~ /^hg/) {
	$tmp = `(cd "$ENV{'PBDIR'}" ; $vcscmd identify )`;
	chomp($tmp);
	$tmp =~ s/^.* //;
	$ENV{'PBREVISION'}=$tmp;
	$ENV{'PBCMSLOGFILE'}="hg.log";
} elsif ($scheme =~ /^git/) {
	$tmp = `(cd "$ENV{'PBDIR'}" ; $vcscmd log | head -1 | cut -f2)`;
	chomp($tmp);
	$tmp =~ s/^.* //;
	$ENV{'PBREVISION'}=$tmp;
	$ENV{'PBCMSLOGFILE'}="git.log";
} elsif ($scheme =~ /^(flat)|(ftp)|(http)|(file)\b/o) {
	$ENV{'PBREVISION'}="flat";
	$ENV{'PBCMSLOGFILE'}="flat.log";
} elsif ($scheme =~ /^svn/) {
	# svnversion more precise than svn info if sbx
	if ((defined $param) && ($param eq "CMS")) {
		$tmp = `(LANGUAGE=C $vcscmd info $pburl->{$ENV{'PBPROJ'}} | grep -E '^Revision:' | cut -d: -f2)`;
		$tmp =~ s/\s+//;
	} else {
		$tmp = `(cd "$ENV{'PBDIR'}" ; $vcscmd"version" .)`;
	}
	chomp($tmp);
	$ENV{'PBREVISION'}=$tmp;
	$ENV{'PBCMSLOGFILE'}="svn.log";
} elsif ($scheme =~ /^svk/) {
	$tmp = `(cd "$ENV{'PBDIR'}" ; LANGUAGE=C $vcscmd info . | grep -E '^Revision:' | cut -d: -f2)`;
	$tmp =~ s/\s+//;
	chomp($tmp);
	$ENV{'PBREVISION'}=$tmp;
	$ENV{'PBCMSLOGFILE'}="svk.log";
} elsif ($scheme =~ /^cvs/) {
	# Way too slow
	#$ENV{'PBREVISION'}=`(cd "$ENV{'PBROOTDIR'}" ; cvs rannotate  -f . 2>&1 | awk '{print \$1}' | grep -E '^[0-9]' | cut -d. -f2 |sort -nu | tail -1)`;
	#chomp($ENV{'PBREVISION'});
	$ENV{'PBREVISION'}="cvs";
	$ENV{'PBCMSLOGFILE'}="cvs.log";
	$ENV{'CVS_RSH'} = "ssh" if ($scheme =~ /ssh/);
} else {
	die "cms $scheme unknown";
}

pb_log(1,"pb_cms_init returns $scheme,$pburl->{$ENV{'PBPROJ'}}\n");
return($scheme,$pburl->{$ENV{'PBPROJ'}});
}

=item B<pb_cms_checkin>

This function updates a CMS content from a local directory.
The first parameter is the schema of the CMS systems (svn, cvs, svn+ssh, ...)
The second parameter is the directory to update from.
The third parameter indicates if we are in a new version creation (undef) or in a new project creation (1)

=cut

sub pb_cms_checkin {
my $scheme = shift;
my $dir = shift;
my $pbinit = shift || undef;

my $ver = basename($dir);
my $msg = "updated to $ver";
$msg = "Project $ENV{'PBPROJ'} creation" if (defined $pbinit);

pb_vcs_checkin($scheme,$dir,$msg);
}

=item B<pb_cms_get_pkg>

This function returns the list of packages we are working on in a CMS action.
The first parameter is the default list of packages from the configuration file.
The second parameter is the optional list of packages from the configuration file.

=cut

sub pb_cms_get_pkg {

my @pkgs = ();
my $defpkgdir = shift || undef;
my $extpkgdir = shift || undef;

# Get packages list
if (not defined $ARGV[0]) {
	@pkgs = keys %$defpkgdir if (defined $defpkgdir);
} elsif ($ARGV[0] =~ /^all$/) {
	@pkgs = keys %$defpkgdir if (defined $defpkgdir);
	push(@pkgs, keys %$extpkgdir) if (defined $extpkgdir);
} else {
	@pkgs = @ARGV;
}
pb_log(0,"Packages: ".join(',',@pkgs)."\n");
return(\@pkgs);
}

=item B<pb_cms_get_real_pkg>

This function returns the real name of a virtual package we are working on in a CMS action.
It supports the following types: perl.
The first parameter is the virtual package name

=cut

sub pb_cms_get_real_pkg {

my $pbpkg = shift || undef;
my $dtype = shift;
my $pbpkgreal = $pbpkg;

my @nametype = pb_conf_get_if("namingtype");
my $type = $nametype[0]->{$pbpkg};
if (defined $type) {
	if ($type eq "perl") {
		if ($dtype eq "rpm") {
			$pbpkgreal = "perl-".$pbpkg;
		} elsif ($dtype eq "deb") {
			# Only lower case allowed in Debian
			# Cf: http://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-Package
			$pbpkgreal = "lib".lc($pbpkg)."-perl";
		} elsif ($dtype eq "ebuild") {
			$pbpkgreal = $pbpkg;
		} elsif ($dtype eq "hpux") {
			$pbpkgreal = $pbpkg;
		} elsif ($dtype eq "pkg") {
			$pbpkgreal = "PB$pbpkg";
		} else {
			die "pb_cms_get_real_pkg not implemented for $dtype yet";
		}
	} else {
		die "nametype $type not implemented yet";
	}
}

pb_log(2,"pb_cms_get_real_pkg returns $pbpkgreal\n");
return($pbpkgreal);
}

=item B<pb_cms_compliant>

This function checks the compliance of the project and the pbconf directory.
The first parameter is the key name of the value that needs to be read in the configuration file.
The second parameter is the environment variable this key will populate.
The third parameter is the location of the pbconf dir.
The fourth parameter is the URI of the CMS content related to the pbconf dir.
The fifth parameter indicates whether we should inititate the context or not.

=cut

sub pb_cms_compliant {

my $param = shift;
my $envar = shift;
my $defdir = shift;
my $uri = shift;
my $pbinit = shift;
my %pdir;

pb_log(1,"pb_cms_compliant: envar: $envar - defdir: $defdir - uri: $uri\n");
my ($pdir) = pb_conf_get_if($param) if (defined $param);
if (defined $pdir) {
	%pdir = %$pdir;
}


if ((defined $pdir) && (%pdir) && (defined $pdir{$ENV{'PBPROJ'}})) {
	# That's always the environment variable that will be used
	$ENV{$envar} = $pdir{$ENV{'PBPROJ'}};
} else {
	if (defined $param) {
		pb_log(1,"WARNING: no $param defined, using $defdir\n");
		pb_log(1,"         Please create a $param reference for project $ENV{'PBPROJ'} in $ENV{'PBETC'}\n");
		pb_log(1,"         if you want to use another directory\n");
	}
	$ENV{$envar} = "$defdir";
}

# Expand potential env variable in it
eval { $ENV{$envar} =~ s/(\$ENV.+\})/$1/eeg };
pb_log(2,"$envar: $ENV{$envar}\n");

my ($scheme, $account, $host, $port, $path) = pb_get_uri($uri);

if (($scheme !~ /^cvs/) && ($scheme !~ /^svn/) && ($scheme !~ /^svk/) && ($scheme !~ /^hg/) && ($scheme !~ /^git/)) {
	# Do not compare if it's not a real cms
	pb_log(1,"pb_cms_compliant useless\n");
	return;
} elsif (defined $pbinit) {
	pb_mkdir_p("$ENV{$envar}");
} elsif (! -d "$ENV{$envar}") {
	# Either we have a version in the uri, and it should be the same
	# as the one in the envar. Or we should add the version to the uri
	if (basename($uri) ne basename($ENV{$envar})) {
		$uri .= "/".basename($ENV{$envar})
	}
	pb_log(1,"Checking out $uri\n");
	# Create structure and remove end dir before exporting
	pb_mkdir_p("$ENV{$envar}");
	pb_rm_rf($ENV{$envar});
	pb_vcs_checkout($scheme,$uri,$ENV{$envar});
} else {
	pb_log(1,"$uri found locally, checking content\n");
	my $cmsurl = pb_vcs_get_uri($scheme,$ENV{$envar});
	my ($scheme2, $account2, $host2, $port2, $path2) = pb_get_uri($cmsurl);
	# For svk, scheme doesn't appear in svk info so remove it here in uri coming from conf file 
	# which needs it to trigger correct behaviour
	$uri =~ s/^svk://;
	if (($scheme2 =~ /^git/) || ($scheme2 =~ /^hg/)) {
		# These VCS manage branches internally not with different tree structures
		# Assuming it's correct for now.
	} elsif ($cmsurl ne $uri) {
		# The local content doesn't correpond to the repository
		pb_log(0,"ERROR: Inconsistency detected:\n");
		pb_log(0,"       * $ENV{$envar} ($envar) refers to $cmsurl but\n");
		pb_log(0,"       * $ENV{'PBETC'} refers to $uri\n");
		die "Project $ENV{'PBPROJ'} is not Project-Builder compliant.";
	} else {
		pb_log(1,"Content correct - doing nothing - you may want to update your repository however\n");
		# they match - do nothing - there may be local changes
	}
}
pb_log(1,"pb_cms_compliant end\n");
}

=item B<pb_cms_create_authors>

This function creates a AUTHORS files for the project. It call it AUTHORS.pb if an AUTHORS file already exists.
The first parameter is the source file for authors information.
The second parameter is the directory where to create the final AUTHORS file.
The third parameter is the schema of the CMS systems (svn, cvs, svn+ssh, ...)

=cut

sub pb_cms_create_authors {

my $authors=shift;
my $dest=shift;
my $scheme=shift;

return if ($authors eq "/dev/null");
open(SAUTH,$authors) || die "Unable to open $authors";
# Save a potentially existing AUTHORS file and write instead to AUTHORS.pb 
my $ext = "";
if (-f "$dest/AUTHORS") {
	$ext = ".pb";
}
open(DAUTH,"> $dest/AUTHORS$ext") || die "Unable to create $dest/AUTHORS$ext";
print DAUTH "Authors of the project are:\n";
print DAUTH "===========================\n";
while (<SAUTH>) {
	my ($nick,$gcos) = split(/:/);
	chomp($gcos);
	print DAUTH "$gcos";
	if (defined $scheme) {
		# Do not give a scheme for flat types
		my $endstr="";
		if ("$ENV{'PBREVISION'}" ne "flat") {
			$endstr = " under $scheme";
		}
		print DAUTH " ($nick$endstr)\n";
	} else {
		print DAUTH "\n";
	}
}
close(DAUTH);
close(SAUTH);
}

=item B<pb_cms_log>

This function creates a ChangeLog file for the project.
The first parameter is the schema of the CMS systems (svn, cvs, svn+ssh, ...)
The second parameter is the directory where the CMS content was checked out.
The third parameter is the directory where to create the final ChangeLog file.
The fourth parameter is unused.
The fifth parameter is the source file for authors information.

It may use a tool like svn2cl or cvs2cl to generate it if present, or the log file from the CMS if not.

=cut


sub pb_cms_log {

my $scheme = shift;
my $pkgdir = shift;
my $dest = shift;
my $chglog = shift;
my $authors = shift;
my $testver = shift || undef;

pb_cms_create_authors($authors,$dest,$scheme);
my $vcscmd = pb_vcs_cmd($scheme);

if ((defined $testver) && (defined $testver->{$ENV{'PBPROJ'}}) && ($testver->{$ENV{'PBPROJ'}} =~ /true/i)) {
	if (! -f "$dest/ChangeLog") {
		open(CL,"> $dest/ChangeLog") || confess "Unable to create $dest/ChangeLog";
		# We need a minimal version for debian type of build
		print CL "\n";
		print CL "\n";
		print CL "\n";
		print CL "\n";
		print CL "1990-01-01  none\n";
		print CL "\n";
		print CL "        * test version\n";
		print CL "\n";
		close(CL);
		pb_log(0,"Generating fake ChangeLog for test version\n");
		open(CL,"> $dest/$ENV{'PBCMSLOGFILE'}") || die "Unable to create $dest/$ENV{'PBCMSLOGFILE'}";
		close(CL);
	}
}

if (! -f "$dest/ChangeLog") {
	if ($scheme =~ /^svn/) {
		# In case we have no network, just create an empty one before to allow correct build
		open(CL,"> $dest/ChangeLog") || die "Unable to create $dest/ChangeLog";
		close(CL);
		my $command = pb_check_req("svn2cl",1);
		if ((defined $command) && (-x $command)) {
			pb_system("$command --group-by-day --authors=$authors -i -o $dest/ChangeLog $pkgdir","Generating ChangeLog from SVN with svn2cl");
		} else {
			# To be written from pbcl
			pb_system("$vcscmd log -v $pkgdir > $dest/$ENV{'PBCMSLOGFILE'}","Extracting log info from SVN");
		}
	} elsif ($scheme =~ /^svk/) {
		pb_system("$vcscmd log -v $pkgdir > $dest/$ENV{'PBCMSLOGFILE'}","Extracting log info from SVK");
	} elsif ($scheme =~ /^hg/) {
		# In case we have no network, just create an empty one before to allow correct build
		open(CL,"> $dest/ChangeLog") || die "Unable to create $dest/ChangeLog";
		close(CL);
		pb_system("$vcscmd log -v $pkgdir > $dest/$ENV{'PBCMSLOGFILE'}","Extracting log info from Mercurial");
	} elsif ($scheme =~ /^git/) {
		# In case we have no network, just create an empty one before to allow correct build
		open(CL,"> $dest/ChangeLog") || die "Unable to create $dest/ChangeLog";
		close(CL);
		pb_system("$vcscmd log -v $pkgdir > $dest/$ENV{'PBCMSLOGFILE'}","Extracting log info from GIT");
	} elsif ($scheme =~ /^(flat)|(ftp)|(http)|(file)|(dir)\b/o) {
		pb_system("echo ChangeLog for $pkgdir > $dest/ChangeLog","Empty ChangeLog file created");
	} elsif ($scheme =~ /^cvs/) {
		my $tmp=basename($pkgdir);
		# CVS needs a relative path !
		# In case we have no network, just create an empty one before to allow correct build
		open(CL,"> $dest/ChangeLog") || die "Unable to create $dest/ChangeLog";
		close(CL);
		my $command = pb_check_req("cvs2cl",1);
		if (-x $command) {
			pb_system("$command --group-by-day -U $authors -f $dest/ChangeLog $pkgdir","Generating ChangeLog from CVS with cvs2cl");
		} else {
			# To be written from pbcl
			pb_system("$vcscmd log $tmp > $dest/$ENV{'PBCMSLOGFILE'}","Extracting log info from CVS");
		}
	} else {
		die "cms $scheme unknown";
	}
}
if (! -f "$dest/ChangeLog") {
	copy("$dest/$ENV{'PBCMSLOGFILE'}","$dest/ChangeLog");
}
}

=back 

=head1 WEB SITES

The main Web site of the project is available at L<http://www.project-builder.org/>. Bug reports should be filled using the trac instance of the project at L<http://trac.project-builder.org/>.

=head1 USER MAILING LIST

None exists for the moment.

=head1 AUTHORS

The Project-Builder.org team L<http://trac.project-builder.org/> lead by Bruno Cornec L<mailto:bruno@project-builder.org>.

=head1 COPYRIGHT

Project-Builder.org is distributed under the GPL v2.0 license
described in the file C<COPYING> included with the distribution.

=cut

1;
