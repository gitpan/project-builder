#!/usr/bin/perl -w
#
# Declare versions that will be used in pb
# Those are filtered with pb mecanism
# and have been isolated here to avoid unrelated effects
#
package ProjectBuilder::Version;

use strict;

# Inherit from the "Exporter" module which handles exporting functions.
 
use Exporter;
 
# Export, by default, all the functions into the namespace of
# any code which uses this module.
our @ISA = qw(Exporter);
our @EXPORT = qw(pb_version_init);

sub pb_version_init {

my $projectbuilderver = "0.9.7.1";
my $projectbuilderrev = "807";

return($projectbuilderver,$projectbuilderrev);
}
1;
