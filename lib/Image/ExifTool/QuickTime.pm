#------------------------------------------------------------------------------
# File:         QuickTime.pm
#
# Description:  Read QuickTime and MP4 meta information
#
# Revisions:    10/04/2005 - P. Harvey Created
#               12/19/2005 - P. Harvey Added MP4 support
#               09/22/2006 - P. Harvey Added M4A support
#
# References:   1) http://developer.apple.com/documentation/QuickTime/
#               2) http://search.cpan.org/dist/MP4-Info-1.04/
#               3) http://www.geocities.com/xhelmboyx/quicktime/formats/mp4-layout.txt
#               4) http://wiki.multimedia.cx/index.php?title=Apple_QuickTime
#------------------------------------------------------------------------------

package Image::ExifTool::QuickTime;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.11';

sub FixWrongFormat($);
sub ProcessMOV($$;$);

# information for time/date-based tags (time zero is Jan 1, 1904)
my %timeInfo = (
    Groups => { 2 => 'Time' },
    ValueConv => 'ConvertUnixTime($val - ((66 * 365 + 17) * 24 * 3600))',
    PrintConv => '$self->ConvertDateTime($val)',
);
# information for duration tags
my %durationInfo = (
    ValueConv => '$self->{TimeScale} ? $val / $self->{TimeScale} : $val',
    PrintConv => '$self->{TimeScale} ? sprintf("%.2fs", $val) : $val',
);

# QuickTime atoms
%Image::ExifTool::QuickTime::Main = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        These tags are used in QuickTime MOV and MP4 videos, and QTIF images.  Tags
        with a question mark after their name are not extracted unless the Unknown
        option is set.
    },
    free => { Unknown => 1, Binary => 1 },
    skip => { Unknown => 1, Binary => 1 },
    wide => { Unknown => 1, Binary => 1 },
    ftyp => { #MP4
        Name => 'FrameType',
        Unknown => 1,
        Notes => 'MP4 only',
        Binary => 1,
    },
    pnot => {
        Name => 'Preview',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Preview' },
    },
    PICT => {
        Name => 'PreviewPICT',
        Binary => 1,
    },
    moov => {
        Name => 'Movie',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Movie' },
    },
    mdat => { Unknown => 1, Binary => 1 },
);

# atoms used in QTIF files
%Image::ExifTool::QuickTime::ImageFile = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Image' },
    NOTES => 'Tags used in QTIF QuickTime Image Files.',
    idsc => {
        Name => 'ImageDescription',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::ImageDesc' },
    },
    idat => {
        Name => 'ImageData',
        Binary => 1,
    },
    iicc => {
        Name => 'ICC_Profile',
        SubDirectory => { TagTable => 'Image::ExifTool::ICC_Profile::Main' },
    },
);

# image description data block
%Image::ExifTool::QuickTime::ImageDesc = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Image' },
    4 => { Name => 'CompressorID',  Format => 'string[4]' },
    20 => { Name => 'VendorID',     Format => 'string[4]' },
    28 => { Name => 'Quality',      Format => 'int32u' },
    32 => { Name => 'ImageWidth',   Format => 'int16u' },
    34 => { Name => 'ImageHeight',  Format => 'int16u' },
    36 => { Name => 'XResolution',  Format => 'int32u' },
    40 => { Name => 'YResolution',  Format => 'int32u' },
    48 => { Name => 'FrameCount',   Format => 'int16u' },
    50 => { Name => 'NameLength',   Format => 'int8u' },
    51 => { Name => 'Compressor',   Format => 'string[$val{46}]' },
    82 => { Name => 'BitDepth',     Format => 'int16u' },
);

# preview data block
%Image::ExifTool::QuickTime::Preview = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Image' },
    FORMAT => 'int16u',
    0 => {
        Name => 'PreviewDate',
        Format => 'int32u',
        %timeInfo,
    },
    2 => 'PreviewVersion',
    3 => {
        Name => 'PreviewAtomType',
        Format => 'string[4]',
    },
    5 => 'PreviewAtomIndex',
);

# movie atoms
%Image::ExifTool::QuickTime::Movie = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    mvhd => {
        Name => 'MovieHeader',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::MovieHdr' },
    },
    trak => {
        Name => 'Track',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Track' },
    },
    udta => {
        Name => 'UserData',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::UserData' },
    },
);

