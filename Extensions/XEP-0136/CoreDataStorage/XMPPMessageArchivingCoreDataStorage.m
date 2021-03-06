#import "XMPPMessageArchivingCoreDataStorage.h"
#import "XMPPCoreDataStorageProtected.h"
#import "XMPPLogging.h"
#import "NSXMLElement+XEP_0203.h"
#import "XMPPMessage+XEP_0085.h"
#import "XMPPMessage+XEP_0184.h"
#import "XMPPMessage+XEP_0333.h"
#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

// Log levels: off, error, warn, info, verbose
// Log flags: trace
#if DEBUG
  static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN; // VERBOSE; // | XMPP_LOG_FLAG_TRACE;
#else
  static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

@interface XMPPMessageArchivingCoreDataStorage ()
{
	NSString *messageEntityName;
	NSString *contactEntityName;
}
@property (copy) void (^copyBlock) (XMPPMessageArchiving_Message_CoreDataObject*);
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPMessageArchivingCoreDataStorage

static XMPPMessageArchivingCoreDataStorage *sharedInstance;

+ (instancetype)sharedInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		sharedInstance = [[XMPPMessageArchivingCoreDataStorage alloc] initWithDatabaseFilename:nil storeOptions:nil];
	});
	
	return sharedInstance;
}

/**
 * Documentation from the superclass (XMPPCoreDataStorage):
 * 
 * If your subclass needs to do anything for init, it can do so easily by overriding this method.
 * All public init methods will invoke this method at the end of their implementation.
 * 
 * Important: If overriden you must invoke [super commonInit] at some point.
**/
- (void)commonInit
{
	[super commonInit];
	
	messageEntityName = @"XMPPMessageArchiving_Message_CoreDataObject";
	contactEntityName = @"XMPPMessageArchiving_Contact_CoreDataObject";
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(managedObjectContextDidChange:)
                                                 name:NSManagedObjectContextObjectsDidChangeNotification
                                               object:self.mainThreadManagedObjectContext];
   }

