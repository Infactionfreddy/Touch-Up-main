//
//  TUCTouchInputManager.m
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#import "TUCTouchInputManager.h"

#import "HIDInterpreter.h"
#import "TUCCursorUtilities.h"

@interface TUCTouchInputManager ()

@property NSInteger currentFrameID;

@property (weak, nullable) TUCTouch *cursorTouch;
@property (weak, nullable) TUCTouch *gestureAdditionalTouch;

@property BOOL cursorTouchQualifiedForTap; // if the cursor entered moving state once it can no longer be interpreted as tap
@property BOOL cursorTouchDidHold; //
@property (strong) NSDate *cursorTouchStationarySinceDate;

@property CGFloat pinchDistance;

@property TUCCursorGesture identifiedMultitouchGesture;

@end


@implementation TUCTouchInputManager

#pragma mark   Start & Stop

- (void)start {
    // KRITISCH: Stelle sicher dass postMouseEvents TRUE ist
    self.postMouseEvents = YES;
    
    printf("[TUCTouchInputManager start] postMouseEvents=%d (FORCED TO YES)\n", self.postMouseEvents);
    
    __weak id weakSelf = self;
    
    // needs to run on main anyway
//    [NSThread detachNewThreadWithBlock:^{
//        [NSThread setThreadPriority:1];
        OpenHIDManager((__bridge void *)(weakSelf));
//    }];
    
}

- (void)stop {
    CloseHIDManager();
}


- (void)didConnectTouchscreen {
    [self.delegate touchscreenDidConnect];
}

- (void)didDisconnectTouchscreen {
    [self.delegate touchscreenDidDisconnect];
}



#pragma mark - Reacting to HID Events

- (void)didProcessReport {
    // go through all touches: if the frame is not the latest one, the touch might be old and should be removed.
    
    NSArray *touchesArray = [[self.touchSet copy] allObjects];
    for (TUCTouch *touch in touchesArray) {
        
        if (touch.lastUpdated + self.errorResistance < self.currentFrameID) {
            printf("[TOUCH TIMEOUT] contactID=%ld lastUpdated=%ld currentFrame=%ld errorResistance=%ld\n",
                   (long)touch.contactID, (long)touch.lastUpdated, (long)self.currentFrameID, (long)self.errorResistance);
            [touch setPhase:NSTouchPhaseCancelled];
            
            // CRITICAL: Wenn dieser Touch der cursorTouch ist, müssen wir ihn auf nil setzen
            if (self.cursorTouch && touch.uuid == self.cursorTouch.uuid) {
                printf("[CURSOR CLEARED BY TIMEOUT] contactID=%ld - resetting cursorTouch\n", (long)touch.contactID);
                self.cursorTouch = nil;
            }
            
            // CRITICAL: Auch gestureAdditionalTouch bereinigen
            if (self.gestureAdditionalTouch && touch.uuid == self.gestureAdditionalTouch.uuid) {
                printf("[GESTURE CLEARED BY TIMEOUT] contactID=%ld - resetting gestureAdditionalTouch\n", (long)touch.contactID);
                self.gestureAdditionalTouch = nil;
            }
            
            [self removeTouch:touch now:NO];
        }
    }
    
    if ([[self activeTouches] count] == 0) {
        [self stopCurrentGesture];
        
        // RADICAL FIX: Wenn KEINE aktiven Touches mehr → touchSet KOMPLETT leeren
        // Das verhindert Ghost-Touches und garantiert sauberen Neustart
        if ([self.touchSet count] > 0) {
            printf("[RADICAL CLEANUP] Keine aktiven Touches → lösche ALLE %ld Touches aus touchSet\n", 
                   (long)[self.touchSet count]);
            [self.touchSet removeAllObjects];
            [[self delegate] touchesDidChange];
        }
    }
    
    // CRITICAL FIX: Proaktive Bereinigung wenn touchSet zu groß wird
    // Bei 10 Fingern kann das Set auf 20+ Touches wachsen wenn Removal nicht schnell genug ist
    NSInteger touchSetSize = [self.touchSet count];
    NSInteger activeCount = [[self activeTouches] count];
    
    if (touchSetSize > 10 || (touchSetSize > activeCount + 3)) {
        NSMutableArray *staleToRemove = [NSMutableArray array];
        for (TUCTouch *t in self.touchSet) {
            if (t.phase == NSTouchPhaseEnded || t.phase == NSTouchPhaseCancelled) {
                [staleToRemove addObject:t];
            }
        }
        
        if ([staleToRemove count] > 0) {
            printf("[PROACTIVE CLEANUP] touchSet zu groß (%ld total, %ld active) - entferne %ld ENDED/CANC: ",
                   touchSetSize, activeCount, (long)[staleToRemove count]);
            for (TUCTouch *t in staleToRemove) {
                printf("ID=%ld ", (long)t.contactID);
                [self.touchSet removeObject:t];
            }
            printf("\n");
            [[self delegate] touchesDidChange];
        }
    }
    
    ++self.currentFrameID;
    
    [self processTouchesForCursorInput];
    
}


