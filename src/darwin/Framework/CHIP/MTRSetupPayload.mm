/**
 *
 *    Copyright (c) 2020 Project CHIP Authors
 *
 *    Licensed under the Apache License, Version 2.0 (the "License");
 *    you may not use this file except in compliance with the License.
 *    You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *    Unless required by applicable law or agreed to in writing, software
 *    distributed under the License is distributed on an "AS IS" BASIS,
 *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *    See the License for the specific language governing permissions and
 *    limitations under the License.
 */

#import "MTRError.h"
#import "MTRError_Internal.h"
#import "MTROnboardingPayloadParser.h"
#import "MTRSetupPayload_Internal.h"
#import "setup_payload/ManualSetupPayloadGenerator.h"
#import <setup_payload/SetupPayload.h>

@implementation MTROptionalQRCodeInfo
@end

@implementation MTRSetupPayload {
    chip::SetupPayload _chipSetupPayload;
}

- (MTRDiscoveryCapabilities)convertRendezvousFlags:(const chip::Optional<chip::RendezvousInformationFlags> &)value
{
    if (!value.HasValue()) {
        return MTRDiscoveryCapabilitiesUnknown;
    }

    NSUInteger flags = 0;
    if (value.Value().Has(chip::RendezvousInformationFlag::kBLE)) {
        flags |= MTRDiscoveryCapabilitiesBLE;
    }
    if (value.Value().Has(chip::RendezvousInformationFlag::kSoftAP)) {
        flags |= MTRDiscoveryCapabilitiesSoftAP;
    }
    if (value.Value().Has(chip::RendezvousInformationFlag::kOnNetwork)) {
        flags |= MTRDiscoveryCapabilitiesOnNetwork;
    }
    if (flags == MTRDiscoveryCapabilitiesUnknown) {
        // OnNetwork has to be supported!
        flags = MTRDiscoveryCapabilitiesOnNetwork;
    }
    return flags;
}

- (MTRCommissioningFlow)convertCommissioningFlow:(chip::CommissioningFlow)value
{
    if (value == chip::CommissioningFlow::kStandard) {
        return MTRCommissioningFlowStandard;
    }
    if (value == chip::CommissioningFlow::kUserActionRequired) {
        return MTRCommissioningFlowUserActionRequired;
    }
    if (value == chip::CommissioningFlow::kCustom) {
        return MTRCommissioningFlowCustom;
    }
    return MTRCommissioningFlowInvalid;
}

- (id)initWithSetupPayload:(chip::SetupPayload)setupPayload
{
    if (self = [super init]) {
        _chipSetupPayload = setupPayload;
        _version = [NSNumber numberWithUnsignedChar:setupPayload.version];
        _vendorID = [NSNumber numberWithUnsignedShort:setupPayload.vendorID];
        _productID = [NSNumber numberWithUnsignedShort:setupPayload.productID];
        _commissioningFlow = [self convertCommissioningFlow:setupPayload.commissioningFlow];
        _discoveryCapabilities = [self convertRendezvousFlags:setupPayload.rendezvousInformation];
        _hasShortDiscriminator = setupPayload.discriminator.IsShortDiscriminator();
        if (_hasShortDiscriminator) {
            _discriminator = [NSNumber numberWithUnsignedShort:setupPayload.discriminator.GetShortValue()];
        } else {
            _discriminator = [NSNumber numberWithUnsignedShort:setupPayload.discriminator.GetLongValue()];
        }
        _setupPasscode = [NSNumber numberWithUnsignedInt:setupPayload.setUpPINCode];

        [self getSerialNumber:setupPayload];
    }
    return self;
}

- (void)getSerialNumber:(chip::SetupPayload)setupPayload
{
    std::string serialNumberC;
    CHIP_ERROR err = setupPayload.getSerialNumber(serialNumberC);
    if (err == CHIP_NO_ERROR) {
        _serialNumber = [NSString stringWithUTF8String:serialNumberC.c_str()];
    }
}

