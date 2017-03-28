#import "RCTMultipeerConnectivity.h"
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
//#import "ObjectStore.h"

@implementation RCTMultipeerConnectivity

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(advertise:(NSString *)channel data:(NSDictionary *)data) {
    self.advertiser =
    [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:data serviceType:channel];
    self.advertiser.delegate = self;
    [self.advertiser startAdvertisingPeer];
}

RCT_EXPORT_METHOD(endAdvertise) {
    [self.advertiser stopAdvertisingPeer];
}

RCT_EXPORT_METHOD(browse:(NSString *)channel)
{
    self.browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self.peerID serviceType:channel];
    self.browser.delegate = self;
    [self.browser startBrowsingForPeers];
}

RCT_EXPORT_METHOD(endBrowse)
{
    [self.browser stopBrowsingForPeers];
}

RCT_EXPORT_METHOD(invite:(NSString *)peerUUID callback:(RCTResponseSenderBlock)callback) {
    MCPeerID *peerID = [self.peerIDs valueForKey:peerUUID];
    [self.browser invitePeer:peerID toSession:self.session withContext:nil timeout:5];
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(rsvp:(NSString *)inviteID accept:(BOOL)accept callback:(RCTResponseSenderBlock)callback) {
    void (^invitationHandler)(BOOL, MCSession *) = [self.invitationHandlers valueForKey:inviteID];
    invitationHandler(accept, self.session);
    [self.invitationHandlers removeObjectForKey:inviteID];
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(broadcast:(NSDictionary *)data forwardEnabled:(BOOL)forwardEnabled callback:(RCTResponseSenderBlock)callback) {
    [self sendData:[self.session connectedPeers] data:data forwardEnabled:forwardEnabled callback:callback];
}

RCT_EXPORT_METHOD(send:(NSArray *)recipients data:(NSDictionary *)data forwardEnabled:(BOOL)forwardEnabled callback:(RCTResponseSenderBlock)callback) {
    NSMutableArray *peers = [NSMutableArray array];
    for (NSString *peerUUID in recipients) {
        [peers addObject:[self.peers valueForKey:peerUUID]];
    }
    
    [self sendData:peers data:data forwardEnabled:forwardEnabled callback:callback];
}

RCT_EXPORT_METHOD(disconnect:(RCTResponseSenderBlock)callback) {
    [self.session disconnect];
    
    callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(getConnectedPeers:(RCTResponseSenderBlock)callback) {
    NSLog(@"[Info] getConnectedPeers connectedPeers.length %lu", (unsigned long)[[self.session connectedPeers] count]);
    NSMutableArray *peers = [NSMutableArray array];
    for (MCPeerID *peerID in [self.session connectedPeers]) {
        if (![self.peers valueForKey:peerID.displayName]) {
            continue;
        }
        NSDictionary *peer = @{
                               @"id": peerID.displayName,
                               @"info": [self.peers valueForKey:peerID.displayName]
                               };
        [peers addObject:peer];
    }
    
    callback(@[[NSNull null], peers]);
}

RCT_EXPORT_METHOD(getAllPeers:(RCTResponseSenderBlock)callback) {
    NSLog(@"[Info] getAllPeers peers.length %lu", (unsigned long)[self.peers.allKeys count]);
    NSMutableArray *peers = [NSMutableArray array];
    for (NSString *peerUUID in self.peers.allKeys) {
        [peers addObject:@{
                           @"id": peerUUID,
                           @"info": [self.peers valueForKey:peerUUID]
                           }];
    }
    
    callback(@[[NSNull null], peers]);
}

// TODO: Waiting for module interop and/or streams over JS bridge

//RCT_EXPORT_METHOD(createStreamForPeer:(NSString *)peerUUID name:(NSString *)name callback:(RCTResponseSenderBlock)callback) {
//  NSError *error = nil;
//  NSString *outputStreamUUID = [[ObjectStore shared] putObject:[self.session startStreamWithName:name toPeer:[self.peers valueForKey:peerUUID] error:&error]];
//  if (error != nil) {
//    callback(@[[error description]]);
//  }
//  else {
//    callback(@[[NSNull null], outputStreamUUID]);
//  }
//}

- (instancetype)init {
    self = [super init];
    self.peers = [NSMutableDictionary dictionary];
    self.peerIDs = [NSMutableDictionary dictionary];
    self.invitationHandlers = [NSMutableDictionary dictionary];
    self.peerID = [[MCPeerID alloc] initWithDisplayName:[[NSUUID UUID] UUIDString]];
    self.session = [[MCSession alloc] initWithPeer:self.peerID securityIdentity:nil encryptionPreference:MCEncryptionOptional];
    self.session.delegate = self;
    
    return self;
}

- (void)sendData:(NSArray *)peers data:(NSDictionary *)data forwardEnabled:(BOOL)forwardEnabled callback:(RCTResponseSenderBlock)callback {
    NSMutableDictionary *dataToSend = [data mutableCopy];
    if (forwardEnabled) {
        NSMutableArray *peerIDs = [NSMutableArray array];
        for (MCPeerID *peerID in peers) {
            [peerIDs addObject:peerID.displayName];
            
            [dataToSend setValue:peerIDs forKey:@"_forwardRecepients"];
        }
        NSLog(@"[Info] sendData forwardEnabled %@", peerIDs);
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataToSend options:0 error:&error];
    [self.session sendData:jsonData toPeers:peers withMode:MCSessionSendDataReliable error:&error];
    if (error == nil) {
        callback(@[[NSNull null]]);
    }
    else {
        callback(@[[error description]]);
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info {
    NSLog(@"[Info] foundPeer %@", peerID.displayName);
    if ([peerID.displayName isEqualToString:self.peerID.displayName]) return;
    
    [self.peers setValue:info forKey:peerID.displayName];
    [self.peerIDs setValue:peerID forKey:peerID.displayName];
    
    NSLog(@"[Info] foundPeer peers.length %lu", [self.peers.allKeys count]);
    
    if (info == nil) {
        info = [NSDictionary dictionary];
    }
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityPeerFound"
                                                    body:@{
                                                           @"peer": @{
                                                                   @"id": peerID.displayName,
                                                                   @"info": info
                                                                   },
                                                           @"self": @{
                                                                   @"id": self.peerID.displayName
                                                                   }
                                                           }];
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    NSLog(@"[Info] lostPeer %@", peerID.displayName);
    if ([peerID.displayName isEqualToString:self.peerID.displayName]) return;
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityPeerLost"
                                                    body:@{
                                                           @"peer": @{
                                                                   @"id": peerID.displayName
                                                                   },
                                                           @"self": @{
                                                                   @"id": self.peerID.displayName
                                                                   }
                                                           }];
    [self.peers removeObjectForKey:peerID.displayName];
    [self.peerIDs removeObjectForKey:peerID.displayName];
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL accept, MCSession *session))invitationHandler {
    NSString *invitationUUID = [[NSUUID UUID] UUIDString];
    [self.invitationHandlers setValue:[invitationHandler copy] forKey:invitationUUID];
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityInviteReceived"
                                                    body:@{
                                                           @"invite": @{
                                                                   @"id": invitationUUID
                                                                   },
                                                           @"peer": @{
                                                                   @"id": peerID.displayName
                                                                   },
                                                           @"self": @{
                                                                   @"id": self.peerID.displayName
                                                                   }
                                                           }];
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    NSLog(@"[Info] didChangeState %ld %@", state, peerID.displayName);
    if ([peerID.displayName isEqualToString:self.peerID.displayName]) return;
    if (![self.peers valueForKey:peerID.displayName]) return;
    if (state == MCSessionStateConnected) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityPeerConnected"
                                                        body:@{
                                                               @"peer": @{
                                                                       @"id": peerID.displayName,
                                                                       @"info": [self.peers valueForKey:peerID.displayName]
                                                                       },
                                                               @"self": @{
                                                                       @"id": self.peerID.displayName
                                                                       }
                                                               }];
    }
    else if (state == MCSessionStateConnecting) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityPeerConnecting"
                                                        body:@{
                                                               @"peer": @{
                                                                       @"id": peerID.displayName
                                                                       },
                                                               @"self": @{
                                                                       @"id": self.peerID.displayName
                                                                       }
                                                               }];
    }
    else if (state == MCSessionStateNotConnected) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityPeerDisconnected"
                                                        body:@{
                                                               @"peer": @{
                                                                       @"id": peerID.displayName
                                                                       },
                                                               @"self": @{
                                                                       @"id": self.peerID.displayName
                                                                       }
                                                               }];
        
    }
}

