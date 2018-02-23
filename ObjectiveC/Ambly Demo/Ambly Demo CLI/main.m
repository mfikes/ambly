#import <Foundation/Foundation.h>
#import "App.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Running...");
        App* app = [[App alloc] init];
        [app setup];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
