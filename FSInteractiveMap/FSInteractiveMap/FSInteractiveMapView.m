//
//  FSInteractiveMapView.m
//  FSInteractiveMap
//
//  Created by Arthur GUIBERT on 23/12/2014.
//  Copyright (c) 2014 Arthur GUIBERT. All rights reserved.
//

#import "FSInteractiveMapView.h"
#import "FSSVG.h"

@interface FSInteractiveMapView ()

@property (nonatomic, strong) FSSVG* svg;
@property (nonatomic, strong) NSMutableArray* scaledPaths;

@property (nonatomic, assign) CGFloat currentScale;
@property (nonatomic, assign) CGPoint currentPan;

@property (nonatomic, assign) CGFloat touchScale;
@property (nonatomic, assign) CGPoint touchPan;

@end


@implementation FSInteractiveMapView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self fs_initInternal];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self fs_initInternal];
    }
    return self;
}

- (void)fs_initInternal {
    _scaledPaths = [NSMutableArray array];

    [self setDefaultParameters];

    self.touchScale = self.currentScale = 1;
    self.touchPan = self.currentPan = CGPointZero;

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tapRecognizer];

    UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinchRecognizer];

    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panRecognizer];
}

- (void)setDefaultParameters
{
    self.lineWidth = kFSInteractiveMapDefaultLineWidth;
    self.fillColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.strokeColor = [UIColor colorWithWhite:0.6 alpha:1];

    self.animationTime = kFSInteractiveMapDefaultAnimationTime;

    self.minZoom = kFSInteractiveMapDefaultZoomMin;
    self.maxZoom = kFSInteractiveMapDefaultZoomMax;
    self.mapInset = UIEdgeInsetsMake(
            kFSInteractiveMapDefaultZoomPadding,
            kFSInteractiveMapDefaultZoomPadding,
            kFSInteractiveMapDefaultZoomPadding,
            kFSInteractiveMapDefaultZoomPadding
    );
}

- (void)setFrame:(CGRect)frame {
    CGSize oldSize = self.frame.size;
    [super setFrame:frame];
    if (!CGSizeEqualToSize(oldSize, frame.size)) {
        [self updateMap];
    }
}

- (void)setBounds:(CGRect)bounds {
    CGSize oldSize = self.bounds.size;
    [super setBounds:bounds];
    if (!CGSizeEqualToSize(oldSize, bounds.size)) {
        [self updateMap];
    }
}

#pragma mark - SVG map loading

- (void)loadMap:(NSString*)mapName withColors:(NSDictionary*)colorsDict
{
    self.touchScale = self.currentScale = 1;
    self.touchPan = self.currentPan = CGPointZero;
    
    [_scaledPaths removeAllObjects];
    
    NSArray<CALayer *> *sublayers = [NSArray arrayWithArray:self.layer.sublayers];
    if (sublayers && sublayers.count) {
        sublayers = [NSArray arrayWithArray:sublayers];
        for (CALayer *sublayer in sublayers) {
            [sublayer removeFromSuperlayer];
        }
    }
    
    _svg = [FSSVG svgWithFile:mapName];

    // Make the map fit inside the frame

    float preScale = [self mapPreScale];
    CGAffineTransform scaleTransform = CGAffineTransformMakeScale(preScale, preScale);
    scaleTransform = CGAffineTransformTranslate(scaleTransform, self.mapInset.left - self.mapInset.right - _svg.bounds.origin.x, self.mapInset.top - self.mapInset.bottom - _svg.bounds.origin.y);
    
    for (FSSVGPathElement* path in _svg.paths) {
        UIBezierPath* scaled = [path.path copy];

        CAShapeLayer *shapeLayer = [CAShapeLayer layer];
        shapeLayer.path = scaled.CGPath;

        [scaled applyTransform:scaleTransform];

        // Setting CAShapeLayer properties
        shapeLayer.strokeColor = self.strokeColor.CGColor;
        shapeLayer.lineWidth = self.lineWidth;
        
        if(path.fill) {
            if(colorsDict && colorsDict[path.identifier]) {
                UIColor* color = colorsDict[path.identifier];
                shapeLayer.fillColor = color.CGColor;
            } else {
                shapeLayer.fillColor = self.fillColor.CGColor;
            }
            
        } else {
            shapeLayer.fillColor = [[UIColor clearColor] CGColor];
        }
        
        [self.layer addSublayer:shapeLayer];
        
        [_scaledPaths addObject:scaled];
    }

    float scaleHorizontal = (self.frame.size.width - self.mapInset.left - self.mapInset.right) / _svg.bounds.size.width;
    float scaleVertical = (self.frame.size.height - self.mapInset.top - self.mapInset.bottom) / _svg.bounds.size.height;
    self.currentScale = MIN(scaleHorizontal, scaleVertical) / preScale;

    self.currentPan = CGPointMake(
            (self.mapInset.left - self.mapInset.right) / self.currentScale * preScale,
            (self.mapInset.top - self.mapInset.bottom) / self.currentScale * preScale
    );

    [self updateMap];
}

