# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl t/ExifTool.t'

######################### We start with some black magic to print on failure.

# Change "1..N" below to so that N matches last test number

BEGIN { $| = 1; print "1..16\n"; }
END {print "not ok 1\n" unless $loaded;}

# test 1: Load ExifTool
use Image::ExifTool 'ImageInfo';
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

use t::TestLib 'check';

my $testname = 'ExifTool';
my $testnum = 1;

# test 2: JPG file using name
{
    ++$testnum;
    my $info = ImageInfo('t/ExifTool.jpg');
    print 'not ' unless check($info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 3: GIF file using data in memory
{
    ++$testnum;
    my $image;
    open(TESTFILE, 't/ExifTool.gif');
    binmode(TESTFILE);
    read(TESTFILE, $image, 5000000);
    close(TESTFILE);
    my $info = ImageInfo(\$image);
    print 'not ' unless check($info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 4: TIFF file using file reference and ExifTool object with options
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(Duplicates => 1, Unknown => 1);
    open(TESTFILE, 't/ExifTool.tif');
    my $info = $exifTool->ImageInfo(\*TESTFILE);
    close(TESTFILE);
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 5: test the Group option to extract EXIF info only
{
    ++$testnum;
    my $info = ImageInfo('t/ExifTool.jpg', {Group1 => 'EXIF'});
    print 'not ' unless check($info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 6: test the DateFormat option and extact specified tags only
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(DateFormat => '%H:%M:%S %a. %b. %e, %Y');
    my @tags = ('CreateDate', 'DateTimeOriginal', 'ModifyDate');
    my $info = $exifTool->ImageInfo('t/ExifTool.jpg', \@tags);
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 7: test the 4 different ways to exclude tags...
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(Exclude => 'ImageWidth');
    my @tagList = ( '-ImageHeight', '-Make' );
    my $info = $exifTool->ImageInfo('t/ExifTool.jpg', '-FileSize',
                        \@tagList, {Group1 => '-MakerNotes'});
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# tests 8/9: test ExtractInfo(), GetInfo(), CombineInfo()
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(Duplicates => 0);  # don't allow duplicates
    $exifTool->ExtractInfo('t/ExifTool.jpg');
    my $info1 = $exifTool->GetInfo({Group1 => 'MakerNotes'});
    my $info2 = $exifTool->GetInfo({Group1 => 'EXIF'});
    my $info = $exifTool->CombineInfo($info1, $info2);
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";

    # combine information in different order
    ++$testnum;
    $info = $exifTool->CombineInfo($info2, $info1);
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 10: test group options across different families
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    my $info = $exifTool->ImageInfo('t/ExifTool.jpg',
                    { Group0 => 'Canon', Group2 => '-Camera' });
    print 'not ' unless check($exifTool, $info, $testname, $testnum);
    print "ok $testnum\n";
}

# test 11/12: test ExtractInfo() and GetInfo()
# (uses output from test 6 for comparison)
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(DateFormat => '%H:%M:%S %a. %b. %e, %Y');
    $exifTool->ExtractInfo('t/ExifTool.jpg');
    my @tags = ('createdate', 'datetimeoriginal', 'modifydate');
    my $info = $exifTool->GetInfo(\@tags);
    my $good = 1;
    my @expectedTags = ('CreateDate', 'DateTimeOriginal', 'ModifyDate');
    for (my $i=0; $i<scalar(@tags); ++$i) {
        $tags[$i] = $expectedTags[$i] or $good = 0;
    }
    print 'not ' unless $good;
    print "ok $testnum\n";

    ++$testnum;
    print 'not ' unless check($exifTool, $info, $testname, $testnum, 6);
    print "ok $testnum\n";
}

# tests 13/14: check precidence of tags extracted from groups
# (Note: these tests should produce the same output as 8/9,
#  so the .out files from tests 8/9 are used)
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->Options(Duplicates => 0);  # don't allow duplicates
    my $info = $exifTool->ImageInfo('t/ExifTool.jpg',{Group1=>['MakerNotes','EXIF']});
    print 'not ' unless check($exifTool, $info, $testname, $testnum, 8);
    print "ok $testnum\n";

    # combine information in different order
    ++$testnum;
    $info = $exifTool->ImageInfo('t/ExifTool.jpg',{Group1=>['EXIF','MakerNotes']});
    print 'not ' unless check($exifTool, $info, $testname, $testnum, 9);
    print "ok $testnum\n";
}

# test 15/16: test GetGroups()
{
    ++$testnum;
    my $exifTool = new Image::ExifTool;
    $exifTool->ExtractInfo('t/ExifTool.jpg');
    my @groups = $exifTool->GetGroups(2);
    my $not;
    foreach ('Camera','ExifTool','Image','Time') {
        $_ eq shift @groups or $not = 1;
    }
    @groups and $not = 1;
    print 'not ' if $not;
    print "ok $testnum\n";
    
    ++$testnum;
    my $info = $exifTool->GetInfo({Group1 => 'EXIF'});
    @groups = $exifTool->GetGroups($info,1);
    print 'not ' unless @groups==1 and $groups[0] eq 'EXIF';
    print "ok $testnum\n";
}



# end
