//
//  HIDInterpreter.c
//  Touch Up Core
//
//  Created by Sebastian Hueber on 03.02.23.
//

#include "HIDInterpreter.h"
#include "TUCTouchInputManager-C.h"

#include <mach/mach_port.h>
#include <mach/mach_time.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/usb/IOUSBLib.h>
#include <dispatch/dispatch.h>
#include <stdbool.h>
#include <pthread.h>
#include <stdarg.h>
#include <string.h>
#include <time.h>

#include <CoreGraphics/CoreGraphics.h>

// Debug logging to file
#define DEBUG_LOG_FILE "/tmp/touchup_debug.log"
#define TOUCH_LOG_FILE "/tmp/touchup_touch_events.log"
static FILE *gDebugLog = NULL;
static FILE *gTouchLog = NULL;

static inline void DebugLog(const char *format, ...) {
    if (!gDebugLog) {
        gDebugLog = fopen(DEBUG_LOG_FILE, "a");
    }
    if (gDebugLog) {
        va_list args;
        va_start(args, format);
        vfprintf(gDebugLog, format, args);
        va_end(args);
        fprintf(gDebugLog, "\n");
        fflush(gDebugLog);
    }
    // Also print to stdout
    printf("[TouchUp] ");
    va_list args2;
    va_start(args2, format);
    vprintf(format, args2);
    va_end(args2);
    printf("\n");
    fflush(stdout);
}

// Touch event logging - dedicated file for touch events only
static inline void TouchLog(const char *format, ...) {
    if (!gTouchLog) {
        gTouchLog = fopen(TOUCH_LOG_FILE, "w");  // Überschreibe bei jedem Start
        if (gTouchLog) {
            // Header mit Zeitstempel
            time_t now = time(NULL);
            fprintf(gTouchLog, "=== Touch Up Touch Event Log ===\n");
            fprintf(gTouchLog, "Started: %s\n", ctime(&now));
            fprintf(gTouchLog, "Format: [Timestamp] Event: Details\n\n");
            fflush(gTouchLog);
        }
    }
    if (gTouchLog) {
        // Timestamp in Millisekunden seit App-Start
        static uint64_t startTime = 0;
        if (startTime == 0) {
            startTime = mach_absolute_time();
        }
        uint64_t now = mach_absolute_time();
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        uint64_t elapsedNano = (now - startTime) * timebase.numer / timebase.denom;
        uint64_t elapsedMs = elapsedNano / 1000000;
        
        fprintf(gTouchLog, "[%6llums] ", elapsedMs);
        va_list args;
        va_start(args, format);
        vfprintf(gTouchLog, format, args);
        va_end(args);
        fprintf(gTouchLog, "\n");
        fflush(gTouchLog);
    }
}

#pragma mark - Global variables

static void* gTouchManager;

static CFRunLoopRef gRunLoopRef;

static IOHIDManagerRef gHidManager;

IOHIDQueueRef gQueue;

// USB Direct Access Handle Structure
typedef struct {
    io_service_t usbDevice;
    void *deviceInterface;
    void *interfaceInterface;
    uint8_t interruptEndpoint;
    void *runLoopSource;
    int pipeRef;
    bool isReading;
    pthread_t readThread;
} USBDirectAccessHandle;

// ELAN Touchscreen Vendor IDs
// 0x04F3 = Original ELAN vendor ID
// 0x0712 = hotlotus vendor ID for "normal Elan" device
#define kELANVendorID 0x0712
#define kELANProductID 0x000A

// Flag to track if we detected an ELAN device
Boolean gIsELANDevice = FALSE;

// USB Direct Access Handle for non-HID ELAN devices
static USBDirectAccessHandle *gUSBDirectAccessHandle = NULL;

// Forward declarations for USB Direct Access helper functions
static void PrintHexDump(const uint8_t *data, uint32_t len, const char *label);
static void* USBInterruptReadThread(void *arg);
static io_service_t FindUSBDevice_Internal(uint16_t vendorID, uint16_t productID);

// Forward declarations for USB Direct Access API functions
USBDirectAccessHandle* USBDirectAccessor_Create(uint16_t vendorID, uint16_t productID);
void USBDirectAccessor_Release(USBDirectAccessHandle *handle);
bool USBDirectAccessor_IsELANDeviceAvailable(uint16_t vendorID, uint16_t productID);
int USBDirectAccessor_ReadInterrupt(USBDirectAccessHandle *handle, uint8_t *buffer,
                                     uint32_t bufferSize, uint32_t timeoutMS);
int USBDirectAccessor_Write(USBDirectAccessHandle *handle, const uint8_t *data, uint32_t dataSize);

uint8_t gAreElementRefsSet = 0;

IOHIDElementRef         gApplicationCollectionElement;
IOHIDElementRef         gScanTimeElement;
CFMutableArrayRef       gTouchCollectionElements;

// Forward declaration of USB Direct Access fallback function
void TryUSBDirectAccess(void);

/**
 stores values for the touch collections: cookie -> latest value
 in hybrid mode (especially if order of touches moves) this data has to be set to last state per collection element receiving touches now
 */
CFMutableDictionaryRef  gStoredInputValues; //


CFIndex gContactCount = 1;
CFIndex gHybridOffset = 0; // how many touches are already sent until this point?
Boolean gTouchscreenUsesHybridMode = FALSE;


CFMutableArrayRef gContactIdentifiers;

// POSITION-BASED DEDUPLICATION: Löst Hybrid-Mode Problem
// Hardware sendet gleiche ContactID=0 für verschiedene Finger
// Wir deduplicaten nach Position statt Hardware-ID
#define MAX_ACTIVE_TOUCHES 10
#define POSITION_MATCH_THRESHOLD 0.05f  // 5% Abstand = gleicher Touch (sehr nah)

typedef struct {
    CFIndex internalID;         // Stabile interne Touch-ID (0-9)
    CGFloat currentX, currentY; // Aktuelle Position
    Boolean isActive;           // Ist dieser Touch gerade aktiv?
} ActiveTouchSlot;

static ActiveTouchSlot gActiveTouches[MAX_ACTIVE_TOUCHES];
static CFIndex gNextInternalTouchID = 0;  // Interne IDs starten bei 0

// Prüfe ob alle Slots inaktiv sind
static Boolean AreAllSlotsInactive(void) {
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        if (gActiveTouches[i].isActive) {
            return FALSE;
        }
    }
    return TRUE;
}

// Setze Slot-Zustand komplett zurück (IDs werden wieder bei 0 gestartet)
static void ResetAllSlots(void) {
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        gActiveTouches[i].internalID = -1;
        gActiveTouches[i].currentX = -1.0;
        gActiveTouches[i].currentY = -1.0;
        gActiveTouches[i].isActive = FALSE;
    }
    gNextInternalTouchID = 0;
}

// Initialisiere das Position-basierte Deduplication-System
static void InitializePositionDeduplication(void) {
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        gActiveTouches[i].internalID = -1;
        gActiveTouches[i].currentX = -1.0;
        gActiveTouches[i].currentY = -1.0;
        gActiveTouches[i].isActive = FALSE;
    }
    gNextInternalTouchID = 0;
}

// Berechne Distanz zwischen zwei Positionen (normalisiert 0.0-1.0 Koordinaten)
static CGFloat PositionDistance(CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGFloat dx = x2 - x1;
    CGFloat dy = y2 - y1;
    return sqrtf(dx*dx + dy*dy);
}

