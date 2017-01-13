//
//  FSInteractiveMapView.h
//  FSInteractiveMap
//
//  Created by Arthur GUIBERT on 23/12/2014.
//  Copyright (c) 2014 Arthur GUIBERT. All rights reserved.
//

#import <UIKit/UIKit.h>

static float const kFSInteractiveMapDefaultZoomMin = 0.9f;
static float const kFSInteractiveMapDefaultZoomMax = 20.0f;

static CGFloat const kFSInteractiveMapDefaultZoomPadding = 10.0f;
static CGFloat const kFSInteractiveMapDefaultLineWidth = 0.5f;

static NSTimeInterval const kFSInteractiveMapDefaultAnimationTime = 0.25f;


@interface FSInteractiveMapView : UIView

// Graphical properties
@property (nonatomic, strong) UIColor* fillColor;
@property (nonatomic, strong) UIColor* strokeColor;
@property (nonatomic, assign) CGFloat lineWidth;

// Zoom properties
@property (nonatomic, assign) float minZoom;
@property (nonatomic, assign) float maxZoom;
@property (nonatomic, assign) UIEdgeInsets mapInset;

@property (nonatomic, assign) NSTimeInterval animationTime;

// Click handler
@property (nonatomic, copy) void (^clickHandler)(NSString* identifier, CAShapeLayer* layer);

// Loading functions
- (void)loadMap:(NSString*)mapName withColors:(NSDictionary*)colorsDict;
- (void)loadMap:(NSString*)mapName withData:(NSDictionary*)data colorAxis:(NSArray*)colors;

// Set the colors by element, if you want to make the map dynamic or update the colors
- (void)setColors:(NSDictionary*)colorsDict;
- (void)setData:(NSDictionary*)data colorAxis:(NSArray*)colors;

// Layers enumeration
- (void)enumerateLayersUsingBlock:(void (^)(NSString *identifier, CAShapeLayer *layer, BOOL *stop))block;

- (void)moveToLayer:(CAShapeLayer *)targetLayer animated:(BOOL)anim adjustScale:(BOOL)changeScale;

@end
