#!/usr/bin/perl -w
#
# ProjectBuilder Filter module
# Filtering subroutines brought by the the Project-Builder project
# which can be easily used by pbinit
#
# $Id$
#
# Copyright B. Cornec 2007
# Provided under the GPL v2

package ProjectBuilder::Filter;

use strict 'vars';
use Data::Dumper;
use English;
use File::Basename;
use File::Copy;
use lib qw (lib);
use ProjectBuilder::Base;
use ProjectBuilder::Changelog;

# Inherit from the "Exporter" module which handles exporting functions.
 
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
 
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_get_filters pb_filter_file_pb pb_filter_file_inplace pb_filter_file);

=pod

=head1 NAME

ProjectBuilder::Filter, part of the project-builder.org

=head1 DESCRIPTION

This module provides filtering functions suitable for pbinit calls.

=over 4

=item B<pb_get_filters>

This function gets all filters to apply. They're cumulative from the less specific to the most specific.

Suffix of those filters is .pbf. Filter all.pbf applies to whatever distribution. The pbfilter directory may be global under pbconf or per package, for overloading values. Then in order filters are loaded for distribution type, distribution family, distribution name, distribution name-version.

The first parameter is the package name.
The second parameter is the distribution type.
The third parameter is the distribution family.
The fourth parameter is the distribution name.
The fifth parameter is the distribution version.

The function returns a pointer on a hash of filters.

=cut

