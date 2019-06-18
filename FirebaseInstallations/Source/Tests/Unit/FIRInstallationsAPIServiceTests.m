/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>
#import "FBLPromise+Testing.h"
#import "FIRInstallationsItem+Tests.h"

#import "FIRInstallationsAPIService.h"
#import "FIRInstallationsErrorUtil.h"
#import "FIRInstallationsStoredAuthToken.h"

typedef FBLPromise * (^FIRInstallationsAPIServiceTask)(void);

@interface FIRInstallationsAPIService (Tests)
- (instancetype)initWithURLSession:(NSURLSession *)URLSession
                            APIKey:(NSString *)APIKey
                         projectID:(NSString *)projectID;
@end

@interface FIRInstallationsAPIServiceTests : XCTestCase
@property(nonatomic) FIRInstallationsAPIService *service;
@property(nonatomic) id mockURLSession;
@property(nonatomic) NSString *APIKey;
@property(nonatomic) NSString *projectID;
@end

@implementation FIRInstallationsAPIServiceTests

- (void)setUp {
  self.APIKey = @"api-key";
  self.projectID = @"project-id";
  self.mockURLSession = OCMClassMock([NSURLSession class]);
  self.service = [[FIRInstallationsAPIService alloc] initWithURLSession:self.mockURLSession
                                                                 APIKey:self.APIKey
                                                              projectID:self.projectID];
}

- (void)tearDown {
  self.service = nil;
  self.mockURLSession = nil;
  self.projectID = nil;
  self.APIKey = nil;
}

