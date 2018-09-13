#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

@interface WFSignatureView : GLKView {
    NSMutableArray* pointsArray;
    NSMutableArray* pathsArray;
    NSMutableArray* colorsArray;
    NSMutableArray* sizesArray;
    
}

@property (assign, nonatomic) UIColor *strokeColor;
@property (assign, nonatomic) BOOL hasSignature;
@property (strong, nonatomic) UIImage *signatureImage;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) int currentPath;
@property (nonatomic, assign) GLKVector3 penColor;

- (void)erase;
- (void)remove;
- (void)pan:(UIPanGestureRecognizer *)p;

@end