- (NSArray<MTROptionalQRCodeInfo *> *)getAllOptionalVendorData:(NSError * __autoreleasing *)error
{
    NSMutableArray<MTROptionalQRCodeInfo *> * allOptionalData = [NSMutableArray new];
    std::vector<chip::OptionalQRCodeInfo> chipOptionalData = _chipSetupPayload.getAllOptionalVendorData();
    for (chip::OptionalQRCodeInfo chipInfo : chipOptionalData) {
        MTROptionalQRCodeInfo * info = [MTROptionalQRCodeInfo new];
        info.tag = [NSNumber numberWithUnsignedChar:chipInfo.tag];
        switch (chipInfo.type) {
        case chip::optionalQRCodeInfoTypeString:
            info.infoType = MTROptionalQRCodeInfoTypeString;
            info.stringValue = [NSString stringWithUTF8String:chipInfo.data.c_str()];
            break;
        case chip::optionalQRCodeInfoTypeInt32:
            info.infoType = MTROptionalQRCodeInfoTypeInt32;
            info.integerValue = [NSNumber numberWithInt:chipInfo.int32];
            break;
        default:
            if (error) {
                *error = [NSError errorWithDomain:MTRErrorDomain code:MTRErrorCodeInvalidArgument userInfo:nil];
            }
            return @[];
        }
        [allOptionalData addObject:info];
    }
    return allOptionalData;
}

+ (NSNumber *)generateRandomSetupPasscode
{
    do {
        // Make sure the thing we generate is in the right range.
        uint32_t setupPIN = arc4random_uniform(chip::kSetupPINCodeMaximumValue) + 1;
        if (chip::SetupPayload::IsValidSetupPIN(setupPIN)) {
            return @(setupPIN);
        }

        // We got pretty unlikely with our random number generation.  Just try
        // again.  The chance that this loop does not terminate in a reasonable
        // amount of time is astronomically low, assuming arc4random_uniform is not
        // broken.
    } while (1);

    // Not reached.
    return @(chip::kSetupPINCodeUndefinedValue);
}

+ (MTRSetupPayload * _Nullable)setupPayloadWithOnboardingPayload:(NSString *)onboardingPayload
                                                           error:(NSError * __autoreleasing *)error
{
    // TODO: Do we actually need the MTROnboardingPayloadParser abstraction?
    return [MTROnboardingPayloadParser setupPayloadForOnboardingPayload:onboardingPayload error:error];
}

#pragma mark - NSSecureCoding

static NSString * const MTRSetupPayloadCodingKeyVersion = @"MTRSP.ck.version";
static NSString * const MTRSetupPayloadCodingKeyVendorID = @"MTRSP.ck.vendorID";
static NSString * const MTRSetupPayloadCodingKeyProductID = @"MTRSP.ck.productID";
static NSString * const MTRSetupPayloadCodingKeyCommissioningFlow = @"MTRSP.ck.commissioningFlow";
static NSString * const MTRSetupPayloadCodingKeyDiscoveryCapabilities = @"MTRSP.ck.discoveryCapabilities";
static NSString * const MTRSetupPayloadCodingKeyHasShortDiscriminator = @"MTRSP.ck.hasShortDiscriminator";
static NSString * const MTRSetupPayloadCodingKeyDiscriminator = @"MTRSP.ck.discriminator";
static NSString * const MTRSetupPayloadCodingKeySetupPasscode = @"MTRSP.ck.setupPasscode";
static NSString * const MTRSetupPayloadCodingKeySerialNumber = @"MTRSP.ck.serialNumber";

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.version forKey:MTRSetupPayloadCodingKeyVersion];
    [coder encodeObject:self.vendorID forKey:MTRSetupPayloadCodingKeyVendorID];
    [coder encodeObject:self.productID forKey:MTRSetupPayloadCodingKeyProductID];
    // Casts are safe because commissioning flow, discoveryCapabilities, and
    // hasShortDiscriminator values are all pretty small and non-negative.
    [coder encodeInteger:static_cast<NSInteger>(self.commissioningFlow) forKey:MTRSetupPayloadCodingKeyCommissioningFlow];
    [coder encodeInteger:static_cast<NSInteger>(self.discoveryCapabilities) forKey:MTRSetupPayloadCodingKeyDiscoveryCapabilities];
    [coder encodeInteger:static_cast<NSInteger>(self.hasShortDiscriminator) forKey:MTRSetupPayloadCodingKeyHasShortDiscriminator];
    [coder encodeObject:self.discriminator forKey:MTRSetupPayloadCodingKeyDiscriminator];
    [coder encodeObject:self.setupPasscode forKey:MTRSetupPayloadCodingKeySetupPasscode];
    [coder encodeObject:self.serialNumber forKey:MTRSetupPayloadCodingKeySerialNumber];
}

