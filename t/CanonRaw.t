# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl t/CanonRaw.t'

######################### We start with some black magic to print on failure.

# Change "1..N" below to so that N matches last test number

BEGIN { $| = 1; print "1..3\n"; }
END {print "not ok 1\n" unless $loaded;}

# test 1: Load ExifTool
use Image::ExifTool 'ImageInfo';
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

use t::TestLib 'check';

my $testname = 'CanonRaw';
my $testnum = 1;

# test 2: Extract information from CanonRaw.crw
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    my $info = $exifTool->ImageInfo('t/CanonRaw.crw');
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 3: Extract JpgFromRaw
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(PrintConv => 0);
    my $info = $exifTool->ImageInfo('t/CanonRaw.crw','JpgFromRaw');
    print 'not ' unless $info->{JpgFromRaw} eq '<Dummy preview image data>';
    print "ok $testnum\n";
}


# end
