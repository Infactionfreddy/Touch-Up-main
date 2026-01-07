//
//  TUCScreen.m
//  Touch Up Core
//
//  Created by Sebastian Hueber on 21.03.23.
//

#import "TUCScreen.h"

@implementation TUCScreen

- (instancetype)initWithScreen:(NSScreen *)screen frameOfFirstScreen:(CGRect)firstFrame {
    if (self = [super init]) {
        NSNumber *number = [[screen deviceDescription] valueForKey:@"NSScreenNumber"];
        CGDirectDisplayID displayID = [number unsignedIntValue];
        
        self.id = displayID;
        
        self.rotation = CGDisplayRotation(displayID);
        
        // Lade gespeicherte Kalibrierung
        [self loadCalibration];
        
        
        self.physicalSize = CGDisplayScreenSize(displayID);
        
        // CRITICAL FIX: Verwende CGDisplayBounds() direkt!
        // CGDisplayBounds gibt bereits die korrekten Core Graphics Koordinaten zurück.
        // NSScreen.frame ist in AppKit-Koordinaten und die manuelle Umrechnung war fehlerhaft.
        self.frame = CGDisplayBounds(displayID);
        
        printf("[TUCScreen] 🟦 DISPLAY FRAME INFO for ID=%u:\n", displayID);
        printf("           CGDisplayBounds: origin=(%.0f, %.0f) size=(%.0f x %.0f)\n",
               self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height);
        
        
        if (@available(macOS 10.15, *)) {
            self.name = [screen localizedName];
        } else {
            // Fallback on earlier versions
            self.name =  [NSString stringWithFormat: @"Display %u", displayID];
        }
        
    }
    
    return self;
}

- (nullable NSScreen *)systemScreen {
    NSArray *screens = [NSScreen screens];
    
    for (NSScreen *screen in screens) {
        NSNumber *number = [[screen deviceDescription] valueForKey:@"NSScreenNumber"];
        CGDirectDisplayID displayID = [number unsignedIntValue];
        if (displayID == self.id) {
            return screen;
        }
    }
    return nil;
}


- (CGFloat)pixelsPerMM {
    return self.frame.size.width / self.physicalSize.width;
}