- (void)loadMap:(NSString*)mapName withData:(NSDictionary*)data colorAxis:(NSArray*)colors
{
    [self loadMap:mapName withColors:[self getColorsForData:data colorAxis:colors]];
}

- (NSDictionary*)getColorsForData:(NSDictionary*)data colorAxis:(NSArray*)colors
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:[data count]];
    
    float min = MAXFLOAT;
    float max = -MAXFLOAT;
    
    for (id key in data) {
        NSNumber* value = data[key];
        
        if([value floatValue] > max)
            max = [value floatValue];
        
        if([value floatValue] < min)
            min = [value floatValue];
    }
    
    for (id key in data) {
        NSNumber* value = data[key];
        float s = fabsf(([value floatValue] - min) / (max - min));
        float segmentLength = 1.0f / ([colors count] - 1);
        NSUInteger minColorIndex = MAX((NSUInteger) floorf(s / segmentLength), 0);
        NSUInteger maxColorIndex = MIN((NSUInteger) ceilf(s / segmentLength), [colors count] - 1);
        
        UIColor* minColor = colors[minColorIndex];
        UIColor* maxColor = colors[maxColorIndex];
        
        s -= segmentLength * minColorIndex;
        
        CGFloat maxColorRed = 0;
        CGFloat maxColorGreen = 0;
        CGFloat maxColorBlue = 0;
        CGFloat minColorRed = 0;
        CGFloat minColorGreen = 0;
        CGFloat minColorBlue = 0;
        
        [maxColor getRed:&maxColorRed green:&maxColorGreen blue:&maxColorBlue alpha:nil];
        [minColor getRed:&minColorRed green:&minColorGreen blue:&minColorBlue alpha:nil];
        
        UIColor* color = [UIColor colorWithRed:minColorRed * (1.0f - s) + maxColorRed * s
                                         green:minColorGreen * (1.0f - s) + maxColorGreen * s
                                          blue:minColorBlue * (1.0f - s) + maxColorBlue * s
                                         alpha:1];
        
        dict[key] = color;
    }
    
    return dict;
}

#pragma mark - Updating the colors and/or the data

- (void)setColors:(NSDictionary*)colorsDict
{
    for (NSUInteger i = 0; i < [_scaledPaths count]; i++) {
        FSSVGPathElement *element = _svg.paths[i];

        if ([self.layer.sublayers[i] isKindOfClass:CAShapeLayer.class] && element.fill) {
            CAShapeLayer *l = (CAShapeLayer *) self.layer.sublayers[i];

            if (element.fill) {
                if (colorsDict && colorsDict[element.identifier]) {
                    UIColor *color = colorsDict[element.identifier];
                    l.fillColor = color.CGColor;
                } else {
                    l.fillColor = self.fillColor.CGColor;
                }
            } else {
                l.fillColor = [[UIColor clearColor] CGColor];
            }
        }
    }
}

- (void)setData:(NSDictionary*)data colorAxis:(NSArray*)colors
{
    [self setColors:[self getColorsForData:data colorAxis:colors]];
}

#pragma mark - Layers enumeration

- (void)enumerateLayersUsingBlock:(void (^)(NSString *, CAShapeLayer *, BOOL *))block
{
    [_scaledPaths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        FSSVGPathElement *element = _svg.paths[idx];
        if ([self.layer.sublayers[idx] isKindOfClass:CAShapeLayer.class] && element.fill) {
            CAShapeLayer *l = (CAShapeLayer *) self.layer.sublayers[idx];
            block(element.identifier, l, stop);
        }
    }];
}

- (void)moveToLayer:(CAShapeLayer *)targetLayer animated:(BOOL)anim adjustScale:(BOOL)changeScale {
    NSUInteger idx = [self.layer.sublayers indexOfObject:targetLayer];
    if (idx != NSNotFound) {
        FSSVGPathElement *element = _svg.paths[idx];
        CGRect bounds = element.path.bounds;
        float preScale = [self mapPreScale];
        CGPoint mapPan = CGPointMake(
                (CGRectGetMidX(_svg.bounds) - CGRectGetMidX(bounds)) * preScale,
                (CGRectGetMidY(_svg.bounds) - CGRectGetMidY(bounds)) * preScale
        );
        if (changeScale) {
            float hScale = (self.frame.size.width - self.mapInset.left - self.mapInset.right) / bounds.size.width;
            float vScale = (self.frame.size.height - self.mapInset.top - self.mapInset.bottom) / bounds.size.height;
            self.currentScale = [self normalizedScale:fminf(hScale, vScale) / preScale];
        }
        mapPan.x += (self.mapInset.left - self.mapInset.right) / self.currentScale * preScale;
        mapPan.y += (self.mapInset.top - self.mapInset.bottom) / self.currentScale * preScale;
        self.currentPan = mapPan;
        [self updateMapAnimated:anim];
    }
}