# movie header data block
%Image::ExifTool::QuickTime::MovieHdr = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Video' },
    FORMAT => 'int32u',
    0 => { Name => 'Version', Format => 'int8u' },
    1 => {
        Name => 'CreateDate',
        %timeInfo,
    },
    2 => {
        Name => 'ModifyDate',
        %timeInfo,
    },
    3 => {
        Name => 'TimeScale',
        RawConv => '$self->{TimeScale} = $val',
    },
    4 => { Name => 'Duration', %durationInfo },
    5 => {
        Name => 'PreferredRate',
        ValueConv => '$val / 0x10000',
    },
    6 => {
        Name => 'PreferredVolume',
        Format => 'int16u',
        ValueConv => '$val / 256',
        PrintConv => 'sprintf("%.2f%%", $val * 100)',
    },
    18 => { Name => 'PreviewTime',      %durationInfo },
    19 => { Name => 'PreviewDuration',  %durationInfo },
    20 => { Name => 'PosterTime',       %durationInfo },
    21 => { Name => 'SelectionTime',    %durationInfo },
    22 => { Name => 'SelectionDuration',%durationInfo },
    23 => { Name => 'CurrentTime',      %durationInfo },
    24 => 'NextTrackID',
);

# track atoms
%Image::ExifTool::QuickTime::Track = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    tkhd => {
        Name => 'TrackHeader',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::TrackHdr' },
    },
    udta => {
        Name => 'UserData',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::UserData' },
    },
    mdia => { #MP4
        Name => 'Media',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Media' },
    },
);

# track header data block
%Image::ExifTool::QuickTime::TrackHdr = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 1 => 'Track#', 2 => 'Video' },
    FORMAT => 'int32u',
    0 => {
        Name => 'TrackVersion',
        Format => 'int8u',
        Priority => 0,
    },
    1 => {
        Name => 'TrackCreateDate',
        Priority => 0,
        %timeInfo,
    },
    2 => {
        Name => 'TrackModifyDate',
        Priority => 0,
        %timeInfo,
    },
    3 => {
        Name => 'TrackID',
        Priority => 0,
    },
    5 => {
        Name => 'TrackDuration',
        Priority => 0,
        %durationInfo,
    },
    8 => {
        Name => 'TrackLayer',
        Format => 'int16u',
        Priority => 0,
    },
    9 => {
        Name => 'TrackVolume',
        Format => 'int16u',
        Priority => 0,
        ValueConv => '$val / 256',
        PrintConv => 'sprintf("%.2f%%", $val * 100)',
    },
    19 => {
        Name => 'ImageWidth',
        Priority => 0,
        RawConv => \&FixWrongFormat,
    },
    20 => {
        Name => 'ImageHeight',
        Priority => 0,
        RawConv => \&FixWrongFormat,
    },
);