- (void)stopCurrentGesture {
    [[TUCCursorUtilities sharedInstance] stopDraggingCursor];
    [[TUCCursorUtilities sharedInstance] stopMagnifying];

    self.identifiedMultitouchGesture = _TUCCursorGestureNone;
}



/**
 Most important event handling callback: it posts the events to the system where the touches need to go
 */
- (void)updateTouch:(NSInteger)contactID withLocation:(CGPoint)digitizerPoint onSurface:(BOOL)isOnSurface tooLargeForFinger:(BOOL)confidenceFlag {
    
    // Debug: Zeige ALLE updateTouch Aufrufe
    static int updateCount = 0;
    if (++updateCount % 100 == 0) {
        printf("[updateTouch] #%d contactID=%ld point=(%.2f,%.2f) onSurface=%d confidence=%d\n",
               updateCount, (long)contactID, digitizerPoint.x, digitizerPoint.y, isOnSurface, confidenceFlag);
    }
    
    // assume that this is an erroneous message!!!
    if (self.ignoreOriginTouches && CGPointEqualToPoint(digitizerPoint, CGPointZero)) {
        return;
    }
    
    CGPoint point = [self convertDigitizerPointToRelativeScreenPoint:digitizerPoint];
    
    BOOL isNewTouch = NO;
    TUCTouch *touch = [self obtainTouchWithID:contactID isNew:&isNewTouch];
    
    if (isNewTouch) {
        printf("[NEW TOUCH] contactID=%ld confidenceFlag=%d onSurface=%d\n", (long)contactID, confidenceFlag, isOnSurface);
    }
    
    // CRITICAL FIX: KEINE cursorTouch-Zuweisung hier!
    // Das wird ausschließlich in processTouchesForCursorInput gemacht
    // Diese Logik hat zu "ID bleibt bei 1 stecken" geführt
    
    [touch setLocation: point];
    [touch setIsOnSurface:isOnSurface];
    [touch setConfidenceFlag:confidenceFlag];
    [touch setLastUpdated:self.currentFrameID];
    
    if (!isOnSurface) {
        [touch setPhase: NSTouchPhaseEnded];
        
        // Nicht hier cursorTouch auf nil setzen! Das wird in processTouchesForCursorInput gemacht
        // nachdem die ENDED-Phase verarbeitet wurde
        if (touch.uuid == self.cursorTouch.uuid) {
            printf("[CURSOR ENDING] contactID=%ld phase=ENDED (wird in processTouches verarbeitet)\n", (long)contactID);
        }
        
        // Touch mit Verzögerung entfernen (damit Phasen-Tracking funktioniert)
        [self removeTouch:touch now:NO];
        [self.delegate touchesDidChange];
        return;
        
    }
    
    if(touch.previousPhase != NSTouchPhaseEnded && !isNewTouch) {
        // update to an existing touch... check if stationary or not
        CGFloat digitizerRelDistance = sqrt(pow(touch.location.x - touch.previousLocation.x, 2) + pow(touch.location.y - touch.previousLocation.y, 2));
        CGFloat screenSize = [self touchscreen].physicalSize.width;
        BOOL isStationary = (digitizerRelDistance * screenSize) < 0.1;
//        BOOL isStationary = CGPointEqualToPoint(touch.location, touch.previousLocation);
        
        if (touch.uuid == self.cursorTouch.uuid) {
            if (!isStationary) {
                self.cursorTouchQualifiedForTap = NO;
                self.cursorTouchStationarySinceDate = nil;
                
            } else if (touch.phase !=  NSTouchPhaseStationary) {
                self.cursorTouchStationarySinceDate = [NSDate date];
            }
        }
        
        [touch setPhase:isStationary ? NSTouchPhaseStationary : NSTouchPhaseMoved];
    }
    
    
    [self.delegate touchesDidChange];
    
    return;
}


