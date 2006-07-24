#------------------------------------------------------------------------------
# File:         ASF.pm
#
# Description:  Read ASF/WMA/WMV meta information
#
# Revisions:    12/23/2005 - P. Harvey Created
#
# References:   1) http://www.microsoft.com/windows/windowsmedia/format/asfspec.aspx
#------------------------------------------------------------------------------

package Image::ExifTool::ASF;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);
use Image::ExifTool::Exif;

$VERSION = '1.02';

sub ProcessMetadata($$$);
sub ProcessContentDescription($$$);
sub ProcessPreview($$$);
sub ProcessCodecList($$$);

# GUID definitions
my %errorCorrection = (
    '20FB5700-5B55-11CF-A8FD-00805F5C442B' => 'No Error Correction',
    'BFC3CD50-618F-11CF-8BB2-00AA00B4E220' => 'Audio Spread',
);

my %streamType = (
    'F8699E40-5B4D-11CF-A8FD-00805F5C442B' => 'Audio',
    'BC19EFC0-5B4D-11CF-A8FD-00805F5C442B' => 'Video',
    '59DACFC0-59E6-11D0-A3AC-00A0C90348F6' => 'Command',
    'B61BE100-5B4E-11CF-A8FD-00805F5C442B' => 'JFIF',
    '35907DE0-E415-11CF-A917-00805F5C442B' => 'Degradable JPEG',
    '91BD222C-F21C-497A-8B6D-5AA86BFC0185' => 'File Transfer',
    '3AFB65E2-47EF-40F2-AC2C-70A90D71D343' => 'Binary',
);

my %mutex = (
    'D6E22A00-35DA-11D1-9034-00A0C90349BE' => 'MutexLanguage',
    'D6E22A01-35DA-11D1-9034-00A0C90349BE' => 'MutexBitrate',
    'D6E22A02-35DA-11D1-9034-00A0C90349BE' => 'MutexUnknown',
);

my %bandwidthSharing = (
    'AF6060AA-5197-11D2-B6AF-00C04FD908E9' => 'SharingExclusive',
    'AF6060AB-5197-11D2-B6AF-00C04FD908E9' => 'SharingPartial',
);

my %typeSpecific = (
    '776257D4-C627-41CB-8F81-7AC7FF1C40CC' => 'WebStreamMediaSubtype',
    'DA1E6B13-8359-4050-B398-388E965BF00C' => 'WebStreamFormat',
);

my %advancedContentEncryption = (
    '7A079BB6-DAA4-4e12-A5CA-91D38DC11A8D' => 'DRMNetworkDevices',
);

# ASF top level objects
%Image::ExifTool::ASF::Main = (
    PROCESS_PROC => \&Image::ExifTool::ASF::ProcessASF,
    NOTES => q{
        ASF format is used by Windows WMA and WMV files.  Tag ID's aren't listed
        because they are huge 128-bit GUID's that would ruin the formatting of this
        table.
    },
    '75B22630-668E-11CF-A6D9-00AA0062CE6C' => {
        Name => 'Header',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::Header', Size => 6 },
    },
    '75B22636-668E-11CF-A6D9-00AA0062CE6C' => 'Data',
    '33000890-E5B1-11CF-89F4-00A0C90349CB' => 'SimpleIndex',
    'D6E229D3-35DA-11D1-9034-00A0C90349BE' => 'Index',
    'FEB103F8-12AD-4C64-840F-2A1D2F7AD48C' => 'MediaIndex',
    '3CB73FD0-0C4A-4803-953D-EDF7B6228F0C' => 'TimecodeIndex',
);

# ASF header objects
%Image::ExifTool::ASF::Header = (
    PROCESS_PROC => \&Image::ExifTool::ASF::ProcessASF,
    '8CABDCA1-A947-11CF-8EE4-00C00C205365' => {
        Name => 'FileProperties',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::FileProperties' },
    },
    'B7DC0791-A9B7-11CF-8EE6-00C00C205365' => {
        Name => 'StreamProperties',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::StreamProperties' },
    },
    '5FBF03B5-A92E-11CF-8EE3-00C00C205365' => {
        Name => 'HeaderExtension',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::HeaderExtension', Size => 22 },
    },
    '86D15240-311D-11D0-A3A4-00A0C90348F6' => {
        Name => 'CodecList',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::CodecList' },
    },
    '1EFB1A30-0B62-11D0-A39B-00A0C90348F6' => 'ScriptCommand',
    'F487CD01-A951-11CF-8EE6-00C00C205365' => 'Marker',
    'D6E229DC-35DA-11D1-9034-00A0C90349BE' => 'BitrateMutualExclusion',
    '75B22635-668E-11CF-A6D9-00AA0062CE6C' => 'ErrorCorrection',
    '75B22633-668E-11CF-A6D9-00AA0062CE6C' => {
        Name => 'ContentDescription',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::ContentDescr' },
    },
    '2211B3FA-BD23-11D2-B4B7-00A0C955FC6E' => {
        Name => 'ContentBranding',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::ContentBranding' },
    },
    'D2D0A440-E307-11D2-97F0-00A0C95EA850' => {
        Name => 'ExtendedContentDescr',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::ExtendedDescr' },
    },
    '7BF875CE-468D-11D1-8D82-006097C9A2B2' => 'StreamBitrateProps',
    '2211B3FB-BD23-11D2-B4B7-00A0C955FC6E' => 'ContentEncryption',
    '298AE614-2622-4C17-B935-DAE07EE9289C' => 'ExtendedContentEncryption',
    '2211B3FC-BD23-11D2-B4B7-00A0C955FC6E' => 'DigitalSignature',
    '1806D474-CADF-4509-A4BA-9AABCB96AAE8' => 'Padding',
);

