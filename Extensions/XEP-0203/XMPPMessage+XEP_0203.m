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
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
    NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
    [delay addAttributeWithName:@"stamp" stringValue:[dateString stringByAppendingString:@"+00:00"]];
    [self addChild:delay];
}

@end