# user data atoms
%Image::ExifTool::QuickTime::UserData = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => q{
        Tag ID's beginning with the copyright symbol (hex 0xa9) are multi-language
        text, but ExifTool only extracts the text from the first language in the
        record.  ExifTool will extract any multi-language user data tags found, even
        if they don't exist in this table.
    },
    "\xa9cpy" => 'Copyright',
    "\xa9day" => 'CreateDate',
    "\xa9dir" => 'Director',
    "\xa9ed1" => 'Edit1',
    "\xa9ed2" => 'Edit2',
    "\xa9ed3" => 'Edit3',
    "\xa9ed4" => 'Edit4',
    "\xa9ed5" => 'Edit5',
    "\xa9ed6" => 'Edit6',
    "\xa9ed7" => 'Edit7',
    "\xa9ed8" => 'Edit8',
    "\xa9ed9" => 'Edit9',
    "\xa9fmt" => 'Format',
    "\xa9inf" => 'Information',
    "\xa9prd" => 'Producer',
    "\xa9prf" => 'Performers',
    "\xa9req" => 'Requirements',
    "\xa9src" => 'Source',
    "\xa9wrt" => 'Writer',
    name => 'Name',
    WLOC => {
        Name => 'WindowLocation',
        Format => 'int16u',
    },
    LOOP => {
        Name => 'LoopStyle',
        Format => 'int32u',
        PrintConv => {
            1 => 'Normal',
            2 => 'Palindromic',
        },
    },
    SelO => {
        Name => 'PlaySelection',
        Format => 'int8u',
    },
    AllF => {
        Name => 'PlayAllFrames',
        Format => 'int8u',
    },
    meta => {
        Name => 'Meta',
        SubDirectory => {
            TagTable => 'Image::ExifTool::QuickTime::Meta',
            HasVersion => 1, # must skip 4-byte version number header
        },
    },
   'ptv '=> {
        Name => 'PrintToVideo',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Video' },
    },
    # hnti => 'HintInfo',
    # hinf => 'HintTrackInfo',
    TAGS => [
        {
            # these tags were initially discovered in a Pentax movie, but
            # seem very similar to those used by Nikon
            Name => 'PentaxTags',
            Condition => '$$valPt =~ /^PENTAX DIGITAL CAMERA\0/',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Pentax::MOV',
                ByteOrder => 'LittleEndian',
            },
        },
        {
            Name => 'NikonTags',
            Condition => '$$valPt =~ /^NIKON DIGITAL CAMERA\0/',
            SubDirectory => {
                TagTable => 'Image::ExifTool::Nikon::MOV',
                ByteOrder => 'LittleEndian',
            },
        },
        {
            Name => 'SanyoMOV',
            Condition => q{
                $$valPt =~ /^SANYO DIGITAL CAMERA\0/ and
                $self->{VALUE}->{FileType} eq "MOV"
            },
            SubDirectory => {
                TagTable => 'Image::ExifTool::Sanyo::MOV',
                ByteOrder => 'LittleEndian',
            },
        },
        {
            Name => 'SanyoMP4',
            Condition => q{
                $$valPt =~ /^SANYO DIGITAL CAMERA\0/ and
                $self->{VALUE}->{FileType} eq "MP4"
            },
            SubDirectory => {
                TagTable => 'Image::ExifTool::Sanyo::MP4',
                ByteOrder => 'LittleEndian',
            },
        },
        {
            Name => 'UnknownTags',
            Unknown => 1,
            Binary => 1
        },
    ],
);

# meta atoms
%Image::ExifTool::QuickTime::Meta = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    ilst => {
        Name => 'InfoList',
        SubDirectory => {
            TagTable => 'Image::ExifTool::QuickTime::InfoList',
            HasData => 1, # process atoms as containers with 'data' elements
        },
    },
);

# info list atoms
# -> these atoms are unique, and contain one or more 'data' atoms
%Image::ExifTool::QuickTime::InfoList = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Audio' },
    "\xa9ART" => 'Artist',
    "\xa9alb" => 'Album',
    "\xa9cmt" => 'Comment',
    "\xa9com" => 'Composer',
    "\xa9day" => 'Year',
    "\xa9des" => 'Description', #4
    "\xa9gen" => 'Genre',
    "\xa9grp" => 'Grouping',
    "\xa9lyr" => 'Lyrics',
    "\xa9nam" => 'Title',
    "\xa9too" => 'Encoder',
    "\xa9trk" => 'Track',
    "\xa9wrt" => 'Composer',
    '----' => {
        Name => 'iTunesInfo',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::iTunesInfo' },
    },
    aART => 'AlbumArtist',
    apid => 'AppleStoreID',
    auth => 'Author',
    covr => 'CoverArt',
    cpil => {
        Name => 'Compilation',
        PrintConv => { 0 => 'No', 1 => 'Yes' },
    },
    cprt => 'Copyright',
    disk => {
        Name => 'DiskNumber',
        ValueConv => 'length($val) >= 6 ? join(" of ",unpack("x2nn",$val)) : \$val',
    },
    dscp => 'Description',
    gnre => 'Genre',
    perf => 'Performer',
    pgap => {
        Name => 'PlayGap',
        PrintConv => {
            0 => 'Insert Gap',
            1 => 'No Gap',
        },
    },
    rtng => 'Rating', # int
    titl => 'Title',
    tmpo => 'BeatsPerMinute', # int
    trkn => {
        Name => 'TrackNumber',
        ValueConv => 'length($val) >= 6 ? join(" of ",unpack("x2nn",$val)) : \$val',
    },
);

# info list atoms
%Image::ExifTool::QuickTime::iTunesInfo = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Audio' },
);

# print to video data block
%Image::ExifTool::QuickTime::Video = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Video' },
    0 => {
        Name => 'DisplaySize',
        PrintConv => {
            0 => 'Normal',
            1 => 'Double Size',
            2 => 'Half Size',
            3 => 'Full Screen',
            4 => 'Current Size',
        },
    },
    6 => {
        Name => 'SlideShow',
        PrintConv => {
            0 => 'No',
            1 => 'Yes',
        },
    },
);