%Image::ExifTool::ASF::ContentDescr = (
    PROCESS_PROC => \&ProcessContentDescription,
    GROUPS => { 2 => 'Video' },
    0 => 'Title',
    1 => { Name => 'Author', Groups => { 2 => 'Author' } },
    2 => { Name => 'Copyright', Groups => { 2 => 'Author' } },
    3 => 'Description',
    4 => 'Rating',
);

%Image::ExifTool::ASF::ContentBranding = (
    PROCESS_PROC => \&ProcessContentBranding,
    GROUPS => { 2 => 'Author' },
    0 => {
        Name => 'BannerImageType',
        PrintConv => {
            0 => 'None',
            1 => 'Bitmap',
            2 => 'JPEG',
            3 => 'GIF',
        },
    },
    1 => { Name => 'BannerImage', ValueConv => '\$val' },
    2 => 'BannerImageURL',
    3 => 'CopyrightURL',
);

%Image::ExifTool::ASF::ExtendedDescr = (
    PROCESS_PROC => \&ProcessExtendedContentDescription,
    GROUPS => { 2 => 'Video' },
    ASFLeakyBucketPairs => { ValueConv => '\$val' },
    AspectRatioX => {},
    AspectRatioY => {},
    Author => { Groups => { 2 => 'Author' } },
    AverageLevel => {},
    BannerImageData => {},
    BannerImageType => {},
    BannerImageURL => {},
    Bitrate => {},
    Broadcast => {},
    BufferAverage => {},
    Can_Skip_Backward => {},
    Can_Skip_Forward => {},
    Copyright => { Groups => { 2 => 'Author' } },
    CopyrightURL => { Groups => { 2 => 'Author' } },
    CurrentBitrate => {},
    Description => {},
    DRM_ContentID => {},
    DRM_DRMHeader_ContentDistributor => {},
    DRM_DRMHeader_ContentID => {},
    DRM_DRMHeader_IndividualizedVersion => {},
    DRM_DRMHeader_KeyID => {},
    DRM_DRMHeader_LicenseAcqURL => {},
    DRM_DRMHeader_SubscriptionContentID => {},
    DRM_DRMHeader => {},
    DRM_IndividualizedVersion => {},
    DRM_KeyID => {},
    DRM_LASignatureCert => {},
    DRM_LASignatureLicSrvCert => {},
    DRM_LASignaturePrivKey => {},
    DRM_LASignatureRootCert => {},
    DRM_LicenseAcqURL => {},
    DRM_V1LicenseAcqURL => {},
    Duration => {},
    FileSize => {},
    HasArbitraryDataStream => {},
    HasAttachedImages => {},
    HasAudio => {},
    HasFileTransferStream => {},
    HasImage => {},
    HasScript => {},
    HasVideo => {},
    Is_Protected => {},
    Is_Trusted => {},
    IsVBR => {},
    NSC_Address => {},
    NSC_Description => {},
    NSC_Email => {},
    NSC_Name => {},
    NSC_Phone => {},
    NumberOfFrames => {},
    OptimalBitrate => {},
    PeakValue => {},
    Rating => {},
    Seekable => {},
    Signature_Name => {},
    Stridable => {},
    Title => {},
    VBRPeak => {},
    # "WM/" tags...
    AlbumArtist => {},
    AlbumCoverURL => {},
    AlbumTitle => {},
    ASFPacketCount => {},
    ASFSecurityObjectsSize => {},
    AudioFileURL => {},
    AudioSourceURL => {},
    AuthorURL => { Groups => { 2 => 'Author' } },
    BeatsPerMinute => {},
    Category => {},
    Codec => {},
    Composer => {},
    Conductor => {},
    ContainerFormat => {},
    ContentDistributor => {},
    ContentGroupDescription => {},
    Director => {},
    DRM => {},
    DVDID => {},
    EncodedBy => {},
    EncodingSettings => {},
    EncodingTime => { Groups => { 2 => 'Time' } },
    Genre => {},
    GenreID => {},
    InitialKey => {},
    ISRC => {},
    Language => {},
    Lyrics => {},
    Lyrics_Synchronised => {},
    MCDI => {},
    MediaClassPrimaryID => {},
    MediaClassSecondaryID => {},
    MediaCredits => {},
    MediaIsDelay => {},
    MediaIsFinale => {},
    MediaIsLive => {},
    MediaIsPremiere => {},
    MediaIsRepeat => {},
    MediaIsSAP => {},
    MediaIsStereo => {},
    MediaIsSubtitled => {},
    MediaIsTape => {},
    MediaNetworkAffiliation => {},
    MediaOriginalBroadcastDateTime => { Groups => { 2 => 'Time' } },
    MediaOriginalChannel => {},
    MediaStationCallSign => {},
    MediaStationName => {},
    ModifiedBy => {},
    Mood => {},
    OriginalAlbumTitle => {},
    OriginalArtist => {},
    OriginalFilename => {},
    OriginalLyricist => {},
    OriginalReleaseTime => { Groups => { 2 => 'Time' } },
    OriginalReleaseYear => { Groups => { 2 => 'Time' } },
    ParentalRating => {},
    ParentalRatingReason => {},
    PartOfSet => {},
    PeakBitrate => {},
    Period => {},
    Picture => {
        SubDirectory => {
            TagTable => 'Image::ExifTool::ASF::Preview',
        },
    },
    PlaylistDelay => {},
    Producer => {},
    PromotionURL => {},
    ProtectionType => {},
    Provider => {},
    ProviderCopyright => {},
    ProviderRating => {},
    ProviderStyle => {},
    Publisher => {},
    RadioStationName => {},
    RadioStationOwner => {},
    SharedUserRating => {},
    StreamTypeInfo => {},
    SubscriptionContentID => {},
    SubTitle => {},
    SubTitleDescription => {},
    Text => {},
    ToolName => {},
    ToolVersion => {},
    Track => {},
    TrackNumber => {},
    UniqueFileIdentifier => {},
    UserWebURL => {},
    VideoClosedCaptioning => {},
    VideoFrameRate => {},
    VideoHeight => {},
    VideoWidth => {},
    WMADRCAverageReference => {},
    WMADRCAverageTarget => {},
    WMADRCPeakReference => {},
    WMADRCPeakTarget => {},
    WMCollectionGroupID => {},
    WMCollectionID => {},
    WMContentID => {},
    Writer => { Groups => { 2 => 'Author' } },
    Year => { Groups => { 2 => 'Time' } },
);