// Mappt Position zu stabiler interner Touch-ID
// Hardware kann gleiche ContactID für verschiedene Finger verwenden (Hybrid-Mode)
static CFIndex MapPositionToInternalID(CFIndex hardwareID, CGFloat x, CGFloat y) {
    // CRITICAL: Ungültige Positionen abfangen (z.B. bei leeren Slots)
    // Diese sollten nicht in das Dedup-System kommen
    if (x < 0.0 || y < 0.0 || x > 1.0 || y > 1.0) {
        TouchLog("[DEDUP-SKIP] Invalid position (%.3f,%.3f) - returning HW-ID=%ld directly", x, y, (long)hardwareID);
        return hardwareID;
    }
    
    // Wenn alles inaktiv ist, IDs zurücksetzen damit wir bei 0-9 bleiben
    if (AreAllSlotsInactive()) {
        TouchLog("[DEDUP-RESET] All slots inactive → resetting to ID=0");
        ResetAllSlots();
    }

    // 1. Suche nach bereits aktivem Touch an ähnlicher Position
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        if (!gActiveTouches[i].isActive) continue;
        
        CGFloat distance = PositionDistance(gActiveTouches[i].currentX, gActiveTouches[i].currentY, x, y);
        
        // Wenn sehr nah → gleicher Touch!
        if (distance < POSITION_MATCH_THRESHOLD) {
            // Update Position (Finger bewegt sich)
            gActiveTouches[i].currentX = x;
            gActiveTouches[i].currentY = y;
            return gActiveTouches[i].internalID;
        }
    }
    
    // 2. Kein Match gefunden → neuer Touch mit neuer ID
    // 2a. Reuse inaktiven Slot mit bestehender ID (hält IDs klein)
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        if (!gActiveTouches[i].isActive && gActiveTouches[i].internalID != -1) {
            CFIndex reusedID = gActiveTouches[i].internalID;
            gActiveTouches[i].currentX = x;
            gActiveTouches[i].currentY = y;
            gActiveTouches[i].isActive = TRUE;
            TouchLog("[DEDUP-REUSE] HW-ID=%ld pos=(%.3f,%.3f) → REUSE ID=%ld",
                   (long)hardwareID, x, y, (long)reusedID);
            return reusedID;
        }
    }

    // 2b. Falls nötig, neue ID erzeugen
    CFIndex newInternalID = gNextInternalTouchID++;
    
    // Finde freien Slot (leer oder inaktiv)
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        if (!gActiveTouches[i].isActive) {
            gActiveTouches[i].internalID = newInternalID;
            gActiveTouches[i].currentX = x;
            gActiveTouches[i].currentY = y;
            gActiveTouches[i].isActive = TRUE;
            TouchLog("[DEDUP-NEW] HW-ID=%ld pos=(%.3f,%.3f) → NEW ID=%ld",
                   (long)hardwareID, x, y, (long)newInternalID);
            return newInternalID;
        }
    }
    
    // Sollte nie passieren (MAX_ACTIVE_TOUCHES zu klein)
    TouchLog("[DEDUP-WARN] All slots full, using HW-ID=%ld directly", (long)hardwareID);
    return hardwareID;
}

// Markiere Touch als beendet (tip=0)
static void DeactivateTouchByID(CFIndex internalID) {
    for (int i = 0; i < MAX_ACTIVE_TOUCHES; i++) {
        if (gActiveTouches[i].internalID == internalID && gActiveTouches[i].isActive) {
            gActiveTouches[i].isActive = FALSE;
            TouchLog("[DEDUP-DEACTIVATE] ID=%ld deactivated", (long)internalID);
            // Reset wird beim nächsten MapPositionToInternalID() Aufruf gecheckt
            return;
        }
    }
}

// SIMPLE & ROBUST TOUCH LIFECYCLE: Set-basiertes Tracking mit Hardware-IDs
// Hardware-IDs direkt verwenden - keine komplexe Remapping-Logik nötig
static uint64_t gStartTime = 0;     // Für relative Timestamps

// ROBUST TOUCH LIFECYCLE: Set-basiertes Tracking
static CFMutableSetRef gActiveTouchIDsThisCycle = NULL;   // Touch-IDs im aktuellen Cycle (als CFNumber)
static CFMutableSetRef gActiveTouchIDsLastCycle = NULL;   // Touch-IDs im vorherigen Cycle
static Boolean gReportCycleInProgress = FALSE;             // Sind wir mitten in einem Report-Cycle?

// Hilfsfunktion: Hole aktuelle Zeit in Millisekunden
static uint64_t GetCurrentTimeMS(void) {
    if (gStartTime == 0) {
        gStartTime = mach_absolute_time();
    }
    
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0) {
        mach_timebase_info(&timebase);
    }
    
    uint64_t elapsed = mach_absolute_time() - gStartTime;
    return (elapsed * timebase.numer) / (timebase.denom * 1000000ULL);
}


#pragma mark General Debug Utilities




void PrintAddress(UInt8 *ptr, UInt64 length) {
    for (int i=0; i<length; i++) {
        printf("%02x ", ptr[i]);
        if ((i+1)%8 == 0) printf("  ");
        if ((i+1)%32 == 0) printf("\n");
    }
    printf("\n");
}


void PrintInput(IOHIDValueRef inHIDValue) {
    IOHIDElementRef elem = IOHIDValueGetElement(inHIDValue);
    CFIndex page = IOHIDElementGetUsagePage(elem);
    CFIndex usage = IOHIDElementGetUsage(elem);
    CFIndex value = IOHIDValueGetIntegerValue(inHIDValue);
    
    IOHIDElementCookie cookie = IOHIDElementGetCookie(elem);
    
    char pageDescr[6]  = "(---)";
    char usageDescr[10] = "(-------)";
    
    if (page == kHIDPage_GenericDesktop) {
        strcpy(pageDescr, "(GD) ");
        if (usage == kHIDUsage_GD_X) {
            strcpy(usageDescr, "(X)      ");
        } else if (usage == kHIDUsage_GD_Y) {
            strcpy(usageDescr, "(Y)      ");
        }
        
    } else if (page == kHIDPage_Digitizer) {
        strcpy(pageDescr, "(Dig)");
        
        if (usage == kHIDUsage_Dig_TipSwitch) {
            strcpy(usageDescr, "(Tip)    ");
        } else if (usage == kHIDUsage_Dig_ContactIdentifier) {
            strcpy(usageDescr, "(Cont ID)");
        } else if (usage == kHIDUsage_Dig_ContactCount) {
            strcpy(usageDescr, "(ContCnt)");
        } else if (usage == kHIDUsage_Dig_TouchValid) {
            strcpy(usageDescr, "(IsValid)");
        } else if (usage == kHIDUsage_Dig_RelativeScanTime) {
            strcpy(usageDescr, "(ScnTime)");
        } else if (usage == kHIDUsage_Dig_Width) {
            strcpy(usageDescr, "(Width)  ");
        } else if (usage == kHIDUsage_Dig_Height) {
            strcpy(usageDescr, "(Height) ");
        } else if (usage == kHIDUsage_Dig_Azimuth) {
            strcpy(usageDescr, "(Azimuth)");
        }
    }
    
    CFIndex  lMin = IOHIDElementGetLogicalMin(elem);
    CFIndex lMax = IOHIDElementGetLogicalMax(elem);
    
    printf("%u\t| %#02lx %s\t| %#02lx %s\t|%8ld\t(%ld-%ld)\n", cookie, page, pageDescr, usage, usageDescr, value, lMin, lMax);
}





#pragma mark - Storing Values


int64_t StorageKeyForElement(IOHIDElementRef element) {
    return IOHIDElementGetCookie(element);
}



CFIndex ValueOfElement(IOHIDElementRef element) {
    
    if (!element) {
        return kCFNotFound;
    }
    
    int64_t hash = StorageKeyForElement(element);
    CFNumberRef key = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &hash);
    
    if (CFDictionaryContainsKey(gStoredInputValues, key)) {
        CFIndex value;
        CFNumberRef num = CFDictionaryGetValue(gStoredInputValues, key);
        CFNumberGetValue(num, kCFNumberCFIndexType, &value);
        CFRelease(key);
        return value;
        
    }
    return kCFNotFound;

}