/**
 * Documentation from the superclass (XMPPCoreDataStorage):
 * 
 * Override me, if needed, to provide customized behavior.
 * For example, you may want to perform cleanup of any non-persistent data before you start using the database.
 * 
 * The default implementation does nothing.
**/
- (void)didCreateManagedObjectContext
{
	// If there are any "composing" messages in the database, delete them (as they are temporary).
	
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSEntityDescription *messageEntity = [self messageEntity:moc];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"composing == YES"];
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	fetchRequest.entity = messageEntity;
	fetchRequest.predicate = predicate;
	fetchRequest.fetchBatchSize = saveThreshold;
	
	NSError *error = nil;
	NSArray *messages = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (messages == nil)
	{
		XMPPLogError(@"%@: %@ - Error executing fetchRequest: %@", [self class], THIS_METHOD, error);
		return;
	}
	
	NSUInteger count = 0;
	
	for (XMPPMessageArchiving_Message_CoreDataObject *message in messages)
	{
		[moc deleteObject:message];
		
		if (++count > saveThreshold)
		{
			if (![moc save:&error])
			{
				XMPPLogWarn(@"%@: Error saving - %@ %@", [self class], error, [error userInfo]);
				[moc rollback];
			}
		}
	}
	
	if (count > 0)
	{
		if (![moc save:&error])
		{
			XMPPLogWarn(@"%@: Error saving - %@ %@", [self class], error, [error userInfo]);
			[moc rollback];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)willInsertMessage:(XMPPMessageArchiving_Message_CoreDataObject *)message
{
    if ([[self delegate] respondsToSelector:@selector(didUpdateMessage:)]) {
        [[self delegate]didUpdateMessage:message];
    }

	// Override hook
}

- (void)didUpdateMessage:(XMPPMessageArchiving_Message_CoreDataObject *)message
{
    if ([[self delegate] respondsToSelector:@selector(didUpdateMessage:)]) {
        [[self delegate]didUpdateMessage:message];
    }

}

- (void)willDeleteMessage:(XMPPMessageArchiving_Message_CoreDataObject *)message
{
	// Override hook
}

- (void)willInsertContact:(XMPPMessageArchiving_Contact_CoreDataObject *)contact
{
	// Override hook
   
}

- (void)didUpdateContact:(XMPPMessageArchiving_Contact_CoreDataObject *)contact
{
	// Override hook
    
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (XMPPMessageArchiving_Message_CoreDataObject *)composingMessageWithJid:(XMPPJID *)messageJid
                                                               streamJid:(XMPPJID *)streamJid
                                                                outgoing:(BOOL)isOutgoing
                                                    managedObjectContext:(NSManagedObjectContext *)moc
{
	XMPPMessageArchiving_Message_CoreDataObject *result = nil;
	
	NSEntityDescription *messageEntity = [self messageEntity:moc];
	
	// Order matters:
	// 1. composing - most likely not many with it set to YES in database
	// 2. bareJidStr - splits database by number of conversations
	// 3. outgoing - splits database in half
	// 4. streamBareJidStr - might not limit database at all
	
	NSString *predicateFrmt = @"composing == YES AND bareJidStr == %@ AND outgoing == %@ AND streamBareJidStr == %@";
	NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateFrmt,
                                                            [messageJid bare], @(isOutgoing),
                                                            [streamJid bare]];
	
	NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	fetchRequest.entity = messageEntity;
	fetchRequest.predicate = predicate;
	fetchRequest.sortDescriptors = @[sortDescriptor];
	fetchRequest.fetchLimit = 1;
	
	NSError *error = nil;
	NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (results == nil || error)
	{
		XMPPLogError(@"%@: %@ - Error executing fetchRequest: %@", THIS_FILE, THIS_METHOD, fetchRequest);
	}
	else
	{
		result = (XMPPMessageArchiving_Message_CoreDataObject *)[results lastObject];
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)insertMessage:(XMPPMessage*) xmlMessage {
    
    NSXMLElement *xmpElement = (NSXMLElement*) xmlMessage;
    if ([xmlMessage attributeForName:@"id"] != nil) {
        NSString *messageId = [xmlMessage attributeForName:@"id"];
       XMPPMessageArchiving_Message_CoreDataObject  *message = [self messageWithMessageId:messageId
                                                                     managedObjectContext:[self mainThreadManagedObjectContext]];
        
        if (message == nil) {
            
        }
    }
}

- (XMPPMessageArchiving_Contact_CoreDataObject *)contactForMessage:(XMPPMessageArchiving_Message_CoreDataObject *)msg
{
	// Potential override hook
	
	return [self contactWithBareJidStr:msg.bareJidStr
	                  streamBareJidStr:msg.streamBareJidStr
	              managedObjectContext:msg.managedObjectContext];
}

- (XMPPMessageArchiving_Contact_CoreDataObject *)contactWithJid:(XMPPJID *)contactJid
                                                      streamJid:(XMPPJID *)streamJid
                                           managedObjectContext:(NSManagedObjectContext *)moc
{
	return [self contactWithBareJidStr:[contactJid bare]
	                  streamBareJidStr:[streamJid bare]
	              managedObjectContext:moc];
}


-(void)insertUpdateTemplateMessage: (NSString*) contactJid status: (NSString*) status stream: (XMPPStream*) stream{
    //[self scheduleBlock:^{
        
        NSManagedObjectContext *moc = [self mainThreadManagedObjectContext];
        NSEntityDescription *entity = [self messageEntity:moc];
        NSPredicate *predicate;
        predicate = [NSPredicate predicateWithFormat:@"conversationJid like %@ AND messageType == %@",contactJid,
                     [NSNumber numberWithInt:kMessageTypeEnquiry]];
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        [fetchRequest setEntity:entity];
        [fetchRequest setFetchLimit:1];
        [fetchRequest setPredicate:predicate];
        
        
        NSError *error = nil;
        NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
        
        
        XMPPMessageArchiving_Message_CoreDataObject *message = [results firstObject];

        if (message == nil) {
            
            message = (XMPPMessageArchiving_Message_CoreDataObject *)
            [[NSManagedObject alloc] initWithEntity:[self messageEntity:moc]
                     insertIntoManagedObjectContext:nil];
            
            message.read = [NSNumber numberWithBool:YES];
            message.messageType = [NSNumber numberWithInt:kMessageTypeEnquiry];
            message.messageId = [stream generateUUID];
            message.toJid = contactJid;
            message.fromJid = [stream myJID].bare;
            message.timestamp = [NSDate dateWithTimeIntervalSince1970:0];
            message.conversationJid = contactJid;
            message.composing = [NSNumber numberWithBool:NO];
            [self willInsertMessage:message];

            [moc insertObject:message];
            [moc save:nil];
        }
        
  //  }];
}

- (void) latestSentmessageWithMessageId:(NSString *)contactJid
    completionBlock:(void (^) (XMPPMessageArchiving_Message_CoreDataObject*) ) completionBlock {
    
    [self scheduleBlock:^{
        
        NSEntityDescription *entity = [self messageEntity:[self managedObjectContext]];
        NSPredicate *predicate;
        predicate = [NSPredicate predicateWithFormat:@"conversationJid like %@ AND outgoing == NO", contactJid];
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        [fetchRequest setEntity:entity];
        [fetchRequest setFetchLimit:1];
        [fetchRequest setPredicate:predicate];
        
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO];

        [fetchRequest setSortDescriptors:@[sortDescriptor]];
        
        NSError *error = nil;
        NSArray *results = [[self managedObjectContext] executeFetchRequest:fetchRequest error:&error];
        

        XMPPMessageArchiving_Message_CoreDataObject *message = [results firstObject];
        
        if (message != nil) {
            completionBlock(message);
        }
    }];
}

- (XMPPMessageArchiving_Message_CoreDataObject *)messageWithMessageId:(NSString *)messageId  managedObjectContext:(NSManagedObjectContext *)moc{
   
    NSEntityDescription *entity = [self messageEntity:moc];
    NSPredicate *predicate;
    predicate = [NSPredicate predicateWithFormat:@"messageId == %@", messageId];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:entity];
    [fetchRequest setFetchLimit:1];
    [fetchRequest setPredicate:predicate];
    
    NSError *error = nil;
    NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
    
    if (results == nil)
    {
        XMPPLogError(@"%@: %@ - Fetch request error: %@", THIS_FILE, THIS_METHOD, error);
        return nil;
    }
    else
    {
        
        return (XMPPMessageArchiving_Message_CoreDataObject *)[results lastObject];
    }

    
}

