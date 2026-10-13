#import "GameSurfaceView.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"
#import "renderer_info.h"

@interface GameSurfaceView()
@end

@implementation GameSurfaceView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.layer.drawsAsynchronously = YES;
    self.layer.opaque = YES;

    return self;
}

+ (Class)layerClass {
    const char *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"].UTF8String;
    if (renderer && ame_renderer_from_name(renderer) == AME_RENDERER_ZINK) {
        return CALayer.class;
    } else {
        return CAMetalLayer.class;
    }
}

@end