- (CGPoint)convertPointRelativeToAbsolute:(CGPoint)relativePoint {
    CGPoint screenOrigin = self.frame.origin;
    CGSize screenSize = self.frame.size;
    
    CGPoint absLoc;
    
    // Prüfe ob wir eine gültige 4-Punkt-Kalibrierung haben
    BOOL hasCalibration = (self.isCalibrated && 
                          self.calibrationTouchB.x != self.calibrationTouchA.x &&
                          self.calibrationTouchD.x != self.calibrationTouchC.x &&
                          self.calibrationTouchC.y != self.calibrationTouchA.y &&
                          self.calibrationTouchD.y != self.calibrationTouchB.y);
    
    if (hasCalibration) {
        // === SIMPLES LINEARES MAPPING ===
        // Die Kalibrierungspunkte sind RAW gespeichert
        // Wir verwenden direkt die RAW-Koordinaten
        
        // RAW Touch-Koordinaten (0.0-1.0) OHNE Transformation
        CGFloat touchX = relativePoint.x;
        CGFloat touchY = relativePoint.y;
        
        // Berechne Min/Max aus Kalibrierungspunkten
        CGFloat touchMinX = fmin(fmin(self.calibrationTouchA.x, self.calibrationTouchB.x),
                                fmin(self.calibrationTouchC.x, self.calibrationTouchD.x));
        CGFloat touchMaxX = fmax(fmax(self.calibrationTouchA.x, self.calibrationTouchB.x),
                                fmax(self.calibrationTouchC.x, self.calibrationTouchD.x));
        
        CGFloat touchMinY = fmin(fmin(self.calibrationTouchA.y, self.calibrationTouchB.y),
                                fmin(self.calibrationTouchC.y, self.calibrationTouchD.y));
        CGFloat touchMaxY = fmax(fmax(self.calibrationTouchA.y, self.calibrationTouchB.y),
                                fmax(self.calibrationTouchC.y, self.calibrationTouchD.y));
        
        // Screen-Bereich: Minimum und Maximum der Screen-Koordinaten
        CGFloat screenMinX = fmin(fmin(self.calibrationScreenA.x, self.calibrationScreenB.x),
                                 fmin(self.calibrationScreenC.x, self.calibrationScreenD.x));
        CGFloat screenMaxX = fmax(fmax(self.calibrationScreenA.x, self.calibrationScreenB.x),
                                 fmax(self.calibrationScreenC.x, self.calibrationScreenD.x));
        
        CGFloat screenMinY = fmin(fmin(self.calibrationScreenA.y, self.calibrationScreenB.y),
                                 fmin(self.calibrationScreenC.y, self.calibrationScreenD.y));
        CGFloat screenMaxY = fmax(fmax(self.calibrationScreenA.y, self.calibrationScreenB.y),
                                 fmax(self.calibrationScreenC.y, self.calibrationScreenD.y));
        
        // Lineares Mapping: (touch - touchMin) * screenRange / touchRange + screenMin
        // WICHTIG: KEINE Clipping der Touch-Koordinaten - Extrapolation erlaubt!
        CGFloat screenX = (touchX - touchMinX) * (screenMaxX - screenMinX) / (touchMaxX - touchMinX) + screenMinX;
        CGFloat screenY = (touchY - touchMinY) * (screenMaxY - screenMinY) / (touchMaxY - touchMinY) + screenMinY;
        
        // ABER: Clippe Screen-Koordinaten auf Display-Ränder
        CGFloat displayMinX = self.frame.origin.x;
        CGFloat displayMaxX = self.frame.origin.x + self.frame.size.width;
        CGFloat displayMinY = self.frame.origin.y;
        CGFloat displayMaxY = self.frame.origin.y + self.frame.size.height;
        
        // Allow small margin at top edge for status bar accessibility
        CGFloat topEdgeMargin = 30.0;  // Allow 30px extrapolation above display origin
        
        if (screenX < displayMinX) screenX = displayMinX;
        if (screenX > displayMaxX) screenX = displayMaxX;
        if (screenY < (displayMinY - topEdgeMargin)) screenY = displayMinY - topEdgeMargin;
        if (screenY > displayMaxY) screenY = displayMaxY;
        
        absLoc = CGPointMake(screenX, screenY);
        
        printf("[TUCScreen] ✅ LINEAR MAPPING (ID=%u):\n", (unsigned int)self.id);
        printf("            RAW touch=(%.4f, %.4f)\n", relativePoint.x, relativePoint.y);
        printf("            Touch range: X[%.4f - %.4f], Y[%.4f - %.4f]\n", 
               touchMinX, touchMaxX, touchMinY, touchMaxY);
        printf("            Screen range: X[%.0f - %.0f], Y[%.0f - %.0f]\n",
               screenMinX, screenMaxX, screenMinY, screenMaxY);
        printf("            Display bounds: X[%.0f - %.0f], Y[%.0f - %.0f]\n",
               displayMinX, displayMaxX, displayMinY, displayMaxY);
        printf("            → Screen=(%.1f, %.1f)\n", screenX, screenY);
    } else {
        // Fallback ohne Kalibrierung
        absLoc = CGPointMake(
            screenOrigin.x + (relativePoint.x * screenSize.width),
            screenOrigin.y + (relativePoint.y * screenSize.height)
        );
        
        printf("[TUCScreen] ❌ NO CALIBRATION (ID=%u): touch(%.4f, %.4f) -> screen(%.0f, %.0f)\n",
               (unsigned int)self.id, relativePoint.x, relativePoint.y, absLoc.x, absLoc.y);
    }
    
    return absLoc;
}

#pragma mark - Kalibrierung

- (void)startCalibration {
    printf("[TUCScreen] CALIBRATION STARTED - Tippe oben-links\n");
    self.isCalibrated = NO;
}