void StoreInputValue(IOHIDValueRef hidValue) {
    
    CFIndex value = IOHIDValueGetIntegerValue(hidValue);
    IOHIDElementRef elem = IOHIDValueGetElement(hidValue);
    
    CFIndex keyValue = StorageKeyForElement(elem);
    
    CFNumberRef key = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &keyValue);
    
    CFNumberRef num = CFNumberCreate(kCFAllocatorDefault, kCFNumberCFIndexType, &value);
    
    CFDictionarySetValue(gStoredInputValues, key, num);
    
    CFRelease(num);
    CFRelease(key);
    
    
    // special case: contact count could be zero in hybrid mode --> s
    CFIndex page = IOHIDElementGetUsagePage(elem);
    CFIndex usage = IOHIDElementGetUsage(elem);
    
    // Debug: Zeige alle Digitizer-Eingaben
    static int inputCount = 0;
    if (page == kHIDPage_Digitizer && ++inputCount % 50 == 0) {
        printf("[StoreInput] #%d page=0x%lx usage=0x%lx value=%ld\n",
               inputCount, (long)page, (long)usage, (long)value);
    }
    
    if (page == kHIDPage_Digitizer && usage == kHIDUsage_Dig_ContactCount) {
        printf("[ContactCount] value=%ld (previous gContactCount=%ld)\n", 
               (long)value, (long)gContactCount);
        // hybrid mode can only exist if the old value is larger than the number of collections that can be communicated at once
        CFIndex numCollections =  CFArrayGetCount(gTouchCollectionElements);
        
        if (gContactCount > numCollections && value == 0 && gHybridOffset > 0) {
            gTouchscreenUsesHybridMode = TRUE;
            
        } else {
            gContactCount = value;
            gHybridOffset = 0;
        }
    }
}




/**
 We need to inspect the HID tree as a whole once to see which elements are grouped into logical groups of touch data.
 Just pass in any element of the tree, the function will walk up the tree, search for the logical groups and rememeber them in the global variables.
 */
void IdentifyElements(IOHIDElementRef anyElement, Boolean printTree) {
    
    IOHIDElementRef applicationCollection = anyElement;
    IOHIDElementType type = kIOHIDElementTypeOutput;
    
    while (type != kIOHIDElementCollectionTypeApplication) {
        IOHIDElementRef next = IOHIDElementGetParent(applicationCollection);
        if (next) {
            applicationCollection = next;
            type = IOHIDElementGetType(applicationCollection);
        } else {
            break;
        }
    }
    
    gApplicationCollectionElement = applicationCollection;
    
    
    CFArrayRef children = IOHIDElementGetChildren(applicationCollection);
    CFIndex numChildren = CFArrayGetCount(children);
    
    if (printTree) {
        printf("# parent (type %u) has %ld children:\n", type, numChildren);
    }
    
    
    for (CFIndex i=0; i<numChildren; i++) {
        IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(children, i);
        
        CFIndex page = IOHIDElementGetUsagePage(element);
        CFIndex usage = IOHIDElementGetUsage(element);
        IOHIDElementType type =  IOHIDElementGetType(element);
        IOHIDElementCollectionType collectionType = IOHIDElementGetCollectionType(element);
        
        if (type == kIOHIDElementTypeCollection && collectionType == kIOHIDElementCollectionTypeLogical) {
            CFArrayAppendValue(gTouchCollectionElements, element);
            
            if (printTree) {
                printf(" > Logical collection %ld\n", i);
                CFArrayRef grandchildren = IOHIDElementGetChildren(element);
                for( CFIndex j=0; j<CFArrayGetCount(grandchildren); j++) {
                    IOHIDElementRef gch = (IOHIDElementRef)CFArrayGetValueAtIndex(grandchildren, j);
                    CFIndex page = IOHIDElementGetUsagePage(gch);
                    CFIndex usage = IOHIDElementGetUsage(gch);
                    CFIndex cookie= IOHIDElementGetCookie(gch);
                    
                    printf("    > %#02lx %#02lx  [%ld]\n", page, usage, cookie);
                }
            }
            
        } // logical collection
        
        else if (page == kHIDPage_Digitizer && usage == kHIDUsage_Dig_ContactCount) {
            if (printTree) {
                printf(" > Contact Count\n");
            }
        }
        
        else if (page == kHIDPage_Digitizer && usage == kHIDUsage_Dig_RelativeScanTime) {
            gScanTimeElement = element;
            if (printTree) {
                printf(" > Scan Time\n");
            }
        }
        
        else {
            if (printTree) {
                printf(" > %#02lx %#02lx\n", page, usage);
            }
        }
    }
}









#pragma mark - Propagate Touch Data to next layer


void PrintTouchCollection(IOHIDElementRef collection) {
    CFArrayRef children = IOHIDElementGetChildren(collection);
    
    // get stored values of all touches
    for (CFIndex i=0; i<CFArrayGetCount(children); i++) {
        IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(children, i);
        
        CFIndex page = IOHIDElementGetUsagePage(element);
        CFIndex usage = IOHIDElementGetUsage(element);
        CFIndex cookie = IOHIDElementGetCookie(element);
        CFIndex value = ValueOfElement(element);
        
        char pageDescr[6]  = "(---)";
        char usageDescr[10] = "(-------)";
        
        if (page == kHIDPage_GenericDesktop) {
            strcpy(pageDescr, "(GD) ");
            if (usage == kHIDUsage_GD_X) {
                strcpy(usageDescr, "(X)      ");
            } else if (usage == kHIDUsage_GD_Y) {
                strcpy(usageDescr, "(Y)      ");
            }
            
        } else if (page == kHIDPage_Digitizer) {
            strcpy(pageDescr, "(Dig)");
            
            if (usage == kHIDUsage_Dig_TipSwitch) {
                strcpy(usageDescr, "(Tip)    ");
            } else if (usage == kHIDUsage_Dig_ContactIdentifier) {
                strcpy(usageDescr, "(Cont ID)");
            } else if (usage == kHIDUsage_Dig_ContactCount) {
                strcpy(usageDescr, "(ContCnt)");
            } else if (usage == kHIDUsage_Dig_TouchValid) {
                strcpy(usageDescr, "(IsValid)");
            } else if (usage == kHIDUsage_Dig_RelativeScanTime) {
                strcpy(usageDescr, "(ScnTime)");
            } else if (usage == kHIDUsage_Dig_Width) {
                strcpy(usageDescr, "(Width)  ");
            } else if (usage == kHIDUsage_Dig_Height) {
                strcpy(usageDescr, "(Height) ");
            } else if (usage == kHIDUsage_Dig_Azimuth) {
                strcpy(usageDescr, "(Azimuth)");
            }
        }
        
        
        
        printf("[%u]\t%#02lx\t%#02lx %s\t %8ld\n", cookie, page, usage, usageDescr,  value);
    }
    printf("\n");
}


/**
 Dispatches touch data for the given collection, but only if all values needed were received
 */

