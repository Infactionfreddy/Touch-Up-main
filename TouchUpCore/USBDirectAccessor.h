//
//  USBDirectAccessor.h
//  TouchUpCore
//
//  USB Direct Access for non-HID ELAN touchscreen devices (e.g., hotlotus 0x0712)
//  This module provides direct USB communication when HID Manager cannot detect the device
//

#ifndef USBDirectAccessor_h
#define USBDirectAccessor_h

#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

typedef struct {
    io_service_t            usbDevice;
    IOUSBDeviceInterface245 **deviceInterface;
    IOUSBInterfaceInterface245 **interfaceInterface;
    CFRunLoopSourceRef      runLoopSource;
    uint8_t                 interfaceNumber;
    uint8_t                 interruptEndpoint;
} USBDirectAccessHandle;

// Initialisiert USB Direct Access für ELAN Geräte
// Returniert non-NULL Handle wenn erfolgreich
USBDirectAccessHandle* USBDirectAccessor_Create(uint16_t vendorID, uint16_t productID);

// Liest Interrupt-Daten vom Gerät
// Blockiert bis Daten verfügbar oder timeout
int USBDirectAccessor_ReadInterrupt(USBDirectAccessHandle *handle, 
                                     uint8_t *buffer, 
                                     uint32_t bufferSize,
                                     uint32_t timeoutMS);

// Schreibt Daten zum Gerät (z.B. für Initialisierung)
int USBDirectAccessor_Write(USBDirectAccessHandle *handle,
                            const uint8_t *data,
                            uint32_t dataSize);

// Schließt die USB-Verbindung
void USBDirectAccessor_Release(USBDirectAccessHandle *handle);

// Überprüft ob ein ELAN-Gerät verfügbar ist
bool USBDirectAccessor_IsELANDeviceAvailable(uint16_t vendorID, uint16_t productID);

#endif /* USBDirectAccessor_h */
