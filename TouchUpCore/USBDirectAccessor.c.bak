//
//  USBDirectAccessor.c
//  TouchUpCore
//
//  USB Direct Access for non-HID ELAN touchscreen devices (e.g., hotlotus 0x0712)
//

#include "USBDirectAccessor.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define USB_TIMEOUT_MS 5000

// Findet ein USB-Gerät anhand von Vendor und Product ID
static io_service_t FindUSBDevice(uint16_t vendorID, uint16_t productID) {
    IOReturn kr;
    CFMutableDictionaryRef matchingDict;
    io_iterator_t iterator = 0;
    io_service_t usbDevice = 0;
    
    // Erstelle Matching Dictionary für USB Devices
    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matchingDict) {
        printf("USBDirectAccessor: Could not create matching dictionary\n");
        return 0;
    }
    
    // Setze Vendor und Product ID als Suchkriterien
    CFNumberRef vendorIDRef = CFNumberCreate(kCFAllocatorDefault, 
                                              kCFNumberShortType, &vendorID);
    CFNumberRef productIDRef = CFNumberCreate(kCFAllocatorDefault, 
                                               kCFNumberShortType, &productID);
    
    CFDictionarySetValue(matchingDict, CFSTR(kUSBVendorID), vendorIDRef);
    CFDictionarySetValue(matchingDict, CFSTR(kUSBProductID), productIDRef);
    
    CFRelease(vendorIDRef);
    CFRelease(productIDRef);
    
    // Suche nach dem Gerät
    kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator);
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor: IOServiceGetMatchingServices failed: 0x%x\n", kr);
        return 0;
    }
    
    // Hole das erste gefundene Gerät
    usbDevice = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    
    if (usbDevice) {
        printf("USBDirectAccessor: Found USB device 0x%04x:0x%04x\n", vendorID, productID);
    } else {
        printf("USBDirectAccessor: USB device 0x%04x:0x%04x not found\n", vendorID, productID);
    }
    
    return usbDevice;
}

// Extrahiert Interrupt Endpoint aus Interface Descriptor
static uint8_t FindInterruptEndpoint(IOUSBInterfaceInterface245 **interfaceInterface) {
    IOReturn kr;
    uint8_t endpoint = 0;
    int direction;
    int transferType;
    int maxPacketSize;
    int interval;
    
    // Iteriere durch alle Endpoints
    for (int ep = 1; ep <= 15; ep++) {
        kr = (*interfaceInterface)->GetPipeProperties(
            interfaceInterface,
            ep,
            &direction,
            &endpoint,
            &transferType,
            &maxPacketSize,
            &interval
        );
        
        if (kr == kIOReturnSuccess) {
            // Suche nach Interrupt Endpoint (Type 3)
            if (transferType == kUSBInterrupt) {
                printf("USBDirectAccessor: Found interrupt endpoint: 0x%02x (max packet: %d)\n", 
                       endpoint, maxPacketSize);
                return endpoint;
            }
        }
    }
    
    printf("USBDirectAccessor: No interrupt endpoint found\n");
    return 0;
}

