#ifndef CIOAVSERVICE_H
#define CIOAVSERVICE_H

#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

// Private IOKit API used by MonitorControl / m1ddc for DDC over Apple Silicon.
typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                   uint32_t offset, void *outputBuffer, uint32_t length);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                    uint32_t dataAddress, void *inputBuffer, uint32_t length);

#endif