- (void)recordCalibrationPoint:(CGPoint)touchPoint atScreenLocation:(CGPoint)screenPoint pointIndex:(NSInteger)index {
    const char *positions[] = {"OBEN-LINKS", "OBEN-RECHTS", "UNTEN-LINKS", "UNTEN-RECHTS"};
    const char *nextPositions[] = {"OBEN-RECHTS", "UNTEN-LINKS", "UNTEN-RECHTS", ""};
    
    printf("[TUCScreen] 🟢 recordCalibrationPoint CALLED: index=%ld touchRAW=(%.4f,%.4f) screen=(%.0f,%.0f)\n",
           index, touchPoint.x, touchPoint.y, screenPoint.x, screenPoint.y);
    
    // SIMPLES LINEARES MAPPING: Speichere RAW Touch-Koordinaten OHNE Transformation
    // Das Mapping wird später in convertPointRelativeToAbsolute durchgeführt
    printf("[TUCScreen]    -> Speichere RAW touch-Koordinaten (KEINE Transformation)\n");
    
    if (index == 0) {
        // Punkt A: oben-links
        self.calibrationTouchA = touchPoint;
        self.calibrationScreenA = screenPoint;
        printf("[TUCScreen] ✓ Punkt 1/4 (%s): touchRAW=(%.4f,%.4f) screen=(%.0f,%.0f) STORED\n",
               positions[0], touchPoint.x, touchPoint.y, screenPoint.x, screenPoint.y);
        printf("[TUCScreen]    -> Tippe jetzt auf %s\n", nextPositions[0]);
    } else if (index == 1) {
        // Punkt B: oben-rechts
        self.calibrationTouchB = touchPoint;
        self.calibrationScreenB = screenPoint;
        printf("[TUCScreen] ✓ Punkt 2/4 (%s): touchRAW=(%.4f,%.4f) screen=(%.0f,%.0f) STORED\n",
               positions[1], touchPoint.x, touchPoint.y, screenPoint.x, screenPoint.y);
        printf("[TUCScreen]    -> Tippe jetzt auf %s\n", nextPositions[1]);
    } else if (index == 2) {
        // Punkt C: unten-links
        self.calibrationTouchC = touchPoint;
        self.calibrationScreenC = screenPoint;
        printf("[TUCScreen] ✓ Punkt 3/4 (%s): touchRAW=(%.4f,%.4f) screen=(%.0f,%.0f) STORED\n",
               positions[2], touchPoint.x, touchPoint.y, screenPoint.x, screenPoint.y);
        printf("[TUCScreen]    -> Tippe jetzt auf %s\n", nextPositions[2]);
    } else if (index == 3) {
        // Punkt D: unten-rechts
        self.calibrationTouchD = touchPoint;
        self.calibrationScreenD = screenPoint;
        printf("[TUCScreen] ✓ Punkt 4/4 (%s): touchRAW=(%.4f,%.4f) screen=(%.0f,%.0f) STORED\n",
               positions[3], touchPoint.x, touchPoint.y, screenPoint.x, screenPoint.y);
        printf("[TUCScreen]    -> KALIBRIERUNG ABGESCHLOSSEN!\n");
        [self finishCalibration];
    }
}

- (void)finishCalibration {
    printf("[TUCScreen] 🔵 finishCalibration CALLED\n");
    printf("[TUCScreen]    -> Setting isCalibrated = YES\n");
    self.isCalibrated = YES;
    printf("[TUCScreen]    -> Calling saveCalibration...\n");
    [self saveCalibration];
    printf("[TUCScreen] ✅ CALIBRATION COMPLETE - isCalibrated=%s\n", self.isCalibrated ? "YES" : "NO");
}

- (void)resetCalibration {
    self.isCalibrated = NO;
    self.calibrationTouchA = CGPointZero;
    self.calibrationTouchB = CGPointZero;
    self.calibrationTouchC = CGPointZero;
    self.calibrationTouchD = CGPointZero;
    self.calibrationScreenA = CGPointZero;
    self.calibrationScreenB = CGPointZero;
    self.calibrationScreenC = CGPointZero;
    self.calibrationScreenD = CGPointZero;
    [self saveCalibration];
    printf("[TUCScreen] CALIBRATION RESET\n");
}

