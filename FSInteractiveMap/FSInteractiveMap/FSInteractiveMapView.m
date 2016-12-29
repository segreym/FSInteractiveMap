//
//  FSInteractiveMapView.m
//  FSInteractiveMap
//
//  Created by Arthur GUIBERT on 23/12/2014.
//  Copyright (c) 2014 Arthur GUIBERT. All rights reserved.
//

#import "FSInteractiveMapView.h"
#import "FSSVG.h"


static float const kMapZoomMax = 20.0f;
static float const kMapZoomMin = 0.9f;


@interface FSInteractiveMapView ()

@property (nonatomic, strong) FSSVG* svg;
@property (nonatomic, strong) NSMutableArray* scaledPaths;

@property (nonatomic, assign) CGFloat currentScale;
@property (nonatomic, assign) CGPoint currentPan;

@property (nonatomic, assign) CGFloat touchScale;
@property (nonatomic, assign) CGPoint touchPan;

@end


@implementation FSInteractiveMapView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self) {
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
    
    return self;
}

- (void)setDefaultParameters
{
    self.fillColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.strokeColor = [UIColor colorWithWhite:0.6 alpha:1];
}

- (void)setFrame:(CGRect)frame {
    CGSize oldSize = self.frame.size;
    [super setFrame:frame];
    if (!CGSizeEqualToSize(oldSize, frame.size)) {
        [self updateMapScaled];
    }
}

- (void)setBounds:(CGRect)bounds {
    CGSize oldSize = self.bounds.size;
    [super setBounds:bounds];
    if (!CGSizeEqualToSize(oldSize, bounds.size)) {
        [self updateMapScaled];
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
    
    for (FSSVGPathElement* path in _svg.paths) {
        // Make the map fits inside the frame
        float scaleHorizontal = self.frame.size.width / _svg.bounds.size.width;
        float scaleVertical = self.frame.size.height / _svg.bounds.size.height;
        float scale = MIN(scaleHorizontal, scaleVertical);
        
        CGAffineTransform scaleTransform = CGAffineTransformIdentity;
        scaleTransform = CGAffineTransformMakeScale(scale, scale);
        scaleTransform = CGAffineTransformTranslate(scaleTransform,-_svg.bounds.origin.x, -_svg.bounds.origin.y);
        
        UIBezierPath* scaled = [path.path copy];
        [scaled applyTransform:scaleTransform];
        
        CAShapeLayer *shapeLayer = [CAShapeLayer layer];
        shapeLayer.path = scaled.CGPath;
        
        // Setting CAShapeLayer properties
        shapeLayer.strokeColor = self.strokeColor.CGColor;
        shapeLayer.lineWidth = 0.5f;
        
        if(path.fill) {
            if(colorsDict && [colorsDict objectForKey:path.identifier]) {
                UIColor* color = [colorsDict objectForKey:path.identifier];
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
        NSNumber* value = [data objectForKey:key];
        
        if([value floatValue] > max)
            max = [value floatValue];
        
        if([value floatValue] < min)
            min = [value floatValue];
    }
    
    for (id key in data) {
        NSNumber* value = [data objectForKey:key];
        float s = ([value floatValue] - min) / (max - min);
        float segmentLength = 1.0 / ([colors count] - 1);
        int minColorIndex = MAX(floorf(s / segmentLength),0);
        int maxColorIndex = MIN(ceilf(s / segmentLength), [colors count] - 1);
        
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
        
        UIColor* color = [UIColor colorWithRed:minColorRed * (1.0 - s) + maxColorRed * s
                                         green:minColorGreen * (1.0 - s) + maxColorGreen * s
                                          blue:minColorBlue * (1.0 - s) + maxColorBlue * s
                                         alpha:1];
        
        [dict setObject:color forKey:key];
    }
    
    return dict;
}

#pragma mark - Updating the colors and/or the data

- (void)setColors:(NSDictionary*)colorsDict
{
    for(int i=0;i<[_scaledPaths count];i++) {
        FSSVGPathElement* element = _svg.paths[i];
        
        if([self.layer.sublayers[i] isKindOfClass:CAShapeLayer.class] && element.fill) {
            CAShapeLayer* l = self.layer.sublayers[i];
            
            if(element.fill) {
                if(colorsDict && [colorsDict objectForKey:element.identifier]) {
                    UIColor* color = [colorsDict objectForKey:element.identifier];
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
        [self updateMapScaled];
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
            self.currentScale = fminf(kMapZoomMax, fmaxf(kMapZoomMin, self.touchScale * self.currentScale));
        }
        self.touchScale = 1;
        [self updateMapScaled];
    } else {
        CGFloat oldScale = self.touchScale;
        self.touchScale *= recognizer.scale;
        CGFloat newScale = fminf(kMapZoomMax, fmaxf(kMapZoomMin, self.touchScale * self.currentScale));
        if (oldScale * self.currentScale != newScale) {
            [self updateMapWithScale:newScale pan:self.currentPan];
        } else {
            self.touchScale = oldScale;
        }
        recognizer.scale = 1;
    }
}

- (void)updateMapScaled {
    [self updateMapWithScale:self.currentScale pan:self.currentPan];
}

- (void)updateMapWithScale:(CGFloat)mapScale pan:(CGPoint)mapPan {
    if (_svg) {
        float scaleHorizontal = self.frame.size.width / _svg.bounds.size.width;
        float scaleVertical = self.frame.size.height / _svg.bounds.size.height;
        float preScale = MIN(scaleHorizontal, scaleVertical);
        
        float scale = preScale * mapScale;
        
        CGFloat targetX = self.frame.size.width / 2 + mapPan.x * mapScale - (scale * _svg.bounds.size.width - 1) / 2;
        CGFloat targetY = self.frame.size.height / 2 + mapPan.y * mapScale - (scale * _svg.bounds.size.height - 1) / 2;
        
        CGAffineTransform translateTransform = CGAffineTransformMakeTranslation(targetX, targetY);
        CGAffineTransform scaleTransform = CGAffineTransformScale(translateTransform, scale, scale);
        
        for (NSUInteger i = 0; i < [_svg.paths count]; i++) {
            FSSVGPathElement *element = _svg.paths[i];
            if ([self.layer.sublayers[i] isKindOfClass:CAShapeLayer.class] && element.fill) {
                CAShapeLayer *l = (CAShapeLayer *) self.layer.sublayers[i];
                UIBezierPath *scaled = [element.path copy];
                [scaled applyTransform:scaleTransform];
                l.path = scaled.CGPath;
                _scaledPaths[i] = scaled;
            }
        }
        [self setNeedsDisplay];
    }
}

@end
