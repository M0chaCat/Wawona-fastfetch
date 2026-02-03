#import "WawonaPreferencesManager.h"
#import <Foundation/Foundation.h>

typedef void (^WaypipeOutputHandler)(NSString *output);

@protocol WawonaWaypipeRunnerDelegate <NSObject>
- (void)runnerDidReceiveSSHPasswordPrompt:(NSString *)prompt;
- (void)runnerDidReceiveSSHError:(NSString *)error;
- (void)runnerDidReadData:(NSData *)data;
- (void)runnerDidReceiveOutput:(NSString *)output isError:(BOOL)isError;
- (void)runnerDidFinishWithExitCode:(int)exitCode;
@end

@interface WawonaWaypipeRunner : NSObject

@property(nonatomic, weak) id<WawonaWaypipeRunnerDelegate> delegate;

+ (instancetype)sharedRunner;

// Logic Helpers
- (NSString *)findWaypipeBinary;
- (NSArray<NSString *> *)buildWaypipeArguments:
    (WawonaPreferencesManager *)prefs;
- (NSString *)generateWaypipePreviewString:(WawonaPreferencesManager *)prefs;

// Execution
- (void)launchWaypipe:(WawonaPreferencesManager *)prefs;
- (void)stopWaypipe;

@end