- (void)testRegisterInstallationSuccess {
  FIRInstallationsItem *installation = [[FIRInstallationsItem alloc] initWithAppID:@"app-id"
                                                                   firebaseAppName:@"name"];
  installation.firebaseInstallationID = [FIRInstallationsItem generateFID];

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [OCMArg checkWithBlock:^BOOL(NSURLRequest *request) {
    XCTAssertEqualObjects(request.HTTPMethod, @"POST");
    XCTAssertEqualObjects(
        request.URL.absoluteString,
        @"https://firebaseinstallations.googleapis.com/v1/projects/project-id/installations/");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Content-Type"], @"application/json");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"X-Goog-Api-Key"], self.APIKey);

    NSError *error;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody
                                                         options:0
                                                           error:&error];
    XCTAssertNotNil(body, @"Error: %@", error);

    XCTAssertEqualObjects(body[@"fid"], installation.firebaseInstallationID);
    XCTAssertEqualObjects(body[@"authVersion"], @"FIS_v2");
    XCTAssertEqualObjects(body[@"appId"], installation.appID);

    // TODO: Find out what the version should we pass and test.
    //    XCTAssertEqualObjects(body[@"sdkVersion"], @"a1.0");

    return YES;
  }];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
      .andReturn(mockDataTask);

  // 2. Call
  FBLPromise<FIRInstallationsItem *> *promise = [self.service registerInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  NSData *successResponseData =
      [self loadFixtureNamed:@"APIRegisterInstallationResponseSuccess.json"];
  taskCompletion(successResponseData, [self responseWithStatusCode:201], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertNil(promise.error);
  XCTAssertNotNil(promise.value);

  XCTAssertNotEqual(promise.value, installation);
  XCTAssertEqualObjects(promise.value.appID, installation.appID);
  XCTAssertEqualObjects(promise.value.firebaseAppName, installation.firebaseAppName);
  XCTAssertEqualObjects(promise.value.firebaseInstallationID, installation.firebaseInstallationID);
  XCTAssertEqualObjects(promise.value.refreshToken, @"aaaaaaabbbbbbbbcccccccccdddddddd00000000");
  XCTAssertEqualObjects(promise.value.authToken.token,
                        @"aaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbb.cccccccccccccccccccccccc");
  [self assertDate:promise.value.authToken.expirationDate
      isApproximatelyEqualCurrentPlusTimeInterval:604800];
}

// TODO: More tests for Register Installation API

- (void)testRefreshAuthTokenSuccess {
  FIRInstallationsItem *installation = [FIRInstallationsItem createRegisteredInstallationItem];
  installation.firebaseInstallationID = @"qwertyuiopasdfghjklzxcvbnm";

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [self refreshTokenRequestValidationArgWithInstallation:installation];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
      .andReturn(mockDataTask);

  // 1.5. Prepare server response data.
  NSData *successResponseData = [self loadFixtureNamed:@"APIGenerateTokenResponseSuccess.json"];

  // 2. Call
  FBLPromise<FIRInstallationsItem *> *promise =
      [self.service refreshAuthTokenForInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  taskCompletion(successResponseData, [self responseWithStatusCode:200], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertNil(promise.error);
  XCTAssertNotNil(promise.value);

  XCTAssertNotEqual(promise.value, installation);
  XCTAssertEqualObjects(promise.value.appID, installation.appID);
  XCTAssertEqualObjects(promise.value.firebaseAppName, installation.firebaseAppName);
  XCTAssertEqualObjects(promise.value.firebaseInstallationID, installation.firebaseInstallationID);
  XCTAssertEqualObjects(promise.value.refreshToken, installation.refreshToken);
  XCTAssertEqualObjects(promise.value.authToken.token,
                        @"aaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbb.cccccccccccccccccccccccc");
  [self assertDate:promise.value.authToken.expirationDate
      isApproximatelyEqualCurrentPlusTimeInterval:3987465];
}

- (void)testRefreshAuthTokenAPIError {
  FIRInstallationsItem *installation = [FIRInstallationsItem createRegisteredInstallationItem];
  installation.firebaseInstallationID = @"qwertyuiopasdfghjklzxcvbnm";

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [self refreshTokenRequestValidationArgWithInstallation:installation];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
      .andReturn(mockDataTask);

  // 1.5. Prepare server response data.
  NSData *errorResponseData =
      [self loadFixtureNamed:@"APIGenerateTokenResponseInvalidRefreshToken.json"];

  // 2. Call
  FBLPromise<FIRInstallationsItem *> *promise =
      [self.service refreshAuthTokenForInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  taskCompletion(errorResponseData, [self responseWithStatusCode:401], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertEqualObjects(promise.error, [FIRInstallationsErrorUtil APIErrorWithHTTPCode:401]);
  XCTAssertNil(promise.value);
}

- (void)testRefreshAuthTokenDataNil {
  FIRInstallationsItem *installation = [FIRInstallationsItem createRegisteredInstallationItem];
  installation.firebaseInstallationID = @"qwertyuiopasdfghjklzxcvbnm";

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [self refreshTokenRequestValidationArgWithInstallation:installation];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
      .andReturn(mockDataTask);

  // 2. Call
  FBLPromise<FIRInstallationsItem *> *promise =
      [self.service refreshAuthTokenForInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  // HTTP 200 but no data (a potential server failure).
  taskCompletion(nil, [self responseWithStatusCode:200], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertEqualObjects(promise.error.userInfo[NSLocalizedFailureReasonErrorKey],
                        @"Failed to serialize JSON data.");
  XCTAssertNil(promise.value);
}

- (void)testDeleteInstallationSuccess {
  FIRInstallationsItem *installation = [FIRInstallationsItem createRegisteredInstallationItem];

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [self deleteInstallationRequestValidationWithInstallation:installation];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
  .andReturn(mockDataTask);

  // 2. Call
  FBLPromise<NSNull *> *promise =
  [self.service deleteInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  // HTTP 200 but no data (a potential server failure).
  NSData *successResponseData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
  taskCompletion(successResponseData, [self responseWithStatusCode:200], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertNil(promise.error);
  XCTAssertTrue(promise.isFulfilled);
}

- (void)testDeleteInstallationErrorNotFound {
  FIRInstallationsItem *installation = [FIRInstallationsItem createRegisteredInstallationItem];

  // 1. Stub URL session:

  // 1.1. URL request validation.
  id URLRequestValidation = [self deleteInstallationRequestValidationWithInstallation:installation];

  // 1.2. Capture completion to call it later.
  __block void (^taskCompletion)(NSData *, NSURLResponse *, NSError *);
  id completionArg = [OCMArg checkWithBlock:^BOOL(id obj) {
    taskCompletion = obj;
    return YES;
  }];

  // 1.3. Create a data task mock.
  id mockDataTask = OCMClassMock([NSURLSessionDataTask class]);
  OCMExpect([mockDataTask resume]);

  // 1.4. Expect `dataTaskWithRequest` to be called.
  OCMExpect([self.mockURLSession dataTaskWithRequest:URLRequestValidation
                                   completionHandler:completionArg])
  .andReturn(mockDataTask);

  // 2. Call
  FBLPromise<NSNull *> *promise =
  [self.service deleteInstallation:installation];

  // 3. Wait for `[NSURLSession dataTaskWithRequest...]` to be called
  OCMVerifyAllWithDelay(self.mockURLSession, 0.5);

  // 4. Wait for the data task `resume` to be called.
  OCMVerifyAllWithDelay(mockDataTask, 0.5);

  // 5. Call the data task completion.
  // HTTP 200 but no data (a potential server failure).
  taskCompletion(nil, [self responseWithStatusCode:404], nil);

  // 6. Check result.
  FBLWaitForPromisesWithTimeout(0.5);

  XCTAssertEqualObjects(promise.error, [FIRInstallationsErrorUtil APIErrorWithHTTPCode:404]);
  XCTAssertNil(promise.value);
}

#pragma mark - Helpers

- (NSData *)loadFixtureNamed:(NSString *)fileName {
  NSURL *fileURL = [[NSBundle bundleForClass:[self class]] URLForResource:fileName
                                                            withExtension:nil];
  XCTAssertNotNil(fileURL);

  NSError *error;
  NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:&error];
  XCTAssertNotNil(data, @"File name: %@ Error: %@", fileName, error);

  return data;
}

- (NSURLResponse *)responseWithStatusCode:(NSUInteger)statusCode {
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL fileURLWithPath:@"/"]
                                                            statusCode:statusCode
                                                           HTTPVersion:nil
                                                          headerFields:nil];
  return response;
}

- (void)assertDate:(NSDate *)date
    isApproximatelyEqualCurrentPlusTimeInterval:(NSTimeInterval)timeInterval {
  NSDate *expectedDate = [NSDate dateWithTimeIntervalSinceNow:timeInterval];

  NSTimeInterval precision = 10;
  XCTAssert(ABS([date timeIntervalSinceDate:expectedDate]) <= precision,
            @"date: %@ is not equal to expected %@ with precision %f - %@", date, expectedDate,
            precision, self.name);
}

- (id)refreshTokenRequestValidationArgWithInstallation:(FIRInstallationsItem *)installation {
  return [OCMArg checkWithBlock:^BOOL(NSURLRequest *request) {
    XCTAssertEqualObjects(request.HTTPMethod, @"POST");
    XCTAssertEqualObjects(request.URL.absoluteString,
                          @"https://firebaseinstallations.googleapis.com/v1/projects/project-id/"
                          @"installations/qwertyuiopasdfghjklzxcvbnm/authTokens:generate");
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"Content-Type"], @"application/json",
                          @"%@", self.name);
    XCTAssertEqualObjects([request valueForHTTPHeaderField:@"X-Goog-Api-Key"], self.APIKey, @"%@",
                          self.name);

    NSError *error;
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody
                                                         options:0
                                                           error:&error];
    XCTAssertNotNil(body, @"Error: %@, test: %@", error, self.name);

    // TODO: Find out what the version should we pass and test.
    XCTAssertEqualObjects(body, @{@"installation" : @{@"sdkVersion" : @"a1.0"}}, @"%@", self.name);

    return YES;
  }];
}

- (id)deleteInstallationRequestValidationWithInstallation:(FIRInstallationsItem *)installation {
  return [OCMArg checkWithBlock:^BOOL(NSURLRequest *request) {
    XCTAssert([request isKindOfClass:[NSURLRequest class]], @"Unexpected class: %@", [request class]);
    XCTAssertEqualObjects(request.HTTPMethod, @"DELETE");
    NSString *expectedURL = [NSString stringWithFormat:@"https://firebaseinstallations.googleapis.com/v1/projects/%@/installations/%@/", self.projectID, installation.firebaseInstallationID];
    XCTAssertEqualObjects(request.URL.absoluteString, expectedURL);
    XCTAssertEqualObjects(request.allHTTPHeaderFields[@"Content-Type"], @"application/json");
    XCTAssertEqualObjects(request.allHTTPHeaderFields[@"X-Goog-Api-Key"], self.APIKey);

    NSError *error;
    NSDictionary *JSONBody = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:&error];
    XCTAssertNotNil(JSONBody, @"Error: %@", error);
    XCTAssertEqualObjects(JSONBody, @{});

    return YES;
  }];
}

@end