// - (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL accept))certificateHandler {
//   certificateHandler(YES);
// }

// TODO: Waiting for module interop and/or streams over JS bridge

//- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {
//  NSString *streamId = [[ObjectStore shared] putObject:stream];
//  [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityStreamOpened"
//                               body:@{
//                                 @"stream": @{
//                                   @"id": streamId,
//                                   @"name": streamName
//                                 },
//                                 @"peer": @{
//                                   @"id": peerID.displayName
//                                 }
//                               }];
//}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSDictionary *parsedJSON = [NSDictionary dictionary];
    
    if([object isKindOfClass:[NSDictionary class]]) {
        parsedJSON = object;
    }
    
    if ([parsedJSON objectForKey:@"_forwardRecepients"]) {
        NSLog(@"[Info] didReceiveData with forwardEnabled %@", [parsedJSON objectForKey:@"_forwardRecepients"]);
    }
    
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"RCTMultipeerConnectivityDataReceived"
                                                    body:@{
                                                           @"peer": @{
                                                                   @"id": peerID.displayName
                                                                   },
                                                           @"self": @{
                                                                   @"id": self.peerID.displayName
                                                                   },
                                                           @"data": parsedJSON
                                                           }];
}

// TODO: Support file transfers once we have a general spec for representing files
//
//- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {
//  NSURL *destinationURL = [NSURL fileURLWithPath:@"/path/to/destination"];
//  if (![[NSFileManager defaultManager] moveItemAtURL:localURL toURL:destinationURL error:&error]) {
//    NSLog(@"[Error] %@", error);
//  }
//}
//
//- (void)session:(MCSession *)session
//didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
//{
//  
//}


@end
