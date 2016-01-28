#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "XMPP.h"

/*public static final int STATUS_RECEIVED = 0;
public static final int STATUS_UNSEND = 1;
public static final int STATUS_SEND = 2;
public static final int STATUS_SEND_FAILED = 3;
public static final int STATUS_WAITING = 5;
public static final int STATUS_OFFERED = 6;
public static final int STATUS_SEND_RECEIVED = 7;
public static final int STATUS_SEND_DISPLAYED = 8;
*/


typedef enum {
    kMessageStatusReceived = 0,
    kMessageStatusUnsend = 1,
    kMessageStatusSend = 2,
    kMessageStatusSendFailed = 3,
    kMessageStatusWaiting = 4,
    kMessageStatusOffered = 5,
    kMessageStatusSendReceived = 6,
    kMessageStatusSendDisplayed = 7
    
} MessageStatus;

@interface XMPPMessageArchiving_Message_CoreDataObject : NSManagedObject

@property (nonatomic, strong) XMPPMessage * message;  // Transient (proper type, not on disk)
@property (nonatomic, strong) NSString * messageStr;  // Shadow (binary data, written to disk)

/**
 * This is the bare jid of the person you're having the conversation with.
 * For example: robbiehanson@deusty.com
 * 
 * Regardless of whether the message was incoming or outgoing,
 * this will represent the "other" participant in the conversation.
**/
@property (nonatomic, strong) XMPPJID * bareJid;      // Transient (proper type, not on disk)
@property (nonatomic, strong) NSString * bareJidStr;  // Shadow (binary data, written to disk)

@property (nonatomic, strong) NSString * body;
@property (nonatomic, strong) NSString * thread;

@property (nonatomic, strong) NSNumber * outgoing;    // Use isOutgoing
@property (nonatomic, assign) BOOL isOutgoing;        // Convenience property

@property (nonatomic, strong) NSNumber * composing;   // Use isComposing
@property (nonatomic, assign) BOOL isComposing;       // Convenience property

@property (nonatomic, strong) NSDate * timestamp;

@property (nonatomic, strong) NSString *fromJid;
@property (nonatomic, strong) NSString *toJid;
@property (nonatomic, strong) NSString *conversationJid;
@property (nonatomic, strong) NSString * streamBareJidStr;
@property  (nonatomic, strong) NSNumber *messageStatus;
@property (nonatomic, strong) NSNumber *read;
@property (nonatomic, strong) NSString *messageId;

@property (nonatomic, assign) MessageStatus status;

/**
 * This method is called immediately before the object is inserted into the managedObjectContext.
 * At this point, all normal properties have been set.
 * 
 * If you extend XMPPMessageArchiving_Message_CoreDataObject,
 * you can use this method as a hook to set your custom properties.
**/
- (void)willInsertObject;

/**
 * This method is called immediately after the message has been changed.
 * At this point, all normal properties have been updated.
 * 
 * If you extend XMPPMessageArchiving_Message_CoreDataObject,
 * you can use this method as a hook to set your custom properties.
**/
- (void)didUpdateObject;

@end
