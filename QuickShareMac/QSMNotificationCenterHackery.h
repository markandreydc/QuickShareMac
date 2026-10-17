//
//  QSMNotificationCenterHackery.h
//  QuickShareMac
//
//  Created by Grishka on 10.04.2023.
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

@interface QSMNotificationCenterHackery : NSObject

+ (void)removeDefaultAction:(UNMutableNotificationContent*) content;

@end

NS_ASSUME_NONNULL_END