# MP4 media
%Image::ExifTool::QuickTime::Media = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => 'MP4 only (most tags unknown because ISO charges for the specification).',
    minf => {
        Name => 'Minf',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Minf' },
    },
);

%Image::ExifTool::QuickTime::Minf = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => 'MP4 only (most tags unknown because ISO charges for the specification).',
    dinf => {
        Name => 'Dinf',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Dinf' },
    },
    stbl => {
        Name => 'Stbl',
        SubDirectory => { TagTable => 'Image::ExifTool::QuickTime::Stbl' },
    },
);

%Image::ExifTool::QuickTime::Stbl = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => 'MP4 only (most tags unknown because ISO charges for the specification).',
);

%Image::ExifTool::QuickTime::Dinf = (
    PROCESS_PROC => \&Image::ExifTool::QuickTime::ProcessMOV,
    GROUPS => { 2 => 'Video' },
    NOTES => 'MP4 only (most tags unknown because ISO charges for the specification).',
);

#------------------------------------------------------------------------------
# Fix incorrect format for ImageWidth/Height as written by Pentax
sub FixWrongFormat($)
{
    my $val = shift;
    return undef unless $val;
    if ($val & 0xffff0000) {
        $val = unpack('n',pack('N',$val));
    }
    return $val;
}