- (XMPPMessageArchiving_Contact_CoreDataObject *)contactWithBareJidStr:(NSString *)contactBareJidStr
                                                      streamBareJidStr:(NSString *)streamBareJidStr
                                                  managedObjectContext:(NSManagedObjectContext *)moc
{
	NSEntityDescription *entity = [self contactEntity:moc];
	
	NSPredicate *predicate;
	if (streamBareJidStr)
	{
		predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@ AND streamBareJidStr == %@",
	                                                              contactBareJidStr, streamBareJidStr];
	}
	else
	{
		predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@", contactBareJidStr];
	}
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity:entity];
	[fetchRequest setFetchLimit:1];
	[fetchRequest setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (results == nil)
	{
		XMPPLogError(@"%@: %@ - Fetch request error: %@", THIS_FILE, THIS_METHOD, error);
		return nil;
	}
	else
	{
        
        
		return (XMPPMessageArchiving_Contact_CoreDataObject *)[results lastObject];
	}
}

- (NSString *)messageEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = messageEntityName;
	};
	
	if (dispatch_get_specific(storageQueueTag))
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setMessageEntityName:(NSString *)entityName
{
	dispatch_block_t block = ^{
		messageEntityName = entityName;
	};
	
	if (dispatch_get_specific(storageQueueTag))
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSString *)contactEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = contactEntityName;
	};
	
	if (dispatch_get_specific(storageQueueTag))
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setContactEntityName:(NSString *)entityName
{
	dispatch_block_t block = ^{
		contactEntityName = entityName;
	};
	
	if (dispatch_get_specific(storageQueueTag))
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSEntityDescription *)messageEntity:(NSManagedObjectContext *)moc
{
	// This is a public method, and may be invoked on any queue.
	// So be sure to go through the public accessor for the entity name.
	
	return [NSEntityDescription entityForName:[self messageEntityName] inManagedObjectContext:moc];
}