%Image::ExifTool::ASF::Preview = (
    PROCESS_PROC => \&ProcessPreview,
    GROUPS => { 2 => 'Video' },
    0 => {
        Name => 'PreviewType',
        PrintConv => {
            0 => 'Other picture type',
            1 => '32x32 PNG file icon',
            2 => 'Other file icon',
            3 => 'Front album cover',
            4 => 'Back album cover',
            5 => 'Leaflet page',
            6 => 'Media label',
            7 => 'Lead artist, performer, or soloist',
            8 => 'Artists or performers',
            9 => 'Conductor',
            10 => 'Band or orchestra',
            11 => 'Composer',
            12 => 'Lyricist or writer',
            13 => 'Recording studio or location',
            14 => 'Recording session',
            15 => 'Performance',
            16 => 'Capture from movie or video',
            17 => 'A bright colored fish',
            18 => 'Illustration',
            19 => 'Band or artist logo',
            20 => 'Publisher or studio logo',
        },
    },
    1 => 'PreviewMimeType',
    2 => 'PreviewDescription',
    3 => {
        Name => 'PreviewImage',
        ValueConv => '$self->ValidateImage(\$val,$tag)',
    },
);

%Image::ExifTool::ASF::FileProperties = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Video' },
    0  => {
        Name => 'FileID',
        Format => 'binary[16]',
        ValueConv => 'Image::ExifTool::ASF::GetGUID($val)',
    },
    16 => { Name => 'FileSize',     Format => 'int64u' },
    24 => {
        Name => 'CreationDate',
        Format => 'int64u',
        Groups => { 2 => 'Time' },
        # time is in 100 ns intervals since 0:00 UTC Jan 1, 1601
        ValueConv => q{ # (89 leap years between 1601 and 1970)
            my $t = $val / 1e7 - (((1970-1601)*365+89)*24*3600);
            return Image::ExifTool::ConvertUnixTime($t) . 'Z';
        }
    },
    32 => { Name => 'DataPackets',  Format => 'int64u' },
    40 => {
        Name => 'PlayDuration',
        Format => 'int64u',
        ValueConv => '$val / 1e7',
        PrintConv => '"$val sec"',
    },
    48 => {
        Name => 'SendDuration',
        Format => 'int64u',
        ValueConv => '$val / 1e7',
        PrintConv => '"$val sec"',
    },
    56 => { Name => 'Preroll',      Format => 'int64u' },
    64 => { Name => 'Flags',        Format => 'int32u' },
    68 => { Name => 'MinPacketSize',Format => 'int32u' },
    72 => { Name => 'MaxPacketSize',Format => 'int32u' },
    76 => { Name => 'MaxBitrate',   Format => 'int32u' },
);