- (void)updateTouch:(NSInteger)contactID withSize:(CGSize)size azimuth:(CGFloat)azimuth {
    BOOL isNewTouch = NO;
    TUCTouch *touch = [self obtainTouchWithID:contactID isNew:&isNewTouch];
    [touch setLastUpdated:self.currentFrameID];
    
    [touch setSize:size];
    [touch setAzimuth:azimuth];
}



#pragma mark - Mouse Cursor Management



- (void)processTouchesForCursorInput {
    
    if(!self.postMouseEvents) {
        return;
    }
    
    NSSet *activeTouches = [self activeTouches];
    NSInteger activeTouchCount = [activeTouches count];
    NSInteger totalTouchCount = [self.touchSet count];
    
    // DEBUG: Zeige ALLE Touches in touchSet + ihre Phasen
    NSMutableString *touchSetDebug = [NSMutableString stringWithFormat:@"[TOUCHSET] %ld total, %ld active: ", totalTouchCount, activeTouchCount];
    for (TUCTouch *t in self.touchSet) {
        NSString *phaseStr;
        switch (t.phase) {
            case NSTouchPhaseBegan: phaseStr = @"BEGAN"; break;
            case NSTouchPhaseStationary: phaseStr = @"STAT"; break;
            case NSTouchPhaseMoved: phaseStr = @"MOVED"; break;
            case NSTouchPhaseEnded: phaseStr = @"ENDED"; break;
            case NSTouchPhaseCancelled: phaseStr = @"CANC"; break;
            default: phaseStr = @"UNK"; break;
        }
        [touchSetDebug appendFormat:@"(ID=%ld:%s) ", (long)t.contactID, [phaseStr UTF8String]];
    }
    printf("%s\n", [touchSetDebug UTF8String]);
    
    // FORCE VALIDATION: Bei jedem Call überprüfen
    // Wenn cursorTouch nicht mehr in activeTouches ist → auf nil setzen
    if (self.cursorTouch && ![activeTouches containsObject:self.cursorTouch]) {
        printf("[VALIDATION FAIL] cursorTouch (ID=%ld) nicht in activeTouches - RESET\n", 
               (long)self.cursorTouch.contactID);
        self.cursorTouch = nil;
        self.gestureAdditionalTouch = nil;
    }
    
    // Auch gestureAdditionalTouch validieren
    if (self.gestureAdditionalTouch && ![activeTouches containsObject:self.gestureAdditionalTouch]) {
        printf("[VALIDATION FAIL] gestureAdditionalTouch (ID=%ld) nicht in activeTouches - RESET\n", 
               (long)self.gestureAdditionalTouch.contactID);
        self.gestureAdditionalTouch = nil;
    }
    
    // Wenn KEINE Touches aktiv sind → sofort komplett zurücksetzen
    if (activeTouchCount == 0) {
        if (self.cursorTouch) {
            printf("[NO TOUCHES] Alle Fingers hochgehoben - RESET cursorTouch\n");
            self.cursorTouch = nil;
            self.gestureAdditionalTouch = nil;
        }
        return;
    }
    
    // CRITICAL FIX: Bei nur 1 aktivem Touch IMMER cursorTouch neu zuweisen
    // Das verhindert "ID bleibt bei 1 stecken" nach Multi-Touch
    if (activeTouchCount == 1) {
        TUCTouch *onlyTouch = [activeTouches anyObject];
        if (!self.cursorTouch || self.cursorTouch.contactID != onlyTouch.contactID) {
            printf("[SINGLE TOUCH] Erzwinge cursorTouch=ID=%ld (war %s)\n", 
                   (long)onlyTouch.contactID,
                   self.cursorTouch ? [[NSString stringWithFormat:@"ID=%ld", (long)self.cursorTouch.contactID] UTF8String] : "nil");
            self.cursorTouch = onlyTouch;
            self.cursorTouchQualifiedForTap = YES;
            self.cursorTouchDidHold = NO;
            self.cursorTouchStationarySinceDate = nil;
            self.gestureAdditionalTouch = nil; // Kein zweiter Finger mehr
        }
        return;
    }
    
    // Wenn kein cursorTouch → assign den mit niedrigster contactID
    if (!self.cursorTouch) {
        TUCTouch *lowestIDTouch = nil;
        NSInteger minID = LLONG_MAX;
        for (TUCTouch *touch in activeTouches) {
            if (touch.contactID < minID) {
                minID = touch.contactID;
                lowestIDTouch = touch;
            }
        }
        
        if (lowestIDTouch) {
            self.cursorTouch = lowestIDTouch;
            self.cursorTouchQualifiedForTap = YES;
            self.cursorTouchDidHold = NO;
            self.cursorTouchStationarySinceDate = nil;
            printf("[NEW CURSOR] Zugewiesen contactID=%ld (lowest of %ld touches)\n", 
                   (long)lowestIDTouch.contactID, (long)activeTouchCount);
        }
        return;
    }
    
    // Jetzt haben wir definitiv einen gültigen cursorTouch
    TUCTouch *cursorTouch = self.cursorTouch;
    NSTouchPhase phase = cursorTouch.phase;
    
    printf("[PROCESS] cursor=%ld phase=%ld activeTouches=%ld\n", 
           (long)cursorTouch.contactID, (long)phase, activeTouchCount);
    
    // Zwei-Finger-Gestenerkennung (wenn 2+ Finger aktiv und noch keine gestureAdditionalTouch)
    if (activeTouchCount >= 2 && !self.gestureAdditionalTouch) {
        for (TUCTouch *touch in activeTouches) {
            if (touch.contactID != cursorTouch.contactID) {
                self.gestureAdditionalTouch = touch;
                printf("[GESTURE DETECTED] zweiter Finger erkannt: cursor=%ld, additional=%ld\n",
                       (long)cursorTouch.contactID, (long)touch.contactID);
                break;
            }
        }
    }
    
    // Wenn weniger als 2 Finger → lösche gestureAdditionalTouch
    if (activeTouchCount < 2 && self.gestureAdditionalTouch) {
        printf("[GESTURE CLEARED] nur noch %ld Touch(es)\n", activeTouchCount);
        self.gestureAdditionalTouch = nil;
    }
    
    // ==== PHASE PROCESSING ====
    
    if (phase == NSTouchPhaseBegan) {
        printf("[BEGAN] contactID=%ld\n", (long)cursorTouch.contactID);
        self.cursorTouchQualifiedForTap = YES;
        return;
    }
    
    else if (phase == NSTouchPhaseStationary) {
        // Ignorieren
        return;
    }
    
    else if (phase == NSTouchPhaseMoved) {
        if (self.gestureAdditionalTouch && activeTouchCount >= 2) {
            printf("[MOVED] zwei-finger drag\n");
            [self performMouseEventForGesture:TUCCursorGestureTwoFingerDrag];
        } else {
            self.cursorTouchQualifiedForTap = NO;
            printf("[MOVED] ein-finger drag\n");
            [self performMouseEventForGesture:TUCCursorGestureDrag];
        }
        return;
    }
    
    else if (phase == NSTouchPhaseEnded) {
        printf("[ENDED] contactID=%ld qualified=%d\n", (long)cursorTouch.contactID, self.cursorTouchQualifiedForTap);
        
        // Sende das entsprechende Event
        if (self.cursorTouchQualifiedForTap) {
            printf("        → sende TAP\n");
            [self performMouseEventForGesture:TUCCursorGestureTap];
        } else {
            printf("        → sende DRAG END\n");
            [self performMouseEventForGesture:TUCCursorGestureDrag];
        }
        
        [self stopCurrentGesture];
        
        // KRITISCH: SOFORT cursorTouch auf nil, damit nächster Touch neu zugewiesen wird
        self.cursorTouch = nil;
        self.gestureAdditionalTouch = nil;
        printf("        → cursorTouch RESET zu nil\n");
        return;
    }
    
    else if (phase == NSTouchPhaseCancelled) {
        printf("[CANCELLED] contactID=%ld\n", (long)cursorTouch.contactID);
        [self stopCurrentGesture];
        
        self.cursorTouch = nil;
        self.gestureAdditionalTouch = nil;
        printf("        → cursorTouch RESET zu nil\n");
        return;
    }
}


