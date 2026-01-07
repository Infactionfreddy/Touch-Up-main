//
//  TUCScreen.h
//  Touch Up Core
//
//  Created by Sebastian Hueber on 21.03.23.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The `TUCScreen` augments `NSScreen` with access to additional screen layout properties and information on the conversion of digitizer coordinate system to pixels.
 */
@interface TUCScreen : NSObject

@property NSUInteger id;
@property (strong) NSString *name;
@property CGFloat rotation;
@property CGSize physicalSize;
@property CGRect frame;

// 4-Punkt-Kalibrierung: Ecken (oben-links, oben-rechts, unten-links, unten-rechts)
@property CGPoint calibrationTouchA;  // oben-links (0.0, 0.0)
@property CGPoint calibrationTouchB;  // oben-rechts (1.0, 0.0)
@property CGPoint calibrationTouchC;  // unten-links (0.0, 1.0)
@property CGPoint calibrationTouchD;  // unten-rechts (1.0, 1.0)
@property CGPoint calibrationScreenA;
@property CGPoint calibrationScreenB;
@property CGPoint calibrationScreenC;
@property CGPoint calibrationScreenD;
@property BOOL isCalibrated;

- (CGFloat)pixelsPerMM;
- (CGPoint)convertPointRelativeToAbsolute:(CGPoint)relativePoint;

// Kalibrierungsmethoden
- (void)startCalibration;
- (void)recordCalibrationPoint:(CGPoint)touchPoint atScreenLocation:(CGPoint)screenPoint pointIndex:(NSInteger)index;
- (void)finishCalibration;
- (void)resetCalibration;

- (nullable NSScreen *)systemScreen;

+ (NSArray *)allScreens;

@end

NS_ASSUME_NONNULL_END
