#------------------------------------------------------------------------------
# File:         DICOM.pm
#
# Description:  Read DICOM and ACR-NEMA medical images
#
# Revisions:    2005/11/09 - P. Harvey Created
#               2009/11/19 - P. Harvey Added private GE tags from ref 4
#
# References:   1) http://medical.nema.org/dicom/2004.html
#               2) http://www.sph.sc.edu/comd/rorden/dicom.html
#               3) http://www.dclunie.com/
#               4) http://www.gehealthcare.com/usen/interoperability/dicom/docs/2258357r3.pdf
#------------------------------------------------------------------------------

package Image::ExifTool::DICOM;

use strict;
use vars qw($VERSION);
use Image::ExifTool qw(:DataAccess :Utils);

$VERSION = '1.08';

# DICOM VR (Value Representation) format conversions
my %dicomFormat = (
    FD => 'double',
    FL => 'float',
    OB => 'int8u',
    OF => 'float',
    OW => 'int16u',
    SL => 'int32s',
    SS => 'int16s',
    UL => 'int32u',
    US => 'int16u',
);

# VR elements with 32-bit length in explicit VR syntax
my %vr32 = ( OB=>1, OW=>1, OF=>1, SQ=>1, UT=>1, UN=>1 );

# data elements with implicit VR regardless of syntax
my %implicitVR = (
    'FFFE,E000' => 1,
    'FFFE,E00D' => 1,
    'FFFE,E0DD' => 1,
);