- (void)saveCalibration {
    printf("[TUCScreen] 🟡 saveCalibration CALLED (isCalibrated=%s)\n", self.isCalibrated ? "YES" : "NO");
    
    // Verwende externe JSON-Datei statt NSUserDefaults
    NSString *appSupportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *appDataDir = [appSupportPath stringByAppendingPathComponent:@"de.schafe.Touch-Up"];
    NSString *calibrationDir = [appDataDir stringByAppendingPathComponent:@"calibrations"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fileManager fileExistsAtPath:calibrationDir]) {
        [fileManager createDirectoryAtPath:calibrationDir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            printf("[TUCScreen] ❌ Error creating directory: %s\n", [[error localizedDescription] UTF8String]);
            return;
        }
    }
    
    NSString *calibrationFile = [calibrationDir stringByAppendingPathComponent:[NSString stringWithFormat:@"screen_%u.json", (unsigned int)self.id]];
    printf("[TUCScreen]    -> Calibration file path: %s\n", [calibrationFile UTF8String]);
    
    if (self.isCalibrated) {
        printf("[TUCScreen]    -> Creating calibration data...\n");
        printf("[TUCScreen]    -> touchA: (%.4f, %.4f) -> screenA: (%.0f, %.0f)\n",
               self.calibrationTouchA.x, self.calibrationTouchA.y,
               self.calibrationScreenA.x, self.calibrationScreenA.y);
        printf("[TUCScreen]    -> touchB: (%.4f, %.4f) -> screenB: (%.0f, %.0f)\n",
               self.calibrationTouchB.x, self.calibrationTouchB.y,
               self.calibrationScreenB.x, self.calibrationScreenB.y);
        printf("[TUCScreen]    -> touchC: (%.4f, %.4f) -> screenC: (%.0f, %.0f)\n",
               self.calibrationTouchC.x, self.calibrationTouchC.y,
               self.calibrationScreenC.x, self.calibrationScreenC.y);
        printf("[TUCScreen]    -> touchD: (%.4f, %.4f) -> screenD: (%.0f, %.0f)\n",
               self.calibrationTouchD.x, self.calibrationTouchD.y,
               self.calibrationScreenD.x, self.calibrationScreenD.y);
        
        NSDictionary *calibData = @{
            @"displayID": @((unsigned int)self.id),
            @"touchA": @{@"x": @(self.calibrationTouchA.x), @"y": @(self.calibrationTouchA.y)},
            @"touchB": @{@"x": @(self.calibrationTouchB.x), @"y": @(self.calibrationTouchB.y)},
            @"touchC": @{@"x": @(self.calibrationTouchC.x), @"y": @(self.calibrationTouchC.y)},
            @"touchD": @{@"x": @(self.calibrationTouchD.x), @"y": @(self.calibrationTouchD.y)},
            @"screenA": @{@"x": @(self.calibrationScreenA.x), @"y": @(self.calibrationScreenA.y)},
            @"screenB": @{@"x": @(self.calibrationScreenB.x), @"y": @(self.calibrationScreenB.y)},
            @"screenC": @{@"x": @(self.calibrationScreenC.x), @"y": @(self.calibrationScreenC.y)},
            @"screenD": @{@"x": @(self.calibrationScreenD.x), @"y": @(self.calibrationScreenD.y)},
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        };
        
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:calibData options:NSJSONWritingPrettyPrinted error:&error];
        if (jsonData) {
            [jsonData writeToFile:calibrationFile atomically:YES];
            printf("[TUCScreen] ✅ 4-POINT CALIBRATION SAVED to: %s\n", [calibrationFile UTF8String]);
        } else {
            printf("[TUCScreen] ❌ Error serializing JSON: %s\n", [[error localizedDescription] UTF8String]);
        }
    } else {
        printf("[TUCScreen]    -> isCalibrated is NO, removing file\n");
        if ([fileManager fileExistsAtPath:calibrationFile]) {
            [fileManager removeItemAtPath:calibrationFile error:&error];
            if (error) {
                printf("[TUCScreen] ❌ Error removing file: %s\n", [[error localizedDescription] UTF8String]);
            } else {
                printf("[TUCScreen] ✅ Calibration file removed: %s\n", [calibrationFile UTF8String]);
            }
        }
    }
}

