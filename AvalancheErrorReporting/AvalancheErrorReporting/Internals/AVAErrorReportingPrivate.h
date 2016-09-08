/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 */

#import "AVAErrorReporting.h"
#import "AVAFeatureInternal.h"
#import <CrashReporter/CrashReporter.h>

@class AVAPLCrashReporter;

@interface AVAErrorReporting () <AVAFeatureInternal>

/**
 * Prototype of a callback function used to execute additional user code. Called
 * upon completion of crash
 * handling, after the crash report has been written to disk.
 *
 * @param context The API client's supplied context value.
 *
 * @see `AVAErrorReportingCallbacks`
 * @see `[AVAErrorReporting setCrashCallbacks:]`
 */
typedef void (*AVAErrorReportingPostCrashSignalCallback)(void *context);

/**
 * This structure contains callbacks supported by `AVAErrorReporting` to allow the host
 * application to perform
 * additional tasks prior to program termination after a crash has occurred.
 *
 * @see `AVAErrorReportingPostCrashSignalCallback`
 * @see `[AVAErrorReporting setCrashCallbacks:]`
 */
typedef struct AVAErrorReportingCallbacks {

  /** An arbitrary user-supplied context value. This value may be NULL. */
  void *context;

  /**
   * The callback used to report caught signal information.
   */
  AVAErrorReportingPostCrashSignalCallback handleSignal;
} AVAErrorReportingCallbacks;

/**
 * A list containing all crash files that currently stored on disk for this app.
 */
@property(nonatomic, copy) NSMutableArray *crashFiles;

/**
 * The directory where all crash reports are stored.
 */
@property(nonatomic, copy) NSString *crashesDir;

/**
 * A file used to indicate that a crash which occured in the last session is
 * currently written to disk.
 */
@property(nonatomic, copy) NSString *analyzerInProgressFile;

/**
 * The `PLCrashReporter` instance used for crash detection.
 */
@property(nonatomic, strong) AVAPLCrashReporter *plCrashReporter;

/**
 * A `NSFileManager` instance used for reading and writing crash reports.
 */
@property(nonatomic, strong) NSFileManager *fileManager;

/**
 * The exception handler used by the crashes module.
 */
@property(nonatomic) NSUncaughtExceptionHandler *exceptionHandler;

/**
 * A flag that indicates that crashes are currently sent to the backend.
 */
@property(nonatomic) BOOL sendingInProgress;

/**
 * The time of initialization, required to calculate offset for crashtime.
 */
@property(nonatomic, readonly) NSDate *initializationDate;

@end