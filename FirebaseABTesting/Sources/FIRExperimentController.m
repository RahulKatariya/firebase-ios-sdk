// Copyright 2019 Google
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <FirebaseABTesting/FIRExperimentController.h>

#import <FirebaseABTesting/FIRLifecycleEvents.h>
#import <FirebaseCore/FIRLogger.h>
#import "FirebaseABTesting/Sources/ABTConditionalUserPropertyController.h"
#import "FirebaseABTesting/Sources/ABTConstants.h"

#import <FirebaseAnalyticsInterop/FIRAnalyticsInterop.h>
#import <FirebaseCore/FIRAppInternal.h>
#import <FirebaseCore/FIRComponent.h>
#import <FirebaseCore/FIRComponentContainer.h>
#import <FirebaseCore/FIRDependency.h>
#import <FirebaseCore/FIRLibrary.h>

#ifndef FIRABTesting_VERSION
#error "FIRABTesting_VERSION is not defined: \
add -DFIRABTesting_VERSION=... to the build invocation"
#endif

// The following two macros supply the incantation so that the C
// preprocessor does not try to parse the version as a floating
// point number. See
// https://www.guyrutenberg.com/2008/12/20/expanding-macros-into-string-constants-in-c/
#define STR(x) STR_EXPAND(x)
#define STR_EXPAND(x) #x

/// Default experiment overflow policy.
const ABTExperimentPayload_ExperimentOverflowPolicy FIRDefaultExperimentOverflowPolicy =
    ABTExperimentPayload_ExperimentOverflowPolicy_DiscardOldest;

/// Deserialize the experiment payloads.
ABTExperimentPayload *ABTDeserializeExperimentPayload(NSData *payload) {
  NSError *error;
  ABTExperimentPayload *experimentPayload = [ABTExperimentPayload parseFromData:payload
                                                                          error:&error];
  if (error) {
    FIRLogError(kFIRLoggerABTesting, @"I-ABT000001", @"Failed to parse experiment payload: %@",
                error.debugDescription);
  }
  return experimentPayload;
}

/// Returns a list of experiments to be set given the payloads and current list of experiments from
/// Firebase Analytics. If an experiment is in payloads but not in experiments, it should be set to
/// Firebase Analytics.
NSArray<ABTExperimentPayload *> *ABTExperimentsToSetFromPayloads(
    NSArray<NSData *> *payloads,
    NSArray<NSDictionary<NSString *, NSString *> *> *experiments,
    id<FIRAnalyticsInterop> _Nullable analytics) {
  NSArray<NSData *> *payloadsCopy = [payloads copy];
  NSArray *experimentsCopy = [experiments copy];
  NSMutableArray *experimentsToSet = [[NSMutableArray alloc] init];
  ABTConditionalUserPropertyController *controller =
      [ABTConditionalUserPropertyController sharedInstanceWithAnalytics:analytics];

  // Check if the experiment is in payloads but not in experiments.
  for (NSData *payload in payloadsCopy) {
    ABTExperimentPayload *experimentPayload = ABTDeserializeExperimentPayload(payload);
    if (!experimentPayload) {
      FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000002",
                 @"Either payload is not set or it cannot be deserialized.");
      continue;
    }

    BOOL isExperimentSet = NO;
    for (id experiment in experimentsCopy) {
      if ([controller isExperiment:experiment theSameAsPayload:experimentPayload]) {
        isExperimentSet = YES;
        break;
      }
    }

    if (!isExperimentSet) {
      [experimentsToSet addObject:experimentPayload];
    }
  }
  return [experimentsToSet copy];
}

/// Returns a list of experiments to be clearred given the payloads and current list of
/// experiments from Firebase Analytics. If an experiment is in experiments but not in payloads, it
/// should be clearred in Firebase Analytics.
NSArray *ABTExperimentsToClearFromPayloads(
    NSArray<NSData *> *payloads,
    NSArray<NSDictionary<NSString *, NSString *> *> *experiments,
    id<FIRAnalyticsInterop> _Nullable analytics) {
  NSMutableArray *experimentsToClear = [[NSMutableArray alloc] init];
  ABTConditionalUserPropertyController *controller =
      [ABTConditionalUserPropertyController sharedInstanceWithAnalytics:analytics];

  // Check if the experiment is in experiments but not payloads.
  for (id experiment in experiments) {
    BOOL doesExperimentNoLongerExist = YES;
    for (NSData *payload in payloads) {
      ABTExperimentPayload *experimentPayload = ABTDeserializeExperimentPayload(payload);
      if (!experimentPayload) {
        FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000002",
                   @"Either payload is not set or it cannot be deserialized.");
        continue;
      }

      if ([controller isExperiment:experiment theSameAsPayload:experimentPayload]) {
        doesExperimentNoLongerExist = NO;
      }
    }
    if (doesExperimentNoLongerExist) {
      [experimentsToClear addObject:experiment];
    }
  }
  return experimentsToClear;
}

// ABT doesn't provide any functionality to other components,
// so it provides a private, empty protocol that it conforms to and use it for registration.

@protocol FIRABTInstanceProvider
@end

@interface FIRExperimentController () <FIRABTInstanceProvider, FIRLibrary>
@property(nonatomic, readwrite, strong) id<FIRAnalyticsInterop> _Nullable analytics;
@end

@implementation FIRExperimentController