- (instancetype _Nullable)initWithCoder:(NSCoder *)decoder
{
    NSNumber * version = [decoder decodeObjectOfClass:[NSNumber class] forKey:MTRSetupPayloadCodingKeyVersion];
    NSNumber * vendorID = [decoder decodeObjectOfClass:[NSNumber class] forKey:MTRSetupPayloadCodingKeyVendorID];
    NSNumber * productID = [decoder decodeObjectOfClass:[NSNumber class] forKey:MTRSetupPayloadCodingKeyProductID];
    NSInteger commissioningFlow = [decoder decodeIntegerForKey:MTRSetupPayloadCodingKeyCommissioningFlow];
    NSInteger discoveryCapabilities = [decoder decodeIntegerForKey:MTRSetupPayloadCodingKeyDiscoveryCapabilities];
    NSInteger hasShortDiscriminator = [decoder decodeIntegerForKey:MTRSetupPayloadCodingKeyHasShortDiscriminator];
    NSNumber * discriminator = [decoder decodeObjectOfClass:[NSNumber class] forKey:MTRSetupPayloadCodingKeyDiscriminator];
    NSNumber * setupPasscode = [decoder decodeObjectOfClass:[NSNumber class] forKey:MTRSetupPayloadCodingKeySetupPasscode];
    NSString * serialNumber = [decoder decodeObjectOfClass:[NSString class] forKey:MTRSetupPayloadCodingKeySerialNumber];

    MTRSetupPayload * payload = [[MTRSetupPayload alloc] init];
    payload.version = version;
    payload.vendorID = vendorID;
    payload.productID = productID;
    payload.commissioningFlow = static_cast<MTRCommissioningFlow>(commissioningFlow);
    payload.discoveryCapabilities = static_cast<MTRDiscoveryCapabilities>(discoveryCapabilities);
    payload.hasShortDiscriminator = static_cast<BOOL>(hasShortDiscriminator);
    payload.discriminator = discriminator;
    payload.setupPasscode = setupPasscode;
    payload.serialNumber = serialNumber;

    return payload;
}

- (NSString * _Nullable)manualEntryCode
{
    CHIP_ERROR err = CHIP_NO_ERROR;
    std::string outDecimalString;
    chip::SetupPayload payload;

    /// The 11 digit manual pairing code only requires the version, VID_PID present flag,
    /// discriminator, and the setup pincode.
    payload.version = [self.version unsignedCharValue];
    if (self.hasShortDiscriminator) {
        payload.discriminator.SetShortValue([self.discriminator unsignedCharValue]);
    } else {
        payload.discriminator.SetLongValue([self.discriminator unsignedShortValue]);
    }
    payload.setUpPINCode = [self.setupPasscode unsignedIntValue];

    err = chip::ManualSetupPayloadGenerator(payload).payloadDecimalStringRepresentation(outDecimalString);

    if (err != CHIP_NO_ERROR) {
        return nil;
    }

    return [NSString stringWithUTF8String:outDecimalString.c_str()];
}

@end