- (BOOL)checkForSecondaryClick {
    // Deaktiviert - nur Klick und Ziehen aktiv
    return NO;
}


- (void)performMouseEventForGesture:(TUCCursorGesture)gesture {
    // CRITICAL: Dies wird vom HID-Queue-Callback aufgerufen, welcher auf einem Background-Thread läuft.
    // CGEventPost MUSS auf dem Main Thread ausgeführt werden!
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        TUCTouch *touch = strongSelf.cursorTouch;
        
        // CRITICAL: Null-check - wenn cursorTouch zwischen Aufruf und Dispatch gelöscht wurde
        if (!touch) return;
        
        CGPoint screenLocation = [strongSelf convertScreenPointRelativeToAbsolute:touch.location];
        CGPoint location2ndFinger = CGPointZero;
        if (strongSelf.gestureAdditionalTouch) {
            location2ndFinger = [strongSelf convertScreenPointRelativeToAbsolute:strongSelf.gestureAdditionalTouch.location];
        }
        
        TUCCursorUtilities *utils = [TUCCursorUtilities sharedInstance];
        
        TUCCursorAction action = [strongSelf actionForGesture:gesture];
       
           // Log detected gestures  
           NSString *actionName = @"Unknown";
           switch (action) {
               case TUCCursorActionNone:           actionName = @"None"; break;
               case TUCCursorActionMove:           actionName = @"Move"; break;
               case TUCCursorActionMoveClickIfNeeded: actionName = @"MoveClickIfNeeded"; break;
               case TUCCursorActionPointAndClick:  actionName = @"PointAndClick"; break;
               case TUCCursorActionDrag:           actionName = @"Drag"; break;
               case TUCCursorActionClick:          actionName = @"Click"; break;
               case TUCCursorActionSecondaryClick: actionName = @"SecondaryClick"; break;
               case TUCCursorActionScroll:         actionName = @"Scroll"; break;
               case TUCCursorActionMagnify:        actionName = @"Magnify"; break;
           }
       
           if (action != TUCCursorActionMove && action != TUCCursorActionMoveClickIfNeeded) {
               printf("[GESTURE] %s at (%.0f, %.0f)\n", [actionName UTF8String], screenLocation.x, screenLocation.y);
           }
        
        CGFloat doubleClickSpan = strongSelf.doubleClickTolerance * [[strongSelf touchscreen] pixelsPerMM];
        [[TUCCursorUtilities sharedInstance] setDoubleClickTolerance:doubleClickSpan];
        
        switch (action) {
            case TUCCursorActionNone:
                break;
                
            case TUCCursorActionMove:
                [utils moveCursorTo:screenLocation];
                break;
                
            case TUCCursorActionMoveClickIfNeeded:
                [utils moveCursorTo:screenLocation];
                if ([strongSelf isLocationOutsideFrontmostWindow:screenLocation]) {
                    [utils performClickAt:screenLocation];
                }
                
                break;
                
            case TUCCursorActionPointAndClick:
                [utils moveCursorTo:screenLocation];
                if (touch.phase == NSTouchPhaseEnded) {
                    [utils performClickAt:screenLocation];
                }
                break;
                
            case TUCCursorActionDrag:
                [utils dragCursorTo:screenLocation phase:touch.phase];
                break;
                
            case TUCCursorActionClick:
                [utils performClickAt:screenLocation];
                break;
                
            case TUCCursorActionSecondaryClick:
                [utils performSecondaryClickAt: screenLocation];
                break;
                
            case TUCCursorActionScroll: {
                CGPoint prevLocation = [strongSelf convertScreenPointRelativeToAbsolute:touch.previousLocation];
                CGPoint translation = CGPointMake(screenLocation.x - prevLocation.x,
                                                  screenLocation.y - prevLocation.y);
                [utils scroll:translation phase:touch.phase];
            
            break; }
            
        case TUCCursorActionMagnify:
            if (strongSelf.cursorTouch && strongSelf.gestureAdditionalTouch) {
                [utils magnifyLocationA:screenLocation
                              locationB:location2ndFinger
                        relativeP1:strongSelf.cursorTouch.location relP2:strongSelf.gestureAdditionalTouch.location];
            }
            
            if (touch.phase == NSTouchPhaseEnded || strongSelf.gestureAdditionalTouch.phase == NSTouchPhaseEnded) {
                [utils stopMagnifying];
            }
            break;
        }
    });
}