#pragma mark - Touch handling

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        CGPoint touchPoint = [recognizer locationInView:self];
        for (NSUInteger i = 0; i < [_scaledPaths count]; i++) {
            UIBezierPath *path = _scaledPaths[i];
            if ([path containsPoint:touchPoint]) {
                FSSVGPathElement *element = _svg.paths[i];
                if ([self.layer.sublayers[i] isKindOfClass:[CAShapeLayer class]] && element.fill) {
                    CAShapeLayer *l = (CAShapeLayer *) self.layer.sublayers[i];
                    if (_clickHandler) {
                        _clickHandler(element.identifier, l);
                        return;
                    }
                }
            }
        }
        if (_clickHandler) {
            _clickHandler(nil, nil);
        }
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateEnded
        || recognizer.state == UIGestureRecognizerStateFailed || recognizer.state == UIGestureRecognizerStateCancelled) {
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            self.currentPan = CGPointMake(self.touchPan.x + self.currentPan.x, self.touchPan.y + self.currentPan.y);
        }
        self.touchPan = CGPointZero;
        [self updateMap];
    } else {
        CGPoint oldPoint = self.touchPan;
        CGPoint point = [recognizer translationInView:self];
        self.touchPan = CGPointMake(self.touchPan.x + point.x / self.currentScale, self.touchPan.y + point.y / self.currentScale);
        CGPoint newPoint = CGPointMake(self.touchPan.x + self.currentPan.x, self.touchPan.y + self.currentPan.y);
        if (!CGPointEqualToPoint(CGPointMake(oldPoint.x + self.currentPan.x, oldPoint.y + self.currentPan.y), newPoint)) {
            [self updateMapWithScale:self.currentScale pan:newPoint];
        } else {
            self.touchPan = oldPoint;
        }
        [recognizer setTranslation:CGPointZero inView:self];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateEnded
        || recognizer.state == UIGestureRecognizerStateFailed || recognizer.state == UIGestureRecognizerStateCancelled) {
        if (recognizer.state == UIGestureRecognizerStateEnded) {
            self.currentScale = [self normalizedScale:self.touchScale * self.currentScale];
        }
        self.touchScale = 1;
        [self updateMap];
    } else {
        CGFloat oldScale = self.touchScale;
        self.touchScale *= recognizer.scale;
        CGFloat newScale = [self normalizedScale:self.touchScale * self.currentScale];
        if (oldScale * self.currentScale != newScale) {
            [self updateMapWithScale:newScale pan:self.currentPan];
        } else {
            self.touchScale = oldScale;
        }
        recognizer.scale = 1;
    }
}

- (void)updateMap {
    [self updateMapAnimated:NO];
}

- (void)updateMapAnimated:(BOOL)anim {
    [self updateMapWithScale:self.currentScale pan:self.currentPan animated:anim];
}

- (void)updateMapWithScale:(CGFloat)mapScale pan:(CGPoint)mapPan {
    [self updateMapWithScale:mapScale pan:mapPan animated:NO];
}

- (void)updateMapWithScale:(CGFloat)mapScale pan:(CGPoint)mapPan animated:(BOOL)anim {
    if (_svg) {
        float scale = [self mapPreScale] * mapScale;
        
        CGFloat targetX = self.frame.size.width / 2 + mapPan.x * mapScale - CGRectGetMidX(_svg.bounds) * scale;
        CGFloat targetY = self.frame.size.height / 2 + mapPan.y * mapScale - CGRectGetMidY(_svg.bounds) * scale;
        
        CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(targetX, targetY);
        CGAffineTransform scaleTransform = CGAffineTransformScale(translateTransform, scale, scale);

        [CATransaction setAnimationDuration:anim ? self.animationTime : 0];
        
        for (NSUInteger i = 0; i < [_svg.paths count]; i++) {
            FSSVGPathElement *element = _svg.paths[i];
            if ([self.layer.sublayers[i] isKindOfClass:CAShapeLayer.class] && element.fill) {
                CAShapeLayer *l = (CAShapeLayer *) self.layer.sublayers[i];
                l.affineTransform = scaleTransform;
                l.lineWidth = self.lineWidth / mapScale;

                UIBezierPath *scaled = [element.path copy];
                [scaled applyTransform:scaleTransform];
                _scaledPaths[i] = scaled;
            }
        }
    }
}

- (float)mapPreScale {
    float scaleHorizontal = self.frame.size.width / _svg.bounds.size.width;
    float scaleVertical = self.frame.size.height / _svg.bounds.size.height;
    return MIN(scaleHorizontal, scaleVertical);
}

- (float)normalizedScale:(float)srcScale {
    return fminf(self.maxZoom, fmaxf(self.minZoom, srcScale));
}

@end