void DispatchTouchDataForCollection(IOHIDElementRef collection) {
    
    CFArrayRef children = IOHIDElementGetChildren(collection);

    CGFloat x = -1;
    CGFloat y = -1;
    
    CFIndex contactID = 0;
    CFIndex tipSwitch = 0;
    CFIndex isValid = 0;
    
    CFIndex width   = kCFNotFound;
    CFIndex height  = kCFNotFound;
    CFIndex azimuth = kCFNotFound;
    
    // get stored values of all touches
    for (CFIndex i=0; i<CFArrayGetCount(children); i++) {
        IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(children, i);
        
        CFIndex page = IOHIDElementGetUsagePage(element);
        CFIndex usage = IOHIDElementGetUsage(element);
        CFIndex value = ValueOfElement(element);
        
        if (value != kCFNotFound) {
            if (page == kHIDPage_GenericDesktop) {
                if (usage == kHIDUsage_GD_X) {
                    CGFloat min = (CGFloat)IOHIDElementGetLogicalMin(element);
                    CGFloat max = (CGFloat)IOHIDElementGetLogicalMax(element);
                    CGFloat curr = (CGFloat)value;
                    x = ( (curr - min) / (max - min) ) + min;
                }
                
                else if (usage == kHIDUsage_GD_Y) {
                    CGFloat min = (CGFloat)IOHIDElementGetLogicalMin(element);
                    CGFloat max = (CGFloat)IOHIDElementGetLogicalMax(element);
                    CGFloat curr = (CGFloat)value;
                    y = ( (curr - min) / (max - min) ) + min;
                }
            } //kHIDPage_GenericDesktop
            
            else if (page == kHIDPage_Digitizer) {
                if (usage == kHIDUsage_Dig_ContactIdentifier) {
                    contactID = value;
                } else if (usage == kHIDUsage_Dig_TipSwitch) {
                    tipSwitch = value;
                } else if (usage == kHIDUsage_Dig_TouchValid) {
                    isValid = value;
                } else if (usage == kHIDUsage_Dig_Width) {
                    width = value;
                } else if (usage == kHIDUsage_Dig_Height) {
                    height = value;
                } else if (usage == kHIDUsage_Dig_Azimuth) {
                    azimuth = value;
                }
            } // kHIDPage_Digitizer
        }
    }
    
    // Debug: Zeige ALLE Reports für Diagnose mit Zeitstempel
    static int reportCount = 0;
    static CFIndex lastTipSwitch = -1;
    static CFIndex lastContactID = -1;
    static uint64_t lastReportTime = 0;
    reportCount++;
    
    uint64_t now = GetCurrentTimeMS();
    uint64_t timeSinceLastReport = (lastReportTime == 0) ? 0 : (now - lastReportTime);
    lastReportTime = now;
    
    int tipSwitchChanged = (tipSwitch != lastTipSwitch);
    int contactChanged = (contactID != lastContactID);
    lastTipSwitch = tipSwitch;
    lastContactID = contactID;
    
    // POSITION-DEDUPLICATION: Map Position zu stabiler interner ID
    // Hardware verwendet gleiche ContactID für verschiedene Finger im Hybrid-Mode
    Boolean isActive = (tipSwitch == 1);
    CFIndex internalTouchID = MapPositionToInternalID(contactID, x, y);
    
    // CRITICAL FIX: Nur Touches mit tipSwitch=1 ODER isValid=1 verarbeiten
    // Leere Slots mit tipSwitch=0 und isValid=0 sind nicht relevant
    if (tipSwitch == 0 && isValid == 0) {
        // Das ist ein leerer Touch-Slot - ignorieren
        if (reportCount <= 10) {
            printf("[HID %llums] Report #%d: SKIPPED (empty slot) HW-ID=%ld tip=%ld valid=%ld\n", 
                   now, reportCount, (long)contactID, (long)tipSwitch, (long)isValid);
        }
        return;
    }
    
    // LIFECYCLE TRACKING: Markiere Touch-ID als aktiv in diesem Cycle
    if (isActive && gActiveTouchIDsThisCycle != NULL) {
        CFNumberRef touchIDNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberCFIndexType, &internalTouchID);
        
        // Prüfe ob Touch im LETZTEN Cycle aktiv war (nicht im aktuellen!)
        Boolean wasActiveLastCycle = (gActiveTouchIDsLastCycle != NULL) && 
                                     CFSetContainsValue(gActiveTouchIDsLastCycle, touchIDNum);
        
        if (!wasActiveLastCycle) {
            // Neuer Touch - erstmals gesehen
            TouchLog("TOUCH START: ID=%ld x=%.3f y=%.3f", (long)internalTouchID, x, y);
        } else {
            // Touch-Move - loggen um Bewegungen zu tracken
            static int moveLogCounter = 0;
            if (++moveLogCounter % 10 == 0) {
                TouchLog("TOUCH MOVE: ID=%ld x=%.3f y=%.3f (report #%d)", (long)internalTouchID, x, y, reportCount);
            }
        }
        
        CFSetAddValue(gActiveTouchIDsThisCycle, touchIDNum);
        CFRelease(touchIDNum);
    }
    
    // Zeige alle Reports für die ersten 100, dann nur Changes
    if (reportCount <= 100 || tipSwitchChanged || contactChanged) {
        printf("[HID %llums +%llums] Report #%d: HW-ID=%ld (mapped→%ld) x=%.2f y=%.2f tip=%ld valid=%ld%s%s\n", 
               now, timeSinceLastReport, reportCount, 
               (long)contactID, (long)internalTouchID, x, y, (long)tipSwitch, (long)isValid,
               tipSwitchChanged ? " [TIP▲]" : "",
               contactChanged ? " [ID▲]" : "");
    }
    
    // Verwende die gemappte ID für den TouchInputManager
    TouchInputManagerUpdateTouchPosition(gTouchManager, internalTouchID, x, y, (int)tipSwitch, (int)isValid);
    
//    if (width != kCFNotFound && height != kCFNotFound && azimuth != kCFNotFound) {
//        TouchInputManagerUpdateTouchSize(gTouchManager, contactID, (CGFloat)width, (CGFloat)height, (CGFloat)azimuth);
//    }
    
}



