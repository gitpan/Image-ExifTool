#------------------------------------------------------------------------------
# File:         Sony.pm
#
# Description:  Definitions for Sony EXIF Maker Notes
#
# Revisions:    04/06/2004  - P. Harvey Created
#
# Notes:        The Sony maker notes use the standard EXIF IFD structure, but
#               the entries are large blocks of binary data for which I can
#               find no documentation.  The only one I recognize is the PrintIM
#               block.  To figure them out will require someone with a Sony
#               camera who is willing to systematically change all the settings
#               and determine where they are stored in these blocks.  You can
#               use "exiftool -v -v -v" to dump these blocks in hex.
#------------------------------------------------------------------------------

package Image::ExifTool::Sony;

use strict;
use vars qw($VERSION);

$VERSION = '1.00';

%Image::ExifTool::Sony::Main = (
    GROUPS => { 1 => 'MakerNotes', 2 => 'Camera' },
    
    0x0e00 => {
        Name => 'PrintIM',
        Description => 'Print Image Matching',
        SubDirectory => {
            TagTable => 'Image::ExifTool::PrintIM::Main',
            Start => '$valuePtr',
        },
    },
);


1;  # end
