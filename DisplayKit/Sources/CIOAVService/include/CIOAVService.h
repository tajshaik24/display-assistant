#ifndef CIOAVSERVICE_H
#define CIOAVSERVICE_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

// Private IOKit API used to talk I2C (and therefore DDC/CI) to external
// displays on Apple Silicon. Not declared in any public header.
typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service) CF_RETURNS_RETAINED;
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

#endif