sub pb_get_filters {

my @ffiles;
my ($ffile00, $ffile0, $ffile1, $ffile2, $ffile3);
my ($mfile00, $mfile0, $mfile1, $mfile2, $mfile3);
my $pbpkg = shift || die "No package specified";
my $dtype = shift || "";
my $dfam = shift || "";
my $ddir = shift || "";
my $dver = shift || "";
my $ptr = undef; # returned value pointer on the hash of filters
my %h;

# Global filter files first, then package specificities
if (-d "$ENV{'PBROOTDIR'}/pbfilter") {
	$mfile00 = "$ENV{'PBROOTDIR'}/pbfilter/all.pbf" if (-f "$ENV{'PBROOTDIR'}/pbfilter/all.pbf");
	$mfile0 = "$ENV{'PBROOTDIR'}/pbfilter/$dtype.pbf" if (-f "$ENV{'PBROOTDIR'}/pbfilter/$dtype.pbf");
	$mfile1 = "$ENV{'PBROOTDIR'}/pbfilter/$dfam.pbf" if (-f "$ENV{'PBROOTDIR'}/pbfilter/$dfam.pbf");
	$mfile2 = "$ENV{'PBROOTDIR'}/pbfilter/$ddir.pbf" if (-f "$ENV{'PBROOTDIR'}/pbfilter/$ddir.pbf");
	$mfile3 = "$ENV{'PBROOTDIR'}/pbfilter/$ddir-$dver.pbf" if (-f "$ENV{'PBROOTDIR'}/pbfilter/$ddir-$dver.pbf");

	push @ffiles,$mfile00 if (defined $mfile00);
	push @ffiles,$mfile0 if (defined $mfile0);
	push @ffiles,$mfile1 if (defined $mfile1);
	push @ffiles,$mfile2 if (defined $mfile2);
	push @ffiles,$mfile3 if (defined $mfile3);
}

if (-d "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter") {
	$ffile00 = "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/all.pbf" if (-f "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/all.pbf");
	$ffile0 = "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$dtype.pbf" if (-f "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$dtype.pbf");
	$ffile1 = "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$dfam.pbf" if (-f "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$dfam.pbf");
	$ffile2 = "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$ddir.pbf" if (-f "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$ddir.pbf");
	$ffile3 = "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$ddir-$dver.pbf" if (-f "$ENV{'PBROOTDIR'}/$pbpkg/pbfilter/$ddir-$dver.pbf");

	push @ffiles,$ffile00 if (defined $ffile00);
	push @ffiles,$ffile0 if (defined $ffile0);
	push @ffiles,$ffile1 if (defined $ffile1);
	push @ffiles,$ffile2 if (defined $ffile2);
	push @ffiles,$ffile3 if (defined $ffile3);
}
if (@ffiles) {
	pb_log(2,"DEBUG ffiles: ".Dumper(\@ffiles)."\n");

	foreach my $f (@ffiles) {
		open(CONF,$f) || next;
		while(<CONF>)  {
			if (/^\s*([A-z0-9-_]+)\s+([[A-z0-9-_]+)\s*=\s*(.+)$/) {
				$h{$1}{$2}=$3;
			}
		}
		close(CONF);

		$ptr = $h{"filter"};
		pb_log(2,"DEBUG f:".Dumper($ptr)."\n");
	}
}
return($ptr);
}

=item B<pb_filter_file>

This function applies all filters to files.

It takes 4 parameters.

The first parameter is the file to filter.
The second parameter is the pointer on the hash of filters.
The third parameter is the destination file after filtering.
The fourth parameter is the pointer on the hash of variables to filter (tag, ver, ...)

=cut

sub pb_filter_file {

my $f=shift;
my $ptr=shift;
my %filter=%$ptr;
my $destfile=shift;
my $pb=shift;

pb_log(2,"DEBUG: From $f to $destfile\n");
pb_mkdir_p(dirname($destfile)) if (! -d dirname($destfile));
open(DEST,"> $destfile") || die "Unable to create $destfile: $!";
open(FILE,"$f") || die "Unable to open $f: $!";
while (<FILE>) {
	my $line = $_;
	foreach my $s (keys %filter) {
		# Process single variables
		my $tmp = $filter{$s};
		next if (not defined $tmp);
		pb_log(3,"DEBUG filter{$s}: $filter{$s}\n");
		# Expand variables if any single one found
		if ($tmp =~ /\$/) {
			# Order is important as we need to handle hashes refs before simple vars
			eval { $tmp =~ s/(\$\w+-\>\{\'\w+\'\})/$1/eeg };
			eval { $tmp =~ s/(\$\w+)/$1/eeg };
			eval { $tmp =~ s/(\$\/)/$1/eeg };
		# special case for ChangeLog only for pb
		} elsif (($s =~ /^PBLOG$/) && ($line =~ /^PBLOG$/)) {
			pb_log(3,"DEBUG filtering PBLOG\n");
			pb_changelog($pb, \*DEST, $tmp);
			$tmp = "";
		} elsif (($s =~ /^PBPATCHSRC$/) && ($line =~ /^PBPATCHSRC$/)) {
			pb_log(3,"DEBUG filtering PBPATCHSRC\n");
			my $i = 0;
			foreach my $p (split(/,/,$pb->{'patches'}->{$pb->{'tuple'}})) {
				print DEST "Patch$i:         ".basename($p).".gz\n";
				$i++;
			}
			$tmp = "";
		} elsif (($s =~ /^PBPATCHCMD$/) && ($line =~ /^PBPATCHCMD$/)) {
			pb_log(3,"DEBUG filtering PBPATCHCMD\n");
			my $i = 0;
			foreach my $p (split(/,/,$pb->{'patches'}->{$pb->{'tuple'}})) {
				print DEST "%patch$i -p1\n";
				$i++;
			}
			print DEST "\n";
			$tmp = "";
		}
		$line =~ s|$s|$tmp|g;
	}
	print DEST $line;
}
close(FILE);
close(DEST);
}

=item B<pb_filter_file_inplace>

This function applies all filters to a file in place.

It takes 3 parameters.

The first parameter is the pointer on the hash of filters.
The second parameter is the destination file after filtering.
The third parameter is the pointer on the hash of variables to filter (tag, ver, ...)

=cut

# Function which applies filter on files (external call)
sub pb_filter_file_inplace {

my $ptr=shift;
my %filter=%$ptr;
my $destfile=shift;
my $pb=shift;

my $cp = "$ENV{'PBTMP'}/".basename($destfile);
copy($destfile,$cp) || die "Unable to copy $destfile to $cp";

pb_filter_file($cp,$ptr,$destfile,$pb);
unlink $cp;
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
