#------------------------------------------------------------------------------
# File:         Sanyo.pm
#
# Description:  Definitions for Sanyo EXIF Maker Notes
#
# Revisions:    04/06/2004  - P. Harvey Created
#
# Reference:    http://www.exif.org/makernotes/SanyoMakerNote.html
#------------------------------------------------------------------------------

package Image::ExifTool::Sanyo;

use strict;
use vars qw($VERSION);

$VERSION = '1.02';

my %offOn = (
    0 => 'Off',
    1 => 'On',
);

%Image::ExifTool::Sanyo::Main = (
    GROUPS => { 0 => 'MakerNotes', 2 => 'Camera' },
    0x00ff => 'MakerNoteOffset',
    0x0100 => 'SanyoThumbnail',
    0x0200 => 'SpecialMode',
    0x0201 => {
        Name => 'SanyoQuality',
        PrintConv => {
            0x0000 => 'Normal/Very Low',
            0x0001 => 'Normal/Low',
            0x0002 => 'Normal/Medium Low',
            0x0003 => 'Normal/Medium',
            0x0004 => 'Normal/Medium High',
            0x0005 => 'Normal/High',
            0x0006 => 'Normal/Very High',
            0x0007 => 'Normal/Super High',
            0x0100 => 'Fine/Very Low',
            0x0101 => 'Fine/Low',
            0x0102 => 'Fine/Medium Low',
            0x0103 => 'Fine/Medium',
            0x0104 => 'Fine/Medium High',
            0x0105 => 'Fine/High',
            0x0106 => 'Fine/Very High',
            0x0107 => 'Fine/Super High',
            0x0200 => 'Super Fine/Very Low',
            0x0201 => 'Super Fine/Low',
            0x0202 => 'Super Fine/Medium Low',
            0x0203 => 'Super Fine/Medium',
            0x0204 => 'Super Fine/Medium High',
            0x0205 => 'Super Fine/High',
            0x0206 => 'Super Fine/Very High',
            0x0207 => 'Super Fine/Super High',
        },
    },
    0x0202 => {
        Name => 'Macro',
        PrintConv => {
            0 => 'Normal',
            1 => 'Macro',
            2 => 'View',
            3 => 'Manual',
        },
    },
    0x0204 => 'DigitalZoom',
    0x0207 => 'SoftwareVersion',
    0x0208 => 'PictInfo',
    0x0209 => 'CameraID',
    0x020e => {
        Name => 'SequentialShot',
        PrintConv => {
            0 => 'None',
            1 => 'Standard',
            2 => 'Best',
            3 => 'Adjust Exposure',
        },
    },
    0x020f => {
        Name => 'WideRange',
        PrintConv => \%offOn,
    },
    0x0210 => {
        Name => 'ColorAdjustmentMode',
        PrintConv => \%offOn,
    },
    0x0213 => {
        Name => 'QuickShot',
        PrintConv => \%offOn,
    },
    0x0214 => {
        Name => 'SelfTimer',
        PrintConv => \%offOn,
    },
    0x0216 => {
        Name => 'VoiceMemo',
        PrintConv => \%offOn,
    },
    0x0217 => {
        Name => 'RecordShutterRelease',
        PrintConv => {
            0 => 'Record while down',
            1 => 'Press start, press stop',
        },
    },
    0x0218 => {
        Name => 'FlickerReduce',
        PrintConv => \%offOn,
    },
    0x0219 => {
        Name => 'OpticalZoomOn',
        PrintConv => \%offOn,
    },
    0x021b => {
        Name => 'DigitalZoomOn',
        PrintConv => \%offOn,
    },
    0x021d => {
        Name => 'LightSourceSpecial',
        PrintConv => \%offOn,
    },
    0x021e => {
        Name => 'Resaved',
        PrintConv => {
            0 => 'No',
            1 => 'Yes',
        },
    },
    0x021f => {
        Name => 'SceneSelect',
        PrintConv => {
            0 => 'Off',
            1 => 'Sport',
            2 => 'TV',
            3 => 'Night',
            4 => 'User 1',
            5 => 'User 2',
        },
    },
    0x0223 => 'ManualFocusDistance',
    0x0224 => {
        Name => 'SequenceShotInterval',
        PrintConv => {
            0 => '5 frames/sec',
            1 => '10 frames/sec',
            2 => '15 frames/sec',
            3 => '20 frames/sec',
        },
    },
    0x0225 => {
        Name => 'FlashMode',
        PrintConv => {
            0 => 'Auto',
            1 => 'Force',
            2 => 'Disabled',
            3 => 'Red eye',
        },
    },
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
            Start => '$valuePtr',
        },
    },
#    0x0f00 => 'DataDump',
);


1;  # end

__END__

=head1 NAME

Image::ExifTool::Sanyo - Definitions for Sanyo EXIF maker notes

=head1 SYNOPSIS

This module is loaded automatically by Image::ExifTool when required.

=head1 DESCRIPTION

This module contains definitions required by Image::ExifTool to interpret
Sanyo maker notes in EXIF information.

=head1 AUTHOR

Copyright 2003-2004, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item http://www.exif.org/makernotes/SanyoMakerNote.html

=back

=head1 SEE ALSO

L<Image::ExifTool|Image::ExifTool>

=cut