- (TUCCursorAction)actionForGesture:(TUCCursorGesture)gesture {
    
    if (self.delegate != nil) {
        return [self.delegate actionForGesture:gesture];
    }
    
    // Vereinfachte Gesten: Klick, Ziehen, Zwei-Finger-Scroll
    switch(gesture) {
        case TUCCursorGestureTap:               return TUCCursorActionClick;
        case TUCCursorGestureDrag:              return TUCCursorActionDrag;
        case TUCCursorGestureTwoFingerDrag:     return TUCCursorActionScroll;  // Zwei-Finger = Horizontal Scroll
        
        // Alle anderen Gesten deaktiviert
        case TUCCursorGestureTouchDown:
        case TUCCursorGestureLongPress:
        case TUCCursorGestureHoldAndDrag:
        case TUCCursorGestureTapSecondFinger:
        case TUCCursorGesturePinch:
        case _TUCCursorGestureNone:
        default:
            return TUCCursorActionMove;
    }
}


#pragma mark - Touch Set

/**
 The `touchSet` can contain touches whose phase is ended or cancelled. activeTouches. filteres those out
 */
- (NSSet<TUCTouch *> *)activeTouches {
    NSPredicate *p1 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseEnded];
    NSPredicate *p2 = [NSPredicate predicateWithFormat:@"phase != %d", NSTouchPhaseCancelled];
    
    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[p1, p2]];
    
    return [self.touchSet filteredSetUsingPredicate:predicate];
}