- (NSEntityDescription *)contactEntity:(NSManagedObjectContext *)moc
{
	// This is a public method, and may be invoked on any queue.
	// So be sure to go through the public accessor for the entity name.
	
	return [NSEntityDescription entityForName:[self contactEntityName] inManagedObjectContext:moc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Storage Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)configureWithParent:(XMPPMessageArchiving *)aParent queue:(dispatch_queue_t)queue
{
	return [super configureWithParent:aParent queue:queue];
}

- (void)removeAndReset {
    
    [self scheduleBlock:^{
        NSManagedObjectContext *moc = [self managedObjectContext];
        NSEntityDescription *messageEntity = [self messageEntity:moc];
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = messageEntity;

        NSError *error = nil;
        NSArray *messages = [moc executeFetchRequest:fetchRequest error:&error];
        if ([messages count] > 0) {
            
            for (XMPPMessageArchiving_Message_CoreDataObject *message in messages) {
                [moc deleteObject:message];
            }
        }
        
        
        
        NSEntityDescription *contactEntity = [self contactEntity:moc];
        fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = contactEntity;
        
        NSArray *contacts = [moc executeFetchRequest:fetchRequest error:&error];
        if ([contacts count] > 0) {
            
            for (XMPPMessageArchiving_Contact_CoreDataObject *contact in contacts) {
                [moc deleteObject:contact];
            }
        }

    }];
}

- (void)markMessage: (NSString*) messageID status: (MessageStatus) status{
    [self scheduleBlock:^{
        
        if (messageID != nil) {
        NSManagedObjectContext *moc = [self managedObjectContext];

        NSEntityDescription *messageEntity = [self messageEntity:moc];
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"messageId == %@",messageID];
        
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = messageEntity;
        fetchRequest.predicate = predicate;
        NSError *error = nil;
        NSArray *messages = [moc executeFetchRequest:fetchRequest error:&error];
            
            if ([messages count] > 0 ) {
                XMPPMessageArchiving_Message_CoreDataObject *dbMessage = [messages firstObject];
                if ([dbMessage isOutgoing]) {
                    
                [dbMessage setStatus:status];
                NSLog(@"DB MESSAGE IS: %@",dbMessage);
                [dbMessage didUpdateObject];       // Override hook
                [self didUpdateMessage:dbMessage];
                }
            }
        }
    }];
}

- (void)markPreviousMessagesAsDisplayed: (NSString*) userJid {
    
    [self scheduleBlock:^{
        NSManagedObjectContext *moc = [self managedObjectContext];
        
        NSEntityDescription *messageEntity = [self messageEntity:moc];
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"conversationJid like %@ && outgoing == YES && messageStatus == %@"
                                  ,userJid, [NSNumber numberWithInt:kMessageStatusSendReceived]];
        
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = messageEntity;
        fetchRequest.predicate = predicate;
        NSError *error = nil;
        NSArray *messages = [moc executeFetchRequest:fetchRequest error:&error];
        
        for (XMPPMessageArchiving_Message_CoreDataObject *object in messages) {
            object.read = [NSNumber numberWithBool:true];
            object.status = kMessageStatusSendDisplayed;
        }
        
    }];

}

- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing
            xmppStream:(XMPPStream *)xmppStream markAsUnRead: (BOOL) markUnRead  {
    
    [self archiveMessage:message outgoing:isOutgoing useClientTimeStamp:NO markAsUnRead:markUnRead xmppStream:xmppStream];
}



- (void)markMessagesAsRead:(NSString*)userJid {
    
    [self scheduleBlock:^{
        NSManagedObjectContext *moc = [self managedObjectContext];

        NSEntityDescription *messageEntity = [self messageEntity:moc];
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"conversationJid like %@ && read == NO",userJid];
        
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        fetchRequest.entity = messageEntity;
        fetchRequest.predicate = predicate;
        NSError *error = nil;
        NSArray *messages = [moc executeFetchRequest:fetchRequest error:&error];
        
        for (XMPPMessageArchiving_Message_CoreDataObject *object in messages) {
            object.read = [NSNumber numberWithBool:true];
            object.status = kMessageStatusReceived;
        }
        
    }];
}

- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing useClientTimeStamp:(BOOL)useClientTimeStamp
          markAsUnRead: (BOOL) markUnRead
            xmppStream:(XMPPStream *)xmppStream status: (NSNumber*) status {
        
        // Message should either have a body, or be a composing notification
        
        NSString *messageBody = [[message elementForName:@"body"] stringValue];
        BOOL isComposing = NO;
        BOOL shouldDeleteComposingMessage = NO;
        
        if ([messageBody length] == 0)
        {
            // Message doesn't have a body.
            // Check to see if it has a chat state (composing, paused, etc).
            
            isComposing = [message hasComposingChatState];
            if (isComposing) return;
            
            if (!isComposing)
            {
                //ORDER IS IMPORTANT
                
                if ([message hasDisplayedChatMarker]) {
                    
                    [self markMessage:[message chatMarkerID] status:kMessageStatusSendDisplayed];
                    if ([[message from] bare])
                        [self markPreviousMessagesAsDisplayed:[[message from] bare]];
                    return;
                    
                }
                
                if ([message hasChatState])
                {
                    // Message has non-composing chat state.
                    // So if there is a current composing message in the database,
                    // then we need to delete it.
                    shouldDeleteComposingMessage = YES;
                    return;
                }
                
                if ([message hasReceiptResponse]) {
                    [self markMessage:[message receiptResponseID] status:kMessageStatusSendReceived];
                    return;
                }
                
                
                else
                {
                    // Message has no body and no chat state.
                    // Nothing to do with it.
                    return;
                }
            }
        }
        
        [self scheduleBlock:^{
            
            NSManagedObjectContext *moc = [self managedObjectContext];
            XMPPJID *myJid = [self myJIDForXMPPStream:xmppStream];
            
            XMPPJID *messageJid = isOutgoing ? [message to] : [message from];
            
            
            // Fetch-n-Update OR Insert new message
            
            XMPPMessageArchiving_Message_CoreDataObject *archivedMessage =
            [self composingMessageWithJid:messageJid
                                streamJid:myJid
                                 outgoing:isOutgoing
                     managedObjectContext:moc];
            
            
            NSString *messageId = [[message attributeForName:@"id"]stringValue];
            
            if (archivedMessage == nil && messageId != nil) {
                archivedMessage = [self messageWithMessageId:messageId managedObjectContext:moc];
            }
            
            if (shouldDeleteComposingMessage)
            {
                if (archivedMessage)
                {
                    [self willDeleteMessage:archivedMessage]; // Override hook
                    [moc deleteObject:archivedMessage];
                }
                else
                {
                    // Composing message has already been deleted (or never existed)
                }
            }
            else
            {
                XMPPLogVerbose(@"Previous archivedMessage: %@", archivedMessage);
                
                BOOL didCreateNewArchivedMessage = NO;
                if (archivedMessage == nil)
                {
                    archivedMessage = (XMPPMessageArchiving_Message_CoreDataObject *)
                    [[NSManagedObject alloc] initWithEntity:[self messageEntity:moc]
                             insertIntoManagedObjectContext:nil];
                    
                    didCreateNewArchivedMessage = YES;
                    if (isOutgoing == YES) {
                        archivedMessage.read = [NSNumber numberWithBool:YES];
                    }
                    else archivedMessage.read = [NSNumber numberWithBool:!markUnRead];
                }
                
                archivedMessage.message = message;
                if (messageBody != nil) {
                NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:messageBody options:0];
                NSString *decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
                archivedMessage.body = decodedString;
                }
                
                if (status) {
                    archivedMessage.status = [status intValue];
                }
                else {
                
                if (isOutgoing) archivedMessage.status = kMessageStatusSend;
                else {
                    archivedMessage.status = kMessageStatusReceived;
                }
                }
                if ([myJid.bare isEqualToString:message.to.bare] == false) {
                    archivedMessage.conversationJid = message.to.bare;
                }
                else {
                    archivedMessage.conversationJid = message.from.bare;
                }
                
                archivedMessage.toJid = message.to.bare;
                archivedMessage.fromJid = message.from.bare;
                
                archivedMessage.bareJid = [messageJid bareJID];
                archivedMessage.streamBareJidStr = [myJid bare];
                
                if (messageId != nil) {
                    archivedMessage.messageId = messageId;
                }
                
                if (useClientTimeStamp) {
                    archivedMessage.timestamp = [[NSDate alloc] init];
                }
                else {
                    
                    NSDate *timestamp = [message delayedDeliveryDate];
                    
                    if (timestamp)
                        archivedMessage.timestamp = timestamp;
                    
                    else if ([[message parent] isKindOfClass:[NSXMLElement class]]) {
                        
                        NSXMLElement *element = (NSXMLElement*) [message parent];
                        timestamp = [element delayedDeliveryDate];
                        archivedMessage.timestamp = timestamp;
                    }
                    
                    
                    if (timestamp == nil || (isOutgoing == false && [timestamp compare:[NSDate date]] == NSOrderedDescending))
                        archivedMessage.timestamp = [[NSDate alloc] init];
                }
                archivedMessage.thread = [[message elementForName:@"thread"] stringValue];
                
                archivedMessage.isOutgoing = isOutgoing;
                archivedMessage.isComposing = isComposing;
                
                XMPPLogVerbose(@"New archivedMessage: %@", archivedMessage);
                
                if (didCreateNewArchivedMessage) // [archivedMessage isInserted] doesn't seem to work
                {
                    XMPPLogVerbose(@"Inserting message...");
                    
                    [archivedMessage willInsertObject];       // Override hook
                    [self willInsertMessage:archivedMessage]; // Override hook
                    [moc insertObject:archivedMessage];
                }
                else
                {
                    XMPPLogVerbose(@"Updating message...");
                    
                    [archivedMessage didUpdateObject];       // Override hook
                    [self didUpdateMessage:archivedMessage]; // Override hook
                }
                
                // Create or update contact (if message with actual content)
                
                if ([messageBody length] > 0)
                {
                    BOOL didCreateNewContact = NO;
                    
                    XMPPMessageArchiving_Contact_CoreDataObject *contact = [self contactForMessage:archivedMessage];
                    XMPPLogVerbose(@"Previous contact: %@", contact);
                    
                    if (contact == nil)
                    {
                        contact = (XMPPMessageArchiving_Contact_CoreDataObject *)
                        [[NSManagedObject alloc] initWithEntity:[self contactEntity:moc]
                                 insertIntoManagedObjectContext:nil];
                        
                        didCreateNewContact = YES;
                    }
                    
                    contact.streamBareJidStr = archivedMessage.streamBareJidStr;
                    contact.bareJid = archivedMessage.bareJid;
                    
                    if (contact.mostRecentMessageTimestamp == nil ||(contact.mostRecentMessageTimestamp != nil
                                                                     && [contact.mostRecentMessageTimestamp compare:archivedMessage.timestamp] == NSOrderedAscending)){
                        contact.mostRecentMessageTimestamp = archivedMessage.timestamp;
                       contact.mostRecentMessageBody = archivedMessage.body;
                       contact.mostRecentMessageOutgoing = @(isOutgoing);
                    }
                    XMPPLogVerbose(@"New contact: %@", contact);
                    
                    if (didCreateNewContact) // [contact isInserted] doesn't seem to work
                    {
                        XMPPLogVerbose(@"Inserting contact...");
                        
                        [contact willInsertObject];       // Override hook
                        [self willInsertContact:contact]; // Override hook
                        [moc insertObject:contact];
                    }
                    else
                    {
                        XMPPLogVerbose(@"Updating contact...");
                        
                        [contact didUpdateObject];       // Override hook
                        [self didUpdateContact:contact]; // Override hook
                    }
                }
            }
        }];
    }

