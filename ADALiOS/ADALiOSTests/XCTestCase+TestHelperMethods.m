// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.

#import "../ADALiOS/ADALiOS.h"
#import "../ADALiOS/ADLogger.h"
#import "../ADALiOS/NSString+ADHelperMethods.h"
#import "../ADALiOS/ADErrorCodes.h"
#import "XCTestCase+TestHelperMethods.h"
#import "../ADALiOS/ADAuthenticationContext.h"
#import "../ADALioS/ADAuthenticationSettings.h"
#import <libkern/OSAtomic.h>
#import <Foundation/NSObjCRuntime.h>
#import <objc/runtime.h>


@implementation XCTestCase (TestHelperMethods)

//Tracks the logged messages.
NSString* const sTestBegin = @"|||TEST_BEGIN|||";
NSString* const sTestEnd = @"|||TEST_END|||";

NSString* const sIdTokenClaims = @"{\"aud\":\"c3c7f5e5-7153-44d4-90e6-329686d48d76\",\"iss\":\"https://sts.windows.net/6fd1f5cd-a94c-4335-889b-6c598e6d8048/\",\"iat\":1387224169,\"nbf\":1387224170,\"exp\":1387227769,\"ver\":\"1.0\",\"tid\":\"6fd1f5cd-a94c-4335-889b-6c598e6d8048\",\"oid\":\"53c6acf2-2742-4538-918d-e78257ec8516\",\"upn\":\"boris@MSOpenTechBV.onmicrosoft.com\",\"unique_name\":\"boris@MSOpenTechBV.onmicrosoft.com\",\"sub\":\"0DxnAlLi12IvGL_dG3dDMk3zp6AQHnjgogyim5AWpSc\",\"family_name\":\"Vidolovv\",\"given_name\":\"Boriss\",\"altsecid\":\"Some Guest id\",\"idp\":\"Fake IDP\",\"email\":\"fake e-mail\"}";
NSString* const sIDTokenHeader = @"{\"typ\":\"JWT\",\"alg\":\"none\"}";

volatile int sAsyncExecuted;//The number of asynchronous callbacks executed.

/* See header for details.*/
-(void) adValidateFactoryForInvalidArgument: (NSString*) argument
                             returnedObject: (id) returnedObject
                                      error: (ADAuthenticationError*) error
{
    XCTAssertNil(returnedObject, "Creator should have returned nil. Object: %@", returnedObject);
    
    //[self adValidateForInvalidArgument:argument error:error];
}
#ifdef AD_CODE_COVERAGE
extern void __gcov_flush(void);
#endif
-(void) adFlushCodeCoverage
{
#ifdef AD_CODE_COVERAGE
    __gcov_flush();
#endif
}

//Creates an new item with all of the properties having correct
//values
- (ADTokenCacheStoreItem*)adCreateCacheItem
{
    ADTokenCacheStoreItem* item = [[ADTokenCacheStoreItem alloc] init];
    //item.resource = @"resource";
    item.scopes = [NSSet setWithObjects:@"mail.read", @"planetarydefense.target.acquire", @"planetarydefense.fire", nil];
    item.authority = @"https://login.windows.net/sometenant.com";
    item.clientId = @"client id";
    item.accessToken = @"access token";
    item.refreshToken = @"refresh token";
    item.sessionKey = nil;
    //1hr into the future:
    item.expiresOn = [NSDate dateWithTimeIntervalSinceNow:3600];
    item.userInformation = [self adCreateUserInformation];
    item.accessTokenType = @"access token type";
    
    [self adVerifyPropertiesAreSet:item];
    
    return item;
}