void DispatchTouches(void) {
    
    // Markiere Beginn eines neuen Report-Cycles beim ersten Aufruf
    if (!gReportCycleInProgress && gActiveTouchIDsThisCycle != NULL) {
        gReportCycleInProgress = TRUE;
        printf("[LIFECYCLE] Neuer Report-Cycle beginnt\n");
    }

    CFIndex numCollections = CFArrayGetCount(gTouchCollectionElements);
    CFIndex remainingUpdates = gContactCount - gHybridOffset;
    
    CFIndex numUpdates = numCollections;
    if (remainingUpdates < numCollections) {
        numUpdates = remainingUpdates;
    }
    
    CFIndex numElementsToPost = CFArrayGetCount(gTouchCollectionElements);
    if (numUpdates < numElementsToPost)
        numElementsToPost = numUpdates;
    
    // CRITICAL FIX: Falls gContactCount noch nicht aktualisiert wurde, aber wir haben Touch-Daten
    // gContactCount basiert auf dem HID ContactCount-Element, das der Touchscreen
    // möglicherweise nicht zuverlässig sendet. Daher: Verarbeite mindestens 1 Touch,
    // wenn wir gTouchCollectionElements haben
    if (numElementsToPost == 0 && numCollections > 0) {
        // ContactCount wurde nicht aktualisiert, aber wir haben Touch Collections
        // Das ist normal bei manchen Touchscreens - verarbeite einfach alle Collections
        numElementsToPost = numCollections;
        printf("[DISPATCH] ContactCount nicht aktualisiert, verarbeite alle %ld Touches trotzdem\n", 
               (long)numElementsToPost);
    }
    
    static int dispatchCount = 0;
    if (++dispatchCount % 100 == 0) {
        printf("[DispatchTouches] #%d: numElementsToPost=%ld gContactCount=%ld\n", 
               dispatchCount, (long)numElementsToPost, (long)gContactCount);
    }
    
    if (numElementsToPost > 0) {
        DebugLog("DispatchTouches: %ld contacts to dispatch (%ld total)", numElementsToPost, gContactCount);
        printf("[DispatchTouches] Processing %ld elements, ContactCount=%ld\n", 
               (long)numElementsToPost, (long)gContactCount);
    }
    
    // update the touch data
    for (CFIndex i=0; i<numElementsToPost; i++) {
        IOHIDElementRef collection = (IOHIDElementRef)CFArrayGetValueAtIndex(gTouchCollectionElements, i);
        DispatchTouchDataForCollection(collection);
    }
    
    gHybridOffset = gHybridOffset + numUpdates;
    
    if (gHybridOffset == gContactCount) {
        gHybridOffset = 0;
    }

    if (gHybridOffset == 0) {
        if (gContactCount > 0) {
            DebugLog("DispatchTouches: Sending report with %ld contacts to TouchManager", gContactCount);
        }
        
        // LIFECYCLE MANAGEMENT: Report-Cycle ist abgeschlossen
        // Finde alle Touches die im LETZTEN Cycle aktiv waren aber NICHT im aktuellen Cycle
        if (gActiveTouchIDsLastCycle != NULL && gActiveTouchIDsThisCycle != NULL) {
            CFIndex lastCycleCount = CFSetGetCount(gActiveTouchIDsLastCycle);
            
            if (lastCycleCount > 0) {
                const void **lastCycleTouches = malloc(sizeof(void*) * lastCycleCount);
                CFSetGetValues(gActiveTouchIDsLastCycle, lastCycleTouches);
                
                // Sende tip=0 für alle Touches die VERSCHWUNDEN sind
                for (CFIndex i = 0; i < lastCycleCount; i++) {
                    CFNumberRef touchIDNum = (CFNumberRef)lastCycleTouches[i];
                    
                    // War dieser Touch im letzten Cycle aktiv aber NICHT im aktuellen?
                    if (!CFSetContainsValue(gActiveTouchIDsThisCycle, touchIDNum)) {
                        CFIndex touchID;
                        CFNumberGetValue(touchIDNum, kCFNumberCFIndexType, &touchID);
                        
                        printf("[LIFECYCLE END] Touch ID=%ld war aktiv, ist jetzt weg → sende tip=0\n", (long)touchID);
                        TouchLog("TOUCH END: ID=%ld (disappeared from reports)", (long)touchID);
                        
                        // CRITICAL: Deaktiviere Touch in Position-Dedup System
                        DeactivateTouchByID(touchID);
                        
                        TouchInputManagerUpdateTouchPosition(gTouchManager, touchID, 0.0, 0.0, 0, 0);
                    }
                }
                
                free(lastCycleTouches);
            }
        }
        
        TouchInputManagerDidProcessReport(gTouchManager);
        
        // Swap: Aktueller Cycle → Letzter Cycle für nächsten Report
        if (gActiveTouchIDsLastCycle != NULL && gActiveTouchIDsThisCycle != NULL) {
            CFSetRemoveAllValues(gActiveTouchIDsLastCycle);
            
            // Kopiere alle Touch-IDs vom aktuellen zum letzten Cycle
            CFIndex count = CFSetGetCount(gActiveTouchIDsThisCycle);
            static CFIndex lastCycleCount = 0;  // Merke vorherige Anzahl für Change-Detection
            
            if (count > 0) {
                const void **values = malloc(sizeof(void*) * count);
                CFSetGetValues(gActiveTouchIDsThisCycle, values);
                for (CFIndex i = 0; i < count; i++) {
                    CFSetAddValue(gActiveTouchIDsLastCycle, values[i]);
                }
                free(values);
                
                // Logge nur wenn Anzahl sich ÄNDERT (nicht bei jedem Report!)
                if (count != lastCycleCount) {
                    printf("[LIFECYCLE] Cycle: %ld aktive Touches (vorher: %ld)\n", (long)count, (long)lastCycleCount);
                    TouchLog("CYCLE: %ld active touch(es)", (long)count);
                    lastCycleCount = count;
                }
            } else if (lastCycleCount > 0) {
                // Touches beendet - nur loggen wenn vorher welche aktiv waren
                printf("[LIFECYCLE] Cycle: 0 aktive Touches (alle beendet)\n");
                TouchLog("CYCLE: 0 active touches (all ended)");
                lastCycleCount = 0;
            }
            
            // Reset für nächsten Cycle
            CFSetRemoveAllValues(gActiveTouchIDsThisCycle);
        }
        
        gContactCount = 0;
        gReportCycleInProgress = FALSE;
    }

}/*!
    @param context void * pointer to your data, often a pointer to an object.
    @param result Completion result of desired operation.
    @param inSender Interface instance sending the completion routine.
*/

static void Handle_QueueValueAvailable(
            void * _Nullable        context,
            IOReturn                result,
            void * _Nullable        inSender
) {
    static int callCount = 0;
    callCount++;
    DebugLog(">>> Queue callback #%d", callCount);
    
    int valueCount = 0;
    do {
        IOHIDValueRef valueRef = IOHIDQueueCopyNextValueWithTimeout((IOHIDQueueRef) inSender, 0.);
        if (!valueRef)  {
            // finished processing 1 report
            if (valueCount > 0) {
                DebugLog("    Queue had %d values", valueCount);
            }
            DispatchTouches();
            break;
        }
        valueCount++;
        // process the HID value reference
        StoreInputValue(valueRef);
        
        // Don't forget to release our HID value reference
        CFRelease(valueRef);
    } while (1) ;
}


static void Handle_InputValueCallback (
                void *          inContext,      // context from IOHIDManagerRegisterInputValueCallback
                IOReturn        inResult,       // completion result for the input value operation
                void *          inSender,       // the IOHIDManagerRef
                IOHIDValueRef   inIOHIDValueRef // the new element value
) {
    if(!gAreElementRefsSet) {
        IOHIDElementRef e = IOHIDValueGetElement(inIOHIDValueRef);
        if (gIsELANDevice) {
            printf("\\n=== ELAN Device Element Structure ===\\n");
        }
        IdentifyElements(e, TRUE);
        gAreElementRefsSet = 1;
        
        if (gIsELANDevice) {
            printf("=== ELAN Device: Found %ld touch collection elements ===\\n\\n", CFArrayGetCount(gTouchCollectionElements));
        }
    }
    
    IOHIDElementRef elem = IOHIDValueGetElement(inIOHIDValueRef);
    
    Boolean added = IOHIDQueueContainsElement(gQueue, elem);
    if(!added) {
        IOHIDQueueAddElement(gQueue, elem);
        StoreInputValue(inIOHIDValueRef);
    }
    
}







