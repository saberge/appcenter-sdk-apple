// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSPushAppDelegate.h"
#import "MSACAppDelegateForwarder.h"
#import "MSPush.h"

@implementation MSPushAppDelegate

#pragma mark - MSACAppDelegate

- (void)application:(__attribute__((unused))MSACApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  [MSPush didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(__attribute__((unused))MSACApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  [MSPush didFailToRegisterForRemoteNotificationsWithError:error];
}

// Callback for macOS + workaround for iOS 10 bug. See
// https://forums.developer.apple.com/thread/54332
- (void)application:(__attribute__((unused))MSACApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
  [MSPush didReceiveRemoteNotification:userInfo];
}

#if !TARGET_OS_OSX

- (void)application:(__attribute__((unused))UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
  BOOL result = [MSPush didReceiveRemoteNotification:userInfo];
  if (result) {
    completionHandler(UIBackgroundFetchResultNewData);
  } else {
    completionHandler(UIBackgroundFetchResultNoData);
  }
}

#endif

@end

#pragma mark - Forwarding

@implementation MSACAppDelegateForwarder (MSPush)

+ (void)load {

  // Register selectors to swizzle for Push.
  [[MSACAppDelegateForwarder sharedInstance] addDelegateSelectorToSwizzle:@selector(application:
                                                                            didRegisterForRemoteNotificationsWithDeviceToken:)];
  [[MSACAppDelegateForwarder sharedInstance] addDelegateSelectorToSwizzle:@selector(application:
                                                                            didFailToRegisterForRemoteNotificationsWithError:)];
  [[MSACAppDelegateForwarder sharedInstance] addDelegateSelectorToSwizzle:@selector(application:didReceiveRemoteNotification:)];
#if !TARGET_OS_OSX
  [[MSACAppDelegateForwarder sharedInstance] addDelegateSelectorToSwizzle:@selector(application:
                                                                            didReceiveRemoteNotification:fetchCompletionHandler:)];
#endif
}

- (void)custom_application:(MSACApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  IMP originalImp = NULL;

  // Forward to the original delegate.
  [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
  if (originalImp) {
    ((void (*)(id, SEL, MSACApplication *, NSData *))originalImp)(self, _cmd, application, deviceToken);
  }

  // Forward to custom delegates.
  [[MSACAppDelegateForwarder sharedInstance] application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)custom_application:(MSACApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  IMP originalImp = NULL;

  // Forward to the original delegate.
  [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
  if (originalImp) {
    ((void (*)(id, SEL, MSACApplication *, NSError *))originalImp)(self, _cmd, application, error);
  }

  // Forward to custom delegates.
  [[MSACAppDelegateForwarder sharedInstance] application:application didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)custom_application:(MSACApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
  IMP originalImp = NULL;

  // Forward to the original delegate.
  [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
  if (originalImp) {
    ((void (*)(id, SEL, MSACApplication *, NSDictionary *))originalImp)(self, _cmd, application, userInfo);
  }

  // Forward to custom delegates.
  [[MSACAppDelegateForwarder sharedInstance] application:application didReceiveRemoteNotification:userInfo];
}

#if !TARGET_OS_OSX

- (void)custom_application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
  __block IMP originalImp = NULL;
  __block UIBackgroundFetchResult actualFetchResult = UIBackgroundFetchResultNoData;
  __block short customHandlerCalledCount = 0;
  __block short customDelegateToCallCount = 0;
  __block MSACCompletionExecutor executors = MSACCompletionExecutorNone;

  // This handler will be used by all the delegates, it unifies the results and execute the real handler at the end.
  void (^commonCompletionHandler)(UIBackgroundFetchResult, MSACCompletionExecutor) =
      ^(UIBackgroundFetchResult fetchResult, MSACCompletionExecutor executor) {
        /*
         * As per the Apple documentation:
         * https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623013-application
         * The `fetchCompletionHandler` is used to let the app the background time for processing the notification and download any data
         * that will be displayed to the end users when the app will start again. There can only be one `UIBackgroundFetchResult` in the end
         * so there is a need for triage while comparing results from delegates.
         *
         * Priorities are: `UIBackgroundFetchResultNewData`>`UIBackgroundFetchResultFailed`>`UIBackgroundFetchResultNoData`. -
         * `UIBackgroundFetchResultNewData` means at least one of the delegates did download something successfully. -
         * `UIBackgroundFetchResultFailed` means there was one/several downloads among the delegates but they failed. -
         * `UIBackgroundFetchResultNoData` means that none of the delegates had anything to download.
         */
        if (fetchResult == UIBackgroundFetchResultNewData || actualFetchResult == UIBackgroundFetchResultNoData) {
          actualFetchResult = fetchResult;
        }

        // This executor is running its completion handler, remembering it.
        executors = executors | executor;

        // Count all custom executors who already ran their completion handler.
        if (executor == MSACCompletionExecutorCustom) {
          customHandlerCalledCount++;
        }

        // Be sure original delegate and/or custom delegates and/or the app forwarder executed their completion handler.
        if ((executor == MSACCompletionExecutorForwarder) ||
            (customHandlerCalledCount == customDelegateToCallCount && (executors & MSACCompletionExecutorOriginal || !originalImp))) {
          completionHandler(actualFetchResult);
        }
      };

  // Completion handler dedicated to custom delegates.
  id customCompletionHandler = ^(UIBackgroundFetchResult fetchResult) {
    commonCompletionHandler(fetchResult, MSACCompletionExecutorCustom);
  };

  // Block any addition/deletion of custom delegates since delegate count must remain the same.
  @synchronized([MSACAppDelegateForwarder class]) {

    // Count how many custom delegates will respond to the selector.
    for (id<MSACCustomApplicationDelegate> delegate in [MSACAppDelegateForwarder sharedInstance].delegates) {
      if ([delegate respondsToSelector:_cmd]) {
        customDelegateToCallCount++;
      }
    }

    // Forward to the original delegate.
    [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
    if (originalImp) {

      // Completion handler dedicated to the original delegate.
      id originalCompletionHandler = ^(UIBackgroundFetchResult fetchResult) {
        commonCompletionHandler(fetchResult, MSACCompletionExecutorOriginal);
      };
      ((void (*)(id, SEL, UIApplication *, NSDictionary *, void (^)(UIBackgroundFetchResult)))originalImp)(
          self, _cmd, application, userInfo, originalCompletionHandler);
    } else if (customDelegateToCallCount == 0) {

      // There is no one to handle this selector but iOS requires to call the completion handler anyway.
      commonCompletionHandler(UIBackgroundFetchResultNoData, MSACCompletionExecutorForwarder);
      return;
    }

    // Forward to custom delegates.
    [[MSACAppDelegateForwarder sharedInstance] application:application
                            didReceiveRemoteNotification:userInfo
                                  fetchCompletionHandler:customCompletionHandler];
  }
}

#endif

@end