-(void)managedObjectContextDidChange: (NSNotification*) note {
 
    NSSet *updatedObjects = [[note userInfo] objectForKey:NSUpdatedObjectsKey];
    NSSet *deletedObjects = [[note userInfo] objectForKey:NSDeletedObjectsKey];
    NSSet *insertedObjects = [[note userInfo] objectForKey:NSInsertedObjectsKey];
    
    if ([insertedObjects count] > 0 || [updatedObjects count] > 0) {
        
        for (NSManagedObject *object in insertedObjects) {
            if ([object isKindOfClass:[XMPPMessageArchiving_Message_CoreDataObject class]]) {
                if ([self.delegate respondsToSelector:@selector(didInsertMessage:)])
                    [self.delegate didInsertMessage:(XMPPMessageArchiving_Message_CoreDataObject*) object];
            }
        }
        
        /*for (NSManagedObject *object in updatedObjects) {
            if ([object isKindOfClass:[XMPPMessageArchiving_Message_CoreDataObject class]]) {
                if ([self.delegate respondsToSelector:@selector(didUpdateMessage:)])
                    [self.delegate didUpdateMessage:(XMPPMessageArchiving_Message_CoreDataObject*) object];
            }
        }*/
        
        if ([self.delegate respondsToSelector:@selector(didMergeAndSaveMainContext)])
            [self.delegate didMergeAndSaveMainContext];

    }
}

- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing useClientTimeStamp:(BOOL)useClientTimeStamp
          markAsUnRead: (BOOL) markUnRead
            xmppStream:(XMPPStream *)xmppStream {
 
    [self archiveMessage:message outgoing:isOutgoing useClientTimeStamp:useClientTimeStamp
            markAsUnRead:markUnRead xmppStream:xmppStream status:nil];
}

- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing xmppStream:(XMPPStream *)xmppStream
{
    [self archiveMessage:message outgoing:isOutgoing xmppStream:xmppStream markAsUnRead:true];
}

- (void)mainThreadManagedObjectContextDidMergeChanges {
    [super mainThreadManagedObjectContextDidMergeChanges];
    
    }
@end