%Image::ExifTool::ASF::StreamProperties = (
    PROCESS_PROC => \&Image::ExifTool::ProcessBinaryData,
    GROUPS => { 2 => 'Video' },
    NOTES => 'Tags with index 54 and greater are conditional based on the StreamType.',
    0  => {
        Name => 'StreamType',
        Format => 'binary[16]',
        RawConv => sub { # set ASF_STREAM_TYPE for use in conditional tags
            my ($val, $exifTool) = @_;
            $exifTool->{ASF_STREAM_TYPE} = $streamType{GetGUID($val)} || '';
            return $val;
        },
        ValueConv => 'Image::ExifTool::ASF::GetGUID($val)',
        PrintConv => \%streamType,
    },
    16 => {
        Name => 'ErrorCorrectionType',
        Format => 'binary[16]',
        ValueConv => 'Image::ExifTool::ASF::GetGUID($val)',
        PrintConv => \%errorCorrection,
    },
    32 => {
        Name => 'TimeOffset',
        Format => 'int64u',
        ValueConv => '$val / 1e7',
        PrintConv => '"$val sec"',
    },
    48 => {
        Name => 'StreamNumber',
        Format => 'int16u',
        PrintConv => '($val & 0x7f) . ($val & 0x8000 ? " (encrypted)" : "")',
    },
    54 => [
        {
            Condition => '$self->{ASF_STREAM_TYPE} eq "Audio"',
            Name => 'AudioCodecID',
            Format => 'int16u',
            PrintHex => 1,
            # from http://www.iana.org/assignments/wave-avi-codec-registry
            # and http://developers.videolan.org/vlc/vlc/doc/doxygen/html/codecs_8h-source.html
            PrintConv => {
                0x0001 => 'Microsoft PCM',
                0x0002 => 'Microsoft ADPCM',
                0x0003 => 'IEEE Float',
                0x0004 => 'Cmpaq VSELP',
                0x0005 => 'IBM CVSD',
                0x0006 => 'Microsoft A-Law',
                0x0007 => 'Microsoft Mu-Law',
                0x0008 => 'DTS Coherent Acoustics 1',
                0x0010 => 'OKI ADPCM',
                0x0011 => 'Intel DVI ADPCM',
                0x0012 => 'Videologic MediaSpace ADPCM',
                0x0013 => 'Sierra ADPCM',
                0x0014 => 'G.723 ADPCM',
                0x0015 => 'DSP Solution DIGISTD',
                0x0016 => 'DSP Solution DIGIFIX',
                0x0017 => 'Dialogic OKI ADPCM',
                0x0018 => 'MediaVision ADPCM',
                0x0019 => 'HP CU',
                0x0020 => 'Yamaha ADPCM',
                0x0021 => 'Speech Compression Sonarc',
                0x0022 => 'DSP Group True Speech',
                0x0023 => 'Echo Speech EchoSC1',
                0x0024 => 'Audiofile AF36',
                0x0025 => 'APTX',
                0x0026 => 'AudioFile AF10',
                0x0027 => 'Prosody 1612',
                0x0028 => 'LRC',
                0x0030 => 'Dolby AC2',
                0x0031 => 'GSM610',
                0x0032 => 'MSNAudio',
                0x0033 => 'Antex ADPCME',
                0x0034 => 'Control Res VQLPC',
                0x0035 => 'Digireal',
                0x0036 => 'DigiADPCM',
                0x0037 => 'Control Res CR10',
                0x0038 => 'NMS VBXADPCM',
                0x0039 => 'Roland RDAC',
                0x003a => 'EchoSC3',
                0x003b => 'Rockwell ADPCM',
                0x003c => 'Rockwell Digit LK',
                0x003d => 'Xebec',
                0x0040 => 'Antex Electronics G.721',
                0x0041 => 'G.728 CELP',
                0x0042 => 'MSG723',
                0x0045 => 'G.726 ADPCM',
                0x0050 => 'MPEG',
                0x0052 => 'RT24',
                0x0053 => 'PAC',
                0x0055 => 'MPEG Layer 3',
                0x0059 => 'Lucent G.723',
                0x0060 => 'Cirrus',
                0x0061 => 'ESPCM',
                0x0062 => 'Voxware',
                0x0063 => 'Canopus Atrac',
                0x0064 => 'G.726 ADPCM',
                0x0066 => 'DSAT',
                0x0067 => 'DSAT Display',
                0x0069 => 'Voxware Byte Aligned',
                0x0070 => 'Voxware AC8',
                0x0071 => 'Voxware AC10',
                0x0072 => 'Voxware AC16',
                0x0073 => 'Voxware AC20',
                0x0074 => 'Voxware MetaVoice',
                0x0075 => 'Voxware MetaSound',
                0x0076 => 'Voxware RT29HW',
                0x0077 => 'Voxware VR12',
                0x0078 => 'Voxware VR18',
                0x0079 => 'Voxware TQ40',
                0x0080 => 'Softsound',
                0x0081 => 'Voxware TQ60',
                0x0082 => 'MSRT24',
                0x0083 => 'G.729A',
                0x0084 => 'MVI MV12',
                0x0085 => 'DF G.726',
                0x0086 => 'DF GSM610',
                0x0088 => 'ISIAudio',
                0x0089 => 'Onlive',
                0x0091 => 'SBC24',
                0x0092 => 'Dolby AC3 SPDIF',
                0x0097 => 'ZyXEL ADPCM',
                0x0098 => 'Philips LPCBB',
                0x0099 => 'Packed',
                0x00FF => 'MPEG-4',
                0x0100 => 'Rhetorex ADPCM',
                0x0101 => 'BeCubed Software IRAT',
                0x0111 => 'Vivo G.723',
                0x0112 => 'Vivo Siren',
                0x0123 => 'Digital G.723',
                0x0160 => 'Windows Media v1',
                0x0161 => 'Windows Media v2',
                0x0162 => 'Windows Media 9 Professional',
                0x0163 => 'Windows Media 9 Lossless',
                0x0200 => 'Creative ADPCM',
                0x0202 => 'Creative FastSpeech8',
                0x0203 => 'Creative FastSpeech10',
                0x0220 => 'Quarterdeck',
                0x0300 => 'FM Towns Snd',
                0x0400 => 'BTV Digital',
                0x0680 => 'VME VMPCM',
                0x1000 => 'OLIGSM',
                0x1001 => 'OLIADPCM',
                0x1002 => 'OLICELP',
                0x1003 => 'OLISBC',
                0x1004 => 'OLIOPR',
                0x1100 => 'LH Codec',
                0x1400 => 'Norris',
                0x1401 => 'ISIAudio',
                0x1500 => 'Soundspace Music Compression',
                0x2000 => 'DVM',
                0x2001 => 'DTS Coherent Acoustics 2',
                0x4143 => 'MPEG-4 (Divio)',
            },
        },
        {
            Condition => '$self->{ASF_STREAM_TYPE} =~ /^(Video|JFIF|Degradable JPEG)$/',
            Name => 'ImageWidth',
            Format => 'int32u',
        },
    ],
    56 => {
        Condition => '$self->{ASF_STREAM_TYPE} eq "Audio"',
        Name => 'AudioChannels',
        Format => 'int16u',
    },
    58 => [
        {
            Condition => '$self->{ASF_STREAM_TYPE} eq "Audio"',
            Name => 'AudioSampleRate',
            Format => 'int32u',
        },
        {
            Condition => '$self->{ASF_STREAM_TYPE} =~ /^(Video|JFIF|Degradable JPEG)$/',
            Name => 'ImageHeight',
            Format => 'int32u',
        },
    ],
);