# DICOM tags
# Note: "XxxGroupLength" tags are generated automatically if they don't exist
%Image::ExifTool::DICOM::Main = (
    GROUPS => { 2 => 'Image' },
    PROCESS_PROC => 0,  # set this to zero to omit tags from lookup (way too many!)
    NOTES => q{
        The DICOM format is based on the ACR-NEMA specification, but adds a file
        header and a number of new tags.  ExifTool will extract information from
        either type of file.  The Tag ID's in the following table are the tag group
        and element numbers in hexadecimal, as given in the DICOM specification
        (L<http://medical.nema.org/dicom/2004.html>).  The table below contains
        standard DICOM tags plus some vendor-specific private tags.
    },
    # file meta information group (names end with VR)
    '0002,0000' => { VR => 'UL', Name => 'FileMetaInfoGroupLength' },
    '0002,0001' => { VR => 'OB', Name => 'FileMetaInfoVersion' },
    '0002,0002' => { VR => 'UI', Name => 'MediaStorageSOPClassUID' },
    '0002,0003' => { VR => 'UI', Name => 'MediaStorageSOPInstanceUID' },
    '0002,0010' => { VR => 'UI', Name => 'TransferSyntaxUID' },
    '0002,0012' => { VR => 'UI', Name => 'ImplementationClassUID' },
    '0002,0013' => { VR => 'SH', Name => 'ImplementationVersionName' },
    '0002,0016' => { VR => 'AE', Name => 'SourceApplicationEntityTitle' },
    '0002,0100' => { VR => 'UI', Name => 'PrivateInformationCreatorUID' },
    '0002,0102' => { VR => 'OB', Name => 'PrivateInformation' },
    # directory structuring group
    '0004,1130' => { VR => 'CS', Name => 'FileSetID' },
    '0004,1141' => { VR => 'CS', Name => 'FileSetDescriptorFileID' },
    '0004,1142' => { VR => 'CS', Name => 'SpecificCharacterSetOfFile' },
    '0004,1200' => { VR => 'UL', Name => 'FirstDirectoryRecordOffset' },
    '0004,1202' => { VR => 'UL', Name => 'LastDirectoryRecordOffset' },
    '0004,1212' => { VR => 'US', Name => 'FileSetConsistencyFlag' },
    '0004,1220' => { VR => 'SQ', Name => 'DirectoryRecordSequence' },
    '0004,1400' => { VR => 'UL', Name => 'OffsetOfNextDirectoryRecord' },
    '0004,1410' => { VR => 'US', Name => 'RecordInUseFlag' },
    '0004,1420' => { VR => 'UL', Name => 'LowerLevelDirectoryEntityOffset' },
    '0004,1430' => { VR => 'CS', Name => 'DirectoryRecordType' },
    '0004,1432' => { VR => 'UI', Name => 'PrivateRecordUID' },
    '0004,1500' => { VR => 'CS', Name => 'ReferencedFileID' },
    '0004,1504' => { VR => 'UL', Name => 'MRDRDirectoryRecordOffset' },
    '0004,1510' => { VR => 'UI', Name => 'ReferencedSOPClassUIDInFile' },
    '0004,1511' => { VR => 'UI', Name => 'ReferencedSOPInstanceUIDInFile' },
    '0004,1512' => { VR => 'UI', Name => 'ReferencedTransferSyntaxUIDInFile' },
    '0004,151A' => { VR => 'UI', Name => 'ReferencedRelatedSOPClassUIDInFile' },
    '0004,1600' => { VR => 'UL', Name => 'NumberOfReferences' },
    # identifying group
    '0008,0000' => { VR => 'UL', Name => 'IdentifyingGroupLength' },
    '0008,0001' => { VR => 'RET',Name => 'LengthToEnd' },
    '0008,0005' => { VR => 'CS', Name => 'SpecificCharacterSet' },
    '0008,0008' => { VR => 'CS', Name => 'ImageType' },
    '0008,0010' => { VR => 'RET',Name => 'RecognitionCode' },
    '0008,0012' => { VR => 'DA', Name => 'InstanceCreationDate' },
    '0008,0013' => { VR => 'TM', Name => 'InstanceCreationTime' },
    '0008,0014' => { VR => 'UI', Name => 'InstanceCreatorUID' },
    '0008,0016' => { VR => 'UI', Name => 'SOPClassUID' },
    '0008,0018' => { VR => 'UI', Name => 'SOPInstanceUID' },
    '0008,001A' => { VR => 'UI', Name => 'RelatedGeneralSOPClassUID' },
    '0008,001B' => { VR => 'UI', Name => 'OriginalSpecializedSOPClassUID' },
    '0008,0020' => { VR => 'DA', Name => 'StudyDate' },
    '0008,0021' => { VR => 'DA', Name => 'SeriesDate' },
    '0008,0022' => { VR => 'DA', Name => 'AcquisitionDate' },
    '0008,0023' => { VR => 'DA', Name => 'ContentDate' },
    '0008,0024' => { VR => 'DA', Name => 'OverlayDate' },
    '0008,0025' => { VR => 'DA', Name => 'CurveDate' },
    '0008,002A' => { VR => 'DT', Name => 'AcquisitionDatetime' },
    '0008,0030' => { VR => 'TM', Name => 'StudyTime' },
    '0008,0031' => { VR => 'TM', Name => 'SeriesTime' },
    '0008,0032' => { VR => 'TM', Name => 'AcquisitionTime' },
    '0008,0033' => { VR => 'TM', Name => 'ContentTime' },
    '0008,0034' => { VR => 'TM', Name => 'OverlayTime' },
    '0008,0035' => { VR => 'TM', Name => 'CurveTime' },
    '0008,0040' => { VR => 'RET',Name => 'DataSetType' },
    '0008,0041' => { VR => 'RET',Name => 'DataSetSubtype' },
    '0008,0042' => { VR => 'RET',Name => 'NuclearMedicineSeriesType' },
    '0008,0050' => { VR => 'SH', Name => 'AccessionNumber' },
    '0008,0052' => { VR => 'CS', Name => 'Query-RetrieveLevel' },
    '0008,0054' => { VR => 'AE', Name => 'RetrieveAETitle' },
    '0008,0056' => { VR => 'CS', Name => 'InstanceAvailability' },
    '0008,0058' => { VR => 'UI', Name => 'FailedSOPInstanceUIDList' },
    '0008,0060' => { VR => 'CS', Name => 'Modality' },
    '0008,0061' => { VR => 'CS', Name => 'ModalitiesInStudy' },
    '0008,0062' => { VR => 'UI', Name => 'SOPClassesInStudy' },
    '0008,0064' => { VR => 'CS', Name => 'ConversionType' },
    '0008,0068' => { VR => 'CS', Name => 'PresentationIntentType' },
    '0008,0070' => { VR => 'LO', Name => 'Manufacturer' },
    '0008,0080' => { VR => 'LO', Name => 'InstitutionName' },
    '0008,0081' => { VR => 'ST', Name => 'InstitutionAddress' },
    '0008,0082' => { VR => 'SQ', Name => 'InstitutionCodeSequence' },
    '0008,0090' => { VR => 'PN', Name => 'ReferringPhysiciansName' },
    '0008,0092' => { VR => 'ST', Name => 'ReferringPhysiciansAddress' },
    '0008,0094' => { VR => 'SH', Name => 'ReferringPhysiciansTelephoneNumber' },
    '0008,0096' => { VR => 'SQ', Name => 'ReferringPhysicianIDSequence' },
    '0008,0100' => { VR => 'SH', Name => 'CodeValue' },
    '0008,0102' => { VR => 'SH', Name => 'CodingSchemeDesignator' },
    '0008,0103' => { VR => 'SH', Name => 'CodingSchemeVersion' },
    '0008,0104' => { VR => 'LO', Name => 'CodeMeaning' },
    '0008,0105' => { VR => 'CS', Name => 'MappingResource' },
    '0008,0106' => { VR => 'DT', Name => 'ContextGroupVersion' },
    '0008,0107' => { VR => 'DT', Name => 'ContextGroupLocalVersion' },
    '0008,010B' => { VR => 'CS', Name => 'ContextGroupExtensionFlag' },
    '0008,010C' => { VR => 'UI', Name => 'CodingSchemeUID' },
    '0008,010D' => { VR => 'UI', Name => 'ContextGroupExtensionCreatorUID' },
    '0008,010F' => { VR => 'CS', Name => 'ContextIdentifier' },
    '0008,0110' => { VR => 'SQ', Name => 'CodingSchemeIDSequence' },
    '0008,0112' => { VR => 'LO', Name => 'CodingSchemeRegistry' },
    '0008,0114' => { VR => 'ST', Name => 'CodingSchemeExternalID' },
    '0008,0115' => { VR => 'ST', Name => 'CodingSchemeName' },
    '0008,0116' => { VR => 'ST', Name => 'ResponsibleOrganization' },
    '0008,0201' => { VR => 'SH', Name => 'TimezoneOffsetFromUTC' },
    '0008,1000' => { VR => 'RET',Name => 'NetworkID' },
    '0008,1010' => { VR => 'SH', Name => 'StationName' },
    '0008,1030' => { VR => 'LO', Name => 'StudyDescription' },
    '0008,1032' => { VR => 'SQ', Name => 'ProcedureCodeSequence' },
    '0008,103E' => { VR => 'LO', Name => 'SeriesDescription' },
    '0008,1040' => { VR => 'LO', Name => 'InstitutionalDepartmentName' },
    '0008,1048' => { VR => 'PN', Name => 'PhysicianOfRecord' },
    '0008,1049' => { VR => 'SQ', Name => 'PhysicianOfRecordIDSequence' },
    '0008,1050' => { VR => 'PN', Name => 'PerformingPhysiciansName' },
    '0008,1052' => { VR => 'SQ', Name => 'PerformingPhysicianIDSequence' },
    '0008,1060' => { VR => 'PN', Name => 'NameOfPhysicianReadingStudy' },
    '0008,1062' => { VR => 'SQ', Name => 'PhysicianReadingStudyIDSequence' },
    '0008,1070' => { VR => 'PN', Name => 'OperatorsName' },
    '0008,1072' => { VR => 'SQ', Name => 'OperatorIDSequence' },
    '0008,1080' => { VR => 'LO', Name => 'AdmittingDiagnosesDescription' },
    '0008,1084' => { VR => 'SQ', Name => 'AdmittingDiagnosesCodeSequence' },
    '0008,1090' => { VR => 'LO', Name => 'ManufacturersModelName' },
    '0008,1100' => { VR => 'SQ', Name => 'ReferencedResultsSequence' },
    '0008,1110' => { VR => 'SQ', Name => 'ReferencedStudySequence' },
    '0008,1111' => { VR => 'SQ', Name => 'ReferencedProcedureStepSequence' },
    '0008,1115' => { VR => 'SQ', Name => 'ReferencedSeriesSequence' },
    '0008,1120' => { VR => 'SQ', Name => 'ReferencedPatientSequence' },
    '0008,1125' => { VR => 'SQ', Name => 'ReferencedVisitSequence' },
    '0008,1130' => { VR => 'SQ', Name => 'ReferencedOverlaySequence' },
    '0008,113A' => { VR => 'SQ', Name => 'ReferencedWaveformSequence' },
    '0008,1140' => { VR => 'SQ', Name => 'ReferencedImageSequence' },
    '0008,1145' => { VR => 'SQ', Name => 'ReferencedCurveSequence' },
    '0008,114A' => { VR => 'SQ', Name => 'ReferencedInstanceSequence' },
    '0008,1150' => { VR => 'UI', Name => 'ReferencedSOPClassUID' },
    '0008,1155' => { VR => 'UI', Name => 'ReferencedSOPInstanceUID' },
    '0008,115A' => { VR => 'UI', Name => 'SOPClassesSupported' },
    '0008,1160' => { VR => 'IS', Name => 'ReferencedFrameNumber' },
    '0008,1195' => { VR => 'UI', Name => 'TransactionUID' },
    '0008,1197' => { VR => 'US', Name => 'FailureReason' },
    '0008,1198' => { VR => 'SQ', Name => 'FailedSOPSequence' },
    '0008,1199' => { VR => 'SQ', Name => 'ReferencedSOPSequence' },
    '0008,1200' => { VR => 'SQ', Name => 'OtherReferencedStudiesSequence' },
    '0008,1250' => { VR => 'SQ', Name => 'RelatedSeriesSequence' },
    '0008,2110' => { VR => 'RET',Name => 'LossyImageCompression' },
    '0008,2111' => { VR => 'ST', Name => 'DerivationDescription' },
    '0008,2112' => { VR => 'SQ', Name => 'SourceImageSequence' },
    '0008,2120' => { VR => 'SH', Name => 'StageName' },
    '0008,2122' => { VR => 'IS', Name => 'StageNumber' },
    '0008,2124' => { VR => 'IS', Name => 'NumberOfStages' },
    '0008,2127' => { VR => 'SH', Name => 'ViewName' },
    '0008,2128' => { VR => 'IS', Name => 'ViewNumber' },
    '0008,2129' => { VR => 'IS', Name => 'NumberOfEventTimers' },
    '0008,212A' => { VR => 'IS', Name => 'NumberOfViewsInStage' },
    '0008,2130' => { VR => 'DS', Name => 'EventElapsedTime' },
    '0008,2132' => { VR => 'LO', Name => 'EventTimerName' },
    '0008,2142' => { VR => 'IS', Name => 'StartTrim' },
    '0008,2143' => { VR => 'IS', Name => 'StopTrim' },
    '0008,2144' => { VR => 'IS', Name => 'RecommendedDisplayFrameRate' },
    '0008,2200' => { VR => 'RET',Name => 'TransducerPosition' },
    '0008,2204' => { VR => 'RET',Name => 'TransducerOrientation' },
    '0008,2208' => { VR => 'RET',Name => 'AnatomicStructure' },
    '0008,2218' => { VR => 'SQ', Name => 'AnatomicRegionSequence' },
    '0008,2220' => { VR => 'SQ', Name => 'AnatomicRegionModifierSequence' },
    '0008,2228' => { VR => 'SQ', Name => 'PrimaryAnatomicStructureSequence' },
    '0008,2229' => { VR => 'SQ', Name => 'AnatomicStructureOrRegionSequence' },
    '0008,2230' => { VR => 'SQ', Name => 'AnatomicStructureModifierSequence' },
    '0008,2240' => { VR => 'SQ', Name => 'TransducerPositionSequence' },
    '0008,2242' => { VR => 'SQ', Name => 'TransducerPositionModifierSequence' },
    '0008,2244' => { VR => 'SQ', Name => 'TransducerOrientationSequence' },
    '0008,2246' => { VR => 'SQ', Name => 'TransducerOrientationModifierSeq' },
    '0008,3001' => { VR => 'SQ', Name => 'AlternateRepresentationSequence' },
    '0008,4000' => { VR => 'RET',Name => 'IdentifyingComments' },
    '0008,9007' => { VR => 'CS', Name => 'FrameType' },
    '0008,9092' => { VR => 'SQ', Name => 'ReferencedImageEvidenceSequence' },
    '0008,9121' => { VR => 'SQ', Name => 'ReferencedRawDataSequence' },
    '0008,9123' => { VR => 'UI', Name => 'CreatorVersionUID' },
    '0008,9124' => { VR => 'SQ', Name => 'DerivationImageSequence' },
    '0008,9154' => { VR => 'SQ', Name => 'SourceImageEvidenceSequence' },
    '0008,9205' => { VR => 'CS', Name => 'PixelPresentation' },
    '0008,9206' => { VR => 'CS', Name => 'VolumetricProperties' },
    '0008,9207' => { VR => 'CS', Name => 'VolumeBasedCalculationTechnique' },
    '0008,9208' => { VR => 'CS', Name => 'ComplexImageComponent' },
    '0008,9209' => { VR => 'CS', Name => 'AcquisitionContrast' },
    '0008,9215' => { VR => 'SQ', Name => 'DerivationCodeSequence' },
    '0008,9237' => { VR => 'SQ', Name => 'GrayscalePresentationStateSequence' },
    '0009,1001' => { VR => 'LO', Name => 'FullFidelity' }, #4
    '0009,1002' => { VR => 'SH', Name => 'SuiteID' }, #4
    '0009,1004' => { VR => 'SH', Name => 'ProductID' }, #4
    '0009,1027' => { VR => 'SL', Name => 'ImageActualDate' }, #4
    '0009,1030' => { VR => 'SH', Name => 'ServiceID' }, #4
    '0009,1031' => { VR => 'SH', Name => 'MobileLocationNumber' }, #4
    '0009,10E3' => { VR => 'UI', Name => 'EquipmentUID' }, #4
    '0009,10E6' => { VR => 'SH', Name => 'GenesisVersionNow' }, #4
    '0009,10E7' => { VR => 'UL', Name => 'ExamRecordChecksum' }, #4
    '0009,10E9' => { VR => 'SL', Name => 'ActualSeriesDataTimeStamp' }, #4
    # patient group
    '0010,0000' => { VR => 'UL', Name => 'PatientGroupLength' },
    '0010,0010' => { VR => 'PN', Name => 'PatientsName' },
    '0010,0020' => { VR => 'LO', Name => 'PatientID' },
    '0010,0021' => { VR => 'LO', Name => 'IssuerOfPatientID' },
    '0010,0030' => { VR => 'DA', Name => 'PatientsBirthDate' },
    '0010,0032' => { VR => 'TM', Name => 'PatientsBirthTime' },
    '0010,0040' => { VR => 'CS', Name => 'PatientsSex' },
    '0010,0050' => { VR => 'SQ', Name => 'PatientsInsurancePlanCodeSequence' },
    '0010,0101' => { VR => 'SQ', Name => 'PatientsPrimaryLanguageCodeSeq' },
    '0010,0102' => { VR => 'SQ', Name => 'PatientsPrimaryLanguageCodeModSeq' },
    '0010,1000' => { VR => 'LO', Name => 'OtherPatientIDs' },
    '0010,1001' => { VR => 'PN', Name => 'OtherPatientNames' },
    '0010,1005' => { VR => 'PN', Name => 'PatientsBirthName' },
    '0010,1010' => { VR => 'AS', Name => 'PatientsAge' },
    '0010,1020' => { VR => 'DS', Name => 'PatientsSize' },
    '0010,1030' => { VR => 'DS', Name => 'PatientsWeight' },
    '0010,1040' => { VR => 'LO', Name => 'PatientsAddress' },
    '0010,1050' => { VR => 'RET',Name => 'InsurancePlanIdentification' },
    '0010,1060' => { VR => 'PN', Name => 'PatientsMothersBirthName' },
    '0010,1080' => { VR => 'LO', Name => 'MilitaryRank' },
    '0010,1081' => { VR => 'LO', Name => 'BranchOfService' },
    '0010,1090' => { VR => 'LO', Name => 'MedicalRecordLocator' },
    '0010,2000' => { VR => 'LO', Name => 'MedicalAlerts' },
    '0010,2110' => { VR => 'LO', Name => 'ContrastAllergies' },
    '0010,2150' => { VR => 'LO', Name => 'CountryOfResidence' },
    '0010,2152' => { VR => 'LO', Name => 'RegionOfResidence' },
    '0010,2154' => { VR => 'SH', Name => 'PatientsTelephoneNumbers' },
    '0010,2160' => { VR => 'SH', Name => 'EthnicGroup' },
    '0010,2180' => { VR => 'SH', Name => 'Occupation' },
    '0010,21A0' => { VR => 'CS', Name => 'SmokingStatus' },
    '0010,21B0' => { VR => 'LT', Name => 'AdditionalPatientHistory' },
    '0010,21C0' => { VR => 'US', Name => 'PregnancyStatus' },
    '0010,21D0' => { VR => 'DA', Name => 'LastMenstrualDate' },
    '0010,21F0' => { VR => 'LO', Name => 'PatientsReligiousPreference' },
    '0010,4000' => { VR => 'LT', Name => 'PatientComments' },
    '0011,1010' => { VR => 'SS', Name => 'PatientStatus' }, #4
    '0012,0010' => { VR => 'LO', Name => 'ClinicalTrialSponsorName' },
    '0012,0020' => { VR => 'LO', Name => 'ClinicalTrialProtocolID' },
    '0012,0021' => { VR => 'LO', Name => 'ClinicalTrialProtocolName' },
    '0012,0030' => { VR => 'LO', Name => 'ClinicalTrialSiteID' },
    '0012,0031' => { VR => 'LO', Name => 'ClinicalTrialSiteName' },
    '0012,0040' => { VR => 'LO', Name => 'ClinicalTrialSubjectID' },
    '0012,0042' => { VR => 'LO', Name => 'ClinicalTrialSubjectReadingID' },
    '0012,0050' => { VR => 'LO', Name => 'ClinicalTrialTimePointID' },
    '0012,0051' => { VR => 'ST', Name => 'ClinicalTrialTimePointDescription' },
    '0012,0060' => { VR => 'LO', Name => 'ClinicalTrialCoordinatingCenter' },
    # acquisition group
    '0018,0000' => { VR => 'UL', Name => 'AcquisitionGroupLength' },
    '0018,0010' => { VR => 'LO', Name => 'Contrast-BolusAgent' },
    '0018,0012' => { VR => 'SQ', Name => 'Contrast-BolusAgentSequence' },
    '0018,0014' => { VR => 'SQ', Name => 'Contrast-BolusAdministrationRoute' },
    '0018,0015' => { VR => 'CS', Name => 'BodyPartExamined' },
    '0018,0020' => { VR => 'CS', Name => 'ScanningSequence' },
    '0018,0021' => { VR => 'CS', Name => 'SequenceVariant' },
    '0018,0022' => { VR => 'CS', Name => 'ScanOptions' },
    '0018,0023' => { VR => 'CS', Name => 'MRAcquisitionType' },
    '0018,0024' => { VR => 'SH', Name => 'SequenceName' },
    '0018,0025' => { VR => 'CS', Name => 'AngioFlag' },
    '0018,0026' => { VR => 'SQ', Name => 'InterventionDrugInformationSeq' },
    '0018,0027' => { VR => 'TM', Name => 'InterventionDrugStopTime' },
    '0018,0028' => { VR => 'DS', Name => 'InterventionDrugDose' },
    '0018,0029' => { VR => 'SQ', Name => 'InterventionDrugSequence' },
    '0018,002A' => { VR => 'SQ', Name => 'AdditionalDrugSequence' },
    '0018,0030' => { VR => 'RET',Name => 'Radionuclide' },
    '0018,0031' => { VR => 'LO', Name => 'Radiopharmaceutical' },
    '0018,0032' => { VR => 'RET',Name => 'EnergyWindowCenterline' },
    '0018,0033' => { VR => 'RET',Name => 'EnergyWindowTotalWidth' },
    '0018,0034' => { VR => 'LO', Name => 'InterventionDrugName' },
    '0018,0035' => { VR => 'TM', Name => 'InterventionDrugStartTime' },
    '0018,0036' => { VR => 'SQ', Name => 'InterventionSequence' },
    '0018,0037' => { VR => 'RET',Name => 'TherapyType' },
    '0018,0038' => { VR => 'CS', Name => 'InterventionStatus' },
    '0018,0039' => { VR => 'RET',Name => 'TherapyDescription' },
    '0018,003A' => { VR => 'ST', Name => 'InterventionDescription' },
    '0018,0040' => { VR => 'IS', Name => 'CineRate' },
    '0018,0050' => { VR => 'DS', Name => 'SliceThickness' },
    '0018,0060' => { VR => 'DS', Name => 'KVP' },
    '0018,0070' => { VR => 'IS', Name => 'CountsAccumulated' },
    '0018,0071' => { VR => 'CS', Name => 'AcquisitionTerminationCondition' },
    '0018,0072' => { VR => 'DS', Name => 'EffectiveDuration' },
    '0018,0073' => { VR => 'CS', Name => 'AcquisitionStartCondition' },
    '0018,0074' => { VR => 'IS', Name => 'AcquisitionStartConditionData' },
    '0018,0075' => { VR => 'IS', Name => 'AcquisitionEndConditionData' },
    '0018,0080' => { VR => 'DS', Name => 'RepetitionTime' },
    '0018,0081' => { VR => 'DS', Name => 'EchoTime' },
    '0018,0082' => { VR => 'DS', Name => 'InversionTime' },
    '0018,0083' => { VR => 'DS', Name => 'NumberOfAverages' },
    '0018,0084' => { VR => 'DS', Name => 'ImagingFrequency' },
    '0018,0085' => { VR => 'SH', Name => 'ImagedNucleus' },
    '0018,0086' => { VR => 'IS', Name => 'EchoNumber' },
    '0018,0087' => { VR => 'DS', Name => 'MagneticFieldStrength' },
    '0018,0088' => { VR => 'DS', Name => 'SpacingBetweenSlices' },
    '0018,0089' => { VR => 'IS', Name => 'NumberOfPhaseEncodingSteps' },
    '0018,0090' => { VR => 'DS', Name => 'DataCollectionDiameter' },
    '0018,0091' => { VR => 'IS', Name => 'EchoTrainLength' },
    '0018,0093' => { VR => 'DS', Name => 'PercentSampling' },
    '0018,0094' => { VR => 'DS', Name => 'PercentPhaseFieldOfView' },
    '0018,0095' => { VR => 'DS', Name => 'PixelBandwidth' },
    '0018,1000' => { VR => 'LO', Name => 'DeviceSerialNumber' },
    '0018,1004' => { VR => 'LO', Name => 'PlateID' },
    '0018,1010' => { VR => 'LO', Name => 'SecondaryCaptureDeviceID' },
    '0018,1011' => { VR => 'LO', Name => 'HardcopyCreationDeviceID' },
    '0018,1012' => { VR => 'DA', Name => 'DateOfSecondaryCapture' },
    '0018,1014' => { VR => 'TM', Name => 'TimeOfSecondaryCapture' },
    '0018,1016' => { VR => 'LO', Name => 'SecondaryCaptureDeviceManufacturer' },
    '0018,1017' => { VR => 'LO', Name => 'HardcopyDeviceManufacturer' },
    '0018,1018' => { VR => 'LO', Name => 'SecondaryCaptureDeviceModelName' },
    '0018,1019' => { VR => 'LO', Name => 'SecondaryCaptureDeviceSoftwareVers' },
    '0018,101A' => { VR => 'LO', Name => 'HardcopyDeviceSoftwareVersion' },
    '0018,101B' => { VR => 'LO', Name => 'HardcopyDeviceModelName' },
    '0018,1020' => { VR => 'LO', Name => 'SoftwareVersion' },
    '0018,1022' => { VR => 'SH', Name => 'VideoImageFormatAcquired' },
    '0018,1023' => { VR => 'LO', Name => 'DigitalImageFormatAcquired' },
    '0018,1030' => { VR => 'LO', Name => 'ProtocolName' },
    '0018,1040' => { VR => 'LO', Name => 'Contrast-BolusRoute' },
    '0018,1041' => { VR => 'DS', Name => 'Contrast-BolusVolume' },
    '0018,1042' => { VR => 'TM', Name => 'Contrast-BolusStartTime' },
    '0018,1043' => { VR => 'TM', Name => 'Contrast-BolusStopTime' },
    '0018,1044' => { VR => 'DS', Name => 'Contrast-BolusTotalDose' },
    '0018,1045' => { VR => 'IS', Name => 'SyringeCounts' },
    '0018,1046' => { VR => 'DS', Name => 'ContrastFlowRate' },
    '0018,1047' => { VR => 'DS', Name => 'ContrastFlowDuration' },
    '0018,1048' => { VR => 'CS', Name => 'Contrast-BolusIngredient' },
    '0018,1049' => { VR => 'DS', Name => 'Contrast-BolusConcentration' },
    '0018,1050' => { VR => 'DS', Name => 'SpatialResolution' },
    '0018,1060' => { VR => 'DS', Name => 'TriggerTime' },
    '0018,1061' => { VR => 'LO', Name => 'TriggerSourceOrType' },
    '0018,1062' => { VR => 'IS', Name => 'NominalInterval' },
    '0018,1063' => { VR => 'DS', Name => 'FrameTime' },
    '0018,1064' => { VR => 'LO', Name => 'FramingType' },
    '0018,1065' => { VR => 'DS', Name => 'FrameTimeVector' },
    '0018,1066' => { VR => 'DS', Name => 'FrameDelay' },
    '0018,1067' => { VR => 'DS', Name => 'ImageTriggerDelay' },
    '0018,1068' => { VR => 'DS', Name => 'MultiplexGroupTimeOffset' },
    '0018,1069' => { VR => 'DS', Name => 'TriggerTimeOffset' },
    '0018,106A' => { VR => 'CS', Name => 'SynchronizationTrigger' },
    '0018,106C' => { VR => 'US', Name => 'SynchronizationChannel' },
    '0018,106E' => { VR => 'UL', Name => 'TriggerSamplePosition' },
    '0018,1070' => { VR => 'LO', Name => 'RadiopharmaceuticalRoute' },
    '0018,1071' => { VR => 'DS', Name => 'RadiopharmaceuticalVolume' },
    '0018,1072' => { VR => 'TM', Name => 'RadiopharmaceuticalStartTime' },
    '0018,1073' => { VR => 'TM', Name => 'RadiopharmaceuticalStopTime' },
    '0018,1074' => { VR => 'DS', Name => 'RadionuclideTotalDose' },
    '0018,1075' => { VR => 'DS', Name => 'RadionuclideHalfLife' },
    '0018,1076' => { VR => 'DS', Name => 'RadionuclidePositronFraction' },
    '0018,1077' => { VR => 'DS', Name => 'RadiopharmaceuticalSpecActivity' },
    '0018,1080' => { VR => 'CS', Name => 'BeatRejectionFlag' },
    '0018,1081' => { VR => 'IS', Name => 'LowRRValue' },
    '0018,1082' => { VR => 'IS', Name => 'HighRRValue' },
    '0018,1083' => { VR => 'IS', Name => 'IntervalsAcquired' },
    '0018,1084' => { VR => 'IS', Name => 'IntervalsRejected' },
    '0018,1085' => { VR => 'LO', Name => 'PVCRejection' },
    '0018,1086' => { VR => 'IS', Name => 'SkipBeats' },
    '0018,1088' => { VR => 'IS', Name => 'HeartRate' },
    '0018,1090' => { VR => 'IS', Name => 'CardiacNumberOfImages' },
    '0018,1094' => { VR => 'IS', Name => 'TriggerWindow' },
    '0018,1100' => { VR => 'DS', Name => 'ReconstructionDiameter' },
    '0018,1110' => { VR => 'DS', Name => 'DistanceSourceToDetector' },
    '0018,1111' => { VR => 'DS', Name => 'DistanceSourceToPatient' },
    '0018,1114' => { VR => 'DS', Name => 'EstimatedRadiographicMagnification' },
    '0018,1120' => { VR => 'DS', Name => 'Gantry-DetectorTilt' },
    '0018,1121' => { VR => 'DS', Name => 'Gantry-DetectorSlew' },
    '0018,1130' => { VR => 'DS', Name => 'TableHeight' },
    '0018,1131' => { VR => 'DS', Name => 'TableTraverse' },
    '0018,1134' => { VR => 'CS', Name => 'TableMotion' },
    '0018,1135' => { VR => 'DS', Name => 'TableVerticalIncrement' },
    '0018,1136' => { VR => 'DS', Name => 'TableLateralIncrement' },
    '0018,1137' => { VR => 'DS', Name => 'TableLongitudinalIncrement' },
    '0018,1138' => { VR => 'DS', Name => 'TableAngle' },
    '0018,113A' => { VR => 'CS', Name => 'TableType' },
    '0018,1140' => { VR => 'CS', Name => 'RotationDirection' },
    '0018,1141' => { VR => 'DS', Name => 'AngularPosition' },
    '0018,1142' => { VR => 'DS', Name => 'RadialPosition' },
    '0018,1143' => { VR => 'DS', Name => 'ScanArc' },
    '0018,1144' => { VR => 'DS', Name => 'AngularStep' },
    '0018,1145' => { VR => 'DS', Name => 'CenterOfRotationOffset' },
    '0018,1146' => { VR => 'RET',Name => 'RotationOffset' },
    '0018,1147' => { VR => 'CS', Name => 'FieldOfViewShape' },
    '0018,1149' => { VR => 'IS', Name => 'FieldOfViewDimensions' },
    '0018,1150' => { VR => 'IS', Name => 'ExposureTime' },
    '0018,1151' => { VR => 'IS', Name => 'XRayTubeCurrent' },
    '0018,1152' => { VR => 'IS', Name => 'Exposure' },
    '0018,1153' => { VR => 'IS', Name => 'ExposureInMicroAmpSec' },
    '0018,1154' => { VR => 'DS', Name => 'AveragePulseWidth' },
    '0018,1155' => { VR => 'CS', Name => 'RadiationSetting' },
    '0018,1156' => { VR => 'CS', Name => 'RectificationType' },
    '0018,115A' => { VR => 'CS', Name => 'RadiationMode' },
    '0018,115E' => { VR => 'DS', Name => 'ImageAreaDoseProduct' },
    '0018,1160' => { VR => 'SH', Name => 'FilterType' },
    '0018,1161' => { VR => 'LO', Name => 'TypeOfFilters' },
    '0018,1162' => { VR => 'DS', Name => 'IntensifierSize' },
    '0018,1164' => { VR => 'DS', Name => 'ImagerPixelSpacing' },
    '0018,1166' => { VR => 'CS', Name => 'Grid' },
    '0018,1170' => { VR => 'IS', Name => 'GeneratorPower' },
    '0018,1180' => { VR => 'SH', Name => 'Collimator-GridName' },
    '0018,1181' => { VR => 'CS', Name => 'CollimatorType' },
    '0018,1182' => { VR => 'IS', Name => 'FocalDistance' },
    '0018,1183' => { VR => 'DS', Name => 'XFocusCenter' },
    '0018,1184' => { VR => 'DS', Name => 'YFocusCenter' },
    '0018,1190' => { VR => 'DS', Name => 'FocalSpot' },
    '0018,1191' => { VR => 'CS', Name => 'AnodeTargetMaterial' },
    '0018,11A0' => { VR => 'DS', Name => 'BodyPartThickness' },
    '0018,11A2' => { VR => 'DS', Name => 'CompressionForce' },
    '0018,1200' => { VR => 'DA', Name => 'DateOfLastCalibration' },
    '0018,1201' => { VR => 'TM', Name => 'TimeOfLastCalibration' },
    '0018,1210' => { VR => 'SH', Name => 'ConvolutionKernel' },
    '0018,1240' => { VR => 'RET',Name => 'Upper-LowerPixelValues' },
    '0018,1242' => { VR => 'IS', Name => 'ActualFrameDuration' },
    '0018,1243' => { VR => 'IS', Name => 'CountRate' },
    '0018,1244' => { VR => 'US', Name => 'PreferredPlaybackSequencing' },
    '0018,1250' => { VR => 'SH', Name => 'ReceiveCoilName' },
    '0018,1251' => { VR => 'SH', Name => 'TransmitCoilName' },
    '0018,1260' => { VR => 'SH', Name => 'PlateType' },
    '0018,1261' => { VR => 'LO', Name => 'PhosphorType' },
    '0018,1300' => { VR => 'DS', Name => 'ScanVelocity' },
    '0018,1301' => { VR => 'CS', Name => 'WholeBodyTechnique' },
    '0018,1302' => { VR => 'IS', Name => 'ScanLength' },
    '0018,1310' => { VR => 'US', Name => 'AcquisitionMatrix' },
    '0018,1312' => { VR => 'CS', Name => 'InPlanePhaseEncodingDirection' },
    '0018,1314' => { VR => 'DS', Name => 'FlipAngle' },
    '0018,1315' => { VR => 'CS', Name => 'VariableFlipAngleFlag' },
    '0018,1316' => { VR => 'DS', Name => 'SAR' },
    '0018,1318' => { VR => 'DS', Name => 'DB-Dt' },
    '0018,1400' => { VR => 'LO', Name => 'AcquisitionDeviceProcessingDescr' },
    '0018,1401' => { VR => 'LO', Name => 'AcquisitionDeviceProcessingCode' },
    '0018,1402' => { VR => 'CS', Name => 'CassetteOrientation' },
    '0018,1403' => { VR => 'CS', Name => 'CassetteSize' },
    '0018,1404' => { VR => 'US', Name => 'ExposuresonPlate' },
    '0018,1405' => { VR => 'IS', Name => 'RelativeXRayExposure' },
    '0018,1450' => { VR => 'DS', Name => 'ColumnAngulation' },
    '0018,1460' => { VR => 'DS', Name => 'TomoLayerHeight' },
    '0018,1470' => { VR => 'DS', Name => 'TomoAngle' },
    '0018,1480' => { VR => 'DS', Name => 'TomoTime' },
    '0018,1490' => { VR => 'CS', Name => 'TomoType' },
    '0018,1491' => { VR => 'CS', Name => 'TomoClass' },
    '0018,1495' => { VR => 'IS', Name => 'NumberOfTomosynthesisSourceImages' },
    '0018,1500' => { VR => 'CS', Name => 'PositionerMotion' },
    '0018,1508' => { VR => 'CS', Name => 'PositionerType' },
    '0018,1510' => { VR => 'DS', Name => 'PositionerPrimaryAngle' },
    '0018,1511' => { VR => 'DS', Name => 'PositionerSecondaryAngle' },
    '0018,1520' => { VR => 'DS', Name => 'PositionerPrimaryAngleIncrement' },
    '0018,1521' => { VR => 'DS', Name => 'PositionerSecondaryAngleIncrement' },
    '0018,1530' => { VR => 'DS', Name => 'DetectorPrimaryAngle' },
    '0018,1531' => { VR => 'DS', Name => 'DetectorSecondaryAngle' },
    '0018,1600' => { VR => 'CS', Name => 'ShutterShape' },
    '0018,1602' => { VR => 'IS', Name => 'ShutterLeftVerticalEdge' },
    '0018,1604' => { VR => 'IS', Name => 'ShutterRightVerticalEdge' },
    '0018,1606' => { VR => 'IS', Name => 'ShutterUpperHorizontalEdge' },
    '0018,1608' => { VR => 'IS', Name => 'ShutterLowerHorizontalEdge' },
    '0018,1610' => { VR => 'IS', Name => 'CenterOfCircularShutter' },
    '0018,1612' => { VR => 'IS', Name => 'RadiusOfCircularShutter' },
    '0018,1620' => { VR => 'IS', Name => 'VerticesOfPolygonalShutter' },
    '0018,1622' => { VR => 'US', Name => 'ShutterPresentationValue' },
    '0018,1623' => { VR => 'US', Name => 'ShutterOverlayGroup' },
    '0018,1700' => { VR => 'CS', Name => 'CollimatorShape' },
    '0018,1702' => { VR => 'IS', Name => 'CollimatorLeftVerticalEdge' },
    '0018,1704' => { VR => 'IS', Name => 'CollimatorRightVerticalEdge' },
    '0018,1706' => { VR => 'IS', Name => 'CollimatorUpperHorizontalEdge' },
    '0018,1708' => { VR => 'IS', Name => 'CollimatorLowerHorizontalEdge' },
    '0018,1710' => { VR => 'IS', Name => 'CenterOfCircularCollimator' },
    '0018,1712' => { VR => 'IS', Name => 'RadiusOfCircularCollimator' },
    '0018,1720' => { VR => 'IS', Name => 'VerticesOfPolygonalCollimator' },
    '0018,1800' => { VR => 'CS', Name => 'AcquisitionTimeSynchronized' },
    '0018,1801' => { VR => 'SH', Name => 'TimeSource' },
    '0018,1802' => { VR => 'CS', Name => 'TimeDistributionProtocol' },
    '0018,1803' => { VR => 'LO', Name => 'NTPSourceAddress' },
    '0018,2001' => { VR => 'IS', Name => 'PageNumberVector' },
    '0018,2002' => { VR => 'SH', Name => 'FrameLabelVector' },
    '0018,2003' => { VR => 'DS', Name => 'FramePrimaryAngleVector' },
    '0018,2004' => { VR => 'DS', Name => 'FrameSecondaryAngleVector' },
    '0018,2005' => { VR => 'DS', Name => 'SliceLocationVector' },
    '0018,2006' => { VR => 'SH', Name => 'DisplayWindowLabelVector' },
    '0018,2010' => { VR => 'DS', Name => 'NominalScannedPixelSpacing' },
    '0018,2020' => { VR => 'CS', Name => 'DigitizingDeviceTransportDirection' },
    '0018,2030' => { VR => 'DS', Name => 'RotationOfScannedFilm' },
    '0018,3100' => { VR => 'CS', Name => 'IVUSAcquisition' },
    '0018,3101' => { VR => 'DS', Name => 'IVUSPullbackRate' },
    '0018,3102' => { VR => 'DS', Name => 'IVUSGatedRate' },
    '0018,3103' => { VR => 'IS', Name => 'IVUSPullbackStartFrameNumber' },
    '0018,3104' => { VR => 'IS', Name => 'IVUSPullbackStopFrameNumber' },
    '0018,3105' => { VR => 'IS', Name => 'LesionNumber' },
    '0018,4000' => { VR => 'RET',Name => 'AcquisitionComments' },
    '0018,5000' => { VR => 'SH', Name => 'OutputPower' },
    '0018,5010' => { VR => 'LO', Name => 'TransducerData' },
    '0018,5012' => { VR => 'DS', Name => 'FocusDepth' },
    '0018,5020' => { VR => 'LO', Name => 'ProcessingFunction' },
    '0018,5021' => { VR => 'LO', Name => 'PostprocessingFunction' },
    '0018,5022' => { VR => 'DS', Name => 'MechanicalIndex' },
    '0018,5024' => { VR => 'DS', Name => 'BoneThermalIndex' },
    '0018,5026' => { VR => 'DS', Name => 'CranialThermalIndex' },
    '0018,5027' => { VR => 'DS', Name => 'SoftTissueThermalIndex' },
    '0018,5028' => { VR => 'DS', Name => 'SoftTissueFocusThermalIndex' },
    '0018,5029' => { VR => 'DS', Name => 'SoftTissueSurfaceThermalIndex' },
    '0018,5030' => { VR => 'RET',Name => 'DynamicRange' },
    '0018,5040' => { VR => 'RET',Name => 'TotalGain' },
    '0018,5050' => { VR => 'IS', Name => 'DepthOfScanField' },
    '0018,5100' => { VR => 'CS', Name => 'PatientPosition' },
    '0018,5101' => { VR => 'CS', Name => 'ViewPosition' },
    '0018,5104' => { VR => 'SQ', Name => 'ProjectionEponymousNameCodeSeq' },
    '0018,5210' => { VR => 'RET',Name => 'ImageTransformationMatrix' },
    '0018,5212' => { VR => 'RET',Name => 'ImageTranslationVector' },
    '0018,6000' => { VR => 'DS', Name => 'Sensitivity' },
    '0018,6011' => { VR => 'SQ', Name => 'SequenceOfUltrasoundRegions' },
    '0018,6012' => { VR => 'US', Name => 'RegionSpatialFormat' },
    '0018,6014' => { VR => 'US', Name => 'RegionDataType' },
    '0018,6016' => { VR => 'UL', Name => 'RegionFlags' },
    '0018,6018' => { VR => 'UL', Name => 'RegionLocationMinX0' },
    '0018,601A' => { VR => 'UL', Name => 'RegionLocationMinY0' },
    '0018,601C' => { VR => 'UL', Name => 'RegionLocationMaxX1' },
    '0018,601E' => { VR => 'UL', Name => 'RegionLocationMaxY1' },
    '0018,6020' => { VR => 'SL', Name => 'ReferencePixelX0' },
    '0018,6022' => { VR => 'SL', Name => 'ReferencePixelY0' },
    '0018,6024' => { VR => 'US', Name => 'PhysicalUnitsXDirection' },
    '0018,6026' => { VR => 'US', Name => 'PhysicalUnitsYDirection' },
    '0018,6028' => { VR => 'FD', Name => 'ReferencePixelPhysicalValueX' },
    '0018,602A' => { VR => 'FD', Name => 'ReferencePixelPhysicalValueY' },
    '0018,602C' => { VR => 'FD', Name => 'PhysicalDeltaX' },
    '0018,602E' => { VR => 'FD', Name => 'PhysicalDeltaY' },
    '0018,6030' => { VR => 'UL', Name => 'TransducerFrequency' },
    '0018,6031' => { VR => 'CS', Name => 'TransducerType' },
    '0018,6032' => { VR => 'UL', Name => 'PulseRepetitionFrequency' },
    '0018,6034' => { VR => 'FD', Name => 'DopplerCorrectionAngle' },
    '0018,6036' => { VR => 'FD', Name => 'SteeringAngle' },
    '0018,6038' => { VR => 'RET',Name => 'DopplerSampleVolumeXPositionUL' },
    '0018,6039' => { VR => 'SL', Name => 'DopplerSampleVolumeXPosition' },
    '0018,603A' => { VR => 'RET',Name => 'DopplerSampleVolumeYPositionUL' },
    '0018,603B' => { VR => 'SL', Name => 'DopplerSampleVolumeYPosition' },
    '0018,603C' => { VR => 'RET',Name => 'TMLinePositionX0UL' },
    '0018,603D' => { VR => 'SL', Name => 'TMLinePositionX0' },
    '0018,603E' => { VR => 'RET',Name => 'TMLinePositionY0UL' },
    '0018,603F' => { VR => 'SL', Name => 'TMLinePositionY0' },
    '0018,6040' => { VR => 'RET',Name => 'TMLinePositionX1UL' },
    '0018,6041' => { VR => 'SL', Name => 'TMLinePositionX1' },
    '0018,6042' => { VR => 'RET',Name => 'TMLinePositionY1UL' },
    '0018,6043' => { VR => 'SL', Name => 'TMLinePositionY1' },
    '0018,6044' => { VR => 'US', Name => 'PixelComponentOrganization' },
    '0018,6046' => { VR => 'UL', Name => 'PixelComponentMask' },
    '0018,6048' => { VR => 'UL', Name => 'PixelComponentRangeStart' },
    '0018,604A' => { VR => 'UL', Name => 'PixelComponentRangeStop' },
    '0018,604C' => { VR => 'US', Name => 'PixelComponentPhysicalUnits' },
    '0018,604E' => { VR => 'US', Name => 'PixelComponentDataType' },
    '0018,6050' => { VR => 'UL', Name => 'NumberOfTableBreakPoints' },
    '0018,6052' => { VR => 'UL', Name => 'TableOfXBreakPoints' },
    '0018,6054' => { VR => 'FD', Name => 'TableOfYBreakPoints' },
    '0018,6056' => { VR => 'UL', Name => 'NumberOfTableEntries' },
    '0018,6058' => { VR => 'UL', Name => 'TableOfPixelValues' },
    '0018,605A' => { VR => 'FL', Name => 'TableOfParameterValues' },
    '0018,6060' => { VR => 'FL', Name => 'RWaveTimeVector' },
    '0018,7000' => { VR => 'CS', Name => 'DetectorConditionsNominalFlag' },
    '0018,7001' => { VR => 'DS', Name => 'DetectorTemperature' },
    '0018,7004' => { VR => 'CS', Name => 'DetectorType' },
    '0018,7005' => { VR => 'CS', Name => 'DetectorConfiguration' },
    '0018,7006' => { VR => 'LT', Name => 'DetectorDescription' },
    '0018,7008' => { VR => 'LT', Name => 'DetectorMode' },
    '0018,700A' => { VR => 'SH', Name => 'DetectorID' },
    '0018,700C' => { VR => 'DA', Name => 'DateOfLastDetectorCalibration' },
    '0018,700E' => { VR => 'TM', Name => 'TimeOfLastDetectorCalibration' },
    '0018,7010' => { VR => 'IS', Name => 'DetectorExposuresSinceCalibration' },
    '0018,7011' => { VR => 'IS', Name => 'DetectorExposuresSinceManufactured' },
    '0018,7012' => { VR => 'DS', Name => 'DetectorTimeSinceLastExposure' },
    '0018,7014' => { VR => 'DS', Name => 'DetectorActiveTime' },
    '0018,7016' => { VR => 'DS', Name => 'DetectorActiveOffsetFromExposure' },
    '0018,701A' => { VR => 'DS', Name => 'DetectorBinning' },
    '0018,7020' => { VR => 'DS', Name => 'DetectorElementPhysicalSize' },
    '0018,7022' => { VR => 'DS', Name => 'DetectorElementSpacing' },
    '0018,7024' => { VR => 'CS', Name => 'DetectorActiveShape' },
    '0018,7026' => { VR => 'DS', Name => 'DetectorActiveDimensions' },
    '0018,7028' => { VR => 'DS', Name => 'DetectorActiveOrigin' },
    '0018,702A' => { VR => 'LO', Name => 'DetectorManufacturerName' },
    '0018,702B' => { VR => 'LO', Name => 'DetectorManufacturersModelName' },
    '0018,7030' => { VR => 'DS', Name => 'FieldOfViewOrigin' },
    '0018,7032' => { VR => 'DS', Name => 'FieldOfViewRotation' },
    '0018,7034' => { VR => 'CS', Name => 'FieldOfViewHorizontalFlip' },
    '0018,7040' => { VR => 'LT', Name => 'GridAbsorbingMaterial' },
    '0018,7041' => { VR => 'LT', Name => 'GridSpacingMaterial' },
    '0018,7042' => { VR => 'DS', Name => 'GridThickness' },
    '0018,7044' => { VR => 'DS', Name => 'GridPitch' },
    '0018,7046' => { VR => 'IS', Name => 'GridAspectRatio' },
    '0018,7048' => { VR => 'DS', Name => 'GridPeriod' },
    '0018,704C' => { VR => 'DS', Name => 'GridFocalDistance' },
    '0018,7050' => { VR => 'CS', Name => 'FilterMaterial' },
    '0018,7052' => { VR => 'DS', Name => 'FilterThicknessMinimum' },
    '0018,7054' => { VR => 'DS', Name => 'FilterThicknessMaximum' },
    '0018,7060' => { VR => 'CS', Name => 'ExposureControlMode' },
    '0018,7062' => { VR => 'LT', Name => 'ExposureControlModeDescription' },
    '0018,7064' => { VR => 'CS', Name => 'ExposureStatus' },
    '0018,7065' => { VR => 'DS', Name => 'PhototimerSetting' },
    '0018,8150' => { VR => 'DS', Name => 'ExposureTimeInMicroSec' },
    '0018,8151' => { VR => 'DS', Name => 'XRayTubeCurrentInMicroAmps' },
    '0018,9004' => { VR => 'CS', Name => 'ContentQualification' },
    '0018,9005' => { VR => 'SH', Name => 'PulseSequenceName' },
    '0018,9006' => { VR => 'SQ', Name => 'MRImagingModifierSequence' },
    '0018,9008' => { VR => 'CS', Name => 'EchoPulseSequence' },
    '0018,9009' => { VR => 'CS', Name => 'InversionRecovery' },
    '0018,9010' => { VR => 'CS', Name => 'FlowCompensation' },
    '0018,9011' => { VR => 'CS', Name => 'MultipleSpinEcho' },
    '0018,9012' => { VR => 'CS', Name => 'MultiPlanarExcitation' },
    '0018,9014' => { VR => 'CS', Name => 'PhaseContrast' },
    '0018,9015' => { VR => 'CS', Name => 'TimeOfFlightContrast' },
    '0018,9016' => { VR => 'CS', Name => 'Spoiling' },
    '0018,9017' => { VR => 'CS', Name => 'SteadyStatePulseSequence' },
    '0018,9018' => { VR => 'CS', Name => 'EchoPlanarPulseSequence' },
    '0018,9019' => { VR => 'FD', Name => 'TagAngleFirstAxis' },
    '0018,9020' => { VR => 'CS', Name => 'MagnetizationTransfer' },
    '0018,9021' => { VR => 'CS', Name => 'T2Preparation' },
    '0018,9022' => { VR => 'CS', Name => 'BloodSignalNulling' },
    '0018,9022' => { VR => 'CS', Name => 'BloodSignalNulling' },
    '0018,9024' => { VR => 'CS', Name => 'SaturationRecovery' },
    '0018,9025' => { VR => 'CS', Name => 'SpectrallySelectedSuppression' },
    '0018,9026' => { VR => 'CS', Name => 'SpectrallySelectedExcitation' },
    '0018,9027' => { VR => 'CS', Name => 'SpatialPreSaturation' },
    '0018,9028' => { VR => 'CS', Name => 'Tagging' },
    '0018,9029' => { VR => 'CS', Name => 'OversamplingPhase' },
    '0018,9030' => { VR => 'FD', Name => 'TagSpacingFirstDimension' },
    '0018,9032' => { VR => 'CS', Name => 'GeometryOfKSpaceTraversal' },
    '0018,9033' => { VR => 'CS', Name => 'SegmentedKSpaceTraversal' },
    '0018,9034' => { VR => 'CS', Name => 'RectilinearPhaseEncodeReordering' },
    '0018,9035' => { VR => 'FD', Name => 'TagThickness' },
    '0018,9036' => { VR => 'CS', Name => 'PartialFourierDirection' },
    '0018,9037' => { VR => 'CS', Name => 'CardiacSynchronizationTechnique' },
    '0018,9041' => { VR => 'LO', Name => 'ReceiveCoilManufacturerName' },
    '0018,9042' => { VR => 'SQ', Name => 'MRReceiveCoilSequence' },
    '0018,9043' => { VR => 'CS', Name => 'ReceiveCoilType' },
    '0018,9044' => { VR => 'CS', Name => 'QuadratureReceiveCoil' },
    '0018,9045' => { VR => 'SQ', Name => 'MultiCoilDefinitionSequence' },
    '0018,9046' => { VR => 'LO', Name => 'MultiCoilConfiguration' },
    '0018,9047' => { VR => 'SH', Name => 'MultiCoilElementName' },
    '0018,9048' => { VR => 'CS', Name => 'MultiCoilElementUsed' },
    '0018,9049' => { VR => 'SQ', Name => 'MRTransmitCoilSequence' },
    '0018,9050' => { VR => 'LO', Name => 'TransmitCoilManufacturerName' },
    '0018,9051' => { VR => 'CS', Name => 'TransmitCoilType' },
    '0018,9052' => { VR => 'FD', Name => 'SpectralWidth' },
    '0018,9053' => { VR => 'FD', Name => 'ChemicalShiftReference' },
    '0018,9054' => { VR => 'CS', Name => 'VolumeLocalizationTechnique' },
    '0018,9058' => { VR => 'US', Name => 'MRAcquisitionFrequencyEncodeSteps' },
    '0018,9059' => { VR => 'CS', Name => 'Decoupling' },
    '0018,9060' => { VR => 'CS', Name => 'DecoupledNucleus' },
    '0018,9061' => { VR => 'FD', Name => 'DecouplingFrequency' },
    '0018,9062' => { VR => 'CS', Name => 'DecouplingMethod' },
    '0018,9063' => { VR => 'FD', Name => 'DecouplingChemicalShiftReference' },
    '0018,9064' => { VR => 'CS', Name => 'KSpaceFiltering' },
    '0018,9065' => { VR => 'CS', Name => 'TimeDomainFiltering' },
    '0018,9066' => { VR => 'US', Name => 'NumberOfZeroFills' },
    '0018,9067' => { VR => 'CS', Name => 'BaselineCorrection' },
    '0018,9069' => { VR => 'FD', Name => 'ParallelReductionFactorInPlane' },
    '0018,9070' => { VR => 'FD', Name => 'CardiacRRIntervalSpecified' },
    '0018,9073' => { VR => 'FD', Name => 'AcquisitionDuration' },
    '0018,9074' => { VR => 'DT', Name => 'FrameAcquisitionDatetime' },
    '0018,9075' => { VR => 'CS', Name => 'DiffusionDirectionality' },
    '0018,9076' => { VR => 'SQ', Name => 'DiffusionGradientDirectionSequence' },
    '0018,9077' => { VR => 'CS', Name => 'ParallelAcquisition' },
    '0018,9078' => { VR => 'CS', Name => 'ParallelAcquisitionTechnique' },
    '0018,9079' => { VR => 'FD', Name => 'InversionTimes' },
    '0018,9080' => { VR => 'ST', Name => 'MetaboliteMapDescription' },
    '0018,9081' => { VR => 'CS', Name => 'PartialFourier' },
    '0018,9082' => { VR => 'FD', Name => 'EffectiveEchoTime' },
    '0018,9083' => { VR => 'SQ', Name => 'MetaboliteMapCodeSequence' },
    '0018,9084' => { VR => 'SQ', Name => 'ChemicalShiftSequence' },
    '0018,9085' => { VR => 'CS', Name => 'CardiacSignalSource' },
    '0018,9087' => { VR => 'FD', Name => 'DiffusionBValue' },
    '0018,9089' => { VR => 'FD', Name => 'DiffusionGradientOrientation' },
    '0018,9090' => { VR => 'FD', Name => 'VelocityEncodingDirection' },
    '0018,9091' => { VR => 'FD', Name => 'VelocityEncodingMinimumValue' },
    '0018,9093' => { VR => 'US', Name => 'NumberOfKSpaceTrajectories' },
    '0018,9094' => { VR => 'CS', Name => 'CoverageOfKSpace' },
    '0018,9095' => { VR => 'UL', Name => 'SpectroscopyAcquisitionPhaseRows' },
    '0018,9098' => { VR => 'FD', Name => 'TransmitterFrequency' },
    '0018,9100' => { VR => 'CS', Name => 'ResonantNucleus' },
    '0018,9101' => { VR => 'CS', Name => 'FrequencyCorrection' },
    '0018,9103' => { VR => 'SQ', Name => 'MRSpectroscopyFOV-GeometrySequence' },
    '0018,9104' => { VR => 'FD', Name => 'SlabThickness' },
    '0018,9105' => { VR => 'FD', Name => 'SlabOrientation' },
    '0018,9106' => { VR => 'FD', Name => 'MidSlabPosition' },
    '0018,9107' => { VR => 'SQ', Name => 'MRSpatialSaturationSequence' },
    '0018,9112' => { VR => 'SQ', Name => 'MRTimingAndRelatedParametersSeq' },
    '0018,9114' => { VR => 'SQ', Name => 'MREchoSequence' },
    '0018,9115' => { VR => 'SQ', Name => 'MRModifierSequence' },
    '0018,9117' => { VR => 'SQ', Name => 'MRDiffusionSequence' },
    '0018,9118' => { VR => 'SQ', Name => 'CardiacTriggerSequence' },
    '0018,9119' => { VR => 'SQ', Name => 'MRAveragesSequence' },
    '0018,9125' => { VR => 'SQ', Name => 'MRFOV-GeometrySequence' },
    '0018,9126' => { VR => 'SQ', Name => 'VolumeLocalizationSequence' },
    '0018,9127' => { VR => 'UL', Name => 'SpectroscopyAcquisitionDataColumns' },
    '0018,9147' => { VR => 'CS', Name => 'DiffusionAnisotropyType' },
    '0018,9151' => { VR => 'DT', Name => 'FrameReferenceDatetime' },
    '0018,9152' => { VR => 'SQ', Name => 'MRMetaboliteMapSequence' },
    '0018,9155' => { VR => 'FD', Name => 'ParallelReductionFactorOutOfPlane' },
    '0018,9159' => { VR => 'UL', Name => 'SpectroscopyOutOfPlanePhaseSteps' },
    '0018,9166' => { VR => 'CS', Name => 'BulkMotionStatus' },
    '0018,9168' => { VR => 'FD', Name => 'ParallelReductionFactSecondInPlane' },
    '0018,9169' => { VR => 'CS', Name => 'CardiacBeatRejectionTechnique' },
    '0018,9170' => { VR => 'CS', Name => 'RespiratoryMotionCompTechnique' },
    '0018,9171' => { VR => 'CS', Name => 'RespiratorySignalSource' },
    '0018,9172' => { VR => 'CS', Name => 'BulkMotionCompensationTechnique' },
    '0018,9173' => { VR => 'CS', Name => 'BulkMotionSignalSource' },
    '0018,9174' => { VR => 'CS', Name => 'ApplicableSafetyStandardAgency' },
    '0018,9175' => { VR => 'LO', Name => 'ApplicableSafetyStandardDescr' },
    '0018,9176' => { VR => 'SQ', Name => 'OperatingModeSequence' },
    '0018,9177' => { VR => 'CS', Name => 'OperatingModeType' },
    '0018,9178' => { VR => 'CS', Name => 'OperatingMode' },
    '0018,9179' => { VR => 'CS', Name => 'SpecificAbsorptionRateDefinition' },
    '0018,9180' => { VR => 'CS', Name => 'GradientOutputType' },
    '0018,9181' => { VR => 'FD', Name => 'SpecificAbsorptionRateValue' },
    '0018,9182' => { VR => 'FD', Name => 'GradientOutput' },
    '0018,9183' => { VR => 'CS', Name => 'FlowCompensationDirection' },
    '0018,9184' => { VR => 'FD', Name => 'TaggingDelay' },
    '0018,9195' => { VR => 'FD', Name => 'ChemicalShiftsMinIntegrateLimitHz' },
    '0018,9196' => { VR => 'FD', Name => 'ChemicalShiftsMaxIntegrateLimitHz' },
    '0018,9197' => { VR => 'SQ', Name => 'MRVelocityEncodingSequence' },
    '0018,9198' => { VR => 'CS', Name => 'FirstOrderPhaseCorrection' },
    '0018,9199' => { VR => 'CS', Name => 'WaterReferencedPhaseCorrection' },
    '0018,9200' => { VR => 'CS', Name => 'MRSpectroscopyAcquisitionType' },
    '0018,9214' => { VR => 'CS', Name => 'RespiratoryCyclePosition' },
    '0018,9217' => { VR => 'FD', Name => 'VelocityEncodingMaximumValue' },
    '0018,9218' => { VR => 'FD', Name => 'TagSpacingSecondDimension' },
    '0018,9219' => { VR => 'SS', Name => 'TagAngleSecondAxis' },
    '0018,9220' => { VR => 'FD', Name => 'FrameAcquisitionDuration' },
    '0018,9226' => { VR => 'SQ', Name => 'MRImageFrameTypeSequence' },
    '0018,9227' => { VR => 'SQ', Name => 'MRSpectroscopyFrameTypeSequence' },
    '0018,9231' => { VR => 'US', Name => 'MRAcqPhaseEncodingStepsInPlane' },
    '0018,9232' => { VR => 'US', Name => 'MRAcqPhaseEncodingStepsOutOfPlane' },
    '0018,9234' => { VR => 'UL', Name => 'SpectroscopyAcqPhaseColumns' },
    '0018,9236' => { VR => 'CS', Name => 'CardiacCyclePosition' },
    '0018,9239' => { VR => 'SQ', Name => 'SpecificAbsorptionRateSequence' },
    '0018,9240' => { VR => 'US', Name => 'RFEchoTrainLength' },
    '0018,9241' => { VR => 'US', Name => 'GradientEchoTrainLength' },
    '0018,9295' => { VR => 'FD', Name => 'ChemicalShiftsMinIntegrateLimitPPM' },
    '0018,9296' => { VR => 'FD', Name => 'ChemicalShiftsMaxIntegrateLimitPPM' },
    '0018,9301' => { VR => 'SQ', Name => 'CTAcquisitionTypeSequence' },
    '0018,9302' => { VR => 'CS', Name => 'AcquisitionType' },
    '0018,9303' => { VR => 'FD', Name => 'TubeAngle' },
    '0018,9304' => { VR => 'SQ', Name => 'CTAcquisitionDetailsSequence' },
    '0018,9305' => { VR => 'FD', Name => 'RevolutionTime' },
    '0018,9306' => { VR => 'FD', Name => 'SingleCollimationWidth' },
    '0018,9307' => { VR => 'FD', Name => 'TotalCollimationWidth' },
    '0018,9308' => { VR => 'SQ', Name => 'CTTableDynamicsSequence' },
    '0018,9309' => { VR => 'FD', Name => 'TableSpeed' },
    '0018,9310' => { VR => 'FD', Name => 'TableFeedPerRotation' },
    '0018,9311' => { VR => 'FD', Name => 'SpiralPitchFactor' },
    '0018,9312' => { VR => 'SQ', Name => 'CTGeometrySequence' },
    '0018,9313' => { VR => 'FD', Name => 'DataCollectionCenterPatient' },
    '0018,9314' => { VR => 'SQ', Name => 'CTReconstructionSequence' },
    '0018,9315' => { VR => 'CS', Name => 'ReconstructionAlgorithm' },
    '0018,9316' => { VR => 'CS', Name => 'ConvolutionKernelGroup' },
    '0018,9317' => { VR => 'FD', Name => 'ReconstructionFieldOfView' },
    '0018,9318' => { VR => 'FD', Name => 'ReconstructionTargetCenterPatient' },
    '0018,9319' => { VR => 'FD', Name => 'ReconstructionAngle' },
    '0018,9320' => { VR => 'SH', Name => 'ImageFilter' },
    '0018,9321' => { VR => 'SQ', Name => 'CTExposureSequence' },
    '0018,9322' => { VR => 'FD', Name => 'ReconstructionPixelSpacing' },
    '0018,9323' => { VR => 'CS', Name => 'ExposureModulationType' },
    '0018,9324' => { VR => 'FD', Name => 'EstimatedDoseSaving' },
    '0018,9325' => { VR => 'SQ', Name => 'CTXRayDetailsSequence' },
    '0018,9326' => { VR => 'SQ', Name => 'CTPositionSequence' },
    '0018,9327' => { VR => 'FD', Name => 'TablePosition' },
    '0018,9328' => { VR => 'FD', Name => 'ExposureTimeInMilliSec' },
    '0018,9329' => { VR => 'SQ', Name => 'CTImageFrameTypeSequence' },
    '0018,9330' => { VR => 'FD', Name => 'XRayTubeCurrentInMilliAmps' },
    '0018,9332' => { VR => 'FD', Name => 'ExposureInMilliAmpSec' },
    '0018,9333' => { VR => 'CS', Name => 'ConstantVolumeFlag' },
    '0018,9334' => { VR => 'CS', Name => 'FluoroscopyFlag' },
    '0018,9335' => { VR => 'FD', Name => 'SourceToDataCollectionCenterDist' },
    '0018,9337' => { VR => 'US', Name => 'Contrast-BolusAgentNumber' },
    '0018,9338' => { VR => 'SQ', Name => 'Contrast-BolusIngredientCodeSeq' },
    '0018,9340' => { VR => 'SQ', Name => 'ContrastAdministrationProfileSeq' },
    '0018,9341' => { VR => 'SQ', Name => 'Contrast-BolusUsageSequence' },
    '0018,9342' => { VR => 'CS', Name => 'Contrast-BolusAgentAdministered' },
    '0018,9343' => { VR => 'CS', Name => 'Contrast-BolusAgentDetected' },
    '0018,9344' => { VR => 'CS', Name => 'Contrast-BolusAgentPhase' },
    '0018,9345' => { VR => 'FD', Name => 'CTDIvol' },
    '0018,A001' => { VR => 'SQ', Name => 'ContributingEquipmentSequence' },
    '0018,A002' => { VR => 'DT', Name => 'ContributionDateTime' },
    '0018,A003' => { VR => 'ST', Name => 'ContributionDescription' },
    '0019,1002' => { VR => 'SL', Name => 'NumberOfCellsIInDetector' }, #4
    '0019,1003' => { VR => 'DS', Name => 'CellNumberAtTheta' }, #4
    '0019,1004' => { VR => 'DS', Name => 'CellSpacing' }, #4
    '0019,100F' => { VR => 'DS', Name => 'HorizFrameOfRef' }, #4
    '0019,1011' => { VR => 'SS', Name => 'SeriesContrast' }, #4
    '0019,1012' => { VR => 'SS', Name => 'LastPseq' }, #4
    '0019,1013' => { VR => 'SS', Name => 'StartNumberForBaseline' }, #4
    '0019,1014' => { VR => 'SS', Name => 'EndNumberForBaseline' }, #4
    '0019,1015' => { VR => 'SS', Name => 'StartNumberForEnhancedScans' }, #4
    '0019,1016' => { VR => 'SS', Name => 'EndNumberForEnhancedScans' }, #4
    '0019,1017' => { VR => 'SS', Name => 'SeriesPlane' }, #4
    '0019,1018' => { VR => 'LO', Name => 'FirstScanRas' }, #4
    '0019,1019' => { VR => 'DS', Name => 'FirstScanLocation' }, #4
    '0019,101A' => { VR => 'LO', Name => 'LastScanRas' }, #4
    '0019,101B' => { VR => 'DS', Name => 'LastScanLoc' }, #4
    '0019,101E' => { VR => 'DS', Name => 'DisplayFieldOfView' }, #4
    '0019,1023' => { VR => 'DS', Name => 'TableSpeed' }, #4
    '0019,1024' => { VR => 'DS', Name => 'MidScanTime' }, #4
    '0019,1025' => { VR => 'SS', Name => 'MidScanFlag' }, #4
    '0019,1026' => { VR => 'SL', Name => 'DegreesOfAzimuth' }, #4
    '0019,1027' => { VR => 'DS', Name => 'GantryPeriod' }, #4
    '0019,102A' => { VR => 'DS', Name => 'XRayOnPosition' }, #4
    '0019,102B' => { VR => 'DS', Name => 'XRayOffPosition' }, #4
    '0019,102C' => { VR => 'SL', Name => 'NumberOfTriggers' }, #4
    '0019,102E' => { VR => 'DS', Name => 'AngleOfFirstView' }, #4
    '0019,102F' => { VR => 'DS', Name => 'TriggerFrequency' }, #4
    '0019,1039' => { VR => 'SS', Name => 'ScanFOVType' }, #4
    '0019,1040' => { VR => 'SS', Name => 'StatReconFlag' }, #4
    '0019,1041' => { VR => 'SS', Name => 'ComputeType' }, #4
    '0019,1042' => { VR => 'SS', Name => 'SegmentNumber' }, #4
    '0019,1043' => { VR => 'SS', Name => 'TotalSegmentsRequested' }, #4
    '0019,1044' => { VR => 'DS', Name => 'InterscanDelay' }, #4
    '0019,1047' => { VR => 'SS', Name => 'ViewCompressionFactor' }, #4
    '0019,104A' => { VR => 'SS', Name => 'TotalNoOfRefChannels' }, #4
    '0019,104B' => { VR => 'SL', Name => 'DataSizeForScanData' }, #4
    '0019,1052' => { VR => 'SS', Name => 'ReconPostProcflag' }, #4
    '0019,1057' => { VR => 'SS', Name => 'CTWaterNumber' }, #4
    '0019,1058' => { VR => 'SS', Name => 'CTBoneNumber' }, #4
    '0019,105A' => { VR => 'FL', Name => 'AcquisitionDuration' }, #4
    '0019,105E' => { VR => 'SL', Name => 'NumberOfChannels' }, #4
    '0019,105F' => { VR => 'SL', Name => 'IncrementBetweenChannels' }, #4
    '0019,1060' => { VR => 'SL', Name => 'StartingView' }, #4
    '0019,1061' => { VR => 'SL', Name => 'NumberOfViews' }, #4
    '0019,1062' => { VR => 'SL', Name => 'IncrementBetweenViews' }, #4
    '0019,106A' => { VR => 'SS', Name => 'DependantOnNoViewsProcessed' }, #4
    '0019,106B' => { VR => 'SS', Name => 'FieldOfViewInDetectorCells' }, #4
    '0019,1070' => { VR => 'SS', Name => 'ValueOfBackProjectionButton' }, #4
    '0019,1071' => { VR => 'SS', Name => 'SetIfFatqEstimatesWereUsed' }, #4
    '0019,1072' => { VR => 'DS', Name => 'ZChanAvgOverViews' }, #4
    '0019,1073' => { VR => 'DS', Name => 'AvgOfLeftRefChansOverViews' }, #4
    '0019,1074' => { VR => 'DS', Name => 'MaxLeftChanOverViews' }, #4
    '0019,1075' => { VR => 'DS', Name => 'AvgOfRightRefChansOverViews' }, #4
    '0019,1076' => { VR => 'DS', Name => 'MaxRightChanOverViews' }, #4
    '0019,107D' => { VR => 'DS', Name => 'SecondEcho' }, #4
    '0019,107E' => { VR => 'SS', Name => 'NumberOfEchoes' }, #4
    '0019,107F' => { VR => 'DS', Name => 'TableDelta' }, #4
    '0019,1081' => { VR => 'SS', Name => 'Contiguous' }, #4
    '0019,1084' => { VR => 'DS', Name => 'PeakSAR' }, #4
    '0019,1085' => { VR => 'SS', Name => 'MonitorSAR' }, #4
    '0019,1087' => { VR => 'DS', Name => 'CardiacRepetitionTime' }, #4
    '0019,1088' => { VR => 'SS', Name => 'ImagesPerCardiacCycle' }, #4
    '0019,108A' => { VR => 'SS', Name => 'ActualReceiveGainAnalog' }, #4
    '0019,108B' => { VR => 'SS', Name => 'ActualReceiveGainDigital' }, #4
    '0019,108D' => { VR => 'DS', Name => 'DelayAfterTrigger' }, #4
    '0019,108F' => { VR => 'SS', Name => 'Swappf' }, #4
    '0019,1090' => { VR => 'SS', Name => 'PauseInterval' }, #4
    '0019,1091' => { VR => 'DS', Name => 'PulseTime' }, #4
    '0019,1092' => { VR => 'SL', Name => 'SliceOffsetOnFreqAxis' }, #4
    '0019,1093' => { VR => 'DS', Name => 'CenterFrequency' }, #4
    '0019,1094' => { VR => 'SS', Name => 'TransmitGain' }, #4
    '0019,1095' => { VR => 'SS', Name => 'AnalogReceiverGain' }, #4
    '0019,1096' => { VR => 'SS', Name => 'DigitalReceiverGain' }, #4
    '0019,1097' => { VR => 'SL', Name => 'BitmapDefiningCVs' }, #4
    '0019,1098' => { VR => 'SS', Name => 'CenterFreqMethod' }, #4
    '0019,109B' => { VR => 'SS', Name => 'PulseSeqMode' }, #4
    '0019,109C' => { VR => 'LO', Name => 'PulseSeqName' }, #4
    '0019,109D' => { VR => 'DT', Name => 'PulseSeqDate' }, #4
    '0019,109E' => { VR => 'LO', Name => 'InternalPulseSeqName' }, #4
    '0019,109F' => { VR => 'SS', Name => 'TransmittingCoil' }, #4
    '0019,10A0' => { VR => 'SS', Name => 'SurfaceCoilType' }, #4
    '0019,10A1' => { VR => 'SS', Name => 'ExtremityCoilFlag' }, #4
    '0019,10A2' => { VR => 'SL', Name => 'RawDataRunNumber' }, #4
    '0019,10A3' => { VR => 'UL', Name => 'CalibratedFieldStrength' }, #4
    '0019,10A4' => { VR => 'SS', Name => 'SATFatWaterBone' }, #4
    '0019,10A5' => { VR => 'DS', Name => 'ReceiveBandwidth' }, #4
    '0019,10A7' => { VR => 'DS', Name => 'UserData01' }, #4
    '0019,10A8' => { VR => 'DS', Name => 'UserData02' }, #4
    '0019,10A9' => { VR => 'DS', Name => 'UserData03' }, #4
    '0019,10AA' => { VR => 'DS', Name => 'UserData04' }, #4
    '0019,10AB' => { VR => 'DS', Name => 'UserData05' }, #4
    '0019,10AC' => { VR => 'DS', Name => 'UserData06' }, #4
    '0019,10AD' => { VR => 'DS', Name => 'UserData07' }, #4
    '0019,10AE' => { VR => 'DS', Name => 'UserData08' }, #4
    '0019,10AF' => { VR => 'DS', Name => 'UserData09' }, #4
    '0019,10B0' => { VR => 'DS', Name => 'UserData10' }, #4
    '0019,10B1' => { VR => 'DS', Name => 'UserData11' }, #4
    '0019,10B2' => { VR => 'DS', Name => 'UserData12' }, #4
    '0019,10B3' => { VR => 'DS', Name => 'UserData13' }, #4
    '0019,10B4' => { VR => 'DS', Name => 'UserData14' }, #4
    '0019,10B5' => { VR => 'DS', Name => 'UserData15' }, #4
    '0019,10B6' => { VR => 'DS', Name => 'UserData16' }, #4
    '0019,10B7' => { VR => 'DS', Name => 'UserData17' }, #4
    '0019,10B8' => { VR => 'DS', Name => 'UserData18' }, #4
    '0019,10B9' => { VR => 'DS', Name => 'UserData19' }, #4
    '0019,10BA' => { VR => 'DS', Name => 'UserData20' }, #4
    '0019,10BB' => { VR => 'DS', Name => 'UserData21' }, #4
    '0019,10BC' => { VR => 'DS', Name => 'UserData22' }, #4
    '0019,10BD' => { VR => 'DS', Name => 'UserData23' }, #4
    '0019,10BE' => { VR => 'DS', Name => 'ProjectionAngle' }, #4
    '0019,10C0' => { VR => 'SS', Name => 'SaturationPlanes' }, #4
    '0019,10C1' => { VR => 'SS', Name => 'SurfaceCoilIntensity' }, #4
    '0019,10C2' => { VR => 'SS', Name => 'SATLocationR' }, #4
    '0019,10C3' => { VR => 'SS', Name => 'SATLocationL' }, #4
    '0019,10C4' => { VR => 'SS', Name => 'SATLocationA' }, #4
    '0019,10C5' => { VR => 'SS', Name => 'SATLocationP' }, #4
    '0019,10C6' => { VR => 'SS', Name => 'SATLocationH' }, #4
    '0019,10C7' => { VR => 'SS', Name => 'SATLocationF' }, #4
    '0019,10C8' => { VR => 'SS', Name => 'SATThicknessR-L' }, #4
    '0019,10C9' => { VR => 'SS', Name => 'SATThicknessA-P' }, #4
    '0019,10CA' => { VR => 'SS', Name => 'SATThicknessH-F' }, #4
    '0019,10CB' => { VR => 'SS', Name => 'PrescribedFlowAxis' }, #4
    '0019,10CC' => { VR => 'SS', Name => 'VelocityEncoding' }, #4
    '0019,10CD' => { VR => 'SS', Name => 'ThicknessDisclaimer' }, #4
    '0019,10CE' => { VR => 'SS', Name => 'PrescanType' }, #4
    '0019,10CF' => { VR => 'SS', Name => 'PrescanStatus' }, #4
    '0019,10D0' => { VR => 'SH', Name => 'RawDataType' }, #4
    '0019,10D2' => { VR => 'SS', Name => 'ProjectionAlgorithm' }, #4
    '0019,10D3' => { VR => 'SH', Name => 'ProjectionAlgorithm' }, #4
    '0019,10D5' => { VR => 'SS', Name => 'FractionalEcho' }, #4
    '0019,10D6' => { VR => 'SS', Name => 'PrepPulse' }, #4
    '0019,10D7' => { VR => 'SS', Name => 'CardiacPhases' }, #4
    '0019,10D8' => { VR => 'SS', Name => 'VariableEchoflag' }, #4
    '0019,10D9' => { VR => 'DS', Name => 'ConcatenatedSAT' }, #4
    '0019,10DA' => { VR => 'SS', Name => 'ReferenceChannelUsed' }, #4
    '0019,10DB' => { VR => 'DS', Name => 'BackProjectorCoefficient' }, #4
    '0019,10DC' => { VR => 'SS', Name => 'PrimarySpeedCorrectionUsed' }, #4
    '0019,10DD' => { VR => 'SS', Name => 'OverrangeCorrectionUsed' }, #4
    '0019,10DE' => { VR => 'DS', Name => 'DynamicZAlphaValue' }, #4
    '0019,10DF' => { VR => 'DS', Name => 'UserData' }, #4
    '0019,10E0' => { VR => 'DS', Name => 'UserData' }, #4
    '0019,10E2' => { VR => 'DS', Name => 'VelocityEncodeScale' }, #4
    '0019,10F2' => { VR => 'SS', Name => 'FastPhases' }, #4
    '0019,10F9' => { VR => 'DS', Name => 'TransmissionGain' }, #4
    # relationship group
    '0020,0000' => { VR => 'UL', Name => 'RelationshipGroupLength' },
    '0020,000D' => { VR => 'UI', Name => 'StudyInstanceUID' },
    '0020,000E' => { VR => 'UI', Name => 'SeriesInstanceUID' },
    '0020,0010' => { VR => 'SH', Name => 'StudyID' },
    '0020,0011' => { VR => 'IS', Name => 'SeriesNumber' },
    '0020,0012' => { VR => 'IS', Name => 'AcquisitionNumber' },
    '0020,0013' => { VR => 'IS', Name => 'InstanceNumber' },
    '0020,0014' => { VR => 'RET',Name => 'IsotopeNumber' },
    '0020,0015' => { VR => 'RET',Name => 'PhaseNumber' },
    '0020,0016' => { VR => 'RET',Name => 'IntervalNumber' },
    '0020,0017' => { VR => 'RET',Name => 'TimeSlotNumber' },
    '0020,0018' => { VR => 'RET',Name => 'AngleNumber' },
    '0020,0019' => { VR => 'IS', Name => 'ItemNumber' },
    '0020,0020' => { VR => 'CS', Name => 'PatientOrientation' },
    '0020,0022' => { VR => 'IS', Name => 'OverlayNumber' },
    '0020,0024' => { VR => 'IS', Name => 'CurveNumber' },
    '0020,0026' => { VR => 'IS', Name => 'LookupTableNumber' },
    '0020,0030' => { VR => 'DS', Name => 'ImagePosition' },
    '0020,0032' => { VR => 'DS', Name => 'ImagePositionPatient' },
    '0020,0035' => { VR => 'DS', Name => 'ImageOrientation' },
    '0020,0037' => { VR => 'DS', Name => 'ImageOrientationPatient' },
    '0020,0050' => { VR => 'RET',Name => 'Location' },
    '0020,0052' => { VR => 'UI', Name => 'FrameOfReferenceUID' },
    '0020,0060' => { VR => 'CS', Name => 'Laterality' },
    '0020,0062' => { VR => 'CS', Name => 'ImageLaterality' },
    '0020,0070' => { VR => 'RET',Name => 'ImageGeometryType' },
    '0020,0080' => { VR => 'RET',Name => 'MaskingImage' },
    '0020,0100' => { VR => 'IS', Name => 'TemporalPositionIdentifier' },
    '0020,0105' => { VR => 'IS', Name => 'NumberOfTemporalPositions' },
    '0020,0110' => { VR => 'DS', Name => 'TemporalResolution' },
    '0020,0200' => { VR => 'UI', Name => 'SynchronizationFrameOfReferenceUID' },
    '0020,1000' => { VR => 'IS', Name => 'SeriesInStudy' },
    '0020,1001' => { VR => 'RET',Name => 'AcquisitionsInSeries' },
    '0020,1002' => { VR => 'IS', Name => 'ImagesInAcquisition' },
    '0020,1004' => { VR => 'IS', Name => 'AcquisitionsInStudy' },
    '0020,1020' => { VR => 'RET',Name => 'Reference' },
    '0020,1040' => { VR => 'LO', Name => 'PositionReferenceIndicator' },
    '0020,1041' => { VR => 'DS', Name => 'SliceLocation' },
    '0020,1070' => { VR => 'IS', Name => 'OtherStudyNumbers' },
    '0020,1200' => { VR => 'IS', Name => 'NumberOfPatientRelatedStudies' },
    '0020,1202' => { VR => 'IS', Name => 'NumberOfPatientRelatedSeries' },
    '0020,1204' => { VR => 'IS', Name => 'NumberOfPatientRelatedInstances' },
    '0020,1206' => { VR => 'IS', Name => 'NumberOfStudyRelatedSeries' },
    '0020,1208' => { VR => 'IS', Name => 'NumberOfStudyRelatedInstances' },
    '0020,1209' => { VR => 'RET',Name => 'NumberOfSeriesRelatedInstances' },
    '0020,31xx' => { VR => 'RET',Name => 'SourceImageIDs' },
    '0020,3401' => { VR => 'RET',Name => 'ModifyingDeviceID' },
    '0020,3402' => { VR => 'RET',Name => 'ModifiedImageID' },
    '0020,3403' => { VR => 'RET',Name => 'ModifiedImageDate' },
    '0020,3404' => { VR => 'RET',Name => 'ModifyingDeviceManufacturer' },
    '0020,3405' => { VR => 'RET',Name => 'ModifiedImageTime' },
    '0020,3406' => { VR => 'RET',Name => 'ModifiedImageDescription' },
    '0020,4000' => { VR => 'LT', Name => 'ImageComments' },
    '0020,5000' => { VR => 'US', Name => 'OriginalImageIdentification' },
    '0020,5002' => { VR => 'RET',Name => 'OriginalImageIdentNomenclature' },
    '0020,9056' => { VR => 'SH', Name => 'StackID' },
    '0020,9057' => { VR => 'UL', Name => 'InStackPositionNumber' },
    '0020,9071' => { VR => 'SQ', Name => 'FrameAnatomySequence' },
    '0020,9072' => { VR => 'CS', Name => 'FrameLaterality' },
    '0020,9111' => { VR => 'SQ', Name => 'FrameContentSequence' },
    '0020,9113' => { VR => 'SQ', Name => 'PlanePositionSequence' },
    '0020,9116' => { VR => 'SQ', Name => 'PlaneOrientationSequence' },
    '0020,9128' => { VR => 'UL', Name => 'TemporalPositionIndex' },
    '0020,9153' => { VR => 'FD', Name => 'TriggerDelayTime' },
    '0020,9156' => { VR => 'US', Name => 'FrameAcquisitionNumber' },
    '0020,9157' => { VR => 'UL', Name => 'DimensionIndexValues' },
    '0020,9158' => { VR => 'LT', Name => 'FrameComments' },
    '0020,9161' => { VR => 'UI', Name => 'ConcatenationUID' },
    '0020,9162' => { VR => 'US', Name => 'InconcatenationNumber' },
    '0020,9163' => { VR => 'US', Name => 'InconcatenationTotalNumber' },
    '0020,9164' => { VR => 'UI', Name => 'DimensionOrganizationUID' },
    '0020,9165' => { VR => 'AT', Name => 'DimensionIndexPointer' },
    '0020,9167' => { VR => 'AT', Name => 'FunctionalGroupPointer' },
    '0020,9213' => { VR => 'LO', Name => 'DimensionIndexPrivateCreator' },
    '0020,9221' => { VR => 'SQ', Name => 'DimensionOrganizationSequence' },
    '0020,9222' => { VR => 'SQ', Name => 'DimensionIndexSequence' },
    '0020,9228' => { VR => 'UL', Name => 'ConcatenationFrameOffsetNumber' },
    '0020,9238' => { VR => 'LO', Name => 'FunctionalGroupPrivateCreator' },
    '0021,1003' => { VR => 'SS', Name => 'SeriesFromWhichPrescribed' }, #4
    '0021,1005' => { VR => 'SH', Name => 'GenesisVersionNow' }, #4
    '0021,1005' => { VR => 'SH', Name => 'GenesisVersionNow' }, #4
    '0021,1007' => { VR => 'UL', Name => 'SeriesRecordChecksum' }, #4
    '0021,1018' => { VR => 'SH', Name => 'GenesisVersionNow' }, #4
    '0021,1018' => { VR => 'SH', Name => 'GenesisVersionNow' }, #4
    '0021,1019' => { VR => 'UL', Name => 'AcqReconRecordChecksum' }, #4
    '0021,1019' => { VR => 'UL', Name => 'AcqreconRecordChecksum' }, #4
    '0021,1020' => { VR => 'DS', Name => 'TableStartLocation' }, #4
    '0021,1035' => { VR => 'SS', Name => 'SeriesFromWhichPrescribed' }, #4
    '0021,1036' => { VR => 'SS', Name => 'ImageFromWhichPrescribed' }, #4
    '0021,1037' => { VR => 'SS', Name => 'ScreenFormat' }, #4
    '0021,104A' => { VR => 'LO', Name => 'AnatomicalReferenceForScout' }, #4
    '0021,104F' => { VR => 'SS', Name => 'LocationsInAcquisition' }, #4
    '0021,1050' => { VR => 'SS', Name => 'GraphicallyPrescribed' }, #4
    '0021,1051' => { VR => 'DS', Name => 'RotationFromSourceXRot' }, #4
    '0021,1052' => { VR => 'DS', Name => 'RotationFromSourceYRot' }, #4
    '0021,1053' => { VR => 'DS', Name => 'RotationFromSourceZRot' }, #4
    '0021,1054' => { VR => 'SH', Name => 'ImagePosition' }, #4
    '0021,1055' => { VR => 'SH', Name => 'ImageOrientation' }, #4
    '0021,1056' => { VR => 'SL', Name => 'IntegerSlop' }, #4
    '0021,1057' => { VR => 'SL', Name => 'IntegerSlop' }, #4
    '0021,1058' => { VR => 'SL', Name => 'IntegerSlop' }, #4
    '0021,1059' => { VR => 'SL', Name => 'IntegerSlop' }, #4
    '0021,105A' => { VR => 'SL', Name => 'IntegerSlop' }, #4
    '0021,105B' => { VR => 'DS', Name => 'FloatSlop' }, #4
    '0021,105C' => { VR => 'DS', Name => 'FloatSlop' }, #4
    '0021,105D' => { VR => 'DS', Name => 'FloatSlop' }, #4
    '0021,105E' => { VR => 'DS', Name => 'FloatSlop' }, #4
    '0021,105F' => { VR => 'DS', Name => 'FloatSlop' }, #4
    '0021,1081' => { VR => 'DS', Name => 'AutoWindowLevelAlpha' }, #4
    '0021,1082' => { VR => 'DS', Name => 'AutoWindowLevelBeta' }, #4
    '0021,1083' => { VR => 'DS', Name => 'AutoWindowLevelWindow' }, #4
    '0021,1084' => { VR => 'DS', Name => 'ToWindowLevelLevel' }, #4
    '0021,1090' => { VR => 'SS', Name => 'TubeFocalSpotPosition' }, #4
    '0021,1091' => { VR => 'SS', Name => 'BiopsyPosition' }, #4
    '0021,1092' => { VR => 'FL', Name => 'BiopsyTLocation' }, #4
    '0021,1093' => { VR => 'FL', Name => 'BiopsyRefLocation' }, #4
    '0022,0001' => { VR => 'US', Name => 'LightPathFilterPassThroughWavelen' },
    '0022,0002' => { VR => 'US', Name => 'LightPathFilterPassBand' },
    '0022,0003' => { VR => 'US', Name => 'ImagePathFilterPassThroughWavelen' },
    '0022,0004' => { VR => 'US', Name => 'ImagePathFilterPassBand' },
    '0022,0005' => { VR => 'CS', Name => 'PatientEyeMovementCommanded' },
    '0022,0006' => { VR => 'SQ', Name => 'PatientEyeMovementCommandCodeSeq' },
    '0022,0007' => { VR => 'FL', Name => 'SphericalLensPower' },
    '0022,0008' => { VR => 'FL', Name => 'CylinderLensPower' },
    '0022,0009' => { VR => 'FL', Name => 'CylinderAxis' },
    '0022,000A' => { VR => 'FL', Name => 'EmmetropicMagnification' },
    '0022,000B' => { VR => 'FL', Name => 'IntraOcularPressure' },
    '0022,000C' => { VR => 'FL', Name => 'HorizontalFieldOfView' },
    '0022,000D' => { VR => 'CS', Name => 'PupilDilated' },
    '0022,000E' => { VR => 'FL', Name => 'DegreeOfDilation' },
    '0022,0010' => { VR => 'FL', Name => 'StereoBaselineAngle' },
    '0022,0011' => { VR => 'FL', Name => 'StereoBaselineDisplacement' },
    '0022,0012' => { VR => 'FL', Name => 'StereoHorizontalPixelOffset' },
    '0022,0013' => { VR => 'FL', Name => 'StereoVerticalPixelOffset' },
    '0022,0014' => { VR => 'FL', Name => 'StereoRotation' },
    '0022,0015' => { VR => 'SQ', Name => 'AcquisitionDeviceTypeCodeSequence' },
    '0022,0016' => { VR => 'SQ', Name => 'IlluminationTypeCodeSequence' },
    '0022,0017' => { VR => 'SQ', Name => 'LightPathFilterTypeStackCodeSeq' },
    '0022,0018' => { VR => 'SQ', Name => 'ImagePathFilterTypeStackCodeSeq' },
    '0022,0019' => { VR => 'SQ', Name => 'LensesCodeSequence' },
    '0022,001A' => { VR => 'SQ', Name => 'ChannelDescriptionCodeSequence' },
    '0022,001B' => { VR => 'SQ', Name => 'RefractiveStateSequence' },
    '0022,001C' => { VR => 'SQ', Name => 'MydriaticAgentCodeSequence' },
    '0022,001D' => { VR => 'SQ', Name => 'RelativeImagePositionCodeSequence' },
    '0022,0020' => { VR => 'SQ', Name => 'StereoPairsSequence' },
    '0022,0021' => { VR => 'SQ', Name => 'LeftImageSequence' },
    '0022,0022' => { VR => 'SQ', Name => 'RightImageSequence' },
    '0023,1001' => { VR => 'SL', Name => 'NumberOfSeriesInStudy' }, #4
    '0023,1002' => { VR => 'SL', Name => 'NumberOfUnarchivedSeries' }, #4
    '0023,1010' => { VR => 'SS', Name => 'ReferenceImageField' }, #4
    '0023,1050' => { VR => 'SS', Name => 'SummaryImage' }, #4
    '0023,1070' => { VR => 'FD', Name => 'StartTimeSecsInFirstAxial' }, #4
    '0023,1074' => { VR => 'SL', Name => 'NoofUpdatesToHeader' }, #4
    '0023,107D' => { VR => 'SS', Name => 'IndicatesIfStudyHasCompleteInfo' }, #4
    '0023,107D' => { VR => 'SS', Name => 'IndicatesIfTheStudyHasCompleteInfo' }, #4
    '0025,1006' => { VR => 'SS', Name => 'LastPulseSequenceUsed' }, #4
    '0025,1007' => { VR => 'SL', Name => 'ImagesInSeries' }, #4
    '0025,1010' => { VR => 'SL', Name => 'LandmarkCounter' }, #4
    '0025,1011' => { VR => 'SS', Name => 'NumberOfAcquisitions' }, #4
    '0025,1014' => { VR => 'SL', Name => 'IndicatesNoofUpdatesToHeader' }, #4
    '0025,1017' => { VR => 'SL', Name => 'SeriesCompleteFlag' }, #4
    '0025,1018' => { VR => 'SL', Name => 'NumberOfImagesArchived' }, #4
    '0025,1019' => { VR => 'SL', Name => 'LastImageNumberUsed' }, #4
    '0025,101A' => { VR => 'SH', Name => 'PrimaryReceiverSuiteAndHost' }, #4
    '0027,1006' => { VR => 'SL', Name => 'ImageArchiveFlag' }, #4
    '0027,1010' => { VR => 'SS', Name => 'ScoutType' }, #4
    '0027,101C' => { VR => 'SL', Name => 'VmaMamp' }, #4
    '0027,101D' => { VR => 'SS', Name => 'VmaPhase' }, #4
    '0027,101E' => { VR => 'SL', Name => 'VmaMod' }, #4
    '0027,101F' => { VR => 'SL', Name => 'VmaClip' }, #4
    '0027,1020' => { VR => 'SS', Name => 'SmartScanOnOffFlag' }, #4
    '0027,1030' => { VR => 'SH', Name => 'ForeignImageRevision' }, #4
    '0027,1031' => { VR => 'SS', Name => 'ImagingMode' }, #4
    '0027,1032' => { VR => 'SS', Name => 'PulseSequence' }, #4
    '0027,1033' => { VR => 'SL', Name => 'ImagingOptions' }, #4
    '0027,1035' => { VR => 'SS', Name => 'PlaneType' }, #4
    '0027,1036' => { VR => 'SL', Name => 'ObliquePlane' }, #4
    '0027,1040' => { VR => 'SH', Name => 'RASLetterOfImageLocation' }, #4
    '0027,1041' => { VR => 'FL', Name => 'ImageLocation' }, #4
    '0027,1042' => { VR => 'FL', Name => 'CenterRCoordOfPlaneImage' }, #4
    '0027,1043' => { VR => 'FL', Name => 'CenterACoordOfPlaneImage' }, #4
    '0027,1044' => { VR => 'FL', Name => 'CenterSCoordOfPlaneImage' }, #4
    '0027,1045' => { VR => 'FL', Name => 'NormalRCoord' }, #4
    '0027,1046' => { VR => 'FL', Name => 'NormalACoord' }, #4
    '0027,1047' => { VR => 'FL', Name => 'NormalSCoord' }, #4
    '0027,1048' => { VR => 'FL', Name => 'RCoordOfTopRightCorner' }, #4
    '0027,1049' => { VR => 'FL', Name => 'ACoordOfTopRightCorner' }, #4
    '0027,104A' => { VR => 'FL', Name => 'SCoordOfTopRightCorner' }, #4
    '0027,104B' => { VR => 'FL', Name => 'RCoordOfBottomRightCorner' }, #4
    '0027,104C' => { VR => 'FL', Name => 'ACoordOfBottomRightCorner' }, #4
    '0027,104D' => { VR => 'FL', Name => 'SCoordOfBottomRightCorner' }, #4
    '0027,1050' => { VR => 'FL', Name => 'TableStartLocation' }, #4
    '0027,1051' => { VR => 'FL', Name => 'TableEndLocation' }, #4
    '0027,1052' => { VR => 'SH', Name => 'RASLetterForSideOfImage' }, #4
    '0027,1053' => { VR => 'SH', Name => 'RASLetterForAnteriorPosterior' }, #4
    '0027,1054' => { VR => 'SH', Name => 'RASLetterForScoutStartLoc' }, #4
    '0027,1055' => { VR => 'SH', Name => 'RASLetterForScoutEndLoc' }, #4
    '0027,1060' => { VR => 'FL', Name => 'ImageDimensionX' }, #4
    '0027,1061' => { VR => 'FL', Name => 'ImageDimensionY' }, #4
    '0027,1062' => { VR => 'FL', Name => 'NumberOfExcitations' }, #4
    # image presentation group
    '0028,0000' => { VR => 'UL', Name => 'ImagePresentationGroupLength' },
    '0028,0002' => { VR => 'US', Name => 'SamplesPerPixel' },
    '0028,0003' => { VR => 'US', Name => 'SamplesPerPixelUsed' },
    '0028,0004' => { VR => 'CS', Name => 'PhotometricInterpretation' },
    '0028,0005' => { VR => 'US', Name => 'ImageDimensions' },
    '0028,0006' => { VR => 'US', Name => 'PlanarConfiguration' },
    '0028,0008' => { VR => 'IS', Name => 'NumberOfFrames' },
    '0028,0009' => { VR => 'AT', Name => 'FrameIncrementPointer' },
    '0028,000A' => { VR => 'AT', Name => 'FrameDimensionPointer' },
    '0028,0010' => { VR => 'US', Name => 'Rows' },
    '0028,0011' => { VR => 'US', Name => 'Columns' },
    '0028,0012' => { VR => 'US', Name => 'Planes' },
    '0028,0014' => { VR => 'US', Name => 'UltrasoundColorDataPresent' },
    '0028,0030' => { VR => 'DS', Name => 'PixelSpacing' },
    '0028,0031' => { VR => 'DS', Name => 'ZoomFactor' },
    '0028,0032' => { VR => 'DS', Name => 'ZoomCenter' },
    '0028,0034' => { VR => 'IS', Name => 'PixelAspectRatio' },
    '0028,0040' => { VR => 'RET',Name => 'ImageFormat' },
    '0028,0050' => { VR => 'RET',Name => 'ManipulatedImage' },
    '0028,0051' => { VR => 'CS', Name => 'CorrectedImage' },
    '0028,0060' => { VR => 'RET',Name => 'CompressionCode' },
    '0028,0100' => { VR => 'US', Name => 'BitsAllocated' },
    '0028,0101' => { VR => 'US', Name => 'BitsStored' },
    '0028,0102' => { VR => 'US', Name => 'HighBit' },
    '0028,0103' => { VR => 'US', Name => 'PixelRepresentation', PrintConv => { 0 => 'Unsigned', 1 => 'Signed' } },
    '0028,0104' => { VR => 'RET',Name => 'SmallestValidPixelValue' },
    '0028,0105' => { VR => 'RET',Name => 'LargestValidPixelValue' },
    '0028,0106' => { VR => 'SS', Name => 'SmallestImagePixelValue' },
    '0028,0107' => { VR => 'SS', Name => 'LargestImagePixelValue' },
    '0028,0108' => { VR => 'SS', Name => 'SmallestPixelValueInSeries' },
    '0028,0109' => { VR => 'SS', Name => 'LargestPixelValueInSeries' },
    '0028,0110' => { VR => 'SS', Name => 'SmallestImagePixelValueInPlane' },
    '0028,0111' => { VR => 'SS', Name => 'LargestImagePixelValueInPlane' },
    '0028,0120' => { VR => 'SS', Name => 'PixelPaddingValue' },
    '0028,0200' => { VR => 'SS', Name => 'ImageLocation' },
    '0028,0300' => { VR => 'CS', Name => 'QualityControlImage' },
    '0028,0301' => { VR => 'CS', Name => 'BurnedInAnnotation' },
    '0028,1040' => { VR => 'CS', Name => 'PixelIntensityRelationship' },
    '0028,1041' => { VR => 'SS', Name => 'PixelIntensityRelationshipSign' },
    '0028,1050' => { VR => 'DS', Name => 'WindowCenter' },
    '0028,1051' => { VR => 'DS', Name => 'WindowWidth' },
    '0028,1052' => { VR => 'DS', Name => 'RescaleIntercept' },
    '0028,1053' => { VR => 'DS', Name => 'RescaleSlope' },
    '0028,1054' => { VR => 'LO', Name => 'RescaleType' },
    '0028,1055' => { VR => 'LO', Name => 'WindowCenterAndWidthExplanation' },
    '0028,1080' => { VR => 'RET',Name => 'GrayScale' },
    '0028,1090' => { VR => 'CS', Name => 'RecommendedViewingMode' },
    '0028,1100' => { VR => 'RET',Name => 'GrayLookupTableDescriptor' },
    '0028,1101' => { VR => 'SS', Name => 'RedPaletteColorTableDescriptor' },
    '0028,1102' => { VR => 'SS', Name => 'GreenPaletteColorTableDescriptor' },
    '0028,1103' => { VR => 'SS', Name => 'BluePaletteColorTableDescriptor' },
    '0028,1199' => { VR => 'UI', Name => 'PaletteColorTableUID' },
    '0028,1200' => { VR => 'RET',Name => 'GrayLookupTableData' },
    '0028,1201' => { VR => 'OW', Name => 'RedPaletteColorTableData' },
    '0028,1202' => { VR => 'OW', Name => 'GreenPaletteColorTableData' },
    '0028,1203' => { VR => 'OW', Name => 'BluePaletteColorTableData' },
    '0028,1221' => { VR => 'OW', Name => 'SegmentedRedColorTableData' },
    '0028,1222' => { VR => 'OW', Name => 'SegmentedGreenColorTableData' },
    '0028,1223' => { VR => 'OW', Name => 'SegmentedBlueColorTableData' },
    '0028,1300' => { VR => 'CS', Name => 'ImplantPresent' },
    '0028,1350' => { VR => 'CS', Name => 'PartialView' },
    '0028,1351' => { VR => 'ST', Name => 'PartialViewDescription' },
    '0028,2110' => { VR => 'CS', Name => 'LossyImageCompression' },
    '0028,2112' => { VR => 'DS', Name => 'LossyImageCompressionRatio' },
    '0028,2114' => { VR => 'CS', Name => 'LossyImageCompressionMethod' },
    '0028,3000' => { VR => 'SQ', Name => 'ModalityLUTSequence' },
    '0028,3002' => { VR => 'SS', Name => 'LUTDescriptor' },
    '0028,3003' => { VR => 'LO', Name => 'LUTExplanation' },
    '0028,3004' => { VR => 'LO', Name => 'ModalityLUTType' },
    '0028,3006' => { VR => 'SS', Name => 'LUTData' },
    '0028,3010' => { VR => 'SQ', Name => 'VOILUTSequence' },
    '0028,3110' => { VR => 'SQ', Name => 'SoftcopyVOILUTSequence' },
    '0028,4000' => { VR => 'RET',Name => 'ImagePresentationComments' },
    '0028,5000' => { VR => 'SQ', Name => 'BiPlaneAcquisitionSequence' },
    '0028,6010' => { VR => 'US', Name => 'RepresentativeFrameNumber' },
    '0028,6020' => { VR => 'US', Name => 'FrameNumbersOfInterestFOI' },
    '0028,6022' => { VR => 'LO', Name => 'FrameOfInterestDescription' },
    '0028,6023' => { VR => 'CS', Name => 'FrameOfInterestType' },
    '0028,6030' => { VR => 'RET',Name => 'MaskPointers' },
    '0028,6040' => { VR => 'US', Name => 'RWavePointer' },
    '0028,6100' => { VR => 'SQ', Name => 'MaskSubtractionSequence' },
    '0028,6101' => { VR => 'CS', Name => 'MaskOperation' },
    '0028,6102' => { VR => 'US', Name => 'ApplicableFrameRange' },
    '0028,6110' => { VR => 'US', Name => 'MaskFrameNumbers' },
    '0028,6112' => { VR => 'US', Name => 'ContrastFrameAveraging' },
    '0028,6114' => { VR => 'FL', Name => 'MaskSubPixelShift' },
    '0028,6120' => { VR => 'SS', Name => 'TIDOffset' },
    '0028,6190' => { VR => 'ST', Name => 'MaskOperationExplanation' },
    '0028,9001' => { VR => 'UL', Name => 'DataPointRows' },
    '0028,9002' => { VR => 'UL', Name => 'DataPointColumns' },
    '0028,9003' => { VR => 'CS', Name => 'SignalDomainColumns' },
    '0028,9099' => { VR => 'US', Name => 'LargestMonochromePixelValue' },
    '0028,9108' => { VR => 'CS', Name => 'DataRepresentation' },
    '0028,9110' => { VR => 'SQ', Name => 'PixelMeasuresSequence' },
    '0028,9132' => { VR => 'SQ', Name => 'FrameVOILUTSequence' },
    '0028,9145' => { VR => 'SQ', Name => 'PixelValueTransformationSequence' },
    '0028,9235' => { VR => 'CS', Name => 'SignalDomainRows' },
    '0029,1004' => { VR => 'SL', Name => 'LowerRangeOfPixels1a' }, #4
    '0029,1005' => { VR => 'DS', Name => 'LowerRangeOfPixels1b' }, #4
    '0029,1006' => { VR => 'DS', Name => 'LowerRangeOfPixels1c' }, #4
    '0029,1007' => { VR => 'SL', Name => 'LowerRangeOfPixels1d' }, #4
    '0029,1008' => { VR => 'SH', Name => 'LowerRangeOfPixels1e' }, #4
    '0029,1009' => { VR => 'SH', Name => 'LowerRangeOfPixels1f' }, #4
    '0029,100A' => { VR => 'SS', Name => 'LowerRangeOfPixels1g' }, #4
    '0029,1015' => { VR => 'SL', Name => 'LowerRangeOfPixels1h' }, #4
    '0029,1016' => { VR => 'SL', Name => 'LowerRangeOfPixels1i' }, #4
    '0029,1017' => { VR => 'SL', Name => 'LowerRangeOfPixels2' }, #4
    '0029,1018' => { VR => 'SL', Name => 'UpperRangeOfPixels2' }, #4
    '0029,101A' => { VR => 'SL', Name => 'LenOfTotHdrInBytes' }, #4
    '0029,1026' => { VR => 'SS', Name => 'VersionOfTheHdrStruct' }, #4
    '0029,1034' => { VR => 'SL', Name => 'AdvantageCompOverflow' }, #4
    '0029,1035' => { VR => 'SL', Name => 'AdvantageCompUnderflow' }, #4
    # study group
    '0032,0000' => { VR => 'UL', Name => 'StudyGroupLength' },
    '0032,000A' => { VR => 'CS', Name => 'StudyStatusID' },
    '0032,000C' => { VR => 'CS', Name => 'StudyPriorityID' },
    '0032,0012' => { VR => 'LO', Name => 'StudyIDIssuer' },
    '0032,0032' => { VR => 'DA', Name => 'StudyVerifiedDate' },
    '0032,0033' => { VR => 'TM', Name => 'StudyVerifiedTime' },
    '0032,0034' => { VR => 'DA', Name => 'StudyReadDate' },
    '0032,0035' => { VR => 'TM', Name => 'StudyReadTime' },
    '0032,1000' => { VR => 'DA', Name => 'ScheduledStudyStartDate' },
    '0032,1001' => { VR => 'TM', Name => 'ScheduledStudyStartTime' },
    '0032,1010' => { VR => 'DA', Name => 'ScheduledStudyStopDate' },
    '0032,1011' => { VR => 'TM', Name => 'ScheduledStudyStopTime' },
    '0032,1020' => { VR => 'LO', Name => 'ScheduledStudyLocation' },
    '0032,1021' => { VR => 'AE', Name => 'ScheduledStudyLocationAETitle' },
    '0032,1030' => { VR => 'LO', Name => 'ReasonForStudy' },
    '0032,1031' => { VR => 'SQ', Name => 'RequestingPhysicianIDSequence' },
    '0032,1032' => { VR => 'PN', Name => 'RequestingPhysician' },
    '0032,1033' => { VR => 'LO', Name => 'RequestingService' },
    '0032,1040' => { VR => 'DA', Name => 'StudyArrivalDate' },
    '0032,1041' => { VR => 'TM', Name => 'StudyArrivalTime' },
    '0032,1050' => { VR => 'DA', Name => 'StudyCompletionDate' },
    '0032,1051' => { VR => 'TM', Name => 'StudyCompletionTime' },
    '0032,1055' => { VR => 'CS', Name => 'StudyComponentStatusID' },
    '0032,1060' => { VR => 'LO', Name => 'RequestedProcedureDescription' },
    '0032,1064' => { VR => 'SQ', Name => 'RequestedProcedureCodeSequence' },
    '0032,1070' => { VR => 'LO', Name => 'RequestedContrastAgent' },
    '0032,4000' => { VR => 'LT', Name => 'StudyComments' },
    # visit group
    '0038,0004' => { VR => 'SQ', Name => 'ReferencedPatientAliasSequence' },
    '0038,0008' => { VR => 'CS', Name => 'VisitStatusID' },
    '0038,0010' => { VR => 'LO', Name => 'AdmissionID' },
    '0038,0011' => { VR => 'LO', Name => 'IssuerOfAdmissionID' },
    '0038,0016' => { VR => 'LO', Name => 'RouteOfAdmissions' },
    '0038,001A' => { VR => 'DA', Name => 'ScheduledAdmissionDate' },
    '0038,001B' => { VR => 'TM', Name => 'ScheduledAdmissionTime' },
    '0038,001C' => { VR => 'DA', Name => 'ScheduledDischargeDate' },
    '0038,001D' => { VR => 'TM', Name => 'ScheduledDischargeTime' },
    '0038,001E' => { VR => 'LO', Name => 'ScheduledPatientInstitResidence' },
    '0038,0020' => { VR => 'DA', Name => 'AdmittingDate' },
    '0038,0021' => { VR => 'TM', Name => 'AdmittingTime' },
    '0038,0030' => { VR => 'DA', Name => 'DischargeDate' },
    '0038,0032' => { VR => 'TM', Name => 'DischargeTime' },
    '0038,0040' => { VR => 'LO', Name => 'DischargeDiagnosisDescription' },
    '0038,0044' => { VR => 'SQ', Name => 'DischargeDiagnosisCodeSequence' },
    '0038,0050' => { VR => 'LO', Name => 'SpecialNeeds' },
    '0038,0300' => { VR => 'LO', Name => 'CurrentPatientLocation' },
    '0038,0400' => { VR => 'LO', Name => 'PatientsInstitutionResidence' },
    '0038,0500' => { VR => 'LO', Name => 'PatientState' },
    '0038,4000' => { VR => 'LT', Name => 'VisitComments' },
    '003A,0004' => { VR => 'CS', Name => 'WaveformOriginality' },
    '003A,0005' => { VR => 'US', Name => 'NumberOfWaveformChannels' },
    '003A,0010' => { VR => 'UL', Name => 'NumberOfWaveformSamples' },
    '003A,001A' => { VR => 'DS', Name => 'SamplingFrequency' },
    '003A,0020' => { VR => 'SH', Name => 'MultiplexGroupLabel' },
    '003A,0200' => { VR => 'SQ', Name => 'ChannelDefinitionSequence' },
    '003A,0202' => { VR => 'IS', Name => 'WaveformChannelNumber' },
    '003A,0203' => { VR => 'SH', Name => 'ChannelLabel' },
    '003A,0205' => { VR => 'CS', Name => 'ChannelStatus' },
    '003A,0208' => { VR => 'SQ', Name => 'ChannelSourceSequence' },
    '003A,0209' => { VR => 'SQ', Name => 'ChannelSourceModifiersSequence' },
    '003A,020A' => { VR => 'SQ', Name => 'SourceWaveformSequence' },
    '003A,020C' => { VR => 'LO', Name => 'ChannelDerivationDescription' },
    '003A,0210' => { VR => 'DS', Name => 'ChannelSensitivity' },
    '003A,0211' => { VR => 'SQ', Name => 'ChannelSensitivityUnitsSequence' },
    '003A,0212' => { VR => 'DS', Name => 'ChannelSensitivityCorrectionFactor' },
    '003A,0213' => { VR => 'DS', Name => 'ChannelBaseline' },
    '003A,0214' => { VR => 'DS', Name => 'ChannelTimeSkew' },
    '003A,0215' => { VR => 'DS', Name => 'ChannelSampleSkew' },
    '003A,0218' => { VR => 'DS', Name => 'ChannelOffset' },
    '003A,021A' => { VR => 'US', Name => 'WaveformBitsStored' },
    '003A,0220' => { VR => 'DS', Name => 'FilterLowFrequency' },
    '003A,0221' => { VR => 'DS', Name => 'FilterHighFrequency' },
    '003A,0222' => { VR => 'DS', Name => 'NotchFilterFrequency' },
    '003A,0223' => { VR => 'DS', Name => 'NotchFilterBandwidth' },
    '003A,0300' => { VR => 'SQ', Name => 'MultiplexAudioChannelsDescrCodeSeq' },
    '003A,0301' => { VR => 'IS', Name => 'ChannelIdentificationCode' },
    '003A,0302' => { VR => 'CS', Name => 'ChannelMode' },
    '0040,0001' => { VR => 'AE', Name => 'ScheduledStationAETitle' },
    '0040,0002' => { VR => 'DA', Name => 'ScheduledProcedureStepStartDate' },
    '0040,0003' => { VR => 'TM', Name => 'ScheduledProcedureStepStartTime' },
    '0040,0004' => { VR => 'DA', Name => 'ScheduledProcedureStepEndDate' },
    '0040,0005' => { VR => 'TM', Name => 'ScheduledProcedureStepEndTime' },
    '0040,0006' => { VR => 'PN', Name => 'ScheduledPerformingPhysiciansName' },
    '0040,0007' => { VR => 'LO', Name => 'ScheduledProcedureStepDescription' },
    '0040,0008' => { VR => 'SQ', Name => 'ScheduledProtocolCodeSequence' },
    '0040,0009' => { VR => 'SH', Name => 'ScheduledProcedureStepID' },
    '0040,000A' => { VR => 'SQ', Name => 'StageCodeSequence' },
    '0040,000B' => { VR => 'SQ', Name => 'ScheduledPerformingPhysicianIDSeq' },
    '0040,0010' => { VR => 'SH', Name => 'ScheduledStationName' },
    '0040,0011' => { VR => 'SH', Name => 'ScheduledProcedureStepLocation' },
    '0040,0012' => { VR => 'LO', Name => 'PreMedication' },
    '0040,0020' => { VR => 'CS', Name => 'ScheduledProcedureStepStatus' },
    '0040,0100' => { VR => 'SQ', Name => 'ScheduledProcedureStepSequence' },
    '0040,0220' => { VR => 'SQ', Name => 'ReferencedNonImageCompositeSOPSeq' },
    '0040,0241' => { VR => 'AE', Name => 'PerformedStationAETitle' },
    '0040,0242' => { VR => 'SH', Name => 'PerformedStationName' },
    '0040,0243' => { VR => 'SH', Name => 'PerformedLocation' },
    '0040,0244' => { VR => 'DA', Name => 'PerformedProcedureStepStartDate' },
    '0040,0245' => { VR => 'TM', Name => 'PerformedProcedureStepStartTime' },
    '0040,0250' => { VR => 'DA', Name => 'PerformedProcedureStepEndDate' },
    '0040,0251' => { VR => 'TM', Name => 'PerformedProcedureStepEndTime' },
    '0040,0252' => { VR => 'CS', Name => 'PerformedProcedureStepStatus' },
    '0040,0253' => { VR => 'SH', Name => 'PerformedProcedureStepID' },
    '0040,0254' => { VR => 'LO', Name => 'PerformedProcedureStepDescription' },
    '0040,0255' => { VR => 'LO', Name => 'PerformedProcedureTypeDescription' },
    '0040,0260' => { VR => 'SQ', Name => 'PerformedProtocolCodeSequence' },
    '0040,0270' => { VR => 'SQ', Name => 'ScheduledStepAttributesSequence' },
    '0040,0275' => { VR => 'SQ', Name => 'RequestAttributesSequence' },
    '0040,0280' => { VR => 'ST', Name => 'CommentsOnPerformedProcedureStep' },
    '0040,0281' => { VR => 'SQ', Name => 'ProcStepDiscontinueReasonCodeSeq' },
    '0040,0293' => { VR => 'SQ', Name => 'QuantitySequence' },
    '0040,0294' => { VR => 'DS', Name => 'Quantity' },
    '0040,0295' => { VR => 'SQ', Name => 'MeasuringUnitsSequence' },
    '0040,0296' => { VR => 'SQ', Name => 'BillingItemSequence' },
    '0040,0300' => { VR => 'US', Name => 'TotalTimeOfFluoroscopy' },
    '0040,0301' => { VR => 'US', Name => 'TotalNumberOfExposures' },
    '0040,0302' => { VR => 'US', Name => 'EntranceDose' },
    '0040,0303' => { VR => 'US', Name => 'ExposedArea' },
    '0040,0306' => { VR => 'DS', Name => 'DistanceSourceToEntrance' },
    '0040,0307' => { VR => 'RET',Name => 'DistanceSourceToSupport' },
    '0040,030E' => { VR => 'SQ', Name => 'ExposureDoseSequence' },
    '0040,0310' => { VR => 'ST', Name => 'CommentsOnRadiationDose' },
    '0040,0312' => { VR => 'DS', Name => 'XRayOutput' },
    '0040,0314' => { VR => 'DS', Name => 'HalfValueLayer' },
    '0040,0316' => { VR => 'DS', Name => 'OrganDose' },
    '0040,0318' => { VR => 'CS', Name => 'OrganExposed' },
    '0040,0320' => { VR => 'SQ', Name => 'BillingProcedureStepSequence' },
    '0040,0321' => { VR => 'SQ', Name => 'FilmConsumptionSequence' },
    '0040,0324' => { VR => 'SQ', Name => 'BillingSuppliesAndDevicesSequence' },
    '0040,0330' => { VR => 'RET',Name => 'ReferencedProcedureStepSequence' },
    '0040,0340' => { VR => 'SQ', Name => 'PerformedSeriesSequence' },
    '0040,0400' => { VR => 'LT', Name => 'CommentsOnScheduledProcedureStep' },
    '0040,0440' => { VR => 'SQ', Name => 'ProtocolContextSequence' },
    '0040,0441' => { VR => 'SQ', Name => 'ContentItemModifierSequence' },
    '0040,050A' => { VR => 'LO', Name => 'SpecimenAccessionNumber' },
    '0040,0550' => { VR => 'SQ', Name => 'SpecimenSequence' },
    '0040,0551' => { VR => 'LO', Name => 'SpecimenIdentifier' },
    '0040,0555' => { VR => 'SQ', Name => 'AcquisitionContextSequence' },
    '0040,0556' => { VR => 'ST', Name => 'AcquisitionContextDescription' },
    '0040,059A' => { VR => 'SQ', Name => 'SpecimenTypeCodeSequence' },
    '0040,06FA' => { VR => 'LO', Name => 'SlideIdentifier' },
    '0040,071A' => { VR => 'SQ', Name => 'ImageCenterPointCoordinatesSeq' },
    '0040,072A' => { VR => 'DS', Name => 'XOffsetInSlideCoordinateSystem' },
    '0040,073A' => { VR => 'DS', Name => 'YOffsetInSlideCoordinateSystem' },
    '0040,074A' => { VR => 'DS', Name => 'ZOffsetInSlideCoordinateSystem' },
    '0040,08D8' => { VR => 'SQ', Name => 'PixelSpacingSequence' },
    '0040,08DA' => { VR => 'SQ', Name => 'CoordinateSystemAxisCodeSequence' },
    '0040,08EA' => { VR => 'SQ', Name => 'MeasurementUnitsCodeSequence' },
    '0040,1001' => { VR => 'SH', Name => 'RequestedProcedureID' },
    '0040,1002' => { VR => 'LO', Name => 'ReasonForRequestedProcedure' },
    '0040,1003' => { VR => 'SH', Name => 'RequestedProcedurePriority' },
    '0040,1004' => { VR => 'LO', Name => 'PatientTransportArrangements' },
    '0040,1005' => { VR => 'LO', Name => 'RequestedProcedureLocation' },
    '0040,1006' => { VR => 'RET',Name => 'PlacerOrderNumber-Procedure' },
    '0040,1007' => { VR => 'RET',Name => 'FillerOrderNumber-Procedure' },
    '0040,1008' => { VR => 'LO', Name => 'ConfidentialityCode' },
    '0040,1009' => { VR => 'SH', Name => 'ReportingPriority' },
    '0040,100A' => { VR => 'SQ', Name => 'ReasonForRequestedProcedureCodeSeq' },
    '0040,1010' => { VR => 'PN', Name => 'NamesOfIntendedRecipientsOfResults' },
    '0040,1011' => { VR => 'SQ', Name => 'IntendedRecipientsOfResultsIDSeq' },
    '0040,1101' => { VR => 'SQ', Name => 'PersonIdentificationCodeSequence' },
    '0040,1102' => { VR => 'ST', Name => 'PersonsAddress' },
    '0040,1103' => { VR => 'LO', Name => 'PersonsTelephoneNumbers' },
    '0040,1400' => { VR => 'LT', Name => 'RequestedProcedureComments' },
    '0040,2001' => { VR => 'RET',Name => 'ReasonForImagingServiceRequest' },
    '0040,2004' => { VR => 'DA', Name => 'IssueDateOfImagingServiceRequest' },
    '0040,2005' => { VR => 'TM', Name => 'IssueTimeOfImagingServiceRequest' },
    '0040,2006' => { VR => 'RET',Name => 'PlacerOrderNum-ImagingServiceReq' },
    '0040,2007' => { VR => 'RET',Name => 'FillerOrderNum-ImagingServiceReq' },
    '0040,2008' => { VR => 'PN', Name => 'OrderEnteredBy' },
    '0040,2009' => { VR => 'SH', Name => 'OrderEnterersLocation' },
    '0040,2010' => { VR => 'SH', Name => 'OrderCallbackPhoneNumber' },
    '0040,2016' => { VR => 'LO', Name => 'PlacerOrderNum-ImagingServiceReq' },
    '0040,2017' => { VR => 'LO', Name => 'FillerOrderNum-ImagingServiceReq' },
    '0040,2400' => { VR => 'LT', Name => 'ImagingServiceRequestComments' },
    '0040,3001' => { VR => 'LO', Name => 'ConfidentialityOnPatientDataDescr' },
    '0040,4001' => { VR => 'CS', Name => 'GenPurposeScheduledProcStepStatus' },
    '0040,4002' => { VR => 'CS', Name => 'GenPurposePerformedProcStepStatus' },
    '0040,4003' => { VR => 'CS', Name => 'GenPurposeSchedProcStepPriority' },
    '0040,4004' => { VR => 'SQ', Name => 'SchedProcessingApplicationsCodeSeq' },
    '0040,4005' => { VR => 'DT', Name => 'SchedProcedureStepStartDateAndTime' },
    '0040,4006' => { VR => 'CS', Name => 'MultipleCopiesFlag' },
    '0040,4007' => { VR => 'SQ', Name => 'PerformedProcessingAppsCodeSeq' },
    '0040,4009' => { VR => 'SQ', Name => 'HumanPerformerCodeSequence' },
    '0040,4010' => { VR => 'DT', Name => 'SchedProcStepModificationDateTime' },
    '0040,4011' => { VR => 'DT', Name => 'ExpectedCompletionDateAndTime' },
    '0040,4015' => { VR => 'SQ', Name => 'ResultingGenPurposePerfProcStepSeq' },
    '0040,4016' => { VR => 'SQ', Name => 'RefGenPurposeSchedProcStepSeq' },
    '0040,4018' => { VR => 'SQ', Name => 'ScheduledWorkitemCodeSequence' },
    '0040,4019' => { VR => 'SQ', Name => 'PerformedWorkitemCodeSequence' },
    '0040,4020' => { VR => 'CS', Name => 'InputAvailabilityFlag' },
    '0040,4021' => { VR => 'SQ', Name => 'InputInformationSequence' },
    '0040,4022' => { VR => 'SQ', Name => 'RelevantInformationSequence' },
    '0040,4023' => { VR => 'UI', Name => 'RefGenPurSchedProcStepTransUID' },
    '0040,4025' => { VR => 'SQ', Name => 'ScheduledStationNameCodeSequence' },
    '0040,4026' => { VR => 'SQ', Name => 'ScheduledStationClassCodeSequence' },
    '0040,4027' => { VR => 'SQ', Name => 'SchedStationGeographicLocCodeSeq' },
    '0040,4028' => { VR => 'SQ', Name => 'PerformedStationNameCodeSequence' },
    '0040,4029' => { VR => 'SQ', Name => 'PerformedStationClassCodeSequence' },
    '0040,4030' => { VR => 'SQ', Name => 'PerformedStationGeogLocCodeSeq' },
    '0040,4031' => { VR => 'SQ', Name => 'RequestedSubsequentWorkItemCodeSeq' },
    '0040,4032' => { VR => 'SQ', Name => 'NonDICOMOutputCodeSequence' },
    '0040,4033' => { VR => 'SQ', Name => 'OutputInformationSequence' },
    '0040,4034' => { VR => 'SQ', Name => 'ScheduledHumanPerformersSequence' },
    '0040,4035' => { VR => 'SQ', Name => 'ActualHumanPerformersSequence' },
    '0040,4036' => { VR => 'LO', Name => 'HumanPerformersOrganization' },
    '0040,4037' => { VR => 'PN', Name => 'HumanPerformersName' },
    '0040,8302' => { VR => 'DS', Name => 'EntranceDoseInMilliGy' },
    '0040,9096' => { VR => 'SQ', Name => 'RealWorldValueMappingSequence' },
    '0040,9210' => { VR => 'SH', Name => 'LUTLabel' },
    '0040,9211' => { VR => 'SS', Name => 'RealWorldValueLastValueMapped' },
    '0040,9212' => { VR => 'FD', Name => 'RealWorldValueLUTData' },
    '0040,9216' => { VR => 'SS', Name => 'RealWorldValueFirstValueMapped' },
    '0040,9224' => { VR => 'FD', Name => 'RealWorldValueIntercept' },
    '0040,9225' => { VR => 'FD', Name => 'RealWorldValueSlope' },
    '0040,A010' => { VR => 'CS', Name => 'RelationshipType' },
    '0040,A027' => { VR => 'LO', Name => 'VerifyingOrganization' },
    '0040,A030' => { VR => 'DT', Name => 'VerificationDateTime' },
    '0040,A032' => { VR => 'DT', Name => 'ObservationDateTime' },
    '0040,A040' => { VR => 'CS', Name => 'ValueType' },
    '0040,A043' => { VR => 'SQ', Name => 'ConceptNameCodeSequence' },
    '0040,A050' => { VR => 'CS', Name => 'ContinuityOfContent' },
    '0040,A073' => { VR => 'SQ', Name => 'VerifyingObserverSequence' },
    '0040,A075' => { VR => 'PN', Name => 'VerifyingObserverName' },
    '0040,A088' => { VR => 'SQ', Name => 'VerifyingObserverIdentCodeSequence' },
    '0040,A0B0' => { VR => 'US', Name => 'ReferencedWaveformChannels' },
    '0040,A120' => { VR => 'DT', Name => 'DateTime' },
    '0040,A121' => { VR => 'DA', Name => 'Date' },
    '0040,A122' => { VR => 'TM', Name => 'Time' },
    '0040,A123' => { VR => 'PN', Name => 'PersonName' },
    '0040,A124' => { VR => 'UI', Name => 'UID' },
    '0040,A130' => { VR => 'CS', Name => 'TemporalRangeType' },
    '0040,A132' => { VR => 'UL', Name => 'ReferencedSamplePositions' },
    '0040,A136' => { VR => 'US', Name => 'ReferencedFrameNumbers' },
    '0040,A138' => { VR => 'DS', Name => 'ReferencedTimeOffsets' },
    '0040,A13A' => { VR => 'DT', Name => 'ReferencedDatetime' },
    '0040,A160' => { VR => 'UT', Name => 'TextValue' },
    '0040,A168' => { VR => 'SQ', Name => 'ConceptCodeSequence' },
    '0040,A170' => { VR => 'SQ', Name => 'PurposeOfReferenceCodeSequence' },
    '0040,A180' => { VR => 'US', Name => 'AnnotationGroupNumber' },
    '0040,A195' => { VR => 'SQ', Name => 'ModifierCodeSequence' },
    '0040,A300' => { VR => 'SQ', Name => 'MeasuredValueSequence' },
    '0040,A301' => { VR => 'SQ', Name => 'NumericValueQualifierCodeSequence' },
    '0040,A30A' => { VR => 'DS', Name => 'NumericValue' },
    '0040,A360' => { VR => 'SQ', Name => 'PredecessorDocumentsSequence' },
    '0040,A370' => { VR => 'SQ', Name => 'ReferencedRequestSequence' },
    '0040,A372' => { VR => 'SQ', Name => 'PerformedProcedureCodeSequence' },
    '0040,A375' => { VR => 'SQ', Name => 'CurrentRequestedProcEvidenceSeq' },
    '0040,A385' => { VR => 'SQ', Name => 'PertinentOtherEvidenceSequence' },
    '0040,A491' => { VR => 'CS', Name => 'CompletionFlag' },
    '0040,A492' => { VR => 'LO', Name => 'CompletionFlagDescription' },
    '0040,A493' => { VR => 'CS', Name => 'VerificationFlag' },
    '0040,A504' => { VR => 'SQ', Name => 'ContentTemplateSequence' },
    '0040,A525' => { VR => 'SQ', Name => 'IdenticalDocumentsSequence' },
    '0040,A730' => { VR => 'SQ', Name => 'ContentSequence' },
    '0040,B020' => { VR => 'SQ', Name => 'AnnotationSequence' },
    '0040,DB00' => { VR => 'CS', Name => 'TemplateIdentifier' },
    '0040,DB06' => { VR => 'RET',Name => 'TemplateVersion' },
    '0040,DB07' => { VR => 'RET',Name => 'TemplateLocalVersion' },
    '0040,DB0B' => { VR => 'RET',Name => 'TemplateExtensionFlag' },
    '0040,DB0C' => { VR => 'RET',Name => 'TemplateExtensionOrganizationUID' },
    '0040,DB0D' => { VR => 'RET',Name => 'TemplateExtensionCreatorUID' },
    '0040,DB73' => { VR => 'UL', Name => 'ReferencedContentItemIdentifier' },
    '0043,1001' => { VR => 'SS', Name => 'BitmapOfPrescanOptions' }, #4
    '0043,1002' => { VR => 'SS', Name => 'GradientOffsetInX' }, #4
    '0043,1003' => { VR => 'SS', Name => 'GradientOffsetInY' }, #4
    '0043,1004' => { VR => 'SS', Name => 'GradientOffsetInZ' }, #4
    '0043,1005' => { VR => 'SS', Name => 'ImgIsOriginalOrUnoriginal' }, #4
    '0043,1006' => { VR => 'SS', Name => 'NumberOfEPIShots' }, #4
    '0043,1007' => { VR => 'SS', Name => 'ViewsPerSegment' }, #4
    '0043,1008' => { VR => 'SS', Name => 'RespiratoryRateBpm' }, #4
    '0043,1009' => { VR => 'SS', Name => 'RespiratoryTriggerPoint' }, #4
    '0043,100A' => { VR => 'SS', Name => 'TypeOfReceiverUsed' }, #4
    '0043,100B' => { VR => 'DS', Name => 'PeakRateOfChangeOfGradientField' }, #4
    '0043,100C' => { VR => 'DS', Name => 'LimitsInUnitsOfPercent' }, #4
    '0043,100D' => { VR => 'DS', Name => 'PSDEstimatedLimit' }, #4
    '0043,100E' => { VR => 'DS', Name => 'PSDEstimatedLimitInTeslaPerSecond' }, #4
    '0043,100F' => { VR => 'DS', Name => 'Saravghead' }, #4
    '0043,1010' => { VR => 'US', Name => 'WindowValue' }, #4
    '0043,1011' => { VR => 'US', Name => 'TotalInputViews' }, #4
    '0043,1012' => { VR => 'SS', Name => 'X-RayChain' }, #4
    '0043,1013' => { VR => 'SS', Name => 'DeconKernelParameters' }, #4
    '0043,1014' => { VR => 'SS', Name => 'CalibrationParameters' }, #4
    '0043,1015' => { VR => 'SS', Name => 'TotalOutputViews' }, #4
    '0043,1016' => { VR => 'SS', Name => 'NumberOfOverranges' }, #4
    '0043,1017' => { VR => 'DS', Name => 'IBHImageScaleFactors' }, #4
    '0043,1018' => { VR => 'DS', Name => 'BBHCoefficients' }, #4
    '0043,1019' => { VR => 'SS', Name => 'NumberOfBBHChainsToBlend' }, #4
    '0043,101A' => { VR => 'SL', Name => 'StartingChannelNumber' }, #4
    '0043,101B' => { VR => 'SS', Name => 'PpscanParameters' }, #4
    '0043,101C' => { VR => 'SS', Name => 'GEImageIntegrity' }, #4
    '0043,101D' => { VR => 'SS', Name => 'LevelValue' }, #4
    '0043,101E' => { VR => 'DS', Name => 'DeltaStartTime' }, #4
    '0043,101F' => { VR => 'SL', Name => 'MaxOverrangesInAView' }, #4
    '0043,1020' => { VR => 'DS', Name => 'AvgOverrangesAllViews' }, #4
    '0043,1021' => { VR => 'SS', Name => 'CorrectedAfterGlowTerms' }, #4
    '0043,1025' => { VR => 'SS', Name => 'ReferenceChannels' }, #4
    '0043,1026' => { VR => 'US', Name => 'NoViewsRefChansBlocked' }, #4
    '0043,1027' => { VR => 'SH', Name => 'ScanPitchRatio' }, #4
    '0043,1028' => { VR => 'OB', Name => 'UniqueImageIden' }, #4
    '0043,1029' => { VR => 'OB', Name => 'HistogramTables' }, #4
    '0043,102A' => { VR => 'OB', Name => 'UserDefinedData' }, #4
    '0043,102B' => { VR => 'SS', Name => 'PrivateScanOptions' }, #4
    '0043,102C' => { VR => 'SS', Name => 'EffectiveEchoSpacing' }, #4
    '0043,102D' => { VR => 'SH', Name => 'StringSlopField1' }, #4
    '0043,102E' => { VR => 'SH', Name => 'StringSlopField2' }, #4
    '0043,102F' => { VR => 'SS', Name => 'RawDataType' }, #4
    '0043,1030' => { VR => 'SS', Name => 'RawDataType' }, #4
    '0043,1031' => { VR => 'DS', Name => 'RACordOfTargetReconCenter' }, #4
    '0043,1032' => { VR => 'SS', Name => 'RawDataType' }, #4
    '0043,1033' => { VR => 'FL', Name => 'NegScanspacing' }, #4
    '0043,1034' => { VR => 'IS', Name => 'OffsetFrequency' }, #4
    '0043,1035' => { VR => 'UL', Name => 'UserUsageTag' }, #4
    '0043,1036' => { VR => 'UL', Name => 'UserFillMapMSW' }, #4
    '0043,1037' => { VR => 'UL', Name => 'UserFillMapLSW' }, #4
    '0043,1038' => { VR => 'FL', Name => 'User25-48' }, #4
    '0043,1039' => { VR => 'IS', Name => 'SlopInt6-9' }, #4
    '0043,1040' => { VR => 'FL', Name => 'TriggerOnPosition' }, #4
    '0043,1041' => { VR => 'FL', Name => 'DegreeOfRotation' }, #4
    '0043,1042' => { VR => 'SL', Name => 'DASTriggerSource' }, #4
    '0043,1043' => { VR => 'SL', Name => 'DASFpaGain' }, #4
    '0043,1044' => { VR => 'SL', Name => 'DASOutputSource' }, #4
    '0043,1045' => { VR => 'SL', Name => 'DASAdInput' }, #4
    '0043,1046' => { VR => 'SL', Name => 'DASCalMode' }, #4
    '0043,1047' => { VR => 'SL', Name => 'DASCalFrequency' }, #4
    '0043,1048' => { VR => 'SL', Name => 'DASRegXm' }, #4
    '0043,1049' => { VR => 'SL', Name => 'DASAutoZero' }, #4
    '0043,104A' => { VR => 'SS', Name => 'StartingChannelOfView' }, #4
    '0043,104B' => { VR => 'SL', Name => 'DASXmPattern' }, #4
    '0043,104C' => { VR => 'SS', Name => 'TGGCTriggerMode' }, #4
    '0043,104D' => { VR => 'FL', Name => 'StartScanToXrayOnDelay' }, #4
    '0043,104E' => { VR => 'FL', Name => 'DurationOfXrayOn' }, #4
    '0043,1060' => { VR => 'IS', Name => 'SlopInt10-17' }, #4
    '0043,1061' => { VR => 'UI', Name => 'ScannerStudyEntityUID' }, #4
    '0043,1062' => { VR => 'SH', Name => 'ScannerStudyID' }, #4
    '0043,106f' => { VR => 'DS', Name => 'ScannerTableEntry' }, #4
    '0045,1001' => { VR => 'LO', Name => 'NumberOfMacroRowsInDetector' }, #4
    '0045,1002' => { VR => 'FL', Name => 'MacroWidthAtISOCenter' }, #4
    '0045,1003' => { VR => 'SS', Name => 'DASType' }, #4
    '0045,1004' => { VR => 'SS', Name => 'DASGain' }, #4
    '0045,1005' => { VR => 'SS', Name => 'DASTemperature' }, #4
    '0045,1006' => { VR => 'CS', Name => 'TableDirectionInOrOut' }, #4
    '0045,1007' => { VR => 'FL', Name => 'ZSmoothingFactor' }, #4
    '0045,1008' => { VR => 'SS', Name => 'ViewWeightingMode' }, #4
    '0045,1009' => { VR => 'SS', Name => 'SigmaRowNumberWhichRowsWereUsed' }, #4
    '0045,100A' => { VR => 'FL', Name => 'MinimumDasValueFoundInTheScanData' }, #4
    '0045,100B' => { VR => 'FL', Name => 'MaximumOffsetShiftValueUsed' }, #4
    '0045,100C' => { VR => 'SS', Name => 'NumberOfViewsShifted' }, #4
    '0045,100D' => { VR => 'SS', Name => 'ZTrackingFlag' }, #4
    '0045,100E' => { VR => 'FL', Name => 'MeanZError' }, #4
    '0045,100F' => { VR => 'FL', Name => 'ZTrackingMaximumError' }, #4
    '0045,1010' => { VR => 'SS', Name => 'StartingViewForRow2a' }, #4
    '0045,1011' => { VR => 'SS', Name => 'NumberOfViewsInRow2a' }, #4
    '0045,1012' => { VR => 'SS', Name => 'StartingViewForRow1a' }, #4
    '0045,1013' => { VR => 'SS', Name => 'SigmaMode' }, #4
    '0045,1014' => { VR => 'SS', Name => 'NumberOfViewsInRow1a' }, #4
    '0045,1015' => { VR => 'SS', Name => 'StartingViewForRow2b' }, #4
    '0045,1016' => { VR => 'SS', Name => 'NumberOfViewsInRow2b' }, #4
    '0045,1017' => { VR => 'SS', Name => 'StartingViewForRow1b' }, #4
    '0045,1018' => { VR => 'SS', Name => 'NumberOfViewsInRow1b' }, #4
    '0045,1019' => { VR => 'SS', Name => 'AirFilterCalibrationDate' }, #4
    '0045,101A' => { VR => 'SS', Name => 'AirFilterCalibrationTime' }, #4
    '0045,101B' => { VR => 'SS', Name => 'PhantomCalibrationDate' }, #4
    '0045,101C' => { VR => 'SS', Name => 'PhantomCalibrationTime' }, #4
    '0045,101D' => { VR => 'SS', Name => 'ZSlopeCalibrationDate' }, #4
    '0045,101E' => { VR => 'SS', Name => 'ZSlopeCalibrationTime' }, #4
    '0045,101F' => { VR => 'SS', Name => 'CrosstalkCalibrationDate' }, #4
    '0045,1020' => { VR => 'SS', Name => 'CrosstalkCalibrationTime' }, #4
    '0045,1021' => { VR => 'SS', Name => 'IterboneOptionFlag' }, #4
    '0045,1022' => { VR => 'SS', Name => 'PeristalticFlagOption' }, #4
    # calibration group
    '0050,0004' => { VR => 'CS', Name => 'CalibrationImage' },
    '0050,0010' => { VR => 'SQ', Name => 'DeviceSequence' },
    '0050,0014' => { VR => 'DS', Name => 'DeviceLength' },
    '0050,0016' => { VR => 'DS', Name => 'DeviceDiameter' },
    '0050,0017' => { VR => 'CS', Name => 'DeviceDiameterUnits' },
    '0050,0018' => { VR => 'DS', Name => 'DeviceVolume' },
    '0050,0019' => { VR => 'DS', Name => 'InterMarkerDistance' },
    '0050,0020' => { VR => 'LO', Name => 'DeviceDescription' },
    # nuclear acquisition group
    '0054,0010' => { VR => 'US', Name => 'EnergyWindowVector' },
    '0054,0011' => { VR => 'US', Name => 'NumberOfEnergyWindows' },
    '0054,0012' => { VR => 'SQ', Name => 'EnergyWindowInformationSequence' },
    '0054,0013' => { VR => 'SQ', Name => 'EnergyWindowRangeSequence' },
    '0054,0014' => { VR => 'DS', Name => 'EnergyWindowLowerLimit' },
    '0054,0015' => { VR => 'DS', Name => 'EnergyWindowUpperLimit' },
    '0054,0016' => { VR => 'SQ', Name => 'RadiopharmaceuticalInformationSeq' },
    '0054,0017' => { VR => 'IS', Name => 'ResidualSyringeCounts' },
    '0054,0018' => { VR => 'SH', Name => 'EnergyWindowName' },
    '0054,0020' => { VR => 'US', Name => 'DetectorVector' },
    '0054,0021' => { VR => 'US', Name => 'NumberOfDetectors' },
    '0054,0022' => { VR => 'SQ', Name => 'DetectorInformationSequence' },
    '0054,0030' => { VR => 'US', Name => 'PhaseVector' },
    '0054,0031' => { VR => 'US', Name => 'NumberOfPhases' },
    '0054,0032' => { VR => 'SQ', Name => 'PhaseInformationSequence' },
    '0054,0033' => { VR => 'US', Name => 'NumberOfFramesInPhase' },
    '0054,0036' => { VR => 'IS', Name => 'PhaseDelay' },
    '0054,0038' => { VR => 'IS', Name => 'PauseBetweenFrames' },
    '0054,0039' => { VR => 'CS', Name => 'PhaseDescription' },
    '0054,0050' => { VR => 'US', Name => 'RotationVector' },
    '0054,0051' => { VR => 'US', Name => 'NumberOfRotations' },
    '0054,0052' => { VR => 'SQ', Name => 'RotationInformationSequence' },
    '0054,0053' => { VR => 'US', Name => 'NumberOfFramesInRotation' },
    '0054,0060' => { VR => 'US', Name => 'RRIntervalVector' },
    '0054,0061' => { VR => 'US', Name => 'NumberOfRRIntervals' },
    '0054,0062' => { VR => 'SQ', Name => 'GatedInformationSequence' },
    '0054,0063' => { VR => 'SQ', Name => 'DataInformationSequence' },
    '0054,0070' => { VR => 'US', Name => 'TimeSlotVector' },
    '0054,0071' => { VR => 'US', Name => 'NumberOfTimeSlots' },
    '0054,0072' => { VR => 'SQ', Name => 'TimeSlotInformationSequence' },
    '0054,0073' => { VR => 'DS', Name => 'TimeSlotTime' },
    '0054,0080' => { VR => 'US', Name => 'SliceVector' },
    '0054,0081' => { VR => 'US', Name => 'NumberOfSlices' },
    '0054,0090' => { VR => 'US', Name => 'AngularViewVector' },
    '0054,0100' => { VR => 'US', Name => 'TimeSliceVector' },
    '0054,0101' => { VR => 'US', Name => 'NumberOfTimeSlices' },
    '0054,0200' => { VR => 'DS', Name => 'StartAngle' },
    '0054,0202' => { VR => 'CS', Name => 'TypeOfDetectorMotion' },
    '0054,0210' => { VR => 'IS', Name => 'TriggerVector' },
    '0054,0211' => { VR => 'US', Name => 'NumberOfTriggersInPhase' },
    '0054,0220' => { VR => 'SQ', Name => 'ViewCodeSequence' },
    '0054,0222' => { VR => 'SQ', Name => 'ViewModifierCodeSequence' },
    '0054,0300' => { VR => 'SQ', Name => 'RadionuclideCodeSequence' },
    '0054,0302' => { VR => 'SQ', Name => 'AdministrationRouteCodeSequence' },
    '0054,0304' => { VR => 'SQ', Name => 'RadiopharmaceuticalCodeSequence' },
    '0054,0306' => { VR => 'SQ', Name => 'CalibrationDataSequence' },
    '0054,0308' => { VR => 'US', Name => 'EnergyWindowNumber' },
    '0054,0400' => { VR => 'SH', Name => 'ImageID' },
    '0054,0410' => { VR => 'SQ', Name => 'PatientOrientationCodeSequence' },
    '0054,0412' => { VR => 'SQ', Name => 'PatientOrientationModifierCodeSeq' },
    '0054,0414' => { VR => 'SQ', Name => 'PatientGantryRelationshipCodeSeq' },
    '0054,0500' => { VR => 'CS', Name => 'SliceProgressionDirection' },
    '0054,1000' => { VR => 'CS', Name => 'SeriesType' },
    '0054,1001' => { VR => 'CS', Name => 'Units' },
    '0054,1002' => { VR => 'CS', Name => 'CountsSource' },
    '0054,1004' => { VR => 'CS', Name => 'ReprojectionMethod' },
    '0054,1100' => { VR => 'CS', Name => 'RandomsCorrectionMethod' },
    '0054,1101' => { VR => 'LO', Name => 'AttenuationCorrectionMethod' },
    '0054,1102' => { VR => 'CS', Name => 'DecayCorrection' },
    '0054,1103' => { VR => 'LO', Name => 'ReconstructionMethod' },
    '0054,1104' => { VR => 'LO', Name => 'DetectorLinesOfResponseUsed' },
    '0054,1105' => { VR => 'LO', Name => 'ScatterCorrectionMethod' },
    '0054,1200' => { VR => 'DS', Name => 'AxialAcceptance' },
    '0054,1201' => { VR => 'IS', Name => 'AxialMash' },
    '0054,1202' => { VR => 'IS', Name => 'TransverseMash' },
    '0054,1203' => { VR => 'DS', Name => 'DetectorElementSize' },
    '0054,1210' => { VR => 'DS', Name => 'CoincidenceWindowWidth' },
    '0054,1220' => { VR => 'CS', Name => 'SecondaryCountsType' },
    '0054,1300' => { VR => 'DS', Name => 'FrameReferenceTime' },
    '0054,1310' => { VR => 'IS', Name => 'PrimaryCountsAccumulated' },
    '0054,1311' => { VR => 'IS', Name => 'SecondaryCountsAccumulated' },
    '0054,1320' => { VR => 'DS', Name => 'SliceSensitivityFactor' },
    '0054,1321' => { VR => 'DS', Name => 'DecayFactor' },
    '0054,1322' => { VR => 'DS', Name => 'DoseCalibrationFactor' },
    '0054,1323' => { VR => 'DS', Name => 'ScatterFractionFactor' },
    '0054,1324' => { VR => 'DS', Name => 'DeadTimeFactor' },
    '0054,1330' => { VR => 'US', Name => 'ImageIndex' },
    '0054,1400' => { VR => 'CS', Name => 'CountsIncluded' },
    '0054,1401' => { VR => 'CS', Name => 'DeadTimeCorrectionFlag' },
    '0060,3000' => { VR => 'SQ', Name => 'HistogramSequence' },
    '0060,3002' => { VR => 'US', Name => 'HistogramNumberOfBins' },
    '0060,3004' => { VR => 'SS', Name => 'HistogramFirstBinValue' },
    '0060,3006' => { VR => 'SS', Name => 'HistogramLastBinValue' },
    '0060,3008' => { VR => 'US', Name => 'HistogramBinWidth' },
    '0060,3010' => { VR => 'LO', Name => 'HistogramExplanation' },
    '0060,3020' => { VR => 'UL', Name => 'HistogramData' },
    '0070,0001' => { VR => 'SQ', Name => 'GraphicAnnotationSequence' },
    '0070,0002' => { VR => 'CS', Name => 'GraphicLayer' },
    '0070,0003' => { VR => 'CS', Name => 'BoundingBoxAnnotationUnits' },
    '0070,0004' => { VR => 'CS', Name => 'AnchorPointAnnotationUnits' },
    '0070,0005' => { VR => 'CS', Name => 'GraphicAnnotationUnits' },
    '0070,0006' => { VR => 'ST', Name => 'UnformattedTextValue' },
    '0070,0008' => { VR => 'SQ', Name => 'TextObjectSequence' },
    '0070,0009' => { VR => 'SQ', Name => 'GraphicObjectSequence' },
    '0070,0010' => { VR => 'FL', Name => 'BoundingBoxTopLeftHandCorner' },
    '0070,0011' => { VR => 'FL', Name => 'BoundingBoxBottomRightHandCorner' },
    '0070,0012' => { VR => 'CS', Name => 'BoundingBoxTextHorizJustification' },
    '0070,0014' => { VR => 'FL', Name => 'AnchorPoint' },
    '0070,0015' => { VR => 'CS', Name => 'AnchorPointVisibility' },
    '0070,0020' => { VR => 'US', Name => 'GraphicDimensions' },
    '0070,0021' => { VR => 'US', Name => 'NumberOfGraphicPoints' },
    '0070,0022' => { VR => 'FL', Name => 'GraphicData' },
    '0070,0023' => { VR => 'CS', Name => 'GraphicType' },
    '0070,0024' => { VR => 'CS', Name => 'GraphicFilled' },
    '0070,0041' => { VR => 'CS', Name => 'ImageHorizontalFlip' },
    '0070,0042' => { VR => 'US', Name => 'ImageRotation' },
    '0070,0052' => { VR => 'SL', Name => 'DisplayedAreaTopLeftHandCorner' },
    '0070,0053' => { VR => 'SL', Name => 'DisplayedAreaBottomRightHandCorner' },
    '0070,005A' => { VR => 'SQ', Name => 'DisplayedAreaSelectionSequence' },
    '0070,0060' => { VR => 'SQ', Name => 'GraphicLayerSequence' },
    '0070,0062' => { VR => 'IS', Name => 'GraphicLayerOrder' },
    '0070,0066' => { VR => 'US', Name => 'GraphicLayerRecDisplayGraysclValue' },
    '0070,0067' => { VR => 'US', Name => 'GraphicLayerRecDisplayRGBValue' },
    '0070,0068' => { VR => 'LO', Name => 'GraphicLayerDescription' },
    '0070,0080' => { VR => 'CS', Name => 'ContentLabel' },
    '0070,0081' => { VR => 'LO', Name => 'ContentDescription' },
    '0070,0082' => { VR => 'DA', Name => 'PresentationCreationDate' },
    '0070,0083' => { VR => 'TM', Name => 'PresentationCreationTime' },
    '0070,0084' => { VR => 'PN', Name => 'ContentCreatorsName' },
    '0070,0100' => { VR => 'CS', Name => 'PresentationSizeMode' },
    '0070,0101' => { VR => 'DS', Name => 'PresentationPixelSpacing' },
    '0070,0102' => { VR => 'IS', Name => 'PresentationPixelAspectRatio' },
    '0070,0103' => { VR => 'FL', Name => 'PresentationPixelMagRatio' },
    '0070,0306' => { VR => 'CS', Name => 'ShapeType' },
    '0070,0308' => { VR => 'SQ', Name => 'RegistrationSequence' },
    '0070,0309' => { VR => 'SQ', Name => 'MatrixRegistrationSequence' },
    '0070,030A' => { VR => 'SQ', Name => 'MatrixSequence' },
    '0070,030C' => { VR => 'CS', Name => 'FrameOfRefTransformationMatrixType' },
    '0070,030D' => { VR => 'SQ', Name => 'RegistrationTypeCodeSequence' },
    '0070,030F' => { VR => 'ST', Name => 'FiducialDescription' },
    '0070,0310' => { VR => 'SH', Name => 'FiducialIdentifier' },
    '0070,0311' => { VR => 'SQ', Name => 'FiducialIdentifierCodeSequence' },
    '0070,0312' => { VR => 'FD', Name => 'ContourUncertaintyRadius' },
    '0070,0314' => { VR => 'SQ', Name => 'UsedFiducialsSequence' },
    '0070,0318' => { VR => 'SQ', Name => 'GraphicCoordinatesDataSequence' },
    '0070,031A' => { VR => 'UI', Name => 'FiducialUID' },
    '0070,031C' => { VR => 'SQ', Name => 'FiducialSetSequence' },
    '0070,031E' => { VR => 'SQ', Name => 'FiducialSequence' },
    # storage group
    '0088,0130' => { VR => 'SH', Name => 'StorageMediaFileSetID' },
    '0088,0140' => { VR => 'UI', Name => 'StorageMediaFileSetUID' },
    '0088,0200' => { VR => 'SQ', Name => 'IconImageSequence' },
    '0088,0904' => { VR => 'LO', Name => 'TopicTitle' },
    '0088,0906' => { VR => 'ST', Name => 'TopicSubject' },
    '0088,0910' => { VR => 'LO', Name => 'TopicAuthor' },
    '0088,0912' => { VR => 'LO', Name => 'TopicKeyWords' },
    '0100,0410' => { VR => 'CS', Name => 'SOPInstanceStatus' },
    '0100,0420' => { VR => 'DT', Name => 'SOPAuthorizationDateAndTime' },
    '0100,0424' => { VR => 'LT', Name => 'SOPAuthorizationComment' },
    '0100,0426' => { VR => 'LO', Name => 'AuthorizationEquipmentCertNumber' },
    '0400,0005' => { VR => 'US', Name => 'MACIDNumber' },
    '0400,0010' => { VR => 'UI', Name => 'MACCalculationTransferSyntaxUID' },
    '0400,0015' => { VR => 'CS', Name => 'MACAlgorithm' },
    '0400,0020' => { VR => 'AT', Name => 'DataElementsSigned' },
    '0400,0100' => { VR => 'UI', Name => 'DigitalSignatureUID' },
    '0400,0105' => { VR => 'DT', Name => 'DigitalSignatureDateTime' },
    '0400,0110' => { VR => 'CS', Name => 'CertificateType' },
    '0400,0115' => { VR => 'OB', Name => 'CertificateOfSigner' },
    '0400,0120' => { VR => 'OB', Name => 'Signature' },
    '0400,0305' => { VR => 'CS', Name => 'CertifiedTimestampType' },
    '0400,0310' => { VR => 'OB', Name => 'CertifiedTimestamp' },
    '0400,0500' => { VR => 'SQ', Name => 'EncryptedAttributesSequence' },
    '0400,0510' => { VR => 'UI', Name => 'EncryptedContentTransferSyntaxUID' },
    '0400,0520' => { VR => 'OB', Name => 'EncryptedContent' },
    '0400,0550' => { VR => 'SQ', Name => 'ModifiedAttributesSequence' },
    '2000,0010' => { VR => 'IS', Name => 'NumberOfCopies' },
    '2000,001E' => { VR => 'SQ', Name => 'PrinterConfigurationSequence' },
    '2000,0020' => { VR => 'CS', Name => 'PrintPriority' },
    '2000,0030' => { VR => 'CS', Name => 'MediumType' },
    '2000,0040' => { VR => 'CS', Name => 'FilmDestination' },
    '2000,0050' => { VR => 'LO', Name => 'FilmSessionLabel' },
    '2000,0060' => { VR => 'IS', Name => 'MemoryAllocation' },
    '2000,0061' => { VR => 'IS', Name => 'MaximumMemoryAllocation' },
    '2000,0062' => { VR => 'CS', Name => 'ColorImagePrintingFlag' },
    '2000,0063' => { VR => 'CS', Name => 'CollationFlag' },
    '2000,0065' => { VR => 'CS', Name => 'AnnotationFlag' },
    '2000,0067' => { VR => 'CS', Name => 'ImageOverlayFlag' },
    '2000,0069' => { VR => 'CS', Name => 'PresentationLUTFlag' },
    '2000,006A' => { VR => 'CS', Name => 'ImageBoxPresentationLUTFlag' },
    '2000,00A0' => { VR => 'US', Name => 'MemoryBitDepth' },
    '2000,00A1' => { VR => 'US', Name => 'PrintingBitDepth' },
    '2000,00A2' => { VR => 'SQ', Name => 'MediaInstalledSequence' },
    '2000,00A4' => { VR => 'SQ', Name => 'OtherMediaAvailableSequence' },
    '2000,00A8' => { VR => 'SQ', Name => 'SupportedImageDisplayFormatSeq' },
    # film box group
    '2000,0500' => { VR => 'SQ', Name => 'ReferencedFilmBoxSequence' },
    '2000,0510' => { VR => 'SQ', Name => 'ReferencedStoredPrintSequence' },
    '2010,0010' => { VR => 'ST', Name => 'ImageDisplayFormat' },
    '2010,0030' => { VR => 'CS', Name => 'AnnotationDisplayFormatID' },
    '2010,0040' => { VR => 'CS', Name => 'FilmOrientation' },
    '2010,0050' => { VR => 'CS', Name => 'FilmSizeID' },
    '2010,0052' => { VR => 'CS', Name => 'PrinterResolutionID' },
    '2010,0054' => { VR => 'CS', Name => 'DefaultPrinterResolutionID' },
    '2010,0060' => { VR => 'CS', Name => 'MagnificationType' },
    '2010,0080' => { VR => 'CS', Name => 'SmoothingType' },
    '2010,00A6' => { VR => 'CS', Name => 'DefaultMagnificationType' },
    '2010,00A7' => { VR => 'CS', Name => 'OtherMagnificationTypesAvailable' },
    '2010,00A8' => { VR => 'CS', Name => 'DefaultSmoothingType' },
    '2010,00A9' => { VR => 'CS', Name => 'OtherSmoothingTypesAvailable' },
    '2010,0100' => { VR => 'CS', Name => 'BorderDensity' },
    '2010,0110' => { VR => 'CS', Name => 'EmptyImageDensity' },
    '2010,0120' => { VR => 'US', Name => 'MinDensity' },
    '2010,0130' => { VR => 'US', Name => 'MaxDensity' },
    '2010,0140' => { VR => 'CS', Name => 'Trim' },
    '2010,0150' => { VR => 'ST', Name => 'ConfigurationInformation' },
    '2010,0152' => { VR => 'LT', Name => 'ConfigurationInformationDescr' },
    '2010,0154' => { VR => 'IS', Name => 'MaximumCollatedFilms' },
    '2010,015E' => { VR => 'US', Name => 'Illumination' },
    '2010,0160' => { VR => 'US', Name => 'ReflectedAmbientLight' },
    '2010,0376' => { VR => 'DS', Name => 'PrinterPixelSpacing' },
    '2010,0500' => { VR => 'SQ', Name => 'ReferencedFilmSessionSequence' },
    '2010,0510' => { VR => 'SQ', Name => 'ReferencedImageBoxSequence' },
    '2010,0520' => { VR => 'SQ', Name => 'ReferencedBasicAnnotationBoxSeq' },
    # image box group
    '2020,0010' => { VR => 'US', Name => 'ImagePosition' },
    '2020,0020' => { VR => 'CS', Name => 'Polarity' },
    '2020,0030' => { VR => 'DS', Name => 'RequestedImageSize' },
    '2020,0040' => { VR => 'CS', Name => 'RequestedDecimate-CropBehavior' },
    '2020,0050' => { VR => 'CS', Name => 'RequestedResolutionID' },
    '2020,00A0' => { VR => 'CS', Name => 'RequestedImageSizeFlag' },
    '2020,00A2' => { VR => 'CS', Name => 'Decimate-CropResult' },
    '2020,0110' => { VR => 'SQ', Name => 'BasicGrayscaleImageSequence' },
    '2020,0111' => { VR => 'SQ', Name => 'BasicColorImageSequence' },
    '2020,0130' => { VR => 'RET',Name => 'ReferencedImageOverlayBoxSequence' },
    '2020,0140' => { VR => 'RET',Name => 'ReferencedVOILUTBoxSequence' },
    # annotation group
    '2030,0010' => { VR => 'US', Name => 'AnnotationPosition' },
    '2030,0020' => { VR => 'LO', Name => 'TextString' },
    # overlay box group
    '2040,0010' => { VR => 'SQ', Name => 'ReferencedOverlayPlaneSequence' },
    '2040,0011' => { VR => 'US', Name => 'ReferencedOverlayPlaneGroups' },
    '2040,0020' => { VR => 'SQ', Name => 'OverlayPixelDataSequence' },
    '2040,0060' => { VR => 'CS', Name => 'OverlayMagnificationType' },
    '2040,0070' => { VR => 'CS', Name => 'OverlaySmoothingType' },
    '2040,0072' => { VR => 'CS', Name => 'OverlayOrImageMagnification' },
    '2040,0074' => { VR => 'US', Name => 'MagnifyToNumberOfColumns' },
    '2040,0080' => { VR => 'CS', Name => 'OverlayForegroundDensity' },
    '2040,0082' => { VR => 'CS', Name => 'OverlayBackgroundDensity' },
    '2040,0090' => { VR => 'RET',Name => 'OverlayMode' },
    '2040,0100' => { VR => 'RET',Name => 'ThresholdDensity' },
    '2040,0500' => { VR => 'RET',Name => 'ReferencedImageBoxSequence' },
    '2050,0010' => { VR => 'SQ', Name => 'PresentationLUTSequence' },
    '2050,0020' => { VR => 'CS', Name => 'PresentationLUTShape' },
    '2050,0500' => { VR => 'SQ', Name => 'ReferencedPresentationLUTSequence' },
    '2100,0010' => { VR => 'SH', Name => 'PrintJobID' },
    '2100,0020' => { VR => 'CS', Name => 'ExecutionStatus' },
    '2100,0030' => { VR => 'CS', Name => 'ExecutionStatusInfo' },
    '2100,0040' => { VR => 'DA', Name => 'CreationDate' },
    '2100,0050' => { VR => 'TM', Name => 'CreationTime' },
    '2100,0070' => { VR => 'AE', Name => 'Originator' },
    '2100,0140' => { VR => 'AE', Name => 'Destination' },
    '2100,0160' => { VR => 'SH', Name => 'OwnerID' },
    '2100,0170' => { VR => 'IS', Name => 'NumberOfFilms' },
    '2100,0500' => { VR => 'SQ', Name => 'ReferencedPrintJobSequence' },
    # printer group
    '2110,0010' => { VR => 'CS', Name => 'PrinterStatus' },
    '2110,0020' => { VR => 'CS', Name => 'PrinterStatusInfo' },
    '2110,0030' => { VR => 'LO', Name => 'PrinterName' },
    '2110,0099' => { VR => 'SH', Name => 'PrintQueueID' },
    '2120,0010' => { VR => 'CS', Name => 'QueueStatus' },
    # print job group
    '2120,0050' => { VR => 'SQ', Name => 'PrintJobDescriptionSequence' },
    '2120,0070' => { VR => 'SQ', Name => 'ReferencedPrintJobSequence' },
    '2130,0010' => { VR => 'SQ', Name => 'PrintManagementCapabilitiesSeq' },
    '2130,0015' => { VR => 'SQ', Name => 'PrinterCharacteristicsSequence' },
    '2130,0030' => { VR => 'SQ', Name => 'FilmBoxContentSequence' },
    '2130,0040' => { VR => 'SQ', Name => 'ImageBoxContentSequence' },
    '2130,0050' => { VR => 'SQ', Name => 'AnnotationContentSequence' },
    '2130,0060' => { VR => 'SQ', Name => 'ImageOverlayBoxContentSequence' },
    '2130,0080' => { VR => 'SQ', Name => 'PresentationLUTContentSequence' },
    '2130,00A0' => { VR => 'SQ', Name => 'ProposedStudySequence' },
    '2130,00C0' => { VR => 'SQ', Name => 'OriginalImageSequence' },
    '2200,0001' => { VR => 'CS', Name => 'LabelFromInfoExtractedFromInstance' },
    '2200,0002' => { VR => 'UT', Name => 'LabelText' },
    '2200,0003' => { VR => 'CS', Name => 'LabelStyleSelection' },
    '2200,0004' => { VR => 'LT', Name => 'MediaDisposition' },
    '2200,0005' => { VR => 'LT', Name => 'BarcodeValue' },
    '2200,0006' => { VR => 'CS', Name => 'BarcodeSymbology' },
    '2200,0007' => { VR => 'CS', Name => 'AllowMediaSplitting' },
    '2200,0008' => { VR => 'CS', Name => 'IncludeNonDICOMObjects' },
    '2200,0009' => { VR => 'CS', Name => 'IncludeDisplayApplication' },
    '2200,000A' => { VR => 'CS', Name => 'SaveCompInstancesAfterMediaCreate' },
    '2200,000B' => { VR => 'US', Name => 'TotalNumberMediaPiecesCreated' },
    '2200,000C' => { VR => 'LO', Name => 'RequestedMediaApplicationProfile' },
    '2200,000D' => { VR => 'SQ', Name => 'ReferencedStorageMediaSequence' },
    '2200,000E' => { VR => 'AT', Name => 'FailureAttributes' },
    '2200,000F' => { VR => 'CS', Name => 'AllowLossyCompression' },
    '2200,0020' => { VR => 'CS', Name => 'RequestPriority' },
    '3002,0002' => { VR => 'SH', Name => 'RTImageLabel' },
    '3002,0003' => { VR => 'LO', Name => 'RTImageName' },
    '3002,0004' => { VR => 'ST', Name => 'RTImageDescription' },
    '3002,000A' => { VR => 'CS', Name => 'ReportedValuesOrigin' },
    '3002,000C' => { VR => 'CS', Name => 'RTImagePlane' },
    '3002,000D' => { VR => 'DS', Name => 'XRayImageReceptorTranslation' },
    '3002,000E' => { VR => 'DS', Name => 'XRayImageReceptorAngle' },
    '3002,0010' => { VR => 'DS', Name => 'RTImageOrientation' },
    '3002,0011' => { VR => 'DS', Name => 'ImagePlanePixelSpacing' },
    '3002,0012' => { VR => 'DS', Name => 'RTImagePosition' },
    '3002,0020' => { VR => 'SH', Name => 'RadiationMachineName' },
    '3002,0022' => { VR => 'DS', Name => 'RadiationMachineSAD' },
    '3002,0024' => { VR => 'DS', Name => 'RadiationMachineSSD' },
    '3002,0026' => { VR => 'DS', Name => 'RTImageSID' },
    '3002,0028' => { VR => 'DS', Name => 'SourceToReferenceObjectDistance' },
    '3002,0029' => { VR => 'IS', Name => 'FractionNumber' },
    '3002,0030' => { VR => 'SQ', Name => 'ExposureSequence' },
    '3002,0032' => { VR => 'DS', Name => 'MetersetExposure' },
    '3002,0034' => { VR => 'DS', Name => 'DiaphragmPosition' },
    '3002,0040' => { VR => 'SQ', Name => 'FluenceMapSequence' },
    '3002,0041' => { VR => 'CS', Name => 'FluenceDataSource' },
    '3002,0042' => { VR => 'DS', Name => 'FluenceDataScale' },
    '3004,0001' => { VR => 'CS', Name => 'DVHType' },
    '3004,0002' => { VR => 'CS', Name => 'DoseUnits' },
    '3004,0004' => { VR => 'CS', Name => 'DoseType' },
    '3004,0006' => { VR => 'LO', Name => 'DoseComment' },
    '3004,0008' => { VR => 'DS', Name => 'NormalizationPoint' },
    '3004,000A' => { VR => 'CS', Name => 'DoseSummationType' },
    '3004,000C' => { VR => 'DS', Name => 'GridFrameOffsetVector' },
    '3004,000E' => { VR => 'DS', Name => 'DoseGridScaling' },
    '3004,0010' => { VR => 'SQ', Name => 'RTDoseROISequence' },
    '3004,0012' => { VR => 'DS', Name => 'DoseValue' },
    '3004,0014' => { VR => 'CS', Name => 'TissueHeterogeneityCorrection' },
    '3004,0040' => { VR => 'DS', Name => 'DVHNormalizationPoint' },
    '3004,0042' => { VR => 'DS', Name => 'DVHNormalizationDoseValue' },
    '3004,0050' => { VR => 'SQ', Name => 'DVHSequence' },
    '3004,0052' => { VR => 'DS', Name => 'DVHDoseScaling' },
    '3004,0054' => { VR => 'CS', Name => 'DVHVolumeUnits' },
    '3004,0056' => { VR => 'IS', Name => 'DVHNumberOfBins' },
    '3004,0058' => { VR => 'DS', Name => 'DVHData' },
    '3004,0060' => { VR => 'SQ', Name => 'DVHReferencedROISequence' },
    '3004,0062' => { VR => 'CS', Name => 'DVHROIContributionType' },
    '3004,0070' => { VR => 'DS', Name => 'DVHMinimumDose' },
    '3004,0072' => { VR => 'DS', Name => 'DVHMaximumDose' },
    '3004,0074' => { VR => 'DS', Name => 'DVHMeanDose' },
    '3006,0002' => { VR => 'SH', Name => 'StructureSetLabel' },
    '3006,0004' => { VR => 'LO', Name => 'StructureSetName' },
    '3006,0006' => { VR => 'ST', Name => 'StructureSetDescription' },
    '3006,0008' => { VR => 'DA', Name => 'StructureSetDate' },
    '3006,0009' => { VR => 'TM', Name => 'StructureSetTime' },
    '3006,0010' => { VR => 'SQ', Name => 'ReferencedFrameOfReferenceSequence' },
    '3006,0012' => { VR => 'SQ', Name => 'RTReferencedStudySequence' },
    '3006,0014' => { VR => 'SQ', Name => 'RTReferencedSeriesSequence' },
    '3006,0016' => { VR => 'SQ', Name => 'ContourImageSequence' },
    '3006,0020' => { VR => 'SQ', Name => 'StructureSetROISequence' },
    '3006,0022' => { VR => 'IS', Name => 'ROINumber' },
    '3006,0024' => { VR => 'UI', Name => 'ReferencedFrameOfReferenceUID' },
    '3006,0026' => { VR => 'LO', Name => 'ROIName' },
    '3006,0028' => { VR => 'ST', Name => 'ROIDescription' },
    '3006,002A' => { VR => 'IS', Name => 'ROIDisplayColor' },
    '3006,002C' => { VR => 'DS', Name => 'ROIVolume' },
    '3006,0030' => { VR => 'SQ', Name => 'RTRelatedROISequence' },
    '3006,0033' => { VR => 'CS', Name => 'RTROIRelationship' },
    '3006,0036' => { VR => 'CS', Name => 'ROIGenerationAlgorithm' },
    '3006,0038' => { VR => 'LO', Name => 'ROIGenerationDescription' },
    '3006,0039' => { VR => 'SQ', Name => 'ROIContourSequence' },
    '3006,0040' => { VR => 'SQ', Name => 'ContourSequence' },
    '3006,0042' => { VR => 'CS', Name => 'ContourGeometricType' },
    '3006,0044' => { VR => 'DS', Name => 'ContourSlabThickness' },
    '3006,0045' => { VR => 'DS', Name => 'ContourOffsetVector' },
    '3006,0046' => { VR => 'IS', Name => 'NumberOfContourPoints' },
    '3006,0048' => { VR => 'IS', Name => 'ContourNumber' },
    '3006,0049' => { VR => 'IS', Name => 'AttachedContours' },
    '3006,0050' => { VR => 'DS', Name => 'ContourData' },
    '3006,0080' => { VR => 'SQ', Name => 'RTROIObservationsSequence' },
    '3006,0082' => { VR => 'IS', Name => 'ObservationNumber' },
    '3006,0084' => { VR => 'IS', Name => 'ReferencedROINumber' },
    '3006,0085' => { VR => 'SH', Name => 'ROIObservationLabel' },
    '3006,0086' => { VR => 'SQ', Name => 'RTROIIdentificationCodeSequence' },
    '3006,0088' => { VR => 'ST', Name => 'ROIObservationDescription' },
    '3006,00A0' => { VR => 'SQ', Name => 'RelatedRTROIObservationsSequence' },
    '3006,00A4' => { VR => 'CS', Name => 'RTROIInterpretedType' },
    '3006,00A6' => { VR => 'PN', Name => 'ROIInterpreter' },
    '3006,00B0' => { VR => 'SQ', Name => 'ROIPhysicalPropertiesSequence' },
    '3006,00B2' => { VR => 'CS', Name => 'ROIPhysicalProperty' },
    '3006,00B4' => { VR => 'DS', Name => 'ROIPhysicalPropertyValue' },
    '3006,00C0' => { VR => 'SQ', Name => 'FrameOfReferenceRelationshipSeq' },
    '3006,00C2' => { VR => 'UI', Name => 'RelatedFrameOfReferenceUID' },
    '3006,00C4' => { VR => 'CS', Name => 'FrameOfReferenceTransformType' },
    '3006,00C6' => { VR => 'DS', Name => 'FrameOfReferenceTransformMatrix' },
    '3006,00C8' => { VR => 'LO', Name => 'FrameOfReferenceTransformComment' },
    '3008,0010' => { VR => 'SQ', Name => 'MeasuredDoseReferenceSequence' },
    '3008,0012' => { VR => 'ST', Name => 'MeasuredDoseDescription' },
    '3008,0014' => { VR => 'CS', Name => 'MeasuredDoseType' },
    '3008,0016' => { VR => 'DS', Name => 'MeasuredDoseValue' },
    '3008,0020' => { VR => 'SQ', Name => 'TreatmentSessionBeamSequence' },
    '3008,0022' => { VR => 'IS', Name => 'CurrentFractionNumber' },
    '3008,0024' => { VR => 'DA', Name => 'TreatmentControlPointDate' },
    '3008,0025' => { VR => 'TM', Name => 'TreatmentControlPointTime' },
    '3008,002A' => { VR => 'CS', Name => 'TreatmentTerminationStatus' },
    '3008,002B' => { VR => 'SH', Name => 'TreatmentTerminationCode' },
    '3008,002C' => { VR => 'CS', Name => 'TreatmentVerificationStatus' },
    '3008,0030' => { VR => 'SQ', Name => 'ReferencedTreatmentRecordSequence' },
    '3008,0032' => { VR => 'DS', Name => 'SpecifiedPrimaryMeterset' },
    '3008,0033' => { VR => 'DS', Name => 'SpecifiedSecondaryMeterset' },
    '3008,0036' => { VR => 'DS', Name => 'DeliveredPrimaryMeterset' },
    '3008,0037' => { VR => 'DS', Name => 'DeliveredSecondaryMeterset' },
    '3008,003A' => { VR => 'DS', Name => 'SpecifiedTreatmentTime' },
    '3008,003B' => { VR => 'DS', Name => 'DeliveredTreatmentTime' },
    '3008,0040' => { VR => 'SQ', Name => 'ControlPointDeliverySequence' },
    '3008,0042' => { VR => 'DS', Name => 'SpecifiedMeterset' },
    '3008,0044' => { VR => 'DS', Name => 'DeliveredMeterset' },
    '3008,0048' => { VR => 'DS', Name => 'DoseRateDelivered' },
    '3008,0050' => { VR => 'SQ', Name => 'TreatmentSummaryCalcDoseRefSeq' },
    '3008,0052' => { VR => 'DS', Name => 'CumulativeDoseToDoseReference' },
    '3008,0054' => { VR => 'DA', Name => 'FirstTreatmentDate' },
    '3008,0056' => { VR => 'DA', Name => 'MostRecentTreatmentDate' },
    '3008,005A' => { VR => 'IS', Name => 'NumberOfFractionsDelivered' },
    '3008,0060' => { VR => 'SQ', Name => 'OverrideSequence' },
    '3008,0062' => { VR => 'AT', Name => 'OverrideParameterPointer' },
    '3008,0064' => { VR => 'IS', Name => 'MeasuredDoseReferenceNumber' },
    '3008,0066' => { VR => 'ST', Name => 'OverrideReason' },
    '3008,0070' => { VR => 'SQ', Name => 'CalculatedDoseReferenceSequence' },
    '3008,0072' => { VR => 'IS', Name => 'CalculatedDoseReferenceNumber' },
    '3008,0074' => { VR => 'ST', Name => 'CalculatedDoseReferenceDescription' },
    '3008,0076' => { VR => 'DS', Name => 'CalculatedDoseReferenceDoseValue' },
    '3008,0078' => { VR => 'DS', Name => 'StartMeterset' },
    '3008,007A' => { VR => 'DS', Name => 'EndMeterset' },
    '3008,0080' => { VR => 'SQ', Name => 'ReferencedMeasuredDoseReferenceSeq' },
    '3008,0082' => { VR => 'IS', Name => 'ReferencedMeasuredDoseReferenceNum' },
    '3008,0090' => { VR => 'SQ', Name => 'ReferencedCalculatedDoseRefSeq' },
    '3008,0092' => { VR => 'IS', Name => 'ReferencedCalculatedDoseRefNumber' },
    '3008,00A0' => { VR => 'SQ', Name => 'BeamLimitingDeviceLeafPairsSeq' },
    '3008,00B0' => { VR => 'SQ', Name => 'RecordedWedgeSequence' },
    '3008,00C0' => { VR => 'SQ', Name => 'RecordedCompensatorSequence' },
    '3008,00D0' => { VR => 'SQ', Name => 'RecordedBlockSequence' },
    '3008,00E0' => { VR => 'SQ', Name => 'TreatmentSummaryMeasuredDoseRefSeq' },
    '3008,0100' => { VR => 'SQ', Name => 'RecordedSourceSequence' },
    '3008,0105' => { VR => 'LO', Name => 'SourceSerialNumber' },
    '3008,0110' => { VR => 'SQ', Name => 'TreatmentSessionAppSetupSeq' },
    '3008,0116' => { VR => 'CS', Name => 'ApplicationSetupCheck' },
    '3008,0120' => { VR => 'SQ', Name => 'RecordedBrachyAccessoryDeviceSeq' },
    '3008,0122' => { VR => 'IS', Name => 'ReferencedBrachyAccessoryDeviceNum' },
    '3008,0130' => { VR => 'SQ', Name => 'RecordedChannelSequence' },
    '3008,0132' => { VR => 'DS', Name => 'SpecifiedChannelTotalTime' },
    '3008,0134' => { VR => 'DS', Name => 'DeliveredChannelTotalTime' },
    '3008,0136' => { VR => 'IS', Name => 'SpecifiedNumberOfPulses' },
    '3008,0138' => { VR => 'IS', Name => 'DeliveredNumberOfPulses' },
    '3008,013A' => { VR => 'DS', Name => 'SpecifiedPulseRepetitionInterval' },
    '3008,013C' => { VR => 'DS', Name => 'DeliveredPulseRepetitionInterval' },
    '3008,0140' => { VR => 'SQ', Name => 'RecordedSourceApplicatorSequence' },
    '3008,0142' => { VR => 'IS', Name => 'ReferencedSourceApplicatorNumber' },
    '3008,0150' => { VR => 'SQ', Name => 'RecordedChannelShieldSequence' },
    '3008,0152' => { VR => 'IS', Name => 'ReferencedChannelShieldNumber' },
    '3008,0160' => { VR => 'SQ', Name => 'BrachyControlPointDeliveredSeq' },
    '3008,0162' => { VR => 'DA', Name => 'SafePositionExitDate' },
    '3008,0164' => { VR => 'TM', Name => 'SafePositionExitTime' },
    '3008,0166' => { VR => 'DA', Name => 'SafePositionReturnDate' },
    '3008,0168' => { VR => 'TM', Name => 'SafePositionReturnTime' },
    '3008,0200' => { VR => 'CS', Name => 'CurrentTreatmentStatus' },
    '3008,0202' => { VR => 'ST', Name => 'TreatmentStatusComment' },
    '3008,0220' => { VR => 'SQ', Name => 'FractionGroupSummarySequence' },
    '3008,0223' => { VR => 'IS', Name => 'ReferencedFractionNumber' },
    '3008,0224' => { VR => 'CS', Name => 'FractionGroupType' },
    '3008,0230' => { VR => 'CS', Name => 'BeamStopperPosition' },
    '3008,0240' => { VR => 'SQ', Name => 'FractionStatusSummarySequence' },
    '3008,0250' => { VR => 'DA', Name => 'TreatmentDate' },
    '3008,0251' => { VR => 'TM', Name => 'TreatmentTime' },
    '300A,0002' => { VR => 'SH', Name => 'RTPlanLabel' },
    '300A,0003' => { VR => 'LO', Name => 'RTPlanName' },
    '300A,0004' => { VR => 'ST', Name => 'RTPlanDescription' },
    '300A,0006' => { VR => 'DA', Name => 'RTPlanDate' },
    '300A,0007' => { VR => 'TM', Name => 'RTPlanTime' },
    '300A,0009' => { VR => 'LO', Name => 'TreatmentProtocols' },
    '300A,000A' => { VR => 'CS', Name => 'TreatmentIntent' },
    '300A,000B' => { VR => 'LO', Name => 'TreatmentSites' },
    '300A,000C' => { VR => 'CS', Name => 'RTPlanGeometry' },
    '300A,000E' => { VR => 'ST', Name => 'PrescriptionDescription' },
    '300A,0010' => { VR => 'SQ', Name => 'DoseReferenceSequence' },
    '300A,0012' => { VR => 'IS', Name => 'DoseReferenceNumber' },
    '300A,0013' => { VR => 'UI', Name => 'DoseReferenceUID' },
    '300A,0014' => { VR => 'CS', Name => 'DoseReferenceStructureType' },
    '300A,0015' => { VR => 'CS', Name => 'NominalBeamEnergyUnit' },
    '300A,0016' => { VR => 'LO', Name => 'DoseReferenceDescription' },
    '300A,0018' => { VR => 'DS', Name => 'DoseReferencePointCoordinates' },
    '300A,001A' => { VR => 'DS', Name => 'NominalPriorDose' },
    '300A,0020' => { VR => 'CS', Name => 'DoseReferenceType' },
    '300A,0021' => { VR => 'DS', Name => 'ConstraintWeight' },
    '300A,0022' => { VR => 'DS', Name => 'DeliveryWarningDose' },
    '300A,0023' => { VR => 'DS', Name => 'DeliveryMaximumDose' },
    '300A,0025' => { VR => 'DS', Name => 'TargetMinimumDose' },
    '300A,0026' => { VR => 'DS', Name => 'TargetPrescriptionDose' },
    '300A,0027' => { VR => 'DS', Name => 'TargetMaximumDose' },
    '300A,0028' => { VR => 'DS', Name => 'TargetUnderdoseVolumeFraction' },
    '300A,002A' => { VR => 'DS', Name => 'OrganAtRiskFullVolumeDose' },
    '300A,002B' => { VR => 'DS', Name => 'OrganAtRiskLimitDose' },
    '300A,002C' => { VR => 'DS', Name => 'OrganAtRiskMaximumDose' },
    '300A,002D' => { VR => 'DS', Name => 'OrganAtRiskOverdoseVolumeFraction' },
    '300A,0040' => { VR => 'SQ', Name => 'ToleranceTableSequence' },
    '300A,0042' => { VR => 'IS', Name => 'ToleranceTableNumber' },
    '300A,0043' => { VR => 'SH', Name => 'ToleranceTableLabel' },
    '300A,0044' => { VR => 'DS', Name => 'GantryAngleTolerance' },
    '300A,0046' => { VR => 'DS', Name => 'BeamLimitingDeviceAngleTolerance' },
    '300A,0048' => { VR => 'SQ', Name => 'BeamLimitingDeviceToleranceSeq' },
    '300A,004A' => { VR => 'DS', Name => 'BeamLimitingDevicePositionTol' },
    '300A,004C' => { VR => 'DS', Name => 'PatientSupportAngleTolerance' },
    '300A,004E' => { VR => 'DS', Name => 'TableTopEccentricAngleTolerance' },
    '300A,0051' => { VR => 'DS', Name => 'TableTopVerticalPositionTolerance' },
    '300A,0052' => { VR => 'DS', Name => 'TableTopLongitudinalPositionTol' },
    '300A,0053' => { VR => 'DS', Name => 'TableTopLateralPositionTolerance' },
    '300A,0055' => { VR => 'CS', Name => 'RTPlanRelationship' },
    '300A,0070' => { VR => 'SQ', Name => 'FractionGroupSequence' },
    '300A,0071' => { VR => 'IS', Name => 'FractionGroupNumber' },
    '300A,0072' => { VR => 'LO', Name => 'FractionGroupDescription' },
    '300A,0078' => { VR => 'IS', Name => 'NumberOfFractionsPlanned' },
    '300A,0079' => { VR => 'IS', Name => 'NumberFractionPatternDigitsPerDay' },
    '300A,007A' => { VR => 'IS', Name => 'RepeatFractionCycleLength' },
    '300A,007B' => { VR => 'LT', Name => 'FractionPattern' },
    '300A,0080' => { VR => 'IS', Name => 'NumberOfBeams' },
    '300A,0082' => { VR => 'DS', Name => 'BeamDoseSpecificationPoint' },
    '300A,0084' => { VR => 'DS', Name => 'BeamDose' },
    '300A,0086' => { VR => 'DS', Name => 'BeamMeterset' },
    '300A,00A0' => { VR => 'IS', Name => 'NumberOfBrachyApplicationSetups' },
    '300A,00A2' => { VR => 'DS', Name => 'BrachyAppSetupDoseSpecPoint' },
    '300A,00A4' => { VR => 'DS', Name => 'BrachyApplicationSetupDose' },
    '300A,00B0' => { VR => 'SQ', Name => 'BeamSequence' },
    '300A,00B2' => { VR => 'SH', Name => 'TreatmentMachineName' },
    '300A,00B3' => { VR => 'CS', Name => 'PrimaryDosimeterUnit' },
    '300A,00B4' => { VR => 'DS', Name => 'SourceAxisDistance' },
    '300A,00B6' => { VR => 'SQ', Name => 'BeamLimitingDeviceSequence' },
    '300A,00B8' => { VR => 'CS', Name => 'RTBeamLimitingDeviceType' },
    '300A,00BA' => { VR => 'DS', Name => 'SourceToBeamLimitingDeviceDistance' },
    '300A,00BC' => { VR => 'IS', Name => 'NumberOfLeaf-JawPairs' },
    '300A,00BE' => { VR => 'DS', Name => 'LeafPositionBoundaries' },
    '300A,00C0' => { VR => 'IS', Name => 'BeamNumber' },
    '300A,00C2' => { VR => 'LO', Name => 'BeamName' },
    '300A,00C3' => { VR => 'ST', Name => 'BeamDescription' },
    '300A,00C4' => { VR => 'CS', Name => 'BeamType' },
    '300A,00C6' => { VR => 'CS', Name => 'RadiationType' },
    '300A,00C7' => { VR => 'CS', Name => 'HighDoseTechniqueType' },
    '300A,00C8' => { VR => 'IS', Name => 'ReferenceImageNumber' },
    '300A,00CA' => { VR => 'SQ', Name => 'PlannedVerificationImageSequence' },
    '300A,00CC' => { VR => 'LO', Name => 'ImagingDeviceSpecificAcqParams' },
    '300A,00CE' => { VR => 'CS', Name => 'TreatmentDeliveryType' },
    '300A,00D0' => { VR => 'IS', Name => 'NumberOfWedges' },
    '300A,00D1' => { VR => 'SQ', Name => 'WedgeSequence' },
    '300A,00D2' => { VR => 'IS', Name => 'WedgeNumber' },
    '300A,00D3' => { VR => 'CS', Name => 'WedgeType' },
    '300A,00D4' => { VR => 'SH', Name => 'WedgeID' },
    '300A,00D5' => { VR => 'IS', Name => 'WedgeAngle' },
    '300A,00D6' => { VR => 'DS', Name => 'WedgeFactor' },
    '300A,00D8' => { VR => 'DS', Name => 'WedgeOrientation' },
    '300A,00DA' => { VR => 'DS', Name => 'SourceToWedgeTrayDistance' },
    '300A,00E0' => { VR => 'IS', Name => 'NumberOfCompensators' },
    '300A,00E1' => { VR => 'SH', Name => 'MaterialID' },
    '300A,00E2' => { VR => 'DS', Name => 'TotalCompensatorTrayFactor' },
    '300A,00E3' => { VR => 'SQ', Name => 'CompensatorSequence' },
    '300A,00E4' => { VR => 'IS', Name => 'CompensatorNumber' },
    '300A,00E5' => { VR => 'SH', Name => 'CompensatorID' },
    '300A,00E6' => { VR => 'DS', Name => 'SourceToCompensatorTrayDistance' },
    '300A,00E7' => { VR => 'IS', Name => 'CompensatorRows' },
    '300A,00E8' => { VR => 'IS', Name => 'CompensatorColumns' },
    '300A,00E9' => { VR => 'DS', Name => 'CompensatorPixelSpacing' },
    '300A,00EA' => { VR => 'DS', Name => 'CompensatorPosition' },
    '300A,00EB' => { VR => 'DS', Name => 'CompensatorTransmissionData' },
    '300A,00EC' => { VR => 'DS', Name => 'CompensatorThicknessData' },
    '300A,00ED' => { VR => 'IS', Name => 'NumberOfBoli' },
    '300A,00EE' => { VR => 'CS', Name => 'CompensatorType' },
    '300A,00F0' => { VR => 'IS', Name => 'NumberOfBlocks' },
    '300A,00F2' => { VR => 'DS', Name => 'TotalBlockTrayFactor' },
    '300A,00F4' => { VR => 'SQ', Name => 'BlockSequence' },
    '300A,00F5' => { VR => 'SH', Name => 'BlockTrayID' },
    '300A,00F6' => { VR => 'DS', Name => 'SourceToBlockTrayDistance' },
    '300A,00F8' => { VR => 'CS', Name => 'BlockType' },
    '300A,00F9' => { VR => 'LO', Name => 'AccessoryCode' },
    '300A,00FA' => { VR => 'CS', Name => 'BlockDivergence' },
    '300A,00FB' => { VR => 'CS', Name => 'BlockMountingPosition' },
    '300A,00FC' => { VR => 'IS', Name => 'BlockNumber' },
    '300A,00FE' => { VR => 'LO', Name => 'BlockName' },
    '300A,0100' => { VR => 'DS', Name => 'BlockThickness' },
    '300A,0102' => { VR => 'DS', Name => 'BlockTransmission' },
    '300A,0104' => { VR => 'IS', Name => 'BlockNumberOfPoints' },
    '300A,0106' => { VR => 'DS', Name => 'BlockData' },
    '300A,0107' => { VR => 'SQ', Name => 'ApplicatorSequence' },
    '300A,0108' => { VR => 'SH', Name => 'ApplicatorID' },
    '300A,0109' => { VR => 'CS', Name => 'ApplicatorType' },
    '300A,010A' => { VR => 'LO', Name => 'ApplicatorDescription' },
    '300A,010C' => { VR => 'DS', Name => 'CumulativeDoseReferenceCoefficient' },
    '300A,010E' => { VR => 'DS', Name => 'FinalCumulativeMetersetWeight' },
    '300A,0110' => { VR => 'IS', Name => 'NumberOfControlPoints' },
    '300A,0111' => { VR => 'SQ', Name => 'ControlPointSequence' },
    '300A,0112' => { VR => 'IS', Name => 'ControlPointIndex' },
    '300A,0114' => { VR => 'DS', Name => 'NominalBeamEnergy' },
    '300A,0115' => { VR => 'DS', Name => 'DoseRateSet' },
    '300A,0116' => { VR => 'SQ', Name => 'WedgePositionSequence' },
    '300A,0118' => { VR => 'CS', Name => 'WedgePosition' },
    '300A,011A' => { VR => 'SQ', Name => 'BeamLimitingDevicePositionSequence' },
    '300A,011C' => { VR => 'DS', Name => 'Leaf-JawPositions' },
    '300A,011E' => { VR => 'DS', Name => 'GantryAngle' },
    '300A,011F' => { VR => 'CS', Name => 'GantryRotationDirection' },
    '300A,0120' => { VR => 'DS', Name => 'BeamLimitingDeviceAngle' },
    '300A,0121' => { VR => 'CS', Name => 'BeamLimitingDeviceRotateDirection' },
    '300A,0122' => { VR => 'DS', Name => 'PatientSupportAngle' },
    '300A,0123' => { VR => 'CS', Name => 'PatientSupportRotationDirection' },
    '300A,0124' => { VR => 'DS', Name => 'TableTopEccentricAxisDistance' },
    '300A,0125' => { VR => 'DS', Name => 'TableTopEccentricAngle' },
    '300A,0126' => { VR => 'CS', Name => 'TableTopEccentricRotateDirection' },
    '300A,0128' => { VR => 'DS', Name => 'TableTopVerticalPosition' },
    '300A,0129' => { VR => 'DS', Name => 'TableTopLongitudinalPosition' },
    '300A,012A' => { VR => 'DS', Name => 'TableTopLateralPosition' },
    '300A,012C' => { VR => 'DS', Name => 'IsocenterPosition' },
    '300A,012E' => { VR => 'DS', Name => 'SurfaceEntryPoint' },
    '300A,0130' => { VR => 'DS', Name => 'SourceToSurfaceDistance' },
    '300A,0134' => { VR => 'DS', Name => 'CumulativeMetersetWeight' },
    '300A,0180' => { VR => 'SQ', Name => 'PatientSetupSequence' },
    '300A,0182' => { VR => 'IS', Name => 'PatientSetupNumber' },
    '300A,0184' => { VR => 'LO', Name => 'PatientAdditionalPosition' },
    '300A,0190' => { VR => 'SQ', Name => 'FixationDeviceSequence' },
    '300A,0192' => { VR => 'CS', Name => 'FixationDeviceType' },
    '300A,0194' => { VR => 'SH', Name => 'FixationDeviceLabel' },
    '300A,0196' => { VR => 'ST', Name => 'FixationDeviceDescription' },
    '300A,0198' => { VR => 'SH', Name => 'FixationDevicePosition' },
    '300A,01A0' => { VR => 'SQ', Name => 'ShieldingDeviceSequence' },
    '300A,01A2' => { VR => 'CS', Name => 'ShieldingDeviceType' },
    '300A,01A4' => { VR => 'SH', Name => 'ShieldingDeviceLabel' },
    '300A,01A6' => { VR => 'ST', Name => 'ShieldingDeviceDescription' },
    '300A,01A8' => { VR => 'SH', Name => 'ShieldingDevicePosition' },
    '300A,01B0' => { VR => 'CS', Name => 'SetupTechnique' },
    '300A,01B2' => { VR => 'ST', Name => 'SetupTechniqueDescription' },
    '300A,01B4' => { VR => 'SQ', Name => 'SetupDeviceSequence' },
    '300A,01B6' => { VR => 'CS', Name => 'SetupDeviceType' },
    '300A,01B8' => { VR => 'SH', Name => 'SetupDeviceLabel' },
    '300A,01BA' => { VR => 'ST', Name => 'SetupDeviceDescription' },
    '300A,01BC' => { VR => 'DS', Name => 'SetupDeviceParameter' },
    '300A,01D0' => { VR => 'ST', Name => 'SetupReferenceDescription' },
    '300A,01D2' => { VR => 'DS', Name => 'TableTopVerticalSetupDisplacement' },
    '300A,01D4' => { VR => 'DS', Name => 'TableTopLongitudinalSetupDisplace' },
    '300A,01D6' => { VR => 'DS', Name => 'TableTopLateralSetupDisplacement' },
    '300A,0200' => { VR => 'CS', Name => 'BrachyTreatmentTechnique' },
    '300A,0202' => { VR => 'CS', Name => 'BrachyTreatmentType' },
    '300A,0206' => { VR => 'SQ', Name => 'TreatmentMachineSequence' },
    '300A,0210' => { VR => 'SQ', Name => 'SourceSequence' },
    '300A,0212' => { VR => 'IS', Name => 'SourceNumber' },
    '300A,0214' => { VR => 'CS', Name => 'SourceType' },
    '300A,0216' => { VR => 'LO', Name => 'SourceManufacturer' },
    '300A,0218' => { VR => 'DS', Name => 'ActiveSourceDiameter' },
    '300A,021A' => { VR => 'DS', Name => 'ActiveSourceLength' },
    '300A,0222' => { VR => 'DS', Name => 'SourceEncapsulationNomThickness' },
    '300A,0224' => { VR => 'DS', Name => 'SourceEncapsulationNomTransmission' },
    '300A,0226' => { VR => 'LO', Name => 'SourceIsotopeName' },
    '300A,0228' => { VR => 'DS', Name => 'SourceIsotopeHalfLife' },
    '300A,022A' => { VR => 'DS', Name => 'ReferenceAirKermaRate' },
    '300A,022C' => { VR => 'DA', Name => 'AirKermaRateReferenceDate' },
    '300A,022E' => { VR => 'TM', Name => 'AirKermaRateReferenceTime' },
    '300A,0230' => { VR => 'SQ', Name => 'ApplicationSetupSequence' },
    '300A,0232' => { VR => 'CS', Name => 'ApplicationSetupType' },
    '300A,0234' => { VR => 'IS', Name => 'ApplicationSetupNumber' },
    '300A,0236' => { VR => 'LO', Name => 'ApplicationSetupName' },
    '300A,0238' => { VR => 'LO', Name => 'ApplicationSetupManufacturer' },
    '300A,0240' => { VR => 'IS', Name => 'TemplateNumber' },
    '300A,0242' => { VR => 'SH', Name => 'TemplateType' },
    '300A,0244' => { VR => 'LO', Name => 'TemplateName' },
    '300A,0250' => { VR => 'DS', Name => 'TotalReferenceAirKerma' },
    '300A,0260' => { VR => 'SQ', Name => 'BrachyAccessoryDeviceSequence' },
    '300A,0262' => { VR => 'IS', Name => 'BrachyAccessoryDeviceNumber' },
    '300A,0263' => { VR => 'SH', Name => 'BrachyAccessoryDeviceID' },
    '300A,0264' => { VR => 'CS', Name => 'BrachyAccessoryDeviceType' },
    '300A,0266' => { VR => 'LO', Name => 'BrachyAccessoryDeviceName' },
    '300A,026A' => { VR => 'DS', Name => 'BrachyAccessoryDeviceNomThickness' },
    '300A,026C' => { VR => 'DS', Name => 'BrachyAccessoryDevNomTransmission' },
    '300A,0280' => { VR => 'SQ', Name => 'ChannelSequence' },
    '300A,0282' => { VR => 'IS', Name => 'ChannelNumber' },
    '300A,0284' => { VR => 'DS', Name => 'ChannelLength' },
    '300A,0286' => { VR => 'DS', Name => 'ChannelTotalTime' },
    '300A,0288' => { VR => 'CS', Name => 'SourceMovementType' },
    '300A,028A' => { VR => 'IS', Name => 'NumberOfPulses' },
    '300A,028C' => { VR => 'DS', Name => 'PulseRepetitionInterval' },
    '300A,0290' => { VR => 'IS', Name => 'SourceApplicatorNumber' },
    '300A,0291' => { VR => 'SH', Name => 'SourceApplicatorID' },
    '300A,0292' => { VR => 'CS', Name => 'SourceApplicatorType' },
    '300A,0294' => { VR => 'LO', Name => 'SourceApplicatorName' },
    '300A,0296' => { VR => 'DS', Name => 'SourceApplicatorLength' },
    '300A,0298' => { VR => 'LO', Name => 'SourceApplicatorManufacturer' },
    '300A,029C' => { VR => 'DS', Name => 'SourceApplicatorWallNomThickness' },
    '300A,029E' => { VR => 'DS', Name => 'SourceApplicatorWallNomTrans' },
    '300A,02A0' => { VR => 'DS', Name => 'SourceApplicatorStepSize' },
    '300A,02A2' => { VR => 'IS', Name => 'TransferTubeNumber' },
    '300A,02A4' => { VR => 'DS', Name => 'TransferTubeLength' },
    '300A,02B0' => { VR => 'SQ', Name => 'ChannelShieldSequence' },
    '300A,02B2' => { VR => 'IS', Name => 'ChannelShieldNumber' },
    '300A,02B3' => { VR => 'SH', Name => 'ChannelShieldID' },
    '300A,02B4' => { VR => 'LO', Name => 'ChannelShieldName' },
    '300A,02B8' => { VR => 'DS', Name => 'ChannelShieldNominalThickness' },
    '300A,02BA' => { VR => 'DS', Name => 'ChannelShieldNominalTransmission' },
    '300A,02C8' => { VR => 'DS', Name => 'FinalCumulativeTimeWeight' },
    '300A,02D0' => { VR => 'SQ', Name => 'BrachyControlPointSequence' },
    '300A,02D2' => { VR => 'DS', Name => 'ControlPointRelativePosition' },
    '300A,02D4' => { VR => 'DS', Name => 'ControlPoint3DPosition' },
    '300A,02D6' => { VR => 'DS', Name => 'CumulativeTimeWeight' },
    '300A,02E0' => { VR => 'CS', Name => 'CompensatorDivergence' },
    '300A,02E1' => { VR => 'CS', Name => 'CompensatorMountingPosition' },
    '300A,02E2' => { VR => 'DS', Name => 'SourceToCompensatorDistance' },
    '300C,0002' => { VR => 'SQ', Name => 'ReferencedRTPlanSequence' },
    '300C,0004' => { VR => 'SQ', Name => 'ReferencedBeamSequence' },
    '300C,0006' => { VR => 'IS', Name => 'ReferencedBeamNumber' },
    '300C,0007' => { VR => 'IS', Name => 'ReferencedReferenceImageNumber' },
    '300C,0008' => { VR => 'DS', Name => 'StartCumulativeMetersetWeight' },
    '300C,0009' => { VR => 'DS', Name => 'EndCumulativeMetersetWeight' },
    '300C,000A' => { VR => 'SQ', Name => 'ReferencedBrachyAppSetupSeq' },
    '300C,000C' => { VR => 'IS', Name => 'ReferencedBrachyAppSetupNumber' },
    '300C,000E' => { VR => 'IS', Name => 'ReferencedSourceNumber' },
    '300C,0020' => { VR => 'SQ', Name => 'ReferencedFractionGroupSequence' },
    '300C,0022' => { VR => 'IS', Name => 'ReferencedFractionGroupNumber' },
    '300C,0040' => { VR => 'SQ', Name => 'ReferencedVerificationImageSeq' },
    '300C,0042' => { VR => 'SQ', Name => 'ReferencedReferenceImageSequence' },
    '300C,0050' => { VR => 'SQ', Name => 'ReferencedDoseReferenceSequence' },
    '300C,0051' => { VR => 'IS', Name => 'ReferencedDoseReferenceNumber' },
    '300C,0055' => { VR => 'SQ', Name => 'BrachyReferencedDoseReferenceSeq' },
    '300C,0060' => { VR => 'SQ', Name => 'ReferencedStructureSetSequence' },
    '300C,006A' => { VR => 'IS', Name => 'ReferencedPatientSetupNumber' },
    '300C,0080' => { VR => 'SQ', Name => 'ReferencedDoseSequence' },
    '300C,00A0' => { VR => 'IS', Name => 'ReferencedToleranceTableNumber' },
    '300C,00B0' => { VR => 'SQ', Name => 'ReferencedBolusSequence' },
    '300C,00C0' => { VR => 'IS', Name => 'ReferencedWedgeNumber' },
    '300C,00D0' => { VR => 'IS', Name => 'ReferencedCompensatorNumber' },
    '300C,00E0' => { VR => 'IS', Name => 'ReferencedBlockNumber' },
    '300C,00F0' => { VR => 'IS', Name => 'ReferencedControlPointIndex' },
    '300E,0002' => { VR => 'CS', Name => 'ApprovalStatus' },
    '300E,0004' => { VR => 'DA', Name => 'ReviewDate' },
    '300E,0005' => { VR => 'TM', Name => 'ReviewTime' },
    '300E,0008' => { VR => 'PN', Name => 'ReviewerName' },
    # text group
    '4000,0000' => { VR => 'UL', Name => 'TextGroupLength' },
    '4000,0010' => { VR => 'RET',Name => 'Arbitrary' },
    '4000,4000' => { VR => 'RET',Name => 'TextComments' },
    # results group
    '4008,0040' => { VR => 'SH', Name => 'ResultsID' },
    '4008,0042' => { VR => 'LO', Name => 'ResultsIDIssuer' },
    '4008,0050' => { VR => 'SQ', Name => 'ReferencedInterpretationSequence' },
    '4008,0100' => { VR => 'DA', Name => 'InterpretationRecordedDate' },
    '4008,0101' => { VR => 'TM', Name => 'InterpretationRecordedTime' },
    '4008,0102' => { VR => 'PN', Name => 'InterpretationRecorder' },
    '4008,0103' => { VR => 'LO', Name => 'ReferenceToRecordedSound' },
    '4008,0108' => { VR => 'DA', Name => 'InterpretationTranscriptionDate' },
    '4008,0109' => { VR => 'TM', Name => 'InterpretationTranscriptionTime' },
    '4008,010A' => { VR => 'PN', Name => 'InterpretationTranscriber' },
    '4008,010B' => { VR => 'ST', Name => 'InterpretationText' },
    '4008,010C' => { VR => 'PN', Name => 'InterpretationAuthor' },
    '4008,0111' => { VR => 'SQ', Name => 'InterpretationApproverSequence' },
    '4008,0112' => { VR => 'DA', Name => 'InterpretationApprovalDate' },
    '4008,0113' => { VR => 'TM', Name => 'InterpretationApprovalTime' },
    '4008,0114' => { VR => 'PN', Name => 'PhysicianApprovingInterpretation' },
    '4008,0115' => { VR => 'LT', Name => 'InterpretationDiagnosisDescription' },
    '4008,0117' => { VR => 'SQ', Name => 'InterpretationDiagnosisCodeSeq' },
    '4008,0118' => { VR => 'SQ', Name => 'ResultsDistributionListSequence' },
    '4008,0119' => { VR => 'PN', Name => 'DistributionName' },
    '4008,011A' => { VR => 'LO', Name => 'DistributionAddress' },
    '4008,0200' => { VR => 'SH', Name => 'InterpretationID' },
    '4008,0202' => { VR => 'LO', Name => 'InterpretationIDIssuer' },
    '4008,0210' => { VR => 'CS', Name => 'InterpretationTypeID' },
    '4008,0212' => { VR => 'CS', Name => 'InterpretationStatusID' },
    '4008,0300' => { VR => 'ST', Name => 'Impressions' },
    '4008,4000' => { VR => 'ST', Name => 'ResultsComments' },
    '4FFE,0001' => { VR => 'SQ', Name => 'MACParametersSequence' },
    # curve group
    '50xx,0005' => { VR => 'US', Name => 'CurveDimensions' },
    '50xx,0010' => { VR => 'US', Name => 'NumberOfPoints' },
    '50xx,0020' => { VR => 'CS', Name => 'TypeOfData' },
    '50xx,0022' => { VR => 'LO', Name => 'CurveDescription' },
    '50xx,0030' => { VR => 'SH', Name => 'AxisUnits' },
    '50xx,0040' => { VR => 'SH', Name => 'AxisLabels' },
    '50xx,0103' => { VR => 'US', Name => 'DataValueRepresentation' },
    '50xx,0104' => { VR => 'US', Name => 'MinimumCoordinateValue' },
    '50xx,0105' => { VR => 'US', Name => 'MaximumCoordinateValue' },
    '50xx,0106' => { VR => 'SH', Name => 'CurveRange' },
    '50xx,0110' => { VR => 'US', Name => 'CurveDataDescriptor' },
    '50xx,0112' => { VR => 'US', Name => 'CoordinateStartValue' },
    '50xx,0114' => { VR => 'US', Name => 'CoordinateStepValue' },
    '50xx,1001' => { VR => 'CS', Name => 'CurveActivationLayer' },
    '50xx,2000' => { VR => 'US', Name => 'AudioType' },
    '50xx,2002' => { VR => 'US', Name => 'AudioSampleFormat' },
    '50xx,2004' => { VR => 'US', Name => 'NumberOfChannels' },
    '50xx,2006' => { VR => 'UL', Name => 'NumberOfSamples' },
    '50xx,2008' => { VR => 'UL', Name => 'SampleRate' },
    '50xx,200A' => { VR => 'UL', Name => 'TotalTime' },
    '50xx,200C' => { VR => 'OB', Name => 'AudioSampleData' },
    '50xx,200E' => { VR => 'LT', Name => 'AudioComments' },
    '50xx,2500' => { VR => 'LO', Name => 'CurveLabel' },
    '50xx,2600' => { VR => 'SQ', Name => 'ReferencedOverlaySequence' },
    '50xx,2610' => { VR => 'US', Name => 'ReferencedOverlayGroup' },
    '50xx,3000' => { VR => 'OB', Name => 'CurveData' },
    '5200,9229' => { VR => 'SQ', Name => 'SharedFunctionalGroupsSequence' },
    '5200,9230' => { VR => 'SQ', Name => 'PerFrameFunctionalGroupsSequence' },
    '5400,0100' => { VR => 'SQ', Name => 'WaveformSequence' },
    '5400,0110' => { VR => 'OW', Name => 'ChannelMinimumValue' },
    '5400,0112' => { VR => 'OW', Name => 'ChannelMaximumValue' },
    '5400,1004' => { VR => 'US', Name => 'WaveformBitsAllocated' },
    '5400,1006' => { VR => 'CS', Name => 'WaveformSampleInterpretation' },
    '5400,100A' => { VR => 'OW', Name => 'WaveformPaddingValue' },
    '5400,1010' => { VR => 'OW', Name => 'WaveformData' },
    '5600,0010' => { VR => 'OF', Name => 'FirstOrderPhaseCorrectionAngle' },
    '5600,0020' => { VR => 'OF', Name => 'SpectroscopyData' },
    # overlay group
    '6000,0000' => { VR => 'UL', Name => 'OverlayGroupLength' },
    '60xx,0010' => { VR => 'US', Name => 'OverlayRows' },
    '60xx,0011' => { VR => 'US', Name => 'OverlayColumns' },
    '60xx,0012' => { VR => 'US', Name => 'OverlayPlanes' },
    '60xx,0015' => { VR => 'IS', Name => 'NumberOfFramesInOverlay' },
    '60xx,0022' => { VR => 'LO', Name => 'OverlayDescription' },
    '60xx,0040' => { VR => 'CS', Name => 'OverlayType' },
    '60xx,0045' => { VR => 'LO', Name => 'OverlaySubtype' },
    '60xx,0050' => { VR => 'SS', Name => 'OverlayOrigin' },
    '60xx,0051' => { VR => 'US', Name => 'ImageFrameOrigin' },
    '60xx,0052' => { VR => 'US', Name => 'OverlayPlaneOrigin' },
    '60xx,0060' => { VR => 'RET',Name => 'CompressionCode' },
    '60xx,0100' => { VR => 'US', Name => 'OverlayBitsAllocated' },
    '60xx,0102' => { VR => 'US', Name => 'OverlayBitPosition' },
    '60xx,0110' => { VR => 'RET',Name => 'OverlayFormat' },
    '60xx,0200' => { VR => 'RET',Name => 'OverlayLocation' },
    '60xx,1001' => { VR => 'CS', Name => 'OverlayActivationLayer' },
    '60xx,1100' => { VR => 'RET',Name => 'OverlayDescriptorGray' },
    '60xx,1101' => { VR => 'RET',Name => 'OverlayDescriptorRed' },
    '60xx,1102' => { VR => 'RET',Name => 'OverlayDescriptorGreen' },
    '60xx,1103' => { VR => 'RET',Name => 'OverlayDescriptorBlue' },
    '60xx,1200' => { VR => 'RET',Name => 'OverlaysGray' },
    '60xx,1201' => { VR => 'RET',Name => 'OverlaysRed' },
    '60xx,1202' => { VR => 'RET',Name => 'OverlaysGreen' },
    '60xx,1203' => { VR => 'RET',Name => 'OverlaysBlue' },
    '60xx,1301' => { VR => 'IS', Name => 'ROIArea' },
    '60xx,1302' => { VR => 'DS', Name => 'ROIMean' },
    '60xx,1303' => { VR => 'DS', Name => 'ROIStandardDeviation' },
    '60xx,1500' => { VR => 'LO', Name => 'OverlayLabel' },
    '60xx,3000' => { VR => 'OW', Name => 'OverlayData' },
    '60xx,4000' => { VR => 'RET',Name => 'OverlayComments' },
    # pixel data group
    '7FE0,0000' => { VR => 'UL', Name => 'PixelDataGroupLength' },
    '7FE0,0010' => { VR => 'OB', Name => 'PixelData', Binary => 1 },
    'FFFA,FFFA' => { VR => 'SQ', Name => 'DigitalSignaturesSequence' },
    'FFFC,FFFC' => { VR => 'OB', Name => 'DataSetTrailingPadding', Binary => 1 },
    # the sequence delimiters have no VR:
    'FFFE,E000' => 'StartOfItem',
    'FFFE,E00D' => 'EndOfItems',
    'FFFE,E0DD' => 'EndOfSequence',
);

# table to translate registered UID values to readable strings
my %uid = (
    '1.2.840.10008.1.1' => 'Verification SOP Class',
    '1.2.840.10008.1.2' => 'Implicit VR Little Endian',
    '1.2.840.10008.1.2.1' => 'Explicit VR Little Endian',
    '1.2.840.10008.1.2.1.99' => 'Deflated Explicit VR Little Endian',
    '1.2.840.10008.1.2.2' => 'Explicit VR Big Endian',
    '1.2.840.10008.1.2.4.50' => 'JPEG Baseline (Process 1)',
    '1.2.840.10008.1.2.4.51' => 'JPEG Extended (Process 2 & 4)',
    '1.2.840.10008.1.2.4.52' => 'JPEG Extended (Process 3 & 5)',
    '1.2.840.10008.1.2.4.53' => 'JPEG Spectral Selection, Non-Hierarchical (Process 6 & 8)',
    '1.2.840.10008.1.2.4.54' => 'JPEG Spectral Selection, Non-Hierarchical (Process 7 & 9)',
    '1.2.840.10008.1.2.4.55' => 'JPEG Full Progression, Non-Hierarchical (Process 10 & 12)',
    '1.2.840.10008.1.2.4.56' => 'JPEG Full Progression, Non-Hierarchical (Process 11 & 13)',
    '1.2.840.10008.1.2.4.57' => 'JPEG Lossless, Non-Hierarchical (Process 14)',
    '1.2.840.10008.1.2.4.58' => 'JPEG Lossless, Non-Hierarchical (Process 15) ',
    '1.2.840.10008.1.2.4.59' => 'JPEG Extended, Hierarchical (Process 16 & 18) ',
    '1.2.840.10008.1.2.4.60' => 'JPEG Extended, Hierarchical (Process 17 & 19) ',
    '1.2.840.10008.1.2.4.61' => 'JPEG Spectral Selection, Hierarchical (Process 20 & 22)',
    '1.2.840.10008.1.2.4.62' => 'JPEG Spectral Selection, Hierarchical (Process 21 & 23)',
    '1.2.840.10008.1.2.4.63' => 'JPEG Full Progression, Hierarchical (Process 24 & 26)',
    '1.2.840.10008.1.2.4.64' => 'JPEG Full Progression, Hierarchical (Process 25 & 27)',
    '1.2.840.10008.1.2.4.65' => 'JPEG Lossless, Hierarchical (Process 28) ',
    '1.2.840.10008.1.2.4.66' => 'JPEG Lossless, Hierarchical (Process 29) ',
    '1.2.840.10008.1.2.4.70' => 'JPEG Lossless, Non-Hierarchical, First-Order Prediction (Process 14-1)',
    '1.2.840.10008.1.2.4.80' => 'JPEG-LS Lossless Image Compression',
    '1.2.840.10008.1.2.4.81' => 'JPEG-LS Lossy (Near-Lossless) Image Compression',
    '1.2.840.10008.1.2.4.90' => 'JPEG 2000 Image Compression (Lossless Only)',
    '1.2.840.10008.1.2.4.91' => 'JPEG 2000 Image Compression',
    '1.2.840.10008.1.2.4.100' => 'MPEG2 Main Profile @ Main Level',
    '1.2.840.10008.1.2.5' => 'RLE Lossless',
    '1.2.840.10008.1.3.10' => 'Media Storage Directory Storage',
    '1.2.840.10008.1.4.1.1' => 'Talairach Brain Atlas Frame of Reference',
    '1.2.840.10008.1.4.1.2' => 'SPM2 T1 Frame of Reference',
    '1.2.840.10008.1.4.1.3' => 'SPM2 T2 Frame of Reference',
    '1.2.840.10008.1.4.1.4' => 'SPM2 PD Frame of Reference',
    '1.2.840.10008.1.4.1.5' => 'SPM2 EPI Frame of Reference',
    '1.2.840.10008.1.4.1.6' => 'SPM2 FIL T1 Frame of Reference',
    '1.2.840.10008.1.4.1.7' => 'SPM2 PET Frame of Reference',
    '1.2.840.10008.1.4.1.8' => 'SPM2 TRANSM Frame of Reference',
    '1.2.840.10008.1.4.1.9' => 'SPM2 SPECT Frame of Reference',
    '1.2.840.10008.1.4.1.10' => 'SPM2 GRAY Frame of Reference',
    '1.2.840.10008.1.4.1.11' => 'SPM2 WHITE Frame of Reference',
    '1.2.840.10008.1.4.1.12' => 'SPM2 CSF Frame of Reference',
    '1.2.840.10008.1.4.1.13' => 'SPM2 BRAINMASK Frame of Reference',
    '1.2.840.10008.1.4.1.14' => 'SPM2 AVG305T1 Frame of Reference',
    '1.2.840.10008.1.4.1.15' => 'SPM2 AVG152T1 Frame of Reference',
    '1.2.840.10008.1.4.1.16' => 'SPM2 AVG152T2 Frame of Reference',
    '1.2.840.10008.1.4.1.17' => 'SPM2 AVG152PD Frame of Reference',
    '1.2.840.10008.1.4.1.18' => 'SPM2 SINGLESUBJT1 Frame of Reference',
    '1.2.840.10008.1.4.2.1' => 'ICBM 452 T1 Frame of Reference',
    '1.2.840.10008.1.4.2.2' => 'ICBM Single Subject MRI Frame of Reference',
    '1.2.840.10008.1.9' => 'Basic Study Content Notification SOP Class',
    '1.2.840.10008.1.20.1' => 'Storage Commitment Push Model SOP Class',
    '1.2.840.10008.1.20.1.1' => 'Storage Commitment Push Model SOP Instance',
    '1.2.840.10008.1.20.2' => 'Storage Commitment Pull Model SOP Class ',
    '1.2.840.10008.1.20.2.1' => 'Storage Commitment Pull Model SOP Instance ',
    '1.2.840.10008.1.40' => 'Procedural Event Logging SOP Class',
    '1.2.840.10008.1.40.1' => 'Procedural Event Logging SOP Instance',
    '1.2.840.10008.2.16.4' => 'DICOM Controlled Terminology Coding Scheme PS 3.16',
    '1.2.840.10008.3.1.1.1' => 'DICOM Application Context Name',
    '1.2.840.10008.3.1.2.1.1' => 'Detached Patient Management SOP Class',
    '1.2.840.10008.3.1.2.1.4' => 'Detached Patient Management Meta SOP Class',
    '1.2.840.10008.3.1.2.2.1' => 'Detached Visit Management SOP Class',
    '1.2.840.10008.3.1.2.3.1' => 'Detached Study Management SOP Class',
    '1.2.840.10008.3.1.2.3.2' => 'Study Component Management SOP Class',
    '1.2.840.10008.3.1.2.3.3' => 'Modality Performed Procedure Step SOP Class',
    '1.2.840.10008.3.1.2.3.4' => 'Modality Performed Procedure Step Retrieve SOP Class',
    '1.2.840.10008.3.1.2.3.5' => 'Modality Performed Procedure Step Notification SOP Class',
    '1.2.840.10008.3.1.2.5.1' => 'Detached Results Management SOP Class',
    '1.2.840.10008.3.1.2.5.4' => 'Detached Results Management Meta SOP Class',
    '1.2.840.10008.3.1.2.5.5' => 'Detached Study Management Meta SOP Class',
    '1.2.840.10008.3.1.2.6.1' => 'Detached Interpretation Management SOP Class',
    '1.2.840.10008.4.2' => 'Storage Service Class Service Class PS 3.4',
    '1.2.840.10008.5.1.1.1' => 'Basic Film Session SOP Class',
    '1.2.840.10008.5.1.1.2' => 'Basic Film Box SOP Class',
    '1.2.840.10008.5.1.1.4' => 'Basic Grayscale Image Box SOP Class',
    '1.2.840.10008.5.1.1.4.1' => 'Basic Color Image Box SOP Class',
    '1.2.840.10008.5.1.1.4.2' => 'Referenced Image Box SOP Class',
    '1.2.840.10008.5.1.1.9' => 'Basic Grayscale Print ManagementMeta SOP Class',
    '1.2.840.10008.5.1.1.9.1' => 'Referenced Grayscale Print Management Meta SOP Class',
    '1.2.840.10008.5.1.1.14' => 'Print Job SOP Class',
    '1.2.840.10008.5.1.1.15' => 'Basic Annotation Box SOP Class',
    '1.2.840.10008.5.1.1.16' => 'Printer SOP Class',
    '1.2.840.10008.5.1.1.16.376' => 'Printer Configuration Retrieval SOP Class',
    '1.2.840.10008.5.1.1.17' => 'Printer SOP Instance',
    '1.2.840.10008.5.1.1.17.376' => 'Printer Configuration RetrievalSOP Instance',
    '1.2.840.10008.5.1.1.18' => 'Basic Color Print Management Meta SOP Class',
    '1.2.840.10008.5.1.1.18.1' => 'Referenced Color Print Management Meta SOP Class',
    '1.2.840.10008.5.1.1.22' => 'VOI LUT Box SOP Class',
    '1.2.840.10008.5.1.1.23' => 'Presentation LUT SOP Class',
    '1.2.840.10008.5.1.1.24' => 'Image Overlay Box SOP Class',
    '1.2.840.10008.5.1.1.24.1' => 'Basic Print Image Overlay Box SOP Class',
    '1.2.840.10008.5.1.1.25' => 'Print Queue SOP Instance',
    '1.2.840.10008.5.1.1.26' => 'Print Queue Management SOP Class',
    '1.2.840.10008.5.1.1.27' => 'Stored Print Storage SOP Class',
    '1.2.840.10008.5.1.1.29' => 'Hardcopy Grayscale Image',
    '1.2.840.10008.5.1.1.30' => 'Hardcopy Color Image Storage SOP Class',
    '1.2.840.10008.5.1.1.31' => 'Pull Print Request SOP Class',
    '1.2.840.10008.5.1.1.32' => 'Pull Stored Print Management Meta SOP Class',
    '1.2.840.10008.5.1.1.33' => 'Media Creation Management SOP Class',
    '1.2.840.10008.5.1.4.1.1.1' => 'Computed Radiography Image Storage',
    '1.2.840.10008.5.1.4.1.1.1.1' => 'Digital X-Ray Image Storage � For Presentation',
    '1.2.840.10008.5.1.4.1.1.1.1.1' => 'Digital X-Ray Image Storage � For Processing',
    '1.2.840.10008.5.1.4.1.1.1.2' => 'Digital Mammography X-Ray Image Storage � For Presentation',
    '1.2.840.10008.5.1.4.1.1.1.2.1' => 'Digital Mammography X-Ray Image Storage � For Processing',
    '1.2.840.10008.5.1.4.1.1.1.3' => 'Digital Intra-oral X-Ray Image Storage � For Presentation',
    '1.2.840.10008.5.1.4.1.1.1.3.1' => 'Digital Intra-oral X-Ray Image Storage � For Processing',
    '1.2.840.10008.5.1.4.1.1.2' => 'CT Image Storage',
    '1.2.840.10008.5.1.4.1.1.2.1' => 'Enhanced CT Image Storage',
    '1.2.840.10008.5.1.4.1.1.3' => 'Ultrasound Multi-frame Image Storage ',
    '1.2.840.10008.5.1.4.1.1.3.1' => 'Ultrasound Multi-frame Image Storage',
    '1.2.840.10008.5.1.4.1.1.4' => 'MR Image Storage',
    '1.2.840.10008.5.1.4.1.1.4.1' => 'Enhanced MR Image Storage',
    '1.2.840.10008.5.1.4.1.1.4.2' => 'MR Spectroscopy Storage',
    '1.2.840.10008.5.1.4.1.1.5' => 'Nuclear Medicine Image Storage',
    '1.2.840.10008.5.1.4.1.1.6' => 'Ultrasound Image Storage',
    '1.2.840.10008.5.1.4.1.1.6.1' => 'Ultrasound Image Storage',
    '1.2.840.10008.5.1.4.1.1.7' => 'Secondary Capture Image Storage',
    '1.2.840.10008.5.1.4.1.1.7.1' => 'Multi-frame Single Bit Secondary',
    '1.2.840.10008.5.1.4.1.1.7.2' => 'Multi-frame Grayscale Byte Secondary Capture Image Storage',
    '1.2.840.10008.5.1.4.1.1.7.3' => 'Multi-frame Grayscale Word Secondary Capture Image Storage',
    '1.2.840.10008.5.1.4.1.1.7.4' => 'Multi-frame True Color Secondary Capture Image Storage',
    '1.2.840.10008.5.1.4.1.1.8' => 'Standalone Overlay Storage',
    '1.2.840.10008.5.1.4.1.1.9' => 'Standalone Curve Storage',
    '1.2.840.10008.5.1.4.1.1.9.1.1' => '12-lead ECG Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.9.1.2' => 'General ECG Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.9.1.3' => 'Ambulatory ECG Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.9.2.1' => 'Hemodynamic Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.9.3.1' => 'Cardiac Electrophysiology Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.9.4.1' => 'Basic Voice Audio Waveform Storage',
    '1.2.840.10008.5.1.4.1.1.10' => 'Standalone Modality LUT Storage',
    '1.2.840.10008.5.1.4.1.1.11' => 'Standalone VOI LUT Storage',
    '1.2.840.10008.5.1.4.1.1.11.1' => 'Grayscale Softcopy Presentation State Storage SOP Class',
    '1.2.840.10008.5.1.4.1.1.12.1' => 'X-Ray Angiographic Image Storage',
    '1.2.840.10008.5.1.4.1.1.12.2' => 'X-Ray Radiofluoroscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.12.3' => 'X-Ray Angiographic Bi-Plane Image Storage ',
    '1.2.840.10008.5.1.4.1.1.20' => 'Nuclear Medicine Image Storage',
    '1.2.840.10008.5.1.4.1.1.66' => 'Raw Data Storage',
    '1.2.840.10008.5.1.4.1.1.66.1' => 'Spatial Registration Storage',
    '1.2.840.10008.5.1.4.1.1.66.2' => 'Spatial Fiducials Storage',
    '1.2.840.10008.5.1.4.1.1.77.1' => 'VL Image Storage ',
    '1.2.840.10008.5.1.4.1.1.77.2' => 'VL Multi-frame Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.1' => 'VL Endoscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.1.1' => 'Video Endoscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.2' => 'VL Microscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.2.1' => 'Video Microscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.3' => 'VL Slide-Coordinates Microscopic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.4' => 'VL Photographic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.4.1' => 'Video Photographic Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.5.1' => 'Ophthalmic Photography 8 Bit Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.5.2' => 'Ophthalmic Photography 16 Bit Image Storage',
    '1.2.840.10008.5.1.4.1.1.77.1.5.3' => 'Stereometric Relationship Storage',
    '1.2.840.10008.5.1.4.1.1.88.11' => 'Basic Text SR',
    '1.2.840.10008.5.1.4.1.1.88.22' => 'Enhanced SR',
    '1.2.840.10008.5.1.4.1.1.88.33' => 'Comprehensive SR',
    '1.2.840.10008.5.1.4.1.1.88.40' => 'Procedure Log Storage',
    '1.2.840.10008.5.1.4.1.1.88.50' => 'Mammography CAD SR',
    '1.2.840.10008.5.1.4.1.1.88.59' => 'Key Object Selection Document',
    '1.2.840.10008.5.1.4.1.1.88.65' => 'Chest CAD SR',
    '1.2.840.10008.5.1.4.1.1.128' => 'Positron Emission Tomography Image Storage',
    '1.2.840.10008.5.1.4.1.1.129' => 'Standalone PET Curve Storage',
    '1.2.840.10008.5.1.4.1.1.481.1' => 'RT Image Storage',
    '1.2.840.10008.5.1.4.1.1.481.2' => 'RT Dose Storage',
    '1.2.840.10008.5.1.4.1.1.481.3' => 'RT Structure Set Storage',
    '1.2.840.10008.5.1.4.1.1.481.4' => 'RT Beams Treatment Record Storage',
    '1.2.840.10008.5.1.4.1.1.481.5' => 'RT Plan Storage',
    '1.2.840.10008.5.1.4.1.1.481.6' => 'RT Brachy Treatment Record Storage',
    '1.2.840.10008.5.1.4.1.1.481.7' => 'RT Treatment Summary Record Storage',
    '1.2.840.10008.5.1.4.1.2.1.1' => 'Patient Root Query/Retrieve Information Model � FIND',
    '1.2.840.10008.5.1.4.1.2.1.2' => 'Patient Root Query/Retrieve Information Model � MOVE',
    '1.2.840.10008.5.1.4.1.2.1.3' => 'Patient Root Query/Retrieve Information Model � GET',
    '1.2.840.10008.5.1.4.1.2.2.1' => 'Study Root Query/Retrieve Information Model � FIND',
    '1.2.840.10008.5.1.4.1.2.2.2' => 'Study Root Query/Retrieve Information Model � MOVE',
    '1.2.840.10008.5.1.4.1.2.2.3' => 'Study Root Query/Retrieve Information Model � GET',
    '1.2.840.10008.5.1.4.1.2.3.1' => 'Patient/Study Only Query/Retrieve Information Model - FIND',
    '1.2.840.10008.5.1.4.1.2.3.2' => 'Patient/Study Only Query/Retrieve Information Model - MOVE',
    '1.2.840.10008.5.1.4.1.2.3.3' => 'Patient/Study Only Query/Retrieve Information Model - GET',
    '1.2.840.10008.5.1.4.31' => 'Modality Worklist Information Model � FIND',
    '1.2.840.10008.5.1.4.32.1' => 'General Purpose Worklist Information Model � FIND',
    '1.2.840.10008.5.1.4.32.2' => 'General Purpose Scheduled Procedure Step SOP Class',
    '1.2.840.10008.5.1.4.32.3' => 'General Purpose Performed Procedure Step SOP Class',
    '1.2.840.10008.5.1.4.32' => 'General Purpose Worklist Management Meta SOP Class',
    '1.2.840.10008.5.1.4.33' => 'Instance Availability Notification SOP Class',
    '1.2.840.10008.5.1.4.37.1' => 'General Relevant Patient Information Query',
    '1.2.840.10008.5.1.4.37.2' => 'Breast Imaging Relevant Patient Information Query',
    '1.2.840.10008.5.1.4.37.3' => 'Cardiac Relevant Patient Information Query',
    '1.2.840.10008.15.0.3.1' => 'dicomDeviceName',
    '1.2.840.10008.15.0.3.2' => 'dicomDescription',
    '1.2.840.10008.15.0.3.3' => 'dicomManufacturer',
    '1.2.840.10008.15.0.3.4' => 'dicomManufacturerModelName',
    '1.2.840.10008.15.0.3.5' => 'dicomSoftwareVersion',
    '1.2.840.10008.15.0.3.6' => 'dicomVendorData',
    '1.2.840.10008.15.0.3.7' => 'dicomAETitle',
    '1.2.840.10008.15.0.3.8' => 'dicomNetworkConnectionReference',
    '1.2.840.10008.15.0.3.9' => 'dicomApplicationCluster',
    '1.2.840.10008.15.0.3.10' => 'dicomAssociationInitiator',
    '1.2.840.10008.15.0.3.11' => 'dicomAssociationAcceptor',
    '1.2.840.10008.15.0.3.12' => 'dicomHostname',
    '1.2.840.10008.15.0.3.13' => 'dicomPort',
    '1.2.840.10008.15.0.3.14' => 'dicomSOPClass',
    '1.2.840.10008.15.0.3.15' => 'dicomTransferRole',
    '1.2.840.10008.15.0.3.16' => 'dicomTransferSyntax',
    '1.2.840.10008.15.0.3.17' => 'dicomPrimaryDeviceType',
    '1.2.840.10008.15.0.3.18' => 'dicomRelatedDeviceReference',
    '1.2.840.10008.15.0.3.19' => 'dicomPreferredCalledAETitle',
    '1.2.840.10008.15.0.3.20' => 'dicomTLSCyphersuite',
    '1.2.840.10008.15.0.3.21' => 'dicomAuthorizedNodeCertificateReference',
    '1.2.840.10008.15.0.3.22' => 'dicomThisNodeCertificateReference',
    '1.2.840.10008.15.0.3.23' => 'dicomInstalled',
    '1.2.840.10008.15.0.3.24' => 'dicomStationName',
    '1.2.840.10008.15.0.3.25' => 'dicomDeviceSerialNumber',
    '1.2.840.10008.15.0.3.26' => 'dicomInstitutionName',
    '1.2.840.10008.15.0.3.27' => 'dicomInstitutionAddress',
    '1.2.840.10008.15.0.3.28' => 'dicomInstitutionDepartmentName',
    '1.2.840.10008.15.0.3.29' => 'dicomIssuerOfPatientID',
    '1.2.840.10008.15.0.3.30' => 'dicomPreferredCallingAETitle',
    '1.2.840.10008.15.0.3.31' => 'dicomSupportedCharacterSet',
    '1.2.840.10008.15.0.4.1' => 'dicomConfigurationRoot',
    '1.2.840.10008.15.0.4.2' => 'dicomDevicesRoot',
    '1.2.840.10008.15.0.4.3' => 'dicomUniqueAETitlesRegistryRoot',
    '1.2.840.10008.15.0.4.4' => 'dicomDevice',
    '1.2.840.10008.15.0.4.5' => 'dicomNetworkAE',
    '1.2.840.10008.15.0.4.6' => 'dicomNetworkConnection',
    '1.2.840.10008.15.0.4.7' => 'dicomUniqueAETitle',
    '1.2.840.10008.15.0.4.8' => 'dicomTransferCapability',
);

#------------------------------------------------------------------------------
# Extract information from a DICOM (DCM) image
# Inputs: 0) ExifTool object reference, 1) DirInfo reference
# Returns: 1 on success, 0 if this wasn't a valid DICOM file
sub ProcessDICM($$)
{
    my ($exifTool, $dirInfo) = @_;
    my $raf = $$dirInfo{RAF};
    my $unknown = $exifTool->Options('Unknown');
    my $verbose = $exifTool->Options('Verbose');
    my ($hdr, $buff, $implicit, $vr, $len);
#
# identify the DICOM or ACR-NEMA file
#
    $raf->Read($hdr, 12) == 12 or return 0; # save for ACR identification later
    $raf->Seek(128, 0) or return 0;         # skip to end of DICM header
    $raf->Read($buff, 4) == 4 or return 0;  # read signature
    if ($buff eq 'DICM') {
        # file meta information transfer syntax is explicit little endian
        SetByteOrder('II');
        $exifTool->SetFileType('DICOM');
    } else {
        # test for a RAW DCM image (ACR-NEMA format, ie. no header)
        foreach ('II','MM','') {
            return 0 unless $_; # no luck identifying the syntax
            SetByteOrder($_);
            my $g = Get16u(\$hdr, 0);
            # expect group number to be small and even
            next if $g < 2 or $g > 8 or $g & 0x01;
            my $e = Get16u(\$hdr, 2);
            next if $e > 0x20;          # expect a low element number at start
            $vr = substr($hdr, 4, 2);   # look for explicit VR
            if ($vr =~ /^[A-Z]{2}$/) {
                $implicit = 0;
                if ($vr32{$vr}) {
                    next unless Get16u(\$hdr, 6) == 0;  # must be 2 zero bytes
                    $len = Get32u(\$hdr, 8);
                } else {
                    next if $e == 0 and $vr ne 'UL';    # group length must be UL
                    $len = Get16u(\$hdr, 6);
                }
            } else {
                $implicit = 1;
                $len = Get32u(\$hdr, 4);
            }
            next if $e == 0 and $len != 4;  # group length value must be 4 bytes
            next if $len > 64;      # first element shouldn't be too long
            last;   # success!
        }
        $raf->Seek(0, 0) or return 0;   # rewind to start of file
        $exifTool->SetFileType('ACR');
    }
#
# process the meta information
#
    my $tagTablePtr = GetTagTable('Image::ExifTool::DICOM::Main');
    my $pos = $raf->Tell();
    my $err = 1;
    my ($transferSyntax, $group2end);
    for (;;) {
        $raf->Read($buff, 8) == 8 or $err = 0, last;
        $pos += 8;
        my $group = Get16u(\$buff, 0);
        # implement the transfer syntax at the end of the group 2 data
        if ($transferSyntax and ($group != 0x0002 or
            ($group2end and $pos > $group2end)))
        {
            # 1.2.840.10008.1.2   = implicit VR little endian
            # 1.2.840.10008.1.2.2 = explicit VR big endian
            # 1.2.840.10008.1.2.x = explicit VR little endian
            # 1.2.840.10008.1.2.1.99 = deflated
            unless ($transferSyntax =~ /^1\.2\.840\.10008\.1\.2(\.\d+)?(\.\d+)?/) {
                $exifTool->Warn("Unrecognized transfer syntax $transferSyntax");
                last;
            }
            if (not $1) {
                $implicit = 1;
            } elsif ($1 eq '.2') {
                SetByteOrder('MM');
                $group = Get16u(\$buff, 0); # must get group again
            } elsif ($1 eq '.1' and $2 and $2 eq '.99') {
                # inflate compressed data stream
                if (eval 'require Compress::Zlib') {
                    # must use undocumented zlib feature to disable zlib header information
                    # because DICOM deflated data doesn't have the zlib header (ref 3)
                    my $wbits = -Compress::Zlib::MAX_WBITS();
                    my $inflate = Compress::Zlib::inflateInit(-WindowBits => $wbits);
                    if ($inflate) {
                        $raf->Seek(-8, 1) or last;
                        my $data = '';
                        while ($raf->Read($buff, 65536)) {
                            my ($buf, $stat) = $inflate->inflate($buff);
                            if ($stat == Compress::Zlib::Z_OK() or
                                $stat == Compress::Zlib::Z_STREAM_END())
                            {
                                $data .= $buf;
                                last if $stat == Compress::Zlib::Z_STREAM_END();
                            } else {
                                $exifTool->Warn('Error inflating compressed data stream');
                                return 1;
                            }
                        }
                        last if length $data < 8;
                        # create new RAF object from inflated data stream
                        $raf = new File::RandomAccess(\$data);
                        # re-read start of stream (now decompressed)
                        $raf->Read($buff, 8) == 8 or last;
                        $group = Get16u(\$buff, 0);
                    } else {
                        $exifTool->Warn('Error initializing inflation');
                        return 1;
                    }
                } else {
                    $exifTool->Warn('Install Compress::Zlib to decode compressed data stream');
                    return 1;
                }
            }
            undef $transferSyntax;
        }
        my $element = Get16u(\$buff,2);
        my $tag = sprintf('%.4X,%.4X', $group, $element);

        if ($implicit or $implicitVR{$tag}) {
            # treat everything as string if implicit VR because it
            # isn't worth it to generate the necessary VR lookup tables
            # for the thousands of defined data elements
            $vr = '';       # no VR (treat everything as string)
            $len = Get32u(\$buff, 4);
        } else {
            $vr = substr($buff,4,2);
            last unless $vr =~ /^[A-Z]{2}$/;
            if ($vr32{$vr}) {
                $raf->Read($buff, 4) == 4 or last;
                $pos += 4;
                $len = Get32u(\$buff, 0);
                $len = 0 if $vr eq 'SQ';    # just recurse into sequences
            } else {
                $len = Get16u(\$buff, 6);
            }
        }
        if ($len == 0xffffffff) {
            $len = 0;   # don't read value if undefined length
            if ($verbose) {
                # start list of items in verbose output
                $exifTool->VPrint(0, "$exifTool->{INDENT}+ [List of items]\n");
                $exifTool->{INDENT} .= '| ';
            }
        }
        # read the element value
        if ($len) {
            $raf->Read($buff, $len) == $len or last;
            $pos += $len;
        } else {
            $buff = '';
        }

        # handle tags not found in the table
        my $tagInfo = $$tagTablePtr{$tag};
        unless ($tagInfo) {
            # look for a tag like '60xx,1203' or '0020,31xx' in table
            my $xx;
            if ((($xx = $tag) =~ s/^(..)../$1xx/ and $$tagTablePtr{$xx}) or
                (($xx = $tag) =~ s/(..)$/xx/ and $$tagTablePtr{$xx}))
            {
                $tag = $xx;
                $tagInfo = $$tagTablePtr{$xx};
            } elsif ($unknown) {
                # create tag info hash for unknown elements
                if ($element == 0) {    # element zero is group length
                    $tagInfo = {
                        Name => sprintf("Group%.4X_Length", $group),
                        Description => sprintf("Group %.4X Length", $group),
                    };
                } else {
                    $tagInfo = {
                        Name => sprintf("DICOM_%.4X_%.4X", $group, $element),
                        Description => sprintf("DICOM %.4X,%.4X", $group, $element),
                    };
                }
                $$tagInfo{Unknown} = 1;
                Image::ExifTool::AddTagToTable($tagTablePtr, $tag, $tagInfo);
            }
        }
        # get VR from our tag information if implicit
        $vr = $$tagInfo{VR} || '  ' if $tagInfo and not $vr;

        if ($element == 0) {
            $vr = 'UL'; # group length element is always unsigned long
        }
        my $val;
        my $format = $dicomFormat{$vr};
        if ($len > 1024) {
            # treat large data elements as binary data
            my $binData;
            if ($exifTool->Options('Binary') or ($tagInfo and
                $exifTool->{REQ_TAG_LOOKUP}->{lc($$tagInfo{Name})}))
            {
                $binData = $buff;   # must make a copy
            } else {
                $binData = "Binary data $len bytes";
            }
            $val = \$binData;
        } elsif ($format) {
            $val = ReadValue(\$buff, 0, $format, undef, $len);
        } else {
            $val = $buff;
            $format = 'string';
            if ($vr eq 'DA') {
                # format date values
                $val =~ s/^(\d{4})(\d{2})(\d{2})/$1:$2:$3/;
            } elsif ($vr eq 'TM') {
                # format time values
                $val =~ s/^(\d{2})(\d{2})(\d{2}.*)/$1:$2:$3/;
            } elsif ($vr eq 'DT') {
                # format date/time values
                $val =~ s/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2}.*)/$1:$2:$3 $4:$5:$6/;
            } elsif ($vr eq 'AT' and $len == 4) {
                # convert attribute tag ID to hex format
                my ($g, $e) = (Get16u(\$buff,0), Get16u(\$buff,2));
                $val = sprintf('%.4X,%.4X', $g, $e);
            } elsif ($vr eq 'UI') {
                # add PrintConv to translate registered UID's
                $val =~ s/\0.*//; # truncate at null
                $$tagInfo{PrintConv} = \%uid if $uid{$val} and $tagInfo;
            }
        }
        # save the group 2 end position and transfer syntax
        if ($group == 0x0002) {
            $element == 0x0000 and $group2end = $pos + $val;
            $element == 0x0010 and $transferSyntax = $val;
        }

        # handle the new tag information
        $exifTool->HandleTag($tagTablePtr, $tag, $val,
            DataPt => \$buff,
            DataPos => $pos - $len,
            Format => $format,
            Start => 0,
            Size => $len,
            Extra => " ($vr)",
        );

        # stop indenting for list if we reached EndOfItems tag
        $exifTool->{INDENT} =~ s/..$// if $verbose and $tag eq 'FFFE,E00D';
    }
    $err and $exifTool->Warn('Error reading DICOM file (corrupted?)');
    return 1;
}