+ (void)load {
  [FIRApp registerInternalLibrary:(Class<FIRLibrary>)self
                         withName:@"fire-abt"
                      withVersion:[NSString stringWithUTF8String:STR(FIRABTesting_VERSION)]];
}

+ (nonnull NSArray<FIRComponent *> *)componentsToRegister {
  FIRDependency *analyticsDep = [FIRDependency dependencyWithProtocol:@protocol(FIRAnalyticsInterop)
                                                           isRequired:NO];
  FIRComponentCreationBlock creationBlock =
      ^id _Nullable(FIRComponentContainer *container, BOOL *isCacheable) {
    // Ensure it's cached so it returns the same instance every time ABTesting is called.
    *isCacheable = YES;
    id<FIRAnalyticsInterop> analytics = FIR_COMPONENT(FIRAnalyticsInterop, container);
    return [[FIRExperimentController alloc] initWithAnalytics:analytics];
  };
  FIRComponent *abtProvider = [FIRComponent componentWithProtocol:@protocol(FIRABTInstanceProvider)
                                              instantiationTiming:FIRInstantiationTimingLazy
                                                     dependencies:@[ analyticsDep ]
                                                    creationBlock:creationBlock];

  return @[ abtProvider ];
}

- (instancetype)initWithAnalytics:(nullable id<FIRAnalyticsInterop>)analytics {
  self = [super init];
  if (self != nil) {
    _analytics = analytics;
  }
  return self;
}

+ (FIRExperimentController *)sharedInstance {
  FIRApp *defaultApp = [FIRApp defaultApp];  // Missing configure will be logged here.
  id<FIRABTInstanceProvider> instance = FIR_COMPONENT(FIRABTInstanceProvider, defaultApp.container);

  // We know the instance coming from the container is a FIRExperimentController instance, cast it.
  return (FIRExperimentController *)instance;
}

- (void)updateExperimentsWithServiceOrigin:(NSString *)origin
                                    events:(FIRLifecycleEvents *)events
                                    policy:(ABTExperimentPayload_ExperimentOverflowPolicy)policy
                             lastStartTime:(NSTimeInterval)lastStartTime
                                  payloads:(NSArray<NSData *> *)payloads {
  FIRExperimentController *__weak weakSelf = self;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
    FIRExperimentController *strongSelf = weakSelf;
    [strongSelf updateExperimentsInBackgroundQueueWithServiceOrigin:origin
                                                             events:events
                                                             policy:policy
                                                      lastStartTime:lastStartTime
                                                           payloads:payloads];
  });
}

- (void)
    updateExperimentsInBackgroundQueueWithServiceOrigin:(NSString *)origin
                                                 events:(FIRLifecycleEvents *)events
                                                 policy:
                                                     (ABTExperimentPayload_ExperimentOverflowPolicy)
                                                         policy
                                          lastStartTime:(NSTimeInterval)lastStartTime
                                               payloads:(NSArray<NSData *> *)payloads {
  ABTConditionalUserPropertyController *controller =
      [ABTConditionalUserPropertyController sharedInstanceWithAnalytics:_analytics];

  // Get the list of expriments from Firebase Analytics.
  NSArray *experiments = [controller experimentsWithOrigin:origin];
  if (!experiments) {
    FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000003",
               @"Failed to get conditional user properties from Firebase Analytics.");
    return;
  }
  NSArray<ABTExperimentPayload *> *experimentsToSet =
      ABTExperimentsToSetFromPayloads(payloads, experiments, _analytics);
  NSArray<NSDictionary<NSString *, NSString *> *> *experimentsToClear =
      ABTExperimentsToClearFromPayloads(payloads, experiments, _analytics);

  for (id experiment in experimentsToClear) {
    NSString *experimentID = [controller experimentIDOfExperiment:experiment];
    NSString *variantID = [controller variantIDOfExperiment:experiment];
    [controller clearExperiment:experimentID
                      variantID:variantID
                     withOrigin:origin
                        payload:nil
                         events:events];
  }

  for (ABTExperimentPayload *experimentPayload in experimentsToSet) {
    if (experimentPayload.experimentStartTimeMillis > lastStartTime * ABT_MSEC_PER_SEC) {
      [controller setExperimentWithOrigin:origin
                                  payload:experimentPayload
                                   events:events
                                   policy:policy];
      FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000008",
                 @"Set Experiment ID %@, variant ID %@ to Firebase Analytics.",
                 experimentPayload.experimentId, experimentPayload.variantId);

    } else {
      FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000009",
                 @"Not setting experiment ID %@, variant ID %@ due to the last update time %lld.",
                 experimentPayload.experimentId, experimentPayload.variantId,
                 (long)lastStartTime * ABT_MSEC_PER_SEC);
    }
  }
}

- (NSTimeInterval)latestExperimentStartTimestampBetweenTimestamp:(NSTimeInterval)timestamp
                                                     andPayloads:(NSArray<NSData *> *)payloads {
  for (NSData *payload in payloads) {
    ABTExperimentPayload *experimentPayload = ABTDeserializeExperimentPayload(payload);
    if (!experimentPayload) {
      FIRLogInfo(kFIRLoggerABTesting, @"I-ABT000002",
                 @"Either payload is not set or it cannot be deserialized.");
      continue;
    }
    if (experimentPayload.experimentStartTimeMillis > timestamp * ABT_MSEC_PER_SEC) {
      timestamp = (double)(experimentPayload.experimentStartTimeMillis / ABT_MSEC_PER_SEC);
    }
  }
  return timestamp;
}
@end