%Image::ExifTool::ASF::HeaderExtension = (
    PROCESS_PROC => \&Image::ExifTool::ASF::ProcessASF,
    '14E6A5CB-C672-4332-8399-A96952065B5A' => 'ExtendedStreamProps',
    'A08649CF-4775-4670-8A16-6E35357566CD' => 'AdvancedMutualExcl',
    'D1465A40-5A79-4338-B71B-E36B8FD6C249' => 'GroupMutualExclusion',
    'D4FED15B-88D3-454F-81F0-ED5C45999E24' => 'StreamPrioritization',
    'A69609E6-517B-11D2-B6AF-00C04FD908E9' => 'BandwidthSharing',
    '7C4346A9-EFE0-4BFC-B229-393EDE415C85' => 'LanguageList',
    'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA' => {
        Name => 'Metadata',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::Metadata' },
    },
    '44231C94-9498-49D1-A141-1D134E457054' => {
        Name => 'MetadataLibrary',
        SubDirectory => { TagTable => 'Image::ExifTool::ASF::Metadata' },
    },
    'D6E229DF-35DA-11D1-9034-00A0C90349BE' => 'IndexParameters',
    '6B203BAD-3F11-48E4-ACA8-D7613DE2CFA7' => 'TimecodeIndexParms',
    '75B22630-668E-11CF-A6D9-00AA0062CE6C' => 'Compatibility',
    '43058533-6981-49E6-9B74-AD12CB86D58C' => 'AdvancedContentEncryption',
    'ABD3D211-A9BA-11cf-8EE6-00C00C205365' => 'Reserved1',
);

