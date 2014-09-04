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

#import "ADPkeyAuthHelper.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "RegistrationInformation.h"
#import "NSString+ADHelperMethods.h"
#import "WorkPlaceJoin.h"
#import "OpenSSLHelper.h"
#import "ADLogger.h"
#import "ADErrorCodes.h"

@implementation ADPkeyAuthHelper

+ (NSString*) createDeviceAuthResponse:(NSString*) authorizationServer
                         challengeData:(NSDictionary*) challengeData
{
    RegistrationInformation *info = [[WorkPlaceJoin WorkPlaceJoinManager] getRegistrationInformation];
    NSString* authHeaderTemplate = @"PKeyAuth %@ Context=\"%@\", Version=\"%@\"";
    NSString* pKeyAuthHeader = @"";
    
    NSString* certAuths = [challengeData valueForKey:@"CertAuthorities"];
    certAuths = [[certAuths adUrlFormDecode] stringByReplacingOccurrencesOfString:@" "
                                                                       withString:@""];
    NSMutableSet* certIssuer = [OpenSSLHelper getCertificateIssuer:[info certificateData]];
    
    if([info isWorkPlaceJoined] && [self isValidIssuer:certAuths keychainCertIssuer:certIssuer]){
        pKeyAuthHeader = [NSString stringWithFormat:@"AuthToken=\"%@\",", [ADPkeyAuthHelper createDeviceAuthResponse:authorizationServer nonce:[challengeData valueForKey:@"nonce"] identity:info]];
    }
    
    [info releaseData];
    info = nil;
    return [NSString stringWithFormat:authHeaderTemplate, pKeyAuthHeader,[challengeData valueForKey:@"Context"],  [challengeData valueForKey:@"Version"]];
}

+ (BOOL) isValidIssuer:(NSString*) certAuths
    keychainCertIssuer:(NSMutableSet*) keychainCertIssuer{
    
    NSArray * acceptedCerts = [certAuths componentsSeparatedByString:@";"];
    BOOL isMatch = TRUE;
    for (int i=0; i<[acceptedCerts count]; i++) {
        isMatch = TRUE;
        NSArray * keyPair = [[acceptedCerts objectAtIndex:i] componentsSeparatedByString:@","];
        for(int index=0;index<[keyPair count]; index++){
            if(![keychainCertIssuer containsObject:[keyPair objectAtIndex:index]]){
                isMatch = false;
                break;
            }
        }
        if(isMatch) return isMatch;
    }
    return isMatch;
}

+ (NSString *) createDeviceAuthResponse:(NSString*) audience
                                  nonce:(NSString*) nonce
                               identity:(RegistrationInformation *) identity{

    NSArray *arrayOfStrings = @[[NSString stringWithFormat:@"%@", [[identity certificateData] base64EncodedStringWithOptions:0]]];
    NSDictionary *header = @{
                             @"alg" : @"RS256",
                             @"typ" : @"JWT",
                             @"x5c" : arrayOfStrings
                             };
    
    NSDictionary *payload = @{
                              @"aud" : audience,
                              @"nonce" : nonce,
                              @"iat" : [NSString stringWithFormat:@"%d", (CC_LONG)[[NSDate date] timeIntervalSince1970]]
                              };
    
    NSString* signingInput = [NSString stringWithFormat:@"%@.%@", [[self createJSONFromDictionary:header] adBase64UrlEncode], [[self createJSONFromDictionary:payload] adBase64UrlEncode]];
    NSData* signedData = [self sign:[identity privateKey] data:[signingInput dataUsingEncoding:NSUTF8StringEncoding]];
    NSString* signedEncodedDataString = [NSString Base64EncodeData: signedData];
    
    return [NSString stringWithFormat:@"%@.%@", signingInput, signedEncodedDataString];
}

+(NSData *) sign: (SecKeyRef) privateKey
            data:(NSData *) plainData
{
    NSData* signedHash = nil;
    size_t signedHashBytesSize = SecKeyGetBlockSize(privateKey);
    uint8_t* signedHashBytes = malloc(signedHashBytesSize);
    memset(signedHashBytes, 0x0, signedHashBytesSize);
    
    size_t hashBytesSize = CC_SHA256_DIGEST_LENGTH;
    uint8_t* hashBytes = malloc(hashBytesSize);
    if (!CC_SHA256([plainData bytes], (CC_LONG)[plainData length], hashBytes)) {
        [ADLogger log:ADAL_LOG_LEVEL_ERROR message:@"Could not compute SHA265 hash." errorCode:AD_ERROR_UNEXPECTED additionalInformation:nil ];
        if (hashBytes)
            free(hashBytes);
        if (signedHashBytes)
            free(signedHashBytes);
        return nil;
    }
    
#if TARGET_OS_IPHONE
    OSStatus status = SecKeyRawSign(privateKey,
                                    kSecPaddingPKCS1SHA256,
                                    hashBytes,
                                    hashBytesSize,
                                    signedHashBytes,
                                    &signedHashBytesSize);
    
    [ADLogger log:ADAL_LOG_LEVEL_INFO message:@"Status returned from data signing - " errorCode:status additionalInformation:nil ];
    signedHash = [NSData dataWithBytes:signedHashBytes
                                        length:(NSUInteger)signedHashBytesSize];
    
    if (hashBytes) {
        free(hashBytes);
    }
    
    if (signedHashBytes) {
        free(signedHashBytes);
    }
    
#else
    
    CFErrorRef error = nil;
    SecTransformRef signingTransform = SecSignTransformCreate(privateKey, &error);
    if (signingTransform == NULL)
        return NULL;
    
    Boolean success = SecTransformSetAttribute(signingTransform, kSecDigestTypeAttribute, kSecDigestSHA2, &error);
    
    if (success) {
        success = SecTransformSetAttribute(signingTransform,
                                           kSecTransformInputAttributeName,
                                           hashBytes,
                                           &error) != false;
    }
    if (!success) {
        CFRelease(signingTransform);
        return NULL;
    }
    
    CFDataRef signature = SecTransformExecute(signingTransform, &error);
    CFRetain(signature);
    signedHash = (__bridge id)signature;
    CFRelease(signingTransform);
    CFRelease(signature);
    
#endif
    return signedHash;
}

+ (NSString *) createJSONFromDictionary:(NSDictionary *) dictionary{
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (! jsonData) {
        [ADLogger log:ADAL_LOG_LEVEL_ERROR message:[NSString stringWithFormat:@"Got an error: %@",error] errorCode:error.code additionalInformation:nil ];
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return nil;
}

@end