- (void)loadCalibration {
    printf("[TUCScreen] 🟣 loadCalibration CALLED for display ID=%u\n", (unsigned int)self.id);
    
    // Lade externe JSON-Datei statt NSUserDefaults
    NSString *appSupportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *appDataDir = [appSupportPath stringByAppendingPathComponent:@"de.schafe.Touch-Up"];
    NSString *calibrationDir = [appDataDir stringByAppendingPathComponent:@"calibrations"];
    NSString *calibrationFile = [calibrationDir stringByAppendingPathComponent:[NSString stringWithFormat:@"screen_%u.json", (unsigned int)self.id]];
    
    printf("[TUCScreen]    -> Looking for calibration file: %s\n", [calibrationFile UTF8String]);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:calibrationFile]) {
        printf("[TUCScreen]    -> ❌ NO calibration file found\n");
        self.isCalibrated = NO;
        printf("[TUCScreen] ❌ NO CALIBRATION found for display %u\n", (unsigned int)self.id);
        return;
    }
    
    printf("[TUCScreen]    -> ✓ Found calibration file\n");
    
    NSError *error = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:calibrationFile options:0 error:&error];
    if (!jsonData) {
        printf("[TUCScreen] ❌ Error reading file: %s\n", [[error localizedDescription] UTF8String]);
        self.isCalibrated = NO;
        return;
    }
    
    NSDictionary *calibData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (!calibData) {
        printf("[TUCScreen] ❌ Error parsing JSON: %s\n", [[error localizedDescription] UTF8String]);
        self.isCalibrated = NO;
        return;
    }
    
    printf("[TUCScreen]    -> ✓ Parsed calibration data\n");
    printf("[TUCScreen]    -> Parsing 4-POINT calibration...\n");
    
    // Parse 4-Punkt-Kalibrierung aus JSON
    NSDictionary *touchADict = calibData[@"touchA"];
    NSDictionary *touchBDict = calibData[@"touchB"];
    NSDictionary *touchCDict = calibData[@"touchC"];
    NSDictionary *touchDDict = calibData[@"touchD"];
    NSDictionary *screenADict = calibData[@"screenA"];
    NSDictionary *screenBDict = calibData[@"screenB"];
    NSDictionary *screenCDict = calibData[@"screenC"];
    NSDictionary *screenDDict = calibData[@"screenD"];
    
    if (touchADict && screenADict && touchDDict && screenDDict) {
        _calibrationTouchA = CGPointMake([touchADict[@"x"] doubleValue], [touchADict[@"y"] doubleValue]);
        printf("[TUCScreen]       → touchA: (%.4f, %.4f)\n", _calibrationTouchA.x, _calibrationTouchA.y);
        
        _calibrationTouchB = CGPointMake([touchBDict[@"x"] doubleValue], [touchBDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → touchB: (%.4f, %.4f)\n", _calibrationTouchB.x, _calibrationTouchB.y);
        
        _calibrationTouchC = CGPointMake([touchCDict[@"x"] doubleValue], [touchCDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → touchC: (%.4f, %.4f)\n", _calibrationTouchC.x, _calibrationTouchC.y);
        
        _calibrationTouchD = CGPointMake([touchDDict[@"x"] doubleValue], [touchDDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → touchD: (%.4f, %.4f)\n", _calibrationTouchD.x, _calibrationTouchD.y);
        
        _calibrationScreenA = CGPointMake([screenADict[@"x"] doubleValue], [screenADict[@"y"] doubleValue]);
        printf("[TUCScreen]       → screenA: (%.0f, %.0f)\n", _calibrationScreenA.x, _calibrationScreenA.y);
        
        _calibrationScreenB = CGPointMake([screenBDict[@"x"] doubleValue], [screenBDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → screenB: (%.0f, %.0f)\n", _calibrationScreenB.x, _calibrationScreenB.y);
        
        _calibrationScreenC = CGPointMake([screenCDict[@"x"] doubleValue], [screenCDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → screenC: (%.0f, %.0f)\n", _calibrationScreenC.x, _calibrationScreenC.y);
        
        _calibrationScreenD = CGPointMake([screenDDict[@"x"] doubleValue], [screenDDict[@"y"] doubleValue]);
        printf("[TUCScreen]       → screenD: (%.0f, %.0f)\n", _calibrationScreenD.x, _calibrationScreenD.y);
        
        self.isCalibrated = YES;
        printf("[TUCScreen] ✅ 4-POINT CALIBRATION LOADED from file for display %u - isCalibrated=YES\n", (unsigned int)self.id);
    } else {
        printf("[TUCScreen]    -> ❌ Incomplete calibration data in file\n");
        self.isCalibrated = NO;
        printf("[TUCScreen] ❌ CORRUPTED CALIBRATION DATA for display %u\n", (unsigned int)self.id);
    }
}



- (NSString *)debugDescription {
    return [NSString stringWithFormat:@"<[TUFScreen ID %ld] Frame: %@, Name: %@>", self.id, NSStringFromRect(self.frame), self.name];
}

+ (NSArray *)allScreens {
    NSMutableArray<TUCScreen *> *myScreens = [NSMutableArray array];
    
    NSArray *nsScreens = [NSScreen screens];
    
    CGRect firstFrame = CGRectZero;
    if ([nsScreens count] > 0) {
        NSScreen  *firstScreen = [nsScreens objectAtIndex:0];
        firstFrame = firstScreen.frame;
    }
    
    for (NSScreen *screen in nsScreens) {
        TUCScreen *e = [[TUCScreen alloc] initWithScreen:screen
                                      frameOfFirstScreen:firstFrame];
        [myScreens addObject:e];
    }
    
    return myScreens;
}

@end
