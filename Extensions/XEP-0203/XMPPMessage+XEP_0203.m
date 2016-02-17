//
//  XMPPMessage+XEP_0203.m
//  Pods
//
//  Created by Sunny on 17/02/16.
//
//

#import "XMPPMessage+XEP_0203.h"

@implementation XMPPMessage (XEP_0203)

- (void)addDelay
{
    NSXMLElement *delay = [NSXMLElement elementWithName:@"delay" xmlns:@"urn:xmpp:delay"];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat:@"yyyyMMdd'T'HH:mm:ss"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    [delay addAttributeWithName:@"stamp" stringValue:[dateFormatter stringFromDate:[NSDate date]]];
    [self addChild:delay];
}

@end