#------------------------------------------------------------------------------
# Process a QuickTime atom
# Inputs: 0) ExifTool object reference, 1) directory information reference
#         2) optional tag table reference
# Returns: 1 on success
sub ProcessMOV($$;$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $raf = $$dirInfo{RAF};
    my $dataPt = $$dirInfo{DataPt};
    my $verbose = $exifTool->Options('Verbose');
    my $dataPos = $$dirInfo{Base} || 0;
    my ($buff, $tag, $size, $track);

    # more convenient to package data as a RandomAccess file
    $raf or $raf = new File::RandomAccess($dataPt);
    # skip leading 4-byte version number if necessary
    ($raf->Read($buff,4) == 4 and $dataPos += 4) or return 0 if $$dirInfo{HasVersion};
    # read size/tag name atom header
    $raf->Read($buff,8) == 8 or return 0;
    $dataPos += 8;
    $tagTablePtr or $tagTablePtr = GetTagTable('Image::ExifTool::QuickTime::Main');
    ($size, $tag) = unpack('Na4', $buff);
    if ($dataPt) {
        $verbose and $exifTool->VerboseDir($$dirInfo{DirName});
    } else {
        # check on file type if called with a RAF
        $$tagTablePtr{$tag} or return 0;
        if ($tag eq 'ftyp') {
            # read ahead 4 bytes to see if this is an M4A file
            my $ftyp = 'MP4';
            if ($raf->Read($buff, 4) == 4) {
                $raf->Seek(-4, 1);
                $ftyp = 'M4A' if $buff eq 'M4A ';
            }
            $exifTool->SetFileType($ftyp);  # MP4 or M4A
        } else {
            $exifTool->SetFileType();       # MOV
        }
        SetByteOrder('MM');
    }
    for (;;) {
        if ($size < 8) {
            last if $size == 0;
            $size == 1 or $exifTool->Warn('Invalid atom size'), last;
            $raf->Read($buff, 8) == 8 or last;
            $dataPos += 8;
            my ($hi, $lo) = unpack('NN', $buff);
            $hi and $exifTool->Warn('End of processing at large atom'), last;
            $size = $lo;
        }
        $size -= 8;
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        # generate tagInfo if Unknown option set
        if (not defined $tagInfo and ($exifTool->{OPTIONS}->{Unknown} or
            $tag =~ /^\xa9/))
        {
            my $name = $tag;
            $name =~ s/([\x00-\x1f\x7f-\xff])/'x'.unpack('H*',$1)/eg;
            if ($name =~ /^xa9(.*)/) {
                $tagInfo = {
                    Name => "UserData_$1",
                    Description => "User Data $1",
                };
            } else {
                $tagInfo = {
                    Name => "Unknown_$name",
                    Description => "Unknown $name",
                    Unknown => 1,
                    Binary => 1,
                };
            }
            Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
        }
        if (defined $tagInfo or $verbose) {
            my $val;
            unless ($raf->Read($val, $size) == $size) {
                $exifTool->Warn("Truncated '$tag' data");
                last;
            }
            # use value to get tag info if necessary
            $tagInfo or $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag, \$val);
            my $hasData = ($$dirInfo{HasData} and $val =~ /^\0...data\0/s);
            if ($verbose and not $hasData) {
                $exifTool->VerboseInfo($tag, $tagInfo,
                    Value => $val,
                    DataPt => \$val,
                    DataPos => $dataPos,
                );
            }
            if ($tagInfo) {
                my $subdir = $$tagInfo{SubDirectory};
                if ($subdir) {
                    my %dirInfo = (
                        DataPt => \$val,
                        DirStart => 0,
                        DirLen => $size,
                        DirName => $$tagInfo{Name},
                        HasData => $$subdir{HasData},
                        HasVersion => $$subdir{HasVersion},
                        # Base needed for IsOffset tags in binary data
                        Base => $dataPos,
                    );
                    if ($$subdir{ByteOrder} and $$subdir{ByteOrder} =~ /^Little/) {
                        SetByteOrder('II');
                    }
                    if ($$tagInfo{Name} eq 'Track') {
                        $track or $track = 0;
                        $exifTool->{SET_GROUP1} = 'Track' . (++$track);
                    }
                    my $subTable = GetTagTable($$subdir{TagTable});
                    $exifTool->ProcessDirectory(\%dirInfo, $subTable);
                    delete $exifTool->{SET_GROUP1};
                    SetByteOrder('MM');
                } elsif ($hasData) {
                    # handle atoms containing 'data' tags
                    my $pos = 0;
                    for (;;) {
                        last if $pos + 16 > $size;
                        my ($len, $type, $flags) = unpack("x${pos}Na4N", $val);
                        last if $pos + $len > $size;
                        my $value;
                        if ($type eq 'data' and $len >= 16) {
                            $pos += 16;
                            $len -= 16;
                            $value = substr($val, $pos, $len);
                            # format flags: 0x0=binary, 0x1=text, 0xd=image, 0x15=boolean 
                            if ($flags == 0x0015) {
                                $value = $len ? ReadValue(\$value, $len-1, 'int8u', 1, 1) : '';
                            } elsif ($flags != 0x01 and not $$tagInfo{ValueConv}) {
                                # make binary data a scalar reference unless a ValueConv exists
                                my $buf = $value;
                                $value = \$buf;
                            }
                        }
                        $exifTool->VerboseInfo($tag, $tagInfo,
                            Value => ref $value ? $$value : $value,
                            DataPt => \$val,
                            DataPos => $dataPos,
                            Start => $pos,
                            Size => $len,
                            Extra => sprintf(", Type='$type', Flags=0x%x",$flags)
                        ) if $verbose;
                        $exifTool->FoundTag($tagInfo, $value) if defined $value;
                        $pos += $len;
                    }
                } else {
                    if ($tag =~ /^\xa9/) {
                        # parse international text to extract first string
                        my $len = unpack('n', $val);
                        # $len should include 4 bytes for length and type words,
                        # but Pentax forgets to add these in, so allow for this
                        $len += 4 if $len == $size - 4;
                        $val = substr($val, 4, $len - 4) if $len <= $size;
                    } elsif ($$tagInfo{Format}) {
                        $val = ReadValue(\$val, 0, $$tagInfo{Format}, $$tagInfo{Count}, length($val));
                    }
                    $exifTool->FoundTag($tagInfo, $val);
                }
            }
        } else {
            $raf->Seek($size, 1) or $exifTool->Warn("Truncated '$tag' data"), last;
        }
        $raf->Read($buff, 8) == 8 or last;
        $dataPos += $size + 8;
        ($size, $tag) = unpack('Na4', $buff);
    }
    return 1;
}

#------------------------------------------------------------------------------
# Process a QuickTime Image File
# Inputs: 0) ExifTool object reference, 1) directory information reference
# Returns: 1 on success
sub ProcessQTIF($$)
{
    my $table = GetTagTable('Image::ExifTool::QuickTime::ImageFile');
    return ProcessMOV($_[0], $_[1], $table);
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::QuickTime - Read QuickTime and MP4 meta information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract
information from QuickTime and MP4 video files.

=head1 BUGS

The MP4 support is rather pathetic since the specification documentation is
not freely available (yes, ISO sucks).

=head1 AUTHOR

Copyright 2003-2006, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://developer.apple.com/documentation/QuickTime/>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/QuickTime Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