1;  # end

__END__

=head1 NAME

Image::ExifTool::DICOM - Read DICOM and ACR-NEMA medical images

=head1 SYNOPSIS

This module is used by Image::ExifTool

=head1 DESCRIPTION

This module contains routines required by Image::ExifTool to extract meta
information from DICOM (Digital Imaging and Communications in Medicine) DCM
and ACR-NEMA (American College of Radiology - National Electrical
Manufacturer's Association) ACR medical images.

=head1 NOTES

Values of retired elements in implicit VR format files are intepreted as
strings, hence they may not be displayed properly.  This is because the
specification no longer lists these VR's, but simply lists 'RET' for these
elements.  (Doh. Who's idea was that? :P)

Images compressed using the DICOM deflated transfer syntax will be decoded
if Compress::Zlib is installed.

No translation of special characters sets is done.

=head1 AUTHOR

Copyright 2003-2009, Phil Harvey (phil at owl.phy.queensu.ca)

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REFERENCES

=over 4

=item L<http://medical.nema.org/dicom/2004.html>

=item L<http://www.sph.sc.edu/comd/rorden/dicom.html>

=item L<http://www.dclunie.com/>

=item L<http://www.gehealthcare.com/usen/interoperability/dicom/docs/2258357r3.pdf>

=back

=head1 SEE ALSO

L<Image::ExifTool::TagNames/DICOM Tags>,
L<Image::ExifTool(3pm)|Image::ExifTool>

=cut