- (CGFloat)distanceBetweenPoint:(CGPoint)p1 and:(CGPoint)p2 {
    CGFloat dx = p1.x - p2.x;
    CGFloat dy = p1.y - p2.y;
    
    return sqrt( pow(dx, 2) + pow(dy, 2) );
}


/**
 maxDistance in mm
 */
- (NSSet<TUCTouch *> *)touchesInProximityTo:(CGPoint)point maxDistance:(CGFloat)mmDistance {
    
    CGFloat screenDistance = mmDistance * [[self touchscreen] pixelsPerMM];
    CGPoint distance = CGPointMake(screenDistance /  [self touchscreen].frame.size.width,
                                   screenDistance /  [self touchscreen].frame.size.height);
    
    NSPredicate * predicate = [NSPredicate predicateWithBlock: ^BOOL(TUCTouch *t, NSDictionary *bind) {
        
        CGFloat dx = [t location].x - point.x;
        CGFloat dy = [t location].y - point.y;
        
        return sqrt( pow(dx, 2) + pow(dy, 2) ) < distance.x;
    }];
    
    return [self.touchSet filteredSetUsingPredicate:predicate];
}


/**
 Removes a touch from the touch set. As a previous touch might be important for gesture evaluation, it is removed after half a second
 */
- (void)removeTouch:(TUCTouch *)touch now:(BOOL)instantDeletion{
//    if (touch.uuid == self.touchUsedForCursor.uuid) {
//        [self processTouchesForCursorInput];
//        self.touchUsedForCursor = nil;
//    }
    
    if (instantDeletion) {
        [[self touchSet] removeObject:touch];
        [[self delegate] touchesDidChange];
        return;
    }
    
    __weak id weakSelf = self;
    NSUUID *uuid = touch.uuid;
    // CRITICAL FIX: 0.1s statt 0.5s - bei vielen Fingern (10+) war 0.5s zu lang
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        for(TUCTouch *touch in [weakSelf touchSet]) {
            if (touch.uuid == uuid && [[weakSelf touchSet] containsObject:touch]) {
                printf("[DELAYED CLEANUP] contactID=%ld nach 0.1s entfernt\n", (long)touch.contactID);
                [[weakSelf touchSet] removeObject:touch];
                [[weakSelf delegate] touchesDidChange];
                return;
            }
        }
    });
}


/**
 Checks the touch set if a touch exists
 */
- (TUCTouch *)findTouchWithID:(NSInteger)contactID includingPastTouches:(BOOL)includePastTouches {
    NSSet *set = includePastTouches ? self.touchSet : [self activeTouches];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"contactID == %d", contactID];
    TUCTouch *touch = [[set filteredSetUsingPredicate:predicate] anyObject];
    return touch;
}

/**
 Returns the existing touch object or a new one if this ID does not exist in the set yet.
 CRITICAL: Wenn wir einen alten Touch mit der ID finden der ENDED/CANC ist, löschen wir ihn sofort
 */
