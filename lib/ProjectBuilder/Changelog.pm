#!/usr/bin/perl -w
#
# ProjectBuilder Changelog module
# Changelog management subroutines brought by the the Project-Builder project
#
# $Id$
#
# Copyright B. Cornec 2007
# Provided under the GPL v2

package ProjectBuilder::Changelog;

use strict 'vars';
use Data::Dumper;
use English;
use Date::Manip;
use POSIX qw(strftime);
use lib qw (lib);
use ProjectBuilder::Base;
use ProjectBuilder::Conf;

# Inherit from the "Exporter" module which handles exporting functions.
 
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_changelog);

=pod

=head1 NAME

ProjectBuilder::Changelog, part of the project-builder.org - module dealing with changelog management

=head1 DESCRIPTION

This modules provides generic functions suitable for changelog management for project-builder.org

=head1 USAGE

=over 4

=item B<pb_changelog>

Function that generates the changelog used in build files, or for announcements (web, mailing-list, ...)

It takes up to 9 parameters:
The first parameter is the type of the distribution.
The second parameter is the package name generated.
The third parameter is the version of the package.
The fourth parameter is the tag of the package.
The fifth parameter is the suffix of the package.
The sixth parameter is now unused.
The seventh parameter is the file descriptor on which to write the changelog content.
The eighth parameter is a flag in the configuration file indicating whether we want changelog expansion or not.
The nineth parameter is the potential changelog file pbcl.

=cut

sub pb_changelog {

my $pb = shift;
my $dtype = $pb->{'dtype'};
my $pbrealpkg = $pb->{'realpkg'};
my $pbver = $pb->{'ver'};
my $pbtag = $pb->{'tag'};
my $pbsuf = $pb->{'suf'};
my $OUTPUT = shift;
my $doit = shift;
my $chglog = $pb->{'chglog'} || undef;

my $log = "";

# For date handling
$ENV{LANG}="C";

if ((not (defined $dtype)) || ($dtype eq "") || 
		(not (defined $pbrealpkg)) || ($pbrealpkg eq "") || 
		(not (defined $pbver)) || ($pbver eq "") || 
		(not (defined $pbtag)) || ($pbtag eq "") || 
		(not (defined $pbsuf)) || ($pbsuf eq "") || 
		(not (defined $OUTPUT)) || ($OUTPUT eq "") ||
		(not (defined $doit)) || ($doit eq "")) {
	print $OUTPUT "\n";
	return;
}

if (((not defined $chglog) || (! -f $chglog)) && ($doit eq "yes")) {
	#pb_log(2,"No ChangeLog file ($chglog) for $pbrealpkg\n";
	print $OUTPUT "\n";
	return;
}

my $date;
my $ndate;
my $n2date;
my $ver;
my $ver2;
my ($pbpackager) = pb_conf_get("pbpackager");

if (not defined $pbpackager->{$ENV{'PBPROJ'}}) {
	$pbpackager->{$ENV{'PBPROJ'}} = "undefined\@noproject.noorg";
}

my @date = pb_get_date();
# If we don't need to do it, or don't have it fake something
if (((not defined $chglog) || (! -f $chglog)) && ($doit ne "yes")) {
	$date = strftime("%Y-%m-%d", @date);
	$ndate = &UnixDate($date,"%a", "%b", "%d", "%Y");
	$n2date = &UnixDate($date,"%a, %d %b %Y %H:%M:%S %z");
	if (($dtype eq "rpm") || ($dtype eq "fc")) {
		$ver2 = "$pbver-$pbtag";
		print $OUTPUT "* $ndate $pbpackager->{$ENV{'PBPROJ'}} $ver2\n";
		print $OUTPUT "- Updated to $pbver\n";
		}
	if ($dtype eq "deb") {
		if ($pbver !~ /^[0-9]/) {
			# dpkg-deb doesn't accept non digit versions. Prepending date
			my $ldate = strftime("%Y%m%d", @date);
			$pbver =~ s/^/$ldate/;
		}
		print $OUTPUT "$pbrealpkg ($pbver) unstable; urgency=low\n";
		print $OUTPUT "\n";
		print $OUTPUT " -- $pbpackager->{$ENV{'PBPROJ'}}  $n2date\n\n\n";
		}
	return;
}

open(INPUT,"$chglog") || die "Unable to open $chglog (read)";

# Skip first 4 lines
my $tmp = <INPUT>;
$tmp = <INPUT>;
$tmp = <INPUT>;
if ($dtype eq "announce") {
	chomp($tmp);
	print $OUTPUT "$tmp<br>\n";
}
$tmp = <INPUT>;
if ($dtype eq "announce") {
	chomp($tmp);
	print $OUTPUT "$tmp<br>\n";
}

my $first=1;

# Handle each block separated by newline
while (<INPUT>) {
	($ver, $date) = split(/ /);
	$ver =~ s/^v//;
	chomp($date);
	$date =~ s/\(([0-9-]+)\)/$1/;
	#pb_log(2,"**$date**\n";
	$ndate = UnixDate($date,"%a", "%b", "%d", "%Y");
	$n2date = UnixDate($date,"%a, %d %b %Y %H:%M:%S %z");
	#pb_log(2,"**$ndate**\n";

	if (($dtype eq "rpm") || ($dtype eq "fc")) {
		if ($ver !~ /-/) {
			if ($first eq 1) {
				$ver2 = "$ver-$pbtag";
				$first=0;
			} else {
				$ver2 = "$ver-1";
			}
		} else {
			$ver2 = "$ver";
		}
		print $OUTPUT "* $ndate $pbpackager->{$ENV{'PBPROJ'}} $ver2\n";
		print $OUTPUT "- Updated to $ver\n";
		}
	if ($dtype eq "deb") {
		if ($ver !~ /^[0-9]/) {
			# dpkg-deb doesn't accept non digit versions. Prepending date
			my $ldate = strftime("%Y%m%d", @date);
			$ver =~ s/^/$ldate/;
		}
		print $OUTPUT "$pbrealpkg ($ver) unstable; urgency=low\n";
		print $OUTPUT "\n";
		}

	$tmp = <INPUT>;	
	while ($tmp !~ /^$/) {
		if ($dtype eq "deb") {
			$tmp =~ s/^- //;
			print $OUTPUT "  * $tmp";
		} elsif ($dtype eq "rpm") {
			print $OUTPUT "$tmp";
		} else {
			chomp($tmp);
			print $OUTPUT "$tmp<br>\n";
		}
		last if (eof(INPUT));
		$tmp = <INPUT>;
	}
	print $OUTPUT "\n";

	if ($dtype eq "deb") {
		# Cf: http://www.debian.org/doc/debian-policy/ch-source.html#s-dpkgchangelog
		print $OUTPUT " -- $pbpackager->{$ENV{'PBPROJ'}}  $n2date\n\n\n";
		}

	last if (eof(INPUT));
	last if ($dtype eq "announce");
}
close(INPUT);
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