// Initialize ELAN device by sending Feature Reports
static void InitializeELANDevice(IOHIDDeviceRef inIOHIDDeviceRef) {
    DebugLog("Attempting to initialize ELAN device...");
    
    // Try to get all Feature elements and read/write them
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(inIOHIDDeviceRef, 
                                                          NULL, 
                                                          kIOHIDOptionsTypeNone);
    if (elements) {
        CFIndex count = CFArrayGetCount(elements);
        DebugLog("Device has %ld HID elements, scanning for Feature elements...", count);
        
        int featureCount = 0;
        for (CFIndex i = 0; i < count; i++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
            IOHIDElementType type = IOHIDElementGetType(element);
            uint32_t reportID = IOHIDElementGetReportID(element);
            CFIndex reportSize = IOHIDElementGetReportSize(element);
            
            // Look for feature report elements
            if (type == kIOHIDElementTypeFeature) {
                featureCount++;
                DebugLog("[Feature %d] Report ID: %u, Size: %ld bytes", featureCount, reportID, reportSize);
                
                // Try to get the feature report with larger buffer
                uint8_t buffer[512] = {0};
                CFIndex bufferSize = sizeof(buffer);
                
                IOReturn getResult = IOHIDDeviceGetReport(inIOHIDDeviceRef,
                                                         kIOHIDReportTypeFeature,
                                                         reportID,
                                                         buffer,
                                                         &bufferSize);
                
                if (getResult == kIOReturnSuccess) {
                    DebugLog("  -> Got Feature Report %u (%ld bytes returned)", reportID, bufferSize);
                    
                    // Print hex dump of first few bytes
                    DebugLog("  -> Data (first 16 bytes): %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
                             buffer[0], buffer[1], buffer[2], buffer[3], 
                             buffer[4], buffer[5], buffer[6], buffer[7],
                             buffer[8], buffer[9], buffer[10], buffer[11],
                             buffer[12], buffer[13], buffer[14], buffer[15]);
                    
                    // Try writing it back (sometimes needed for activation)
                    IOReturn setResult = IOHIDDeviceSetReport(inIOHIDDeviceRef,
                                                             kIOHIDReportTypeFeature,
                                                             reportID,
                                                             buffer,
                                                             bufferSize);
                    DebugLog("  -> Set Feature Report %u back: 0x%08X", reportID, setResult);
                } else {
                    DebugLog("  -> Failed to get Feature Report %u: 0x%08X", reportID, getResult);
                }
            }
        }
        
        DebugLog("Scanned %d Feature elements total", featureCount);
        CFRelease(elements);
    }
    
    DebugLog("ELAN device initialization complete");
    
    // EXPERIMENTAL: Versuche den Touchscreen zu aktivieren
    // Manche ELAN-Geräte brauchen einen speziellen "Wake Up" oder "Set Mode" Befehl
    DebugLog("Sending wake-up command to ELAN device...");
    
    // Versuch 1: Feature Report 2 mit 0x0F (oft "wake up" oder "set mode")
    uint8_t wakeupCmd1[] = {0x02, 0x0F};
    IOReturn wakeResult1 = IOHIDDeviceSetReport(inIOHIDDeviceRef,
                                                kIOHIDReportTypeFeature,
                                                2,
                                                wakeupCmd1,
                                                sizeof(wakeupCmd1));
    DebugLog("Wake-up command 1 (Report 2, 0x0F): 0x%08X", wakeResult1);
    printf("[ELAN Init] Wake-up cmd 1 result: 0x%08X\n", wakeResult1);
    
    // Versuch 2: Feature Report 2 mit 0x01 (möglicherweise "enable continuous reporting")
    uint8_t wakeupCmd2[] = {0x02, 0x01};
    IOReturn wakeResult2 = IOHIDDeviceSetReport(inIOHIDDeviceRef,
                                                kIOHIDReportTypeFeature,
                                                2,
                                                wakeupCmd2,
                                                sizeof(wakeupCmd2));
    DebugLog("Wake-up command 2 (Report 2, 0x01): 0x%08X", wakeResult2);
    printf("[ELAN Init] Wake-up cmd 2 result: 0x%08X\n", wakeResult2);
    
    DebugLog("ELAN device wake-up sequence complete");
}

// this will be called when the HID Manager matches a new (hot plugged) HID device
static void Handle_DeviceMatchingCallback(
            void *          inContext,       // context from IOHIDManagerRegisterDeviceMatchingCallback
            IOReturn        inResult,        // the result of the matching operation
            void *          inSender,        // the IOHIDManagerRef for the new device
            IOHIDDeviceRef  inIOHIDDeviceRef // the new HID device
) {
    printf("%s(context: %p, result: %p, sender: %p, device: %p).\n",
        __PRETTY_FUNCTION__, inContext, (void *) inResult, inSender, (void*) inIOHIDDeviceRef);
   
    // Get device information
    CFNumberRef vendorIDRef = IOHIDDeviceGetProperty(inIOHIDDeviceRef, CFSTR(kIOHIDVendorIDKey));
    CFNumberRef productIDRef = IOHIDDeviceGetProperty(inIOHIDDeviceRef, CFSTR(kIOHIDProductIDKey));
    CFStringRef productRef = IOHIDDeviceGetProperty(inIOHIDDeviceRef, CFSTR(kIOHIDProductKey));
    
    int vendorID = 0;
    int productID = 0;
    
    if (vendorIDRef) {
        CFNumberGetValue(vendorIDRef, kCFNumberIntType, &vendorID);
    }
    if (productIDRef) {
        CFNumberGetValue(productIDRef, kCFNumberIntType, &productID);
    }
    
    printf("Device detected - Vendor ID: 0x%04X, Product ID: 0x%04X\n", vendorID, productID);
    DebugLog("Device detected - Vendor ID: 0x%04X, Product ID: 0x%04X", vendorID, productID);
    
    if (productRef) {
        char productName[256];
        CFStringGetCString(productRef, productName, sizeof(productName), kCFStringEncodingUTF8);
        printf("Product Name: %s\n", productName);
        DebugLog("Product Name: %s", productName);
    }
    
    // Check if this is an ELAN device (by vendor ID OR by product name containing "Elan" or "ELAN")
    bool isELAN = false;
    if (vendorID == kELANVendorID) {
        isELAN = true;
        printf("Matched by ELAN vendor ID 0x0712\n");
        DebugLog("Matched by ELAN vendor ID 0x0712");
    }
    
    // Also check product name for "Elan" string
    if (productRef && !isELAN) {
        char productName[256];
        CFStringGetCString(productRef, productName, sizeof(productName), kCFStringEncodingUTF8);
        if (strcasestr(productName, "elan") != NULL) {
            isELAN = true;
            printf("Matched by product name containing 'Elan'\n");
            DebugLog("Matched by product name containing 'Elan': %s", productName);
        }
    }
    
    if (isELAN) {
        gIsELANDevice = TRUE;
        printf(">>> ELAN Touchscreen detected! <<<\n");
        DebugLog(">>> ELAN Touchscreen detected! <<<");
        TouchLog("DEVICE: ELAN Touchscreen detected - Vendor:0x%04X Product:0x%04X", vendorID, productID);
    } else {
        gIsELANDevice = FALSE;
        printf("Device is NOT an ELAN touchscreen - IGNORING\n");
        DebugLog("Device is NOT an ELAN touchscreen - IGNORING");
        TouchLog("DEVICE: Non-ELAN device IGNORED - Vendor:0x%04X Product:0x%04X", vendorID, productID);
        
        // CRITICAL: Reject non-ELAN devices (z.B. MacBook Trackpad)
        // Nur ELAN Touchscreens sollen verarbeitet werden
        return;
    }
    
    gAreElementRefsSet = 0;
    
    
    IOHIDQueueRef queue = IOHIDQueueCreate(kCFAllocatorDefault, inIOHIDDeviceRef, 1000, kNilOptions);
    
    if (CFGetTypeID(queue) != IOHIDQueueGetTypeID()) {
        // this is not a valid HID queue reference!
    }
    
    IOHIDQueueRegisterValueAvailableCallback(queue, Handle_QueueValueAvailable, NULL);
    IOHIDQueueStart(queue);
    gQueue = queue;
    
    IOHIDQueueScheduleWithRunLoop(queue, gRunLoopRef, kCFRunLoopCommonModes);
    
    // CRITICAL FIX: Proaktiv alle Input-Elemente zur Queue hinzufügen
    // Nicht warten bis Handle_InputValueCallback aufgerufen wird
    CFArrayRef allElements = IOHIDDeviceCopyMatchingElements(inIOHIDDeviceRef, NULL, kIOHIDOptionsTypeNone);
    if (allElements) {
        CFIndex elementCount = CFArrayGetCount(allElements);
        printf("[Queue Setup] Adding %ld elements to queue proactively\n", (long)elementCount);
        
        int addedCount = 0;
        IOHIDElementRef firstElement = NULL;
        
        for (CFIndex i = 0; i < elementCount; i++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(allElements, i);
            IOHIDElementType type = IOHIDElementGetType(element);
            
            // Merke das erste Element für IdentifyElements
            if (i == 0) {
                firstElement = element;
            }
            
            // Nur Input-Elemente zur Queue hinzufügen
            if (type == kIOHIDElementTypeInput_Misc ||
                type == kIOHIDElementTypeInput_Button ||
                type == kIOHIDElementTypeInput_Axis ||
                type == kIOHIDElementTypeInput_ScanCodes) {
                
                IOHIDQueueAddElement(queue, element);
                addedCount++;
            }
        }
        
        printf("[Queue Setup] Added %d input elements to queue\n", addedCount);
        
        // Jetzt identifiziere die Touch-Collections
        if (firstElement) {
            if (gIsELANDevice) {
                printf("\\n=== ELAN Device Element Structure ===\\n");
            }
            IdentifyElements(firstElement, TRUE);
            gAreElementRefsSet = 1;
            
            if (gIsELANDevice) {
                printf("=== ELAN Device: Found %ld touch collection elements ===\\n\\n", CFArrayGetCount(gTouchCollectionElements));
            }
        }
        
        CFRelease(allElements);
    }
    
    // Initialize ELAN device if detected
    if (gIsELANDevice) {
        InitializeELANDevice(inIOHIDDeviceRef);
    }
    
    TouchInputManagerDidConnectTouchscreen(gTouchManager);
    
}   // Handle_DeviceMatchingCallback
 