- (TUCTouch *)obtainTouchWithID:(NSInteger)contactID isNew:(BOOL*)isNew {
    *isNew = NO;
    
    // CRITICAL FIX: Suche nach vorhandenem Touch mit dieser ID
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"contactID == %d", contactID];
    TUCTouch *existingTouch = [[self.touchSet filteredSetUsingPredicate:predicate] anyObject];
    
    if (existingTouch) {
        // Wenn der Touch ENDED oder CANCELLED ist → entfernen und neu erstellen
        if (existingTouch.phase == NSTouchPhaseEnded || existingTouch.phase == NSTouchPhaseCancelled) {
            printf("[CLEANUP OLD] Touch ID=%ld (phase=%ld) entfernt, wird neu erstellt\n", 
                   (long)contactID, (long)existingTouch.phase);
            [self.touchSet removeObject:existingTouch];
            [[self delegate] touchesDidChange];
        } else {
            // Touch ist AKTIV (BEGAN/MOVED/STATIONARY) → wiederverwenden!
            printf("[REUSE TOUCH] ID=%ld (phase=%ld) wird wiederverwendet\n", 
                   (long)contactID, (long)existingTouch.phase);
            return existingTouch;
        }
    }
    
    // Bereinige auch ALLE anderen alten ENDED/CANC Touches (nicht die mit dieser ID - wurde schon erledigt)
    NSMutableArray *touchesToRemove = [NSMutableArray array];
    for (TUCTouch *t in self.touchSet) {
        if ((t.phase == NSTouchPhaseEnded || t.phase == NSTouchPhaseCancelled) && t.contactID != contactID) {
            [touchesToRemove addObject:t];
        }
    }
    
    if ([touchesToRemove count] > 0) {
        printf("[CLEANUP ALL] %ld andere alte ENDED/CANC Touches entfernt: ", (long)[touchesToRemove count]);
        for (TUCTouch *t in touchesToRemove) {
            printf("ID=%ld ", (long)t.contactID);
            [self.touchSet removeObject:t];
        }
        printf("\n");
        [[self delegate] touchesDidChange];
    }
    
    // Jetzt neuen Touch erstellen
    TUCTouch *touch = [[TUCTouch alloc] initWithContactID:contactID];
    [self.touchSet addObject:touch];
    *isNew = YES;
    printf("[NEW TOUCH] ContactID=%ld erstellt (touchSet size=%ld)\n", 
           (long)contactID, (long)[self.touchSet count]);
    
    return touch;
}





#pragma mark - Screen Characteristics

/**
 the relative hardware points are always in the direction the digitizer is built in.
 If the display is rotated, we need to rotate these points
 */
- (CGPoint)convertDigitizerPointToRelativeScreenPoint:(CGPoint)devicePoint {
    CGFloat rotation = [self touchscreen].rotation;
    if (rotation == 0) {
        return devicePoint;
        
    } else if (rotation == 180) {
        return CGPointMake(1 - devicePoint.x, 1 - devicePoint.y);
        
    } else if (rotation == 90) {
        return CGPointMake(1 - devicePoint.y, devicePoint.x);
        
    } else if (rotation == 270) {
        return CGPointMake(devicePoint.y, 1 - devicePoint.x);
    }
    
    return devicePoint;
}



- (CGPoint)convertScreenPointRelativeToAbsolute:(CGPoint)relativePoint {
    return [[self touchscreen] convertPointRelativeToAbsolute:relativePoint];
}



- (TUCScreen *)touchscreen {
    if (self.delegate != nil) {
        return [self.delegate touchscreen];
    }
    
    return [[TUCScreen allScreens] firstObject];
}



- (BOOL)isPointInMenuBar:(CGPoint)point {
    CGFloat menuBarHeight = [[[NSApplication sharedApplication] mainMenu] menuBarHeight];

    CGRect screenFrame = [self touchscreen].frame;
    CGRect menuBarFrame = CGRectMake(screenFrame.origin.x,
                                     screenFrame.origin.y * -1,
                                     screenFrame.size.width,
                                     menuBarHeight);
    
    if (CGRectContainsPoint(menuBarFrame, point)) {
        return YES;
    }
    return NO;
}


