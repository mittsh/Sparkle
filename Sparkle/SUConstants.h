//
//  SUConstants.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#ifndef SUCONSTANTS_H
#define SUCONSTANTS_H

// -----------------------------------------------------------------------------
//	Misc:
// -----------------------------------------------------------------------------

extern const NSTimeInterval SUMinimumUpdateCheckInterval;
extern const NSTimeInterval SUDefaultUpdateCheckInterval;

extern NSString *const SUBundleIdentifier;

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

extern NSString *const SUTechnicalErrorInformationKey;

// -----------------------------------------------------------------------------
//	PList keys::
// -----------------------------------------------------------------------------

extern NSString *const SUFeedURLKey;
extern NSString *const SUHasLaunchedBeforeKey;
extern NSString *const SUShowReleaseNotesKey;
extern NSString *const SUSkippedVersionKey;
extern NSString *const SUScheduledCheckIntervalKey;
extern NSString *const SULastCheckTimeKey;
extern NSString *const SUExpectsDSASignatureKey;
extern NSString *const SUPublicDSAKeyKey;
extern NSString *const SUPublicDSAKeyFileKey;
extern NSString *const SUAutomaticallyUpdateKey;
extern NSString *const SUAllowsAutomaticUpdatesKey;
extern NSString *const SUEnableAutomaticChecksKey;
extern NSString *const SUEnableAutomaticChecksKeyOld;
extern NSString *const SUEnableSystemProfilingKey;
extern NSString *const SUSendProfileInfoKey;
extern NSString *const SULastProfileSubmitDateKey;
extern NSString *const SUPromptUserOnFirstLaunchKey;
extern NSString *const SUKeepDownloadOnFailedInstallKey;
extern NSString *const SUDefaultsDomainKey;
extern NSString *const SUFixedHTMLDisplaySizeKey __attribute__((deprecated("This key is obsolete and has no effect.")));

extern NSString *const SUAppendVersionNumberKey;
extern NSString *const SUEnableAutomatedDowngradesKey;
extern NSString *const SUNormalizeInstalledApplicationNameKey;
extern NSString *const SURelaunchToolNameKey;

// -----------------------------------------------------------------------------
//	Appcast keys::
// -----------------------------------------------------------------------------

extern NSString *const SUAppcastCriticalUpdateKey;
extern NSString *const SUAppcastDeltasKey;
extern NSString *const SUAppcastDeltaFromKey;
extern NSString *const SUAppcastDSASignatureKey;
extern NSString *const SUAppcastMinimumSystemVersionKey;
extern NSString *const SUAppcastMaximumSystemVersionKey;
extern NSString *const SUAppcastReleaseNotesLinkKey;
extern NSString *const SUAppcastShortVersionStringKey;
extern NSString *const SUAppcastTagsKey;
extern NSString *const SUAppcastVersionKey;

// -----------------------------------------------------------------------------
//	Errors:
// -----------------------------------------------------------------------------

extern NSString *const SUSparkleErrorDomain;
// Appcast phase errors.
extern OSStatus SUAppcastParseError;
extern OSStatus SUNoUpdateError;
extern OSStatus SUAppcastError;
extern OSStatus SURunningFromDiskImageError;

// Downlaod phase errors.
extern OSStatus SUTemporaryDirectoryError;

// Extraction phase errors.
extern OSStatus SUUnarchivingError;
extern OSStatus SUSignatureError;

// Installation phase errors.
extern OSStatus SUFileCopyFailure;
extern OSStatus SUAuthenticationFailure;
extern OSStatus SUMissingUpdateError;
extern OSStatus SUMissingInstallerToolError;
extern OSStatus SURelaunchError;
extern OSStatus SUInstallationError;
extern OSStatus SUDowngradeError;

#endif