- (ADUserInformation*)adCreateUserInformation
{
    ADAuthenticationError* error = nil;
    //This one sets the "userId" property:
    NSString* id_token = [NSString stringWithFormat:@"%@.%@.",
                          [sIDTokenHeader adBase64UrlEncode],
                          [sIdTokenClaims adBase64UrlEncode]];
    ADUserInformation* userInfo = [ADUserInformation userInformationWithIdToken:id_token error:&error];
    ADAssertNoError;
    XCTAssertNotNil(userInfo, "Nil user info returned.");
    
    //Check the standard properties:
    XCTAssertEqualObjects(userInfo.userId, @"boris@msopentechbv.onmicrosoft.com");
    XCTAssertEqualObjects(userInfo.givenName, @"Boriss");
    XCTAssertEqualObjects(userInfo.familyName, @"Vidolovv");
    XCTAssertEqualObjects(userInfo.subject, @"0DxnAlLi12IvGL_dG3dDMk3zp6AQHnjgogyim5AWpSc");
    XCTAssertEqualObjects(userInfo.tenantId, @"6fd1f5cd-a94c-4335-889b-6c598e6d8048");
    XCTAssertEqualObjects(userInfo.upn, @"boris@MSOpenTechBV.onmicrosoft.com");
    XCTAssertEqualObjects(userInfo.uniqueName, @"boris@MSOpenTechBV.onmicrosoft.com");
    XCTAssertEqualObjects(userInfo.eMail, @"fake e-mail");
    XCTAssertEqualObjects(userInfo.identityProvider, @"Fake IDP");
    XCTAssertEqualObjects(userInfo.userObjectId, @"53c6acf2-2742-4538-918d-e78257ec8516");
    XCTAssertEqualObjects(userInfo.guestId, @"Some Guest id");
    
    //Check unmapped claims:
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"aud"], @"c3c7f5e5-7153-44d4-90e6-329686d48d76");
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"iss"], @"https://sts.windows.net/6fd1f5cd-a94c-4335-889b-6c598e6d8048/");
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"iat"], [NSNumber numberWithLong:1387224169]);
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"nbf"], [NSNumber numberWithLong:1387224170]);
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"exp"], [NSNumber numberWithLong:1387227769]);
    XCTAssertEqualObjects([userInfo.allClaims objectForKey:@"ver"], @"1.0");
    
    //This will check absolutely all properties, so that if we add a new one later
    //it will fail if it is not set:
    [self adVerifyPropertiesAreSet:userInfo];
    
    return userInfo;
}

-(void) adVerifyPropertiesAreSet: (NSObject*) object
{
    if (!object)
    {
        XCTFail("object must be set.");
        return;//Return to avoid crashing below
    }
    
    //Add here calculated properties that cannot be initialized and shouldn't be checked for initialization:
    NSDictionary* const exceptionProperties = @{
                                                NSStringFromClass([ADTokenCacheStoreItem class]):[NSSet setWithObjects:@"multiResourceRefreshToken",
                                                                                                  @"sessionKey",nil], };
    
    //Enumerate all properties and ensure that they are set to non-default values:
    unsigned int propertyCount;
    objc_property_t* properties = class_copyPropertyList([object class], &propertyCount);
    
    for (int i = 0; i < propertyCount; ++i)
    {
        NSString* propertyName = [NSString stringWithCString:property_getName(properties[i])
                                                    encoding:NSUTF8StringEncoding];
        NSSet* exceptions = [exceptionProperties valueForKey:NSStringFromClass([object class])];//May be nil
        if ([exceptions containsObject:propertyName])
        {
            continue;//Respect the exception
        }
        
        id value = [object valueForKey:propertyName];
        if ([value isKindOfClass:[NSNumber class]])
        {
            //Cast to the scalar to double and ensure it is far from 0 (default)
            
            double dValue = [(NSNumber*)value doubleValue];
            if (fabs(dValue) < 0.0001)
            {
                XCTFail("The value of the property %@ is 0. Please update the initialization method to set it.", propertyName);
            }
        }
        else //Not a scalar type, we can compare to nil:
        {
            XCTAssertNotNil(value, "The value of the property %@ is nil. Please update the initialization method to set it.", propertyName);
        }
    }
}

-(void) adCallAndWaitWithFile: (NSString*) file
                         line: (int) line
                    semaphore: (dispatch_semaphore_t)sem
                        block: (void (^)(void)) block
{
    THROW_ON_NIL_ARGUMENT(sem);
    THROW_ON_NIL_EMPTY_ARGUMENT(file);
    THROW_ON_NIL_ARGUMENT(block);
    
    block();//Run the intended asynchronous method
    while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW))
    {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

@end