// this will be called when a HID device is removed (unplugged)
static void Handle_RemovalCallback(
                void *         inContext,       // context from IOHIDManagerRegisterDeviceMatchingCallback
                IOReturn       inResult,        // the result of the removing operation
                void *         inSender,        // the IOHIDManagerRef for the device being removed
                IOHIDDeviceRef inIOHIDDeviceRef // the removed HID device
) {
    printf("%s(context: %p, result: %p, sender: %p, device: %p).\n",
        __PRETTY_FUNCTION__, inContext, (void *) inResult, inSender, (void*) inIOHIDDeviceRef);
    
    if (gIsELANDevice) {
        printf("ELAN Touchscreen disconnected\n");
        gIsELANDevice = FALSE;
    }
    
    IOHIDQueueStop(gQueue);
    CFRelease(gQueue);
    gQueue = NULL;
    
    CFArrayRemoveAllValues(gTouchCollectionElements);
    CFArrayRemoveAllValues(gContactIdentifiers);
    CFDictionaryRemoveAllValues(gStoredInputValues);
    
    TouchInputManagerDidDisconnectTouchscreen(gTouchManager);
}   // Handle_RemovalCallback



#pragma mark - Start / Stop


// function to create matching dictionary
static CFMutableDictionaryRef CreateDeviceMatchingDictionary(UInt32 inUsagePage, UInt32 inUsage) {
    // create a dictionary to add usage page/usages to
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (result) {
        if (inUsagePage) {
            // Add key for device type to refine the matching dictionary.
            CFNumberRef pageCFNumberRef = CFNumberCreate(
                            kCFAllocatorDefault, kCFNumberIntType, &inUsagePage);
            if (pageCFNumberRef) {
                CFDictionarySetValue(result,
                        CFSTR(kIOHIDDeviceUsagePageKey), pageCFNumberRef);
                CFRelease(pageCFNumberRef);
 
                // note: the usage is only valid if the usage page is also defined
                if (inUsage) {
                    CFNumberRef usageCFNumberRef = CFNumberCreate(
                                    kCFAllocatorDefault, kCFNumberIntType, &inUsage);
                    if (usageCFNumberRef) {
                        CFDictionarySetValue(result,
                            CFSTR(kIOHIDDeviceUsageKey), usageCFNumberRef);
                        CFRelease(usageCFNumberRef);
                    } else {
                        fprintf(stderr, "%s: CFNumberCreate(usage) failed.", __PRETTY_FUNCTION__);
                    }
                }
            } else {
                fprintf(stderr, "%s: CFNumberCreate(usage page) failed.", __PRETTY_FUNCTION__);
            }
        }
    } else {
        fprintf(stderr, "%s: CFDictionaryCreateMutable failed.", __PRETTY_FUNCTION__);
    }
    return result;
}   // CreateDeviceMatchingDictionary
 




void OpenHIDManager(void *delegate) {
    gTouchManager = delegate;
    
    // Initialize Position-Deduplication für Hybrid-Mode Multi-Touch
    InitializePositionDeduplication();
    
    gHidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    
    if (CFGetTypeID(gHidManager) != IOHIDManagerGetTypeID()) {
        printf("OH CRAP THIS IS NOT AN HID MANAGER");
    }
        
    
    gTouchCollectionElements = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    gContactIdentifiers      = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    gStoredInputValues       = CFDictionaryCreateMutable(kCFAllocatorDefault,0, NULL, NULL);
    
    // Initialize touch lifecycle tracking sets
    gActiveTouchIDsThisCycle = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    gActiveTouchIDsLastCycle = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
   
    printf("Initializing HID Manager with ELAN touchscreen support...\n");
    printf("ELAN Vendor ID: 0x%04X\n", kELANVendorID);

    // Create matching dictionaries for different touchscreen types
    // Standard touchscreen matching
    CFMutableDictionaryRef touchscreenMatch = CreateDeviceMatchingDictionary(kHIDPage_Digitizer, kHIDUsage_Dig_TouchScreen);
    
    // Also match digitizer touch devices (some ELAN devices report as this)
    CFMutableDictionaryRef touchMatch = CreateDeviceMatchingDictionary(kHIDPage_Digitizer, kHIDUsage_Dig_Touch);
    
    CFMutableDictionaryRef matchesList[] = {
        touchscreenMatch,
        touchMatch,
    };
    
    CFArrayRef matches = CFArrayCreate(kCFAllocatorDefault,
            (const void **)matchesList, 2, NULL);
    IOHIDManagerSetDeviceMatchingMultiple(gHidManager, matches);
    CFRelease(matches);
    
    IOHIDManagerRegisterDeviceMatchingCallback(gHidManager, Handle_DeviceMatchingCallback, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(gHidManager, Handle_RemovalCallback, NULL);
    
//    IOHIDManagerRegisterInputReportWithTimeStampCallback(gHidManager, Handle_ReportCallback, NULL);
    IOHIDManagerRegisterInputValueCallback(gHidManager, Handle_InputValueCallback, NULL);
    
    
    gRunLoopRef = CFRunLoopGetMain();
    
    IOHIDManagerScheduleWithRunLoop(gHidManager, gRunLoopRef,
                                    kCFRunLoopCommonModes);

    IOHIDManagerOpen(gHidManager, kIOHIDOptionsTypeNone);
    
    // USB Direct Access is disabled - HID works directly
    // Archive: USBDirectAccessor wurde in _Archive/unused_code verschoben
    // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
    //                dispatch_get_main_queue(), ^{
    //     TryUSBDirectAccess();
    // });
}



void CloseHIDManager(void) {
    IOHIDManagerUnscheduleFromRunLoop(gHidManager, gRunLoopRef, kCFRunLoopCommonModes);
    IOHIDManagerClose(gHidManager, kIOHIDOptionsTypeNone);
    
    // Clean up USB Direct Access if it was initialized
    if (gUSBDirectAccessHandle) {
        USBDirectAccessor_Release(gUSBDirectAccessHandle);
        gUSBDirectAccessHandle = NULL;
    }
    
    // Clean up touch lifecycle tracking sets
    if (gActiveTouchIDsThisCycle != NULL) {
        CFRelease(gActiveTouchIDsThisCycle);
        gActiveTouchIDsThisCycle = NULL;
    }
    if (gActiveTouchIDsLastCycle != NULL) {
        CFRelease(gActiveTouchIDsLastCycle);
        gActiveTouchIDsLastCycle = NULL;
    }
}

#pragma mark - USB Direct Access Implementation (Fallback for non-HID devices)

// Simplified USB Device Finder
static io_service_t FindUSBDevice_Internal(uint16_t vendorID, uint16_t productID) {
    CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matchingDict) {
        printf("USBDirectAccess: Could not create matching dictionary\n");
        return 0;
    }
    
    CFNumberRef vendorIDRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberShortType, &vendorID);
    CFNumberRef productIDRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberShortType, &productID);
    
    CFDictionarySetValue(matchingDict, CFSTR(kUSBVendorID), vendorIDRef);
    CFDictionarySetValue(matchingDict, CFSTR(kUSBProductID), productIDRef);
    
    CFRelease(vendorIDRef);
    CFRelease(productIDRef);
    
    io_iterator_t iterator = 0;
    IOReturn kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator);
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccess: IOServiceGetMatchingServices failed: 0x%x\n", kr);
        return 0;
    }
    
    io_service_t usbDevice = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    
    if (usbDevice) {
        printf("USBDirectAccess: Found USB device 0x%04x:0x%04x\n", vendorID, productID);
    }
    
    return usbDevice;
}