// Erstellt USB Direct Access Handle
USBDirectAccessHandle* USBDirectAccessor_Create(uint16_t vendorID, uint16_t productID) {
    IOReturn kr;
    IOUSBDeviceInterface245 **deviceInterface = NULL;
    IOUSBInterfaceInterface245 **interfaceInterface = NULL;
    UInt8 numInterfaces;
    
    printf("USBDirectAccessor_Create: Attempting to access 0x%04x:0x%04x\n", vendorID, productID);
    
    // Finde das USB-Gerät
    io_service_t usbDevice = FindUSBDevice(vendorID, productID);
    if (!usbDevice) {
        printf("USBDirectAccessor: Device not found\n");
        return NULL;
    }
    
    // Erstelle Plugin Interface
    SInt32 score;
    kr = IOCreatePlugInInterfaceForService(
        usbDevice,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &deviceInterface,
        &score
    );
    
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor: Could not create plugin interface: 0x%x\n", kr);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    // Öffne das Gerät
    IOUSBDeviceInterface245 **dev = deviceInterface;
    kr = (*dev)->USBDeviceOpen(dev);
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor: Could not open device: 0x%x\n", kr);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    printf("USBDirectAccessor: Device opened successfully\n");
    
    // Finde erste Schnittstelle
    kr = (*dev)->GetNumberOfInterfaces(dev, &numInterfaces);
    if (kr != kIOReturnSuccess || numInterfaces == 0) {
        printf("USBDirectAccessor: No interfaces found (error: 0x%x, count: %d)\n", kr, numInterfaces);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    printf("USBDirectAccessor: Device has %d interface(s)\n", numInterfaces);
    
    // Versuche erste Interface zu öffnen
    io_service_t interface = 0;
    kr = (*dev)->GetInterfaceServiceIterator(dev, &interface);
    
    if (kr != kIOReturnSuccess || !interface) {
        printf("USBDirectAccessor: Could not get interface iterator: 0x%x\n", kr);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    // Erstelle Interface Plugin
    kr = IOCreatePlugInInterfaceForService(
        interface,
        kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &interfaceInterface,
        &score
    );
    
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor: Could not create interface plugin: 0x%x\n", kr);
        IOObjectRelease(interface);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    // Öffne die Interface
    IOUSBInterfaceInterface245 **intf = interfaceInterface;
    kr = (*intf)->USBInterfaceOpen(intf);
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor: Could not open interface: 0x%x\n", kr);
        (*intf)->Release(intf);
        IOObjectRelease(interface);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    printf("USBDirectAccessor: Interface opened successfully\n");
    
    // Finde Interrupt Endpoint
    uint8_t interruptEndpoint = FindInterruptEndpoint(intf);
    
    // Erstelle Handle
    USBDirectAccessHandle *handle = malloc(sizeof(USBDirectAccessHandle));
    if (!handle) {
        printf("USBDirectAccessor: Memory allocation failed\n");
        (*intf)->USBInterfaceClose(intf);
        (*intf)->Release(intf);
        IOObjectRelease(interface);
        (*dev)->USBDeviceClose(dev);
        (*dev)->Release(dev);
        IOObjectRelease(usbDevice);
        return NULL;
    }
    
    handle->usbDevice = usbDevice;
    handle->deviceInterface = deviceInterface;
    handle->interfaceInterface = interfaceInterface;
    handle->interruptEndpoint = interruptEndpoint;
    handle->runLoopSource = NULL;
    
    printf("USBDirectAccessor: Handle created successfully\n");
    
    return handle;
}

// Liest Daten vom Interrupt Endpoint
int USBDirectAccessor_ReadInterrupt(USBDirectAccessHandle *handle,
                                     uint8_t *buffer,
                                     uint32_t bufferSize,
                                     uint32_t timeoutMS) {
    if (!handle || !handle->interfaceInterface || !buffer) {
        return -1;
    }
    
    if (handle->interruptEndpoint == 0) {
        printf("USBDirectAccessor_ReadInterrupt: No interrupt endpoint available\n");
        return -1;
    }
    
    IOReturn kr;
    UInt32 bytesRead = 0;
    
    // Versuche asynchron zu lesen (mit Timeout)
    kr = (*handle->interfaceInterface)->ReadPipeAsync(
        handle->interfaceInterface,
        handle->interruptEndpoint,
        buffer,
        bufferSize,
        NULL,
        NULL
    );
    
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor_ReadInterrupt: ReadPipeAsync failed: 0x%x\n", kr);
        return -1;
    }
    
    // Warte kurz auf Daten
    usleep(50000); // 50ms
    
    return bytesRead;
}

// Schreibt Daten zum Gerät
int USBDirectAccessor_Write(USBDirectAccessHandle *handle,
                            const uint8_t *data,
                            uint32_t dataSize) {
    if (!handle || !handle->deviceInterface || !data || dataSize == 0) {
        return -1;
    }
    
    IOReturn kr;
    
    // Sende Control Request (SetReport)
    IOUSBDevRequest request;
    request.bmRequestType = 0x21; // Class, Interface, OUT
    request.bRequest = 0x09;      // SET_REPORT
    request.wValue = 0x0200;      // Report ID 2, Type Feature
    request.wIndex = 0x0000;      // Interface 0
    request.wLength = dataSize;
    request.pData = (void *)data;
    
    kr = (*handle->deviceInterface)->DeviceRequest(
        handle->deviceInterface,
        &request
    );
    
    if (kr != kIOReturnSuccess) {
        printf("USBDirectAccessor_Write: DeviceRequest failed: 0x%x\n", kr);
        return -1;
    }
    
    printf("USBDirectAccessor_Write: Wrote %d bytes\n", dataSize);
    return (int)dataSize;
}

// Schließt USB Handle
void USBDirectAccessor_Release(USBDirectAccessHandle *handle) {
    if (!handle) {
        return;
    }
    
    if (handle->interfaceInterface) {
        (*handle->interfaceInterface)->USBInterfaceClose(handle->interfaceInterface);
        (*handle->interfaceInterface)->Release(handle->interfaceInterface);
    }
    
    if (handle->deviceInterface) {
        (*handle->deviceInterface)->USBDeviceClose(handle->deviceInterface);
        (*handle->deviceInterface)->Release(handle->deviceInterface);
    }
    
    if (handle->usbDevice) {
        IOObjectRelease(handle->usbDevice);
    }
    
    free(handle);
    printf("USBDirectAccessor: Handle released\n");
}

// Überprüft ob ELAN-Gerät verfügbar ist
bool USBDirectAccessor_IsELANDeviceAvailable(uint16_t vendorID, uint16_t productID) {
    io_service_t device = FindUSBDevice(vendorID, productID);
    if (device) {
        IOObjectRelease(device);
        return true;
    }
    return false;
}