%Image::ExifTool::ASF::Metadata = (
    PROCESS_PROC => \&Image::ExifTool::ASF::ProcessMetadata,
);

%Image::ExifTool::ASF::CodecList = (
    PROCESS_PROC => \&ProcessCodecList,
    VideoCodecName => {},
    VideoCodecDescription => {},
    AudioCodecName => {},
    AudioCodecDescription => {},
    OtherCodecName => {},
    OtherCodecDescription => {},
);

#------------------------------------------------------------------------------
# Generate GUID from 16 bytes of binary data
# Inputs: 0) data
# Returns: GUID
sub GetGUID($)
{
    # must do some byte swapping
    my $buff = unpack('H*',pack('NnnNN',unpack('VvvNN',$_[0])));
    $buff =~ s/(.{8})(.{4})(.{4})(.{4})/$1-$2-$3-$4-/;
    return uc($buff);
}

#------------------------------------------------------------------------------
# Process ASF content description
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessContentDescription($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    return 0 if $dirLen < 10;
    my @len = unpack('v5', $$dataPt);
    my $pos = 10;
    my $tag;
    foreach $tag (0..4) {
        my $len = shift @len;
        next unless $len;
        return 0 if $pos + $len > $dirLen;
        my $val = $exifTool->Unicode2Byte(substr($$dataPt,$pos,$len),'II');
        $exifTool->HandleTag($tagTablePtr, $tag, $val);
        $pos += $len;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Process ASF content branding
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessContentBranding($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    return 0 if $dirLen < 40;
    # decode banner image type
    $exifTool->HandleTag($tagTablePtr, 0, unpack('V', $$dataPt));
    # decode banner image, banner URL and copyright URL
    my $pos = 4;
    my $tag;
    foreach $tag (1..3) {
        return 0 if $pos + 4 > $dirLen;
        my $size = unpack("x${pos}V", $$dataPt);
        $pos += 4;
        next unless $size;
        return 0 if $pos + $size > $dirLen;
        my $val = substr($$dataPt, $pos, $size);
        $exifTool->HandleTag($tagTablePtr, $tag, $val);
        $pos += $size;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Read ASF value
# Inputs: 0) ExifTool object ref, 1) data reference, 2) value offset,
#         3) format number, 4) size
# Returns: converted value
sub ReadASF($$$$$)
{
    my ($exifTool, $dataPt, $pos, $format, $size) = @_;
    my @vals;
    if ($format == 0) { # unicode string
        $vals[0] = $exifTool->Unicode2Byte(substr($$dataPt,$pos,$size),'II');
    } elsif ($format == 2) { # 4-byte boolean
        @vals = ReadValue($dataPt, $pos, 'int32u', undef, $size);
        foreach (@vals) {
            $_ = $_ ? 'True' : 'False';
        }
    } elsif ($format == 3) { # int32u
        @vals = ReadValue($dataPt, $pos, 'int32u', undef, $size);
    } elsif ($format == 4) { # int64u
        @vals = ReadValue($dataPt, $pos, 'int64u', undef, $size);
    } elsif ($format == 5) { # int16u
        @vals = ReadValue($dataPt, $pos, 'int16u', undef, $size);
    } else { # any other format (including 1, byte array): return raw data
        $vals[0] = substr($$dataPt,$pos,$size);
    }
    return join ' ', @vals;
}

#------------------------------------------------------------------------------
# Process extended content description
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessExtendedContentDescription($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    return 0 if $dirLen < 2;
    my $count = Get16u($dataPt, 0);
    $verbose and $exifTool->VerboseDir($$dirInfo{DirName}, $count);
    my $pos = 2;
    my $i;
    for ($i=0; $i<$count; ++$i) {
        return 0 if $pos + 6 > $dirLen;
        my $nameLen = unpack("x${pos}v", $$dataPt);
        $pos += 2;
        return 0 if $pos + $nameLen + 4 > $dirLen;
        my $tag = Image::ExifTool::Unicode2Latin(substr($$dataPt,$pos,$nameLen),'v');
        $tag =~ s/^WM\///; # remove leading "WM/"
        $pos += $nameLen;
        my ($dType, $dLen) = unpack("x${pos}v2", $$dataPt);
        my $val = ReadASF($exifTool,$dataPt,$pos+4,$dType,$dLen);
        $exifTool->HandleTag($tagTablePtr, $tag, $val,
            DataPt => $dataPt,
            Start  => $pos + 4,
            Size   => $dLen,
        );
        $pos += 4 + $dLen;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Process WM/Picture preview
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessPreview($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirStart = $$dirInfo{DirStart};
    my $dirLen = $$dirInfo{DirLen};
    return 0 unless $dirLen > 9;
    # extract picture type and length
    my ($type, $picLen) = unpack("x${dirStart}CV", $$dataPt);
    $exifTool->HandleTag($tagTablePtr, 0, $type);
    # extract mime type and description strings (null-terminated unicode strings)
    my $n = $dirLen - 5 - $picLen;
    return 0 if $n & 0x01 or $n < 4;
    my $str = substr($$dataPt, $dirStart+5, $n);
    if ($str =~ /^((?:..)*?)\0\0((?:..)*?)\0\0/) {
        my ($mime, $desc) = ($1, $2);
        $exifTool->HandleTag($tagTablePtr, 1, $mime);
        $exifTool->HandleTag($tagTablePtr, 2, $desc) if length $desc;
    }
    $exifTool->HandleTag($tagTablePtr, 3, substr($$dataPt, $dirStart+5+$n, $picLen));
    return 1;
}

#------------------------------------------------------------------------------
# Process codec list
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessCodecList($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    return 0 if $dirLen < 20;
    my $count = Get32u($dataPt, 16);
    $verbose and $exifTool->VerboseDir($$dirInfo{DirName}, $count);
    my $pos = 20;
    my $i;
    my %codecType = ( 1 => 'Video', 2 => 'Audio' );
    for ($i=0; $i<$count; ++$i) {
        return 0 if $pos + 8 > $dirLen;
        my $type = ($codecType{Get16u($dataPt, $pos)} || 'Other') . 'Codec';
        # stupid Windows programmers: these lengths are in characters (others are in bytes)
        my $nameLen = Get16u($dataPt, $pos + 2) * 2;
        $pos += 4;
        return 0 if $pos + $nameLen + 2 > $dirLen;
        my $name = Image::ExifTool::Unicode2Latin(substr($$dataPt,$pos,$nameLen),'v');
        $exifTool->HandleTag($tagTablePtr, "${type}Name", $name);
        my $descLen = Get16u($dataPt, $pos + $nameLen) * 2;
        $pos += $nameLen + 2;
        return 0 if $pos + $descLen + 2 > $dirLen;
        my $desc = Image::ExifTool::Unicode2Latin(substr($$dataPt,$pos,$descLen),'v');
        $exifTool->HandleTag($tagTablePtr, "${type}Description", $desc);
        my $infoLen = Get16u($dataPt, $pos + $descLen);
        $pos += $descLen + 2 + $infoLen;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Process ASF metadata library
# Inputs: 0) ExifTool object reference, 1) dirInfo ref, 2) tag table reference
# Returns: 1 on success
sub ProcessMetadata($$$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $verbose = $exifTool->Options('Verbose');
    my $dataPt = $$dirInfo{DataPt};
    my $dirLen = $$dirInfo{DirLen};
    return 0 if $dirLen < 2;
    my $count = Get16u($dataPt, 0);
    $verbose and $exifTool->VerboseDir($$dirInfo{DirName}, $count);
    my $pos = 2;
    my $i;
    for ($i=0; $i<$count; ++$i) {
        return 0 if $pos + 12 > $dirLen;
        my ($index, $stream, $nameLen, $dType, $dLen) = unpack("x${pos}v4V", $$dataPt);
        $pos += 12;
        return 0 if $pos + $nameLen + $dLen > $dirLen;
        my $tag = Image::ExifTool::Unicode2Latin(substr($$dataPt,$pos,$nameLen),'v');
        my $val = ReadASF($exifTool,$dataPt,$pos+$nameLen,$dType,$dLen);
        $exifTool->HandleTag($tagTablePtr, $tag, $val,
            DataPt => $dataPt,
            Start  => $pos,
            Size   => $dLen,
        );
        $pos += $nameLen + $dLen;
    }
    return 1;
}

#------------------------------------------------------------------------------
# Extract information from a ASF file
# Inputs: 0) ExifTool object reference, 1) dirInfo reference, 2) tag table ref
# Returns: 1 on success, 0 if this wasn't a valid ASF file
sub ProcessASF($$;$)
{
    my ($exifTool, $dirInfo, $tagTablePtr) = @_;
    my $raf = $$dirInfo{RAF};
    my $verbose = $exifTool->Options('Verbose');
    my $rtnVal = 0;
    my $pos = 0;
    my ($buff, $err, @parentTable, @childEnd, %dumpParms);

    if ($verbose > 2) {
        $dumpParms{MaxLen} = 96 unless $verbose > 3;
        $dumpParms{Prefix} = $$exifTool{INDENT};
        $dumpParms{Out} = $exifTool->Options('TextOut');
    }
    for (;;) {
        last unless $raf->Read($buff, 24) == 24;
        $pos += 24;
        my $tag = GetGUID($buff);
        unless ($tagTablePtr) {
            # verify this is a valid ASF file
            last unless $tag eq '75B22630-668E-11CF-A6D9-00AA0062CE6C';
            my $fileType = $exifTool->{FILE_EXT};
            $fileType = 'ASF' unless $fileType and $fileType =~ /^(ASF|WMV|WMA)$/;
            $exifTool->SetFileType($fileType);
            SetByteOrder('II');
            $tagTablePtr = GetTagTable('Image::ExifTool::ASF::Main');
            $rtnVal = 1;
        }
        my $size = Image::ExifTool::Get64u(\$buff, 16) - 24;
        if ($size > 0xffffffff) {
            $err = 'Large ASF objects not supported';
            last;
        }
        # go back to parent tag table if done with previous children
        if (@childEnd and $pos >= $childEnd[-1]) {
            pop @childEnd;
            $tagTablePtr = pop @parentTable;
            $exifTool->{INDENT} = substr($exifTool->{INDENT},0,-2);
            $dumpParms{Prefix} = $exifTool->{INDENT};
        }
        my $tagInfo = $exifTool->GetTagInfo($tagTablePtr, $tag);
        $verbose and $exifTool->VerboseInfo($tag, $tagInfo);
        if ($tagInfo) {
            my $subdir = $$tagInfo{SubDirectory};
            if ($subdir) {
                my $subTable = GetTagTable($$subdir{TagTable});
                if ($$subTable{PROCESS_PROC} eq \&ProcessASF) {
                    if (defined $$subdir{Size}) {
                        my $s = $$subdir{Size};
                        if ($verbose > 2) {
                            $raf->Read($buff, $s) == $s or $err = 'Truncated file', last;
                            Image::ExifTool::HexDump(\$buff, undef, %dumpParms);
                        } elsif (not $raf->Seek($s, 1)) {
                            $err = 'Seek error';
                            last;
                        }
                        # continue processing linearly using subTable
                        push @parentTable, $tagTablePtr;
                        push @childEnd, $pos + $size;
                        $tagTablePtr = $subTable;
                        $pos += $$subdir{Size};
                        if ($verbose) {
                            $exifTool->{INDENT} .= '| ';
                            $dumpParms{Prefix} = $exifTool->{INDENT};
                            $exifTool->VerboseDir($$tagInfo{Name});
                        }
                        next;
                    }
                } elsif ($raf->Read($buff, $size) == $size) {
                    my %subdirInfo = (
                        DataPt => \$buff,
                        DirStart => 0,
                        DirLen => $size,
                        DirName => $$tagInfo{Name},
                    );
                    if ($verbose > 2) {
                        Image::ExifTool::HexDump(\$buff, undef, %dumpParms);
                    }
                    unless ($exifTool->ProcessDirectory(\%subdirInfo, $subTable)) {
                        $exifTool->Warn("Error processing $$tagInfo{Name} directory");
                    }
                    $pos += $size;
                    next;
                } else {
                    $err = 'Unexpected end of file';
                    last;
                }
            }
        }
        if ($verbose > 2) {
            $raf->Read($buff, $size) == $size or $err = 'Truncated file', last;
            Image::ExifTool::HexDump(\$buff, undef, %dumpParms);
        } elsif (not $raf->Seek($size, 1)) { # skip the block
            $err = 'Seek error';
            last;
        }
        $pos += $size;
    }
    $err and $exifTool->Warn($err);
    return $rtnVal;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::ASF - Read ASF/WMA/WMV meta information

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract
information from Microsoft Advanced Systems Format (ASF) files, including
Windows Media Audio (WMA) and Windows Media Video (WMV) files.

=head1 AUTHOR

Copyright 2003-2006, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://www.microsoft.com/windows/windowsmedia/format/asfspec.aspx>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/ASF Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