// Check if ELAN device is available
bool USBDirectAccessor_IsELANDeviceAvailable(uint16_t vendorID, uint16_t productID) {
    io_service_t device = FindUSBDevice_Internal(vendorID, productID);
    if (device) {
        IOObjectRelease(device);
        return true;
    }
    return false;
}

// Create USB Direct Access Handle
USBDirectAccessHandle* USBDirectAccessor_Create(uint16_t vendorID, uint16_t productID) {
    printf("USBDirectAccessor_Create: Attempting to access 0x%04x:0x%04x\n", vendorID, productID);
    
    io_service_t usbDevice = FindUSBDevice_Internal(vendorID, productID);
    if (!usbDevice) {
        printf("USBDirectAccessor: Device not found\n");
        return NULL;
    }
    
    // For now, just create a handle and return it
    // Full implementation would open device and interfaces
    USBDirectAccessHandle *handle = malloc(sizeof(USBDirectAccessHandle));
    if (!handle) {
        printf("USBDirectAccessor: Memory allocation failed\n");
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    handle->usbDevice = usbDevice;
    handle->deviceInterface = NULL;
    handle->interfaceInterface = NULL;
    handle->interruptEndpoint = 0;
    handle->runLoopSource = NULL;
    handle->pipeRef = -1;
    handle->isReading = true;
    
    // Start background thread to read from device
    int rc = pthread_create(&handle->readThread, NULL, USBInterruptReadThread, (void *)handle);
    if (rc != 0) {
        DebugLog("USBDirectAccessor: Failed to create read thread: %d", rc);
        free(handle);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    printf("USBDirectAccessor: Handle created, read thread started\n");
    return handle;
}

// Helper: Print hex dump for debugging
static void PrintHexDump(const uint8_t *data, uint32_t len, const char *label) {
    printf("%s (%u bytes): ", label, len);
    for (uint32_t i = 0; i < len && i < 64; i++) {
        printf("%02x ", data[i]);
        if ((i + 1) % 16 == 0) printf("\n              ");
    }
    printf("\n");
}

// Thread function to continuously read from USB device
static void* USBInterruptReadThread(void *arg) {
    USBDirectAccessHandle *handle = (USBDirectAccessHandle *)arg;
    uint8_t buffer[64];
    
    printf("USBInterruptReadThread: Started reading from device\n");
    
    while (handle->isReading) {
        // Simple synchronous read with timeout
        // In a real implementation, would use async callbacks
        memset(buffer, 0, sizeof(buffer));
        
        // Try to read control request to get interrupt data
        IOUSBDevRequest req;
        req.bmRequestType = 0xC0; // IN, Vendor-specific
        req.bRequest = 0x81;      // Custom request to read data
        req.wValue = 0x0000;
        req.wIndex = 0x0000;
        req.wLength = sizeof(buffer);
        req.pData = buffer;
        
        // Note: This is attempting a custom read - device may have different protocol
        // Will print whatever comes back for protocol analysis
        
        // For now, just log every 2 seconds that we're waiting for data
        printf("USBInterruptReadThread: Waiting for data (device may need init command)\n");
        
        usleep(2000000); // 2 second wait between attempts
    }
    
    printf("USBInterruptReadThread: Stopped reading\n");
    return NULL;
}

// Read from interrupt endpoint
int USBDirectAccessor_ReadInterrupt(USBDirectAccessHandle *handle,
                                     uint8_t *buffer,
                                     uint32_t bufferSize,
                                     uint32_t timeoutMS) {
    if (!handle || !buffer) {
        return -1;
    }
    
    DebugLog("USBDirectAccessor_ReadInterrupt: Attempting to read up to %u bytes", bufferSize);
    
    // For simplicity, return 0 bytes for now
    // Actual implementation would use libusb or IOUSBHostInterface
    return 0;
}

// Write data to device
int USBDirectAccessor_Write(USBDirectAccessHandle *handle,
                            const uint8_t *data,
                            uint32_t dataSize) {
    if (!handle || !data || dataSize == 0) {
        return -1;
    }
    
    printf("USBDirectAccessor_Write: Write attempted with %u bytes (not yet fully implemented)\n", dataSize);
    return (int)dataSize;
}

// Release USB handle
void USBDirectAccessor_Release(USBDirectAccessHandle *handle) {
    if (!handle) {
        return;
    }
    
    // Stop reading thread
    handle->isReading = false;
    
    // Wait for thread to finish (with 1 second timeout)
    if (handle->readThread != 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1LL * NSEC_PER_SEC),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            pthread_cancel(handle->readThread);
        });
        pthread_join(handle->readThread, NULL);
    }
    
    if (handle->deviceInterface) {
        // Release deviceInterface
    }
    
    if (handle->interfaceInterface) {
        // Release interfaceInterface
    }
    
    if (handle->usbDevice) {
        IOObjectRelease(handle->usbDevice);
    }
    
    free(handle);
    DebugLog("USBDirectAccessor: Handle released");
}

// ARCHIVED: USB Direct Access ist nicht mehr nötig - HID funktioniert direkt
// Diese Funktion wurde deaktiviert, Code in _Archive/unused_code/
/*
void TryUSBDirectAccess(void) {
    // Check if HID manager found the device
    if (gIsELANDevice) {
        DebugLog("HIDInterpreter: ELAN device already found via HID Manager");
        return;
    }
    
    DebugLog("HIDInterpreter: HID Manager failed, attempting USB Direct Access for 0x%04x:0x%04x",
           kELANVendorID, kELANProductID);
    
    // Check if device is available
    if (!USBDirectAccessor_IsELANDeviceAvailable(kELANVendorID, kELANProductID)) {
        DebugLog("HIDInterpreter: ELAN device (0x%04x:0x%04x) not available",
               kELANVendorID, kELANProductID);
        return;
    }
    
    // Try to create USB Direct Access
    gUSBDirectAccessHandle = USBDirectAccessor_Create(kELANVendorID, kELANProductID);
    if (!gUSBDirectAccessHandle) {
        DebugLog("HIDInterpreter: Failed to create USB Direct Access handle");
        return;
    }
    
    DebugLog("HIDInterpreter: USB Direct Access initialized successfully");
    
    // TODO: Start reading from USB device in separate thread
    // For now, just log that we have access
}
*/