- (BOOL)isLocationOutsideFrontmostWindow:(CGPoint)point {
    
    if ([self isPointInMenuBar:point]) {
        return NO;
    }
    
    pid_t frontmostPID = [[[NSWorkspace sharedWorkspace] frontmostApplication] processIdentifier];
    
    CFArrayRef array;
    array = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    
//    NSLog(@"%@", array);
    
    BOOL behindFrontmostWindow = NO;
    
    // propagate through window list the structure of this array is as follows:
    // [control center and menubar] [windows of frontmost app] [windows of other apps]
    // we have to insert a click to bring other windows to front, but not the menubar / control center stuff
    
    BOOL res = NO;
//    CFStringRef name = CFDictionaryGetValue(dic, kCGWindowOwnerPID);
    
    for (CFIndex i=0; i<CFArrayGetCount(array); i++) {
        CFDictionaryRef dic = CFArrayGetValueAtIndex(array, i);
        
        CFNumberRef numPid = CFDictionaryGetValue(dic, kCGWindowOwnerPID);
        pid_t currPID;
        CFNumberGetValue(numPid, kCFNumberIntType,  &currPID);
        BOOL isFrontmostApp = currPID == frontmostPID;
        
        // in fullscreen the app might also own the menu bar backgground window, so we need to test
        CFDictionaryRef bounds = CFDictionaryGetValue(dic, kCGWindowBounds);
        CGRect nextFrame;
        CGRectMakeWithDictionaryRepresentation(bounds, &nextFrame);
        BOOL isInside = CGRectContainsPoint(nextFrame, point);
        
        
        if (isFrontmostApp && !behindFrontmostWindow) {
            behindFrontmostWindow = YES;
        }
        
        
        
        if (isInside && !behindFrontmostWindow) {
            // operate without additional clicks
            res = NO;
            break;
        }
        
        else if (isInside && behindFrontmostWindow && !isFrontmostApp) {
            res = YES;
            break;
        }
        
    }
    
    CFRelease(array);
    return res;
}
        



#pragma mark -

- (instancetype)init {
    if(self = [super init]) {
        self.touchSet = [NSMutableSet new];
        self.postMouseEvents = YES;
        
        self.cursorTouchQualifiedForTap = NO;
        self.cursorTouchStationarySinceDate = nil;
        
        self.currentFrameID = 0;
        self.identifiedMultitouchGesture = _TUCCursorGestureNone;
        
        self.doubleClickTolerance = 5;
        self.holdDuration = 0.08;
        self.errorResistance = 5;  // 5 frames minimal timeout
        
        self.ignoreOriginTouches = NO;
        
        // Initialize gesture options - all enabled by default
        self.isScrollingWithOneFingerEnabled = YES;
        self.isSecondaryClickEnabled = YES;
        self.isMagnificationEnabled = YES;
        self.isClickWindowToFrontEnabled = NO;
        self.isClickOnLiftEnabled = NO;
    }
    return self;
}


- (NSString *)debugDescription {
    NSMutableString *str = [[NSString stringWithFormat:@"Touch Set contains %ld touches:{\n", [self.touchSet count]] mutableCopy];
    
    for (TUCTouch *touch in [[self.touchSet allObjects] sortedArrayUsingSelector:@selector(compareWithAnotherTouch:)] ) {
        [str appendString: [NSString stringWithFormat:@"  %@", [touch debugDescription]] ];
        if (touch.contactID == self.cursorTouch.contactID) {
            [str appendString: @" <<<CURSOR>>>\n" ];
        } else {
            [str appendString: @"\n" ];
        }
    }
    
    [str appendString:@"}"];
    return str;
}

- (void)triggerSystemAccessibilityAccessAlert {
    CGPoint loc = [[TUCCursorUtilities sharedInstance] currentCursorLocation];
    [[TUCCursorUtilities sharedInstance] moveCursorTo:loc];
}



#pragma mark - Bridge calls of C Header to Objective-C

void TouchInputManagerUpdateTouchPosition(void *self, CFIndex contactID, CGFloat x, CGFloat y, Boolean onSurface, Boolean isValid) {
    CGPoint point = CGPointMake(x, y);
    [(__bridge id)self updateTouch:(NSInteger)contactID withLocation:point onSurface:onSurface tooLargeForFinger:isValid];
}

void TouchInputManagerUpdateTouchSize(void *self, CFIndex contactID, CGFloat width, CGFloat height, CGFloat azimuth) {
    CGSize size = CGSizeMake(width, height);
    [(__bridge id)self updateTouch:(NSInteger)contactID withSize:size azimuth:azimuth];
}

void TouchInputManagerDidProcessReport(void *self) {
    [(__bridge id)self didProcessReport];
}

void TouchInputManagerDidConnectTouchscreen(void *self) {
    [(__bridge id)self didConnectTouchscreen];
}

void TouchInputManagerDidDisconnectTouchscreen(void *self) {
    [(__bridge id)self didDisconnectTouchscreen];
}


@end